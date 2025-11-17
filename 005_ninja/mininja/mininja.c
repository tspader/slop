// MINIMAL NINJA - Build graph executor using sp.h
// Distilled from ninja/src/{graph.h,state.h,build.h,graph.cc,build.cc}

#include "sp.h"
#include <sys/stat.h>

// ============================================================================
// CORE DATA STRUCTURES (ninja/src/graph.h:42,175 + state.h:95)
// ============================================================================

typedef s64 timestamp_t;  // mtime: -1=unknown, 0=missing, >0=exists

typedef struct node_t node_t;
typedef struct edge_t edge_t;

struct node_t {
  sp_str_t path;
  timestamp_t mtime;
  bool dirty;
  edge_t* in_edge;           // edge producing this node (NULL for sources)
  sp_da(edge_t*) out_edges;  // edges consuming this node
};

struct edge_t {
  sp_str_t command;
  sp_da(node_t*) inputs;
  sp_da(node_t*) outputs;
  bool outputs_ready;        // all outputs up-to-date
};

typedef struct {
  sp_ht(sp_str_t, node_t*) nodes;  // path -> node lookup
  sp_da(edge_t*) edges;
} state_t;

typedef struct {
  sp_da(edge_t*) ready;
  sp_da(edge_t*) pending;
} plan_t;

// ============================================================================
// NODE OPERATIONS (ninja/src/graph.cc:33)
// ============================================================================

node_t* node_create(sp_str_t path) {
  node_t* n = (node_t*)sp_alloc(sizeof(node_t));
  *n = SP_ZERO_STRUCT(node_t);
  n->path = sp_str_copy(path);
  n->mtime = -1;
  return n;
}

timestamp_t node_stat(node_t* n) {
  if (n->mtime != -1) return n->mtime;

  const c8* cpath = sp_str_to_cstr(n->path);
  struct stat st;
  if (stat(cpath, &st) == 0) {
    n->mtime = (timestamp_t)st.st_mtime * 1000000000LL;
  } else {
    n->mtime = 0;
  }
  return n->mtime;
}

// ============================================================================
// EDGE OPERATIONS (ninja/src/graph.h:175,185)
// ============================================================================

edge_t* edge_create(sp_str_t command) {
  edge_t* e = (edge_t*)sp_alloc(sizeof(edge_t));
  *e = SP_ZERO_STRUCT(edge_t);
  e->command = sp_str_copy(command);
  return e;
}

void edge_add_input(edge_t* e, node_t* n) {
  sp_dyn_array_push(e->inputs, n);
  sp_dyn_array_push(n->out_edges, e);
}

void edge_add_output(edge_t* e, node_t* n) {
  sp_dyn_array_push(e->outputs, n);
  n->in_edge = e;
}

bool edge_all_inputs_ready(edge_t* e) {
  sp_dyn_array_for(e->inputs, i) {
    node_t* input = e->inputs[i];
    if (input->in_edge && !input->in_edge->outputs_ready)
      return false;
  }
  return true;
}

// ============================================================================
// STATE OPERATIONS (ninja/src/state.cc)
// ============================================================================

state_t* state_create(void) {
  state_t* s = (state_t*)sp_alloc(sizeof(state_t));
  *s = SP_ZERO_STRUCT(state_t);
  sp_ht_set_fns(s->nodes, sp_ht_on_hash_str_key, sp_ht_on_compare_str_key);
  return s;
}

node_t* state_get_node(state_t* s, sp_str_t path) {
  node_t** existing = sp_ht_getp(s->nodes, path);
  if (existing) return *existing;

  node_t* n = node_create(path);
  sp_ht_insert(s->nodes, path, n);
  return n;
}

void state_add_edge(state_t* s, edge_t* e) {
  sp_dyn_array_push(s->edges, e);
}

// ============================================================================
// DIRTY SCANNING (ninja/src/graph.cc:48 DependencyScan::RecomputeDirty)
// ============================================================================

bool recompute_dirty(node_t* node) {
  edge_t* edge = node->in_edge;

  // Leaf node (source file): dirty if missing
  if (!edge) {
    node_stat(node);
    node->dirty = (node->mtime == 0);
    return true;
  }

  // Get output mtime
  timestamp_t output_mtime = node_stat(node);

  // Recursively check all inputs
  timestamp_t newest_input = 0;
  sp_dyn_array_for(edge->inputs, i) {
    if (!recompute_dirty(edge->inputs[i])) return false;

    timestamp_t input_mtime = edge->inputs[i]->mtime;
    if (input_mtime > newest_input)
      newest_input = input_mtime;
  }

  // Dirty if: output missing OR input newer OR input dirty
  node->dirty = (output_mtime == 0) || (newest_input > output_mtime);
  sp_dyn_array_for(edge->inputs, i) {
    if (edge->inputs[i]->dirty) {
      node->dirty = true;
      break;
    }
  }

  edge->outputs_ready = !node->dirty;
  return true;
}

// ============================================================================
// BUILD EXECUTION (ninja/src/build.cc:80 Plan + Builder)
// ============================================================================

plan_t* plan_create(void) {
  plan_t* p = (plan_t*)sp_alloc(sizeof(plan_t));
  *p = SP_ZERO_STRUCT(plan_t);
  return p;
}

void plan_add_edge(plan_t* plan, edge_t* edge) {
  // Check if any output is dirty
  bool dirty = false;
  sp_dyn_array_for(edge->outputs, i) {
    if (edge->outputs[i]->dirty) {
      dirty = true;
      break;
    }
  }

  if (!dirty) {
    edge->outputs_ready = true;
    return;
  }

  // Add to ready or pending
  if (edge_all_inputs_ready(edge)) {
    sp_dyn_array_push(plan->ready, edge);
  } else {
    sp_dyn_array_push(plan->pending, edge);
  }
}

