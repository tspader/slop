# NINJA BUILD GRAPH ARCHITECTURE

Distilled from `ninja/src/graph.h`, `state.h`, `build.h`

## CORE DATA STRUCTURES

### Node (graph.h:42)
```cpp
struct Node {
    string path_;              // File path
    TimeStamp mtime_;          // -1=unknown, 0=missing, >0=file mtime
    bool dirty_;               // Needs rebuild
    Edge* in_edge_;            // Edge that produces this node
    vector<Edge*> out_edges_;  // Edges that consume this node
};
```

**Purpose**: File in dependency graph
**Key invariant**: Each node has at most ONE producing edge (in_edge)

### Edge (graph.h:175)
```cpp
struct Edge {
    const Rule* rule_;             // Build rule (contains command template)
    vector<Node*> inputs_;         // Input files
    vector<Node*> outputs_;        // Output files
    bool outputs_ready_;           // All outputs up-to-date
    VisitMark mark_;              // Cycle detection: None/InStack/Done
    int64_t critical_path_weight_; // Scheduling priority
};
```

**Purpose**: Build command linking inputs → outputs
**Key invariant**: Edge executes when all input edges are outputs_ready

### State (state.h:95)
```cpp
struct State {
    Paths paths_;              // Hash map: path → Node*
    vector<Edge*> edges_;      // All edges
    BindingEnv bindings_;      // Variable scope
};
```

**Purpose**: Global build graph container
**Operations**:
- `GetNode(path)`: Lookup or create node
- `AddEdge(rule)`: Create new edge

## BUILD GRAPH CONSTRUCTION

**From**: `state.cc`, `manifest_parser.cc`

```
1. Parse build.ninja
   ├─ Read "build output: input1 input2"
   ├─ Create Edge with rule
   ├─ GetNode(output) → set in_edge = edge
   └─ GetNode(input) → add to out_edges

2. Result: Directed Acyclic Graph
   Nodes = files, Edges = build commands
```

Example:
```
build main.o: cc main.c
build prog: link main.o lib.o
```
→
```
main.c ──→ [cc] ──→ main.o ──→ [link] ──→ prog
                      ↑
lib.o ────────────────┘
```

## DIRTY CHECKING ALGORITHM

**From**: `graph.cc:48` `DependencyScan::RecomputeDirty`

```cpp
bool RecomputeNodeDirty(Node* node) {
    Edge* edge = node->in_edge;

    // Base case: leaf node (source file)
    if (!edge) {
        node->Stat();  // Get mtime from disk
        node->dirty = !node->exists();
        return true;
    }

    // Recursive case: check inputs
    TimeStamp output_mtime = node->Stat();
    TimeStamp newest_input = 0;

    for (Node* input : edge->inputs) {
        RecomputeNodeDirty(input);  // Recurse
        newest_input = max(newest_input, input->mtime);
    }

    // Dirty if: output missing OR input newer OR input dirty
    node->dirty = (output_mtime == 0) ||
                  (newest_input > output_mtime) ||
                  any_input_dirty;

    edge->outputs_ready = !node->dirty;
    return true;
}
```

**Key insight**: Postorder DFS traversal
- Visits inputs before outputs
- Propagates dirty state upward

## BUILD EXECUTION

**From**: `build.cc:80` `Plan` and `Builder`

### Plan (build.h:41)
```cpp
struct Plan {
    map<Edge*, Want> want_;    // Want state per edge
    EdgePriorityQueue ready_;  // Ready to execute
    int wanted_edges_;         // Total edges needed
};

enum Want { kWantNothing, kWantToStart, kWantToFinish };
```

### Algorithm (build.cc:93)
```cpp
// 1. Add target to plan
bool AddTarget(Node* target) {
    Edge* edge = target->in_edge;
    if (!edge || !target->dirty) return false;

    // Mark edge wanted
    want_[edge] = kWantToStart;
    wanted_edges_++;

    // Recursively add input edges
    for (Node* input : edge->inputs)
        AddTarget(input);

    return true;
}

// 2. Schedule ready edges
void ScheduleInitialEdges() {
    for (auto& [edge, want] : want_) {
        if (want == kWantToStart && AllInputsReady(edge)) {
            ready_.push(edge);
            want = kWantToFinish;
        }
    }
}

// 3. Execute loop
while (!ready_.empty()) {
    Edge* edge = ready_.top();
    ready_.pop();

    ExecuteCommand(edge);  // Run shell command

    // Mark outputs ready
    edge->outputs_ready = true;

    // Check if any dependent edges became ready
    for (Node* output : edge->outputs) {
        for (Edge* out_edge : output->out_edges) {
            if (AllInputsReady(out_edge))
                ready_.push(out_edge);
        }
    }
}
```

**Execution order**: Determined by `EdgePriorityQueue`
- Priority = `critical_path_weight` (longest chain to target)
- Computed via topological sort with max-path weights

## CRITICAL PATH SCHEDULING

**From**: `build.cc:462` `Plan::ComputeCriticalPath`

```cpp
// Compute weight = max(input_weights) + this_edge_time
void ComputeCriticalPath() {
    // Topological sort: process edges in dependency order
    for (Edge* edge : topological_order) {
        int64_t max_input_weight = 0;

        for (Node* input : edge->inputs) {
            if (input->in_edge)
                max_input_weight = max(max_input_weight,
                                      input->in_edge->critical_path_weight);
        }

        edge->critical_path_weight = max_input_weight + edge->prev_elapsed_time;
    }
}
```

**Purpose**: Schedule longest chains first to minimize total build time

## KEY NINJA ALGORITHMS SUMMARY

1. **Graph Construction**: Hash-map-based node deduplication
2. **Dirty Detection**: Recursive mtime comparison (DFS postorder)
3. **Execution Planning**: Topological sort + critical path priority
4. **Incremental Builds**: Only rebuild dirty subgraph
5. **Parallelism**: Ready queue + max parallelism limit

## MININJA SIMPLIFICATIONS

What was stripped from full Ninja:

- ❌ Pools (concurrency limiting)
- ❌ Phony rules
- ❌ Depfiles (.d files for header deps)
- ❌ Dyndep (dynamic dependencies)
- ❌ Build log (.ninja_log for timestamps)
- ❌ Manifest parser (build.ninja DSL)
- ❌ Critical path computation
- ❌ Parallel execution
- ❌ Progress display
- ❌ Error recovery

What remains:
- ✅ Core Node/Edge graph
- ✅ Dirty propagation via mtime
- ✅ Topological execution order
- ✅ Incremental builds
