# NINJA BUILD GRAPH - CORE STRUCTURES & FLOW

## DATA STRUCTURES (from ninja/src/)

### Node (graph.h:42)
```cpp
struct Node {
    string path_;              // "main.o", "lib.a"
    TimeStamp mtime_;          // -1=unknown, 0=missing, >0=exists
    bool dirty_;               // needs rebuild
    Edge* in_edge_;            // edge producing this node (NULL for sources)
    vector<Edge*> out_edges_;  // edges consuming this node
};
```

### Edge (graph.h:175)
```cpp
struct Edge {
    const Rule* rule_;         // "cc", "link" (contains command template)
    vector<Node*> inputs_;     // [main.c, header.h]
    vector<Node*> outputs_;    // [main.o]
    bool outputs_ready_;       // all outputs up-to-date
    VisitMark mark_;           // None/InStack/Done (cycle detection)
};
```

### State (state.h:95)
```cpp
struct State {
    Paths paths_;              // hash_map<string, Node*>
    vector<Edge*> edges_;      // all build edges
    BindingEnv bindings_;      // rule definitions, variables
};
```

## CONSTRUCTION FLOW

```
Parse build.ninja
  ↓
For each "build out: rule in1 in2"
  ↓
  edge = new Edge(rule)
  edge->inputs = [GetNode(in1), GetNode(in2)]
  edge->outputs = [GetNode(out)]
  ↓
  out->in_edge = edge
  in1->out_edges.push(edge)
  in2->out_edges.push(edge)
  ↓
State contains full DAG
```

**Example**:
```ninja
build main.o: cc main.c
build prog: link main.o lib.o
```
→
```
[main.c]──→[cc]──→[main.o]──→[link]──→[prog]
                     ↑
           [lib.o]───┘
```

## DIRTY DETECTION (graph.cc:48)

```cpp
bool RecomputeNodeDirty(Node* node) {
    // Leaf: source file
    if (!node->in_edge) {
        node->Stat();  // get mtime
        node->dirty = !node->exists();
        return true;
    }

    // Internal: has producing edge
    Edge* edge = node->in_edge;
    TimeStamp out_mtime = node->Stat();
    TimeStamp newest_in = 0;

    // Recurse inputs
    for (Node* in : edge->inputs) {
        RecomputeNodeDirty(in);
        newest_in = max(newest_in, in->mtime);
    }

    // Dirty if:
    node->dirty = out_mtime == 0           // missing
               || newest_in > out_mtime    // input newer
               || any(in->dirty);          // input dirty

    edge->outputs_ready = !node->dirty;
}
```

**Traversal**: Postorder DFS (inputs before outputs)

## BUILD EXECUTION (build.cc:80)

### Plan Structure
```cpp
struct Plan {
    map<Edge*, Want> want_;    // {edge: kWantNothing/ToStart/ToFinish}
    EdgePriorityQueue ready_;  // priority_queue by critical_path_weight
    int wanted_edges_;
};
```

### Algorithm
```
1. AddTarget(node)
   ├─ If node->dirty: mark node->in_edge as kWantToStart
   └─ Recursively add inputs

2. ScheduleInitialEdges()
   ├─ For each edge with kWantToStart:
   │   If AllInputsReady(edge): ready_.push(edge)
   └─ Mark as kWantToFinish

3. Build loop:
   while (!ready_.empty()) {
       edge = ready_.pop()
       ExecuteCommand(edge)
       edge->outputs_ready = true

       // Propagate readiness
       for (out : edge->outputs) {
           for (dep_edge : out->out_edges) {
               if (AllInputsReady(dep_edge))
                   ready_.push(dep_edge)
           }
       }
   }
```

### AllInputsReady
```cpp
bool AllInputsReady(Edge* e) {
    for (Node* in : e->inputs) {
        if (in->in_edge && !in->in_edge->outputs_ready)
            return false;
    }
    return true;
}
```

## CRITICAL PATH SCHEDULING (build.cc:462)

```cpp
// Compute weight = longest path to this edge
void ComputeCriticalPath() {
    // Topological order
    for (Edge* e : topo_sorted_edges) {
        int64_t max_in = 0;
        for (Node* in : e->inputs) {
            if (in->in_edge)
                max_in = max(max_in, in->in_edge->critical_path_weight);
        }
        e->critical_path_weight = max_in + e->prev_elapsed_time;
    }
}

// Priority queue orders by:
// 1. Highest weight (longest chain)
// 2. Lowest ID (stable)
```

**Purpose**: Execute long chains first → minimize total build time

## KEY INVARIANTS

1. **DAG**: `VerifyDAG()` ensures no cycles via DFS + InStack marking
2. **Single producer**: Each node has ≤1 `in_edge`
3. **Dirty propagation**: Leaf→root (postorder)
4. **Execution order**: Root→leaf via ready queue (topological)

## MINIMAL IMPLEMENTATION

`005_ninja/mininja/mininja.c` (388 LOC):
- ✅ Node/Edge graph
- ✅ Mtime-based dirty check
- ✅ Topological execution
- ✅ Incremental builds
- ❌ Parallelism, pools, depfiles, build log, manifest DSL

**Tests**: simple (1 file) → medium (3 files) → complex (100 deep chain)