void plan_update_ready(plan_t* plan) {
  sp_da(edge_t*) new_pending = SP_NULLPTR;

  sp_dyn_array_for(plan->pending, i) {
    edge_t* edge = plan->pending[i];
    if (edge_all_inputs_ready(edge)) {
      sp_dyn_array_push(plan->ready, edge);
    } else {
      sp_dyn_array_push(new_pending, edge);
    }
  }

  plan->pending = new_pending;
}

bool execute_edge(edge_t* edge) {
  SP_LOG("[BUILD] {}", SP_FMT_STR(edge->command));

  const c8* cmd = sp_str_to_cstr(edge->command);
  s32 ret = system(cmd);
  if (ret != 0) {
    SP_LOG("{:color red}: {}", SP_FMT_CSTR("FAILED"), SP_FMT_STR(edge->command));
    return false;
  }

  edge->outputs_ready = true;

  // Update output mtimes
  sp_dyn_array_for(edge->outputs, i) {
    edge->outputs[i]->mtime = -1;  // force re-stat
    node_stat(edge->outputs[i]);
  }

  return true;
}

bool build(state_t* s, node_t* target) {
  // 1. Recompute dirty state (ninja/src/graph.cc:48)
  SP_LOG("[SCAN] Checking dependencies...");
  if (!recompute_dirty(target)) {
    SP_LOG("{:color red}: Failed to scan dependencies", SP_FMT_CSTR("ERROR"));
    return false;
  }

  if (!target->dirty) {
    SP_LOG("[DONE] Target '{}' is up to date", SP_FMT_STR(target->path));
    return true;
  }

  // 2. Build plan: collect dirty edges (ninja/src/build.cc:93)
  plan_t* plan = plan_create();

  sp_dyn_array_for(s->edges, i) {
    plan_add_edge(plan, s->edges[i]);
  }

  // 3. Execute ready edges (ninja/src/build.cc:160)
  u32 total_built = 0;
  while (sp_dyn_array_size(plan->ready) > 0) {
    // Pop edge from ready queue
    edge_t* edge = plan->ready[sp_dyn_array_size(plan->ready) - 1];
    sp_dyn_array_pop(plan->ready);

    if (!execute_edge(edge)) {
      return false;
    }
    total_built++;

    // Check if any pending edges became ready
    plan_update_ready(plan);
  }

  u32 pending_count = sp_dyn_array_size(plan->pending);
  if (pending_count > 0) {
    SP_LOG("{:color red}: {} edges still pending (circular dependency?)",
           SP_FMT_CSTR("ERROR"), SP_FMT_U32(pending_count));
    return false;
  }

  SP_LOG("[DONE] Built {} targets", SP_FMT_U32(total_built));
  return true;
}

// ============================================================================
// PARSING
// ============================================================================

bool parse_build_file(state_t* s, sp_str_t path, node_t** out_target) {
  sp_str_t content = sp_io_read_file(path);
  if (sp_str_empty(content)) {
    SP_LOG("{:color red}: Failed to read build file: {}",
           SP_FMT_CSTR("ERROR"), SP_FMT_STR(path));
    return false;
  }

  sp_da(sp_str_t) lines = sp_str_split_c8(content, '\n');
  node_t* last_target = SP_NULLPTR;

  sp_dyn_array_for(lines, line_idx) {
    sp_str_t line = lines[line_idx];
    line = sp_str_trim(line);

    // Skip comments and blank lines
    if (sp_str_empty(line) || sp_str_at(line, 0) == '#') continue;

    // Parse: output: input1 input2 | command
    if (!sp_str_contains(line, SP_LIT(":"))) continue;
    if (!sp_str_contains(line, SP_LIT("|"))) continue;

    sp_str_pair_t output_rest = sp_str_cleave_c8(line, ':');
    sp_str_pair_t inputs_command = sp_str_cleave_c8(output_rest.second, '|');

    sp_str_t output_str = sp_str_trim(output_rest.first);
    sp_str_t inputs_str = sp_str_trim(inputs_command.first);
    sp_str_t command_str = sp_str_trim(inputs_command.second);

    if (sp_str_empty(output_str) || sp_str_empty(command_str)) continue;

    // Create edge
    edge_t* edge = edge_create(command_str);

    // Add output
    node_t* output = state_get_node(s, output_str);
    edge_add_output(edge, output);
    last_target = output;

    // Add inputs
    sp_da(sp_str_t) input_tokens = sp_str_split_c8(inputs_str, ' ');
    sp_dyn_array_for(input_tokens, input_idx) {
      sp_str_t input = sp_str_trim(input_tokens[input_idx]);
      if (!sp_str_empty(input)) {
        node_t* input_node = state_get_node(s, input);
        edge_add_input(edge, input_node);
      }
    }

    state_add_edge(s, edge);
  }

  *out_target = last_target;
  return last_target != SP_NULLPTR;
}

// ============================================================================
// MAIN
// ============================================================================

s32 main(s32 argc, c8** argv) {
  if (argc < 2) {
    SP_LOG("{:color red}: Usage: {} <build_file>",
           SP_FMT_CSTR("ERROR"), SP_FMT_CSTR(argv[0]));
    return 1;
  }

  state_t* state = state_create();
  node_t* target = SP_NULLPTR;

  sp_str_t build_file = sp_str_view(argv[1]);
  if (!parse_build_file(state, build_file, &target)) {
    SP_LOG("{:color red}: No targets in build file", SP_FMT_CSTR("ERROR"));
    return 1;
  }

  SP_LOG("[TARGET] {}", SP_FMT_STR(target->path));
  return build(state, target) ? 0 : 1;
}
