# Build Tool Architecture Analysis

## SPN (C Package Manager)

### Data Model
**Core Structures:**
- `spn_package_t`: Package metadata (name, version, deps, bins, libs)
- `spn_lock_file_t`: Dependency resolution state
- `spn_dep_context_t`: Per-dependency build context
- `spn_app_t`: Global application state
- Hash tables for deps/bins, dynamic arrays for versions/includes

**Characteristics:**
- Flat, imperative structures
- No complex inheritance or abstractions
- Direct field access throughout

### Disk I/O
**Read:** TOML parser (embedded toml.h) reads spn.toml + spn.lock
- `spn_toml_parse()` → toml_table_t → populate spn_package_t structures
- Lock file: `spn_load_lock_file()` at spn.c:2867

**Write:** Custom TOML writer with stack-based context tracking
- `spn_toml_writer_t` builds TOML incrementally
- Lock file: `spn_app_update_lock_file()` at spn.c:4180-4196
- Manifest: `spn_app_write_manifest()` at spn.c:4199-4331

**Transform:** TOML → structs → TOML (roundtrip via serialization)

### Command Handling
**Dispatch:** Simple string comparison in `spn_cli_run()` (spn.c:5181-5223)
- No command registry or dynamic dispatch
- Each command: separate function (spn_cli_build, spn_cli_add, etc)

**Partial Loading:**
- Always loads full manifest on startup
- Lock file loaded in full for any command that needs deps
- No lazy loading or incremental parsing
- No command-specific data filtering

### Architecture Trace: `spn build`
```
main() (6008)
  → spn_init() - parse args, load config
  → spn_cli_run() (5181)
    → strcmp("build") → spn_cli_build() (5869)
      → spn_cli_parse_command() - parse flags
      → spn_app_resolve() - load manifest + lock
        → spn_package_load() → spn_toml_parse()
        → spn_load_lock_file() (2867) → parse lock TOML
      → spn_app_prepare_deps() - resolve dep graph
      → spawn threads: spn_dep_thread_build() for each dep
        → spn_dep_context_build() (3628)
          → git clone/fetch/checkout if needed
          → execute on_configure callback (TCC compilation)
          → execute on_build callback
          → spn_dep_context_stamp() - write stamp file
      → spn_dep_context_build(&build) - build project itself
        → spn_cc_new() - init compiler context (uses TCC)
        → spn_cc_run() - compile
      → spn_app_update_lock_file() (4175) - write lock
        → spn_toml_writer_new()
        → iterate deps, append entries
        → sp_io_write_str() to disk
```

### Data Robustness

**Strengths:**
- Simple, transparent data model
- TOML is human-readable and version-control friendly
- Lock file provides reproducible builds

**Weaknesses:**
- No schema validation of TOML
- Error handling via SP_FATAL() macros - aborts on error
- No transactional writes (lock file could corrupt on crash)
- State scattered across: manifest, lock, git repos, stamp files, logs
- Build state lives in file system, not in memory structures

**State Clarity:** Medium
- Easy to inspect manifest/lock files manually
- Hard to reason about overall build state (distributed across filesystem)
- Stamp files determine "already built" (spn_dep_context_is_build_stamped)

**Extensibility:** Low
- Single-file monolith (6015 lines)
- No plugin system
- Adding commands requires editing main dispatch
- Tight coupling to TCC for compilation

**Error Resistance:** Low
- Liberal use of assertions/fatals
- No graceful degradation
- Concurrent dep builds use threads but minimal synchronization
- Partial state possible if interrupted

---

## TCC (Tiny C Compiler)

### Data Model
**Core Structure:** `TCCState` (tcc.h:738-1087) - monolithic compilation state

**Key Fields:**
- Config flags (80+ bitfields for options)
- Path arrays: include_paths, library_paths, crt_paths
- Section array: text_section, data_section, symtab_section, etc.
- Symbol tables: BufferedFile stack for includes
- Parser state: token stack, preprocessor state
- Code generation: current function, local variables
- Runtime: relocation data, dynamic linking info

**Characteristics:**
- Flat structure, ~350 fields
- State machine encoded in bitfields + pointers
- Everything reachable from single TCCState*

### Pipeline Architecture

**1. Initialization:**
```c
tcc_new()                    // libtcc.c:1240
  → tcc_state_new()
  → init default paths/options
```

**2. Configuration:**
```c
tcc_set_output_type()       // Set: memory/exe/dll/obj
tcc_add_include_path()      // Build include search path
tcc_add_library_path()      // Build lib search path
tcc_define_symbol()         // Preprocessor defines
```

**3. Compilation:**
```c
tcc_add_file()              // libtcc.c:1385
  → tcc_compile()
    → set_idnum(s)          // Init token/sym IDs
    → tccelf_begin_file()   // Start ELF section mgmt
    → tccpp_new()           // Init preprocessor
    → next()                // Get first token
    → translation_unit()    // tccgen.c:6840 - parse/codegen
      → external_decl()     // Parse declarations
        → decl()            // Variable/function decls
        → gen_function()    // For functions (tccgen.c:6275)
          → gen_block()     // Statement codegen
            → [x86_64-gen.c] - emit machine code to sections
    → tccpp_delete()
    → tccelf_end_file()
```

**4. Linking:**
```c
// For TCC_OUTPUT_MEMORY:
tcc_relocate()               // libtcc.c:1607
  → relocate_init()
  → tcc_relocate_ex(s, mem, size)
    → tidy_section_headers() // Merge/align sections
    → alloc_sec_names()
    → layout_sections()      // Compute offsets
    → fill_got_and_plt()     // GOT/PLT for dynamic libs
    → bind_exe_dynsyms()     // Resolve external symbols
    → relocate_syms()        // Apply relocations
    → relocate_sections()    // Patch code/data

tcc_get_symbol()             // libtcc.c:1666
  → lookup in symtab_section → return address
```

**5. Execution (Memory Mode):**
```c
int (*func)() = tcc_get_symbol(s, "main");
func();  // Direct call to JIT'd code in memory
```

### Disk I/O
**Read:**
- Source files: `tcc_compile_string()` or `tcc_add_file()`
- Include files: Buffered I/O (BufferedFile* stack)
- Libraries: `tcc_add_library()` → dlopen() for shared libs
- Object files: Read ELF/COFF sections into TCCState sections

**Write:**
- Object/exe output: `tcc_output_file()` → `tccelf_output_file()`
- Writes ELF/PE binary with sections/symbols/relocations
- No persistent cache or incremental state

**Transform:**
C source → tokens → AST (implicit) → machine code → sections → executable/memory

### Data Robustness

**Strengths:**
- Single ownership model (TCCState owns everything)
- Deterministic compilation (no hidden state)
- Clear pipeline: source → tokens → code → binary
- Memory mode eliminates disk artifacts

**Weaknesses:**
- No incremental compilation (full recompile every time)
- Limited error recovery (setjmp/longjmp on errors)
- Section management complex (60+ section types)
- Relocation done in-place (modifies structures during link)

**State Clarity:** High during compilation, Medium during linking
- Compilation phase: clear token stream → codegen
- Linking phase: complex section merging/relocation
- At any point, can dump sections/symbols for inspection

**Extensibility:** Medium
- Can add new targets (see arm-gen.c, x86_64-gen.c)
- Preprocessor/parser are modular
- Codegen tied to ELF/PE formats
- No plugin system

**Error Resistance:** Medium
- Error callback mechanism for custom handlers
- Uses setjmp/longjmp for error unwinding
- On error, entire TCCState is invalid (must recreate)
- No partial compilation results

### TCC Memory Execution Trace
```c
// User code:
TCCState *s = tcc_new();
tcc_set_output_type(s, TCC_OUTPUT_MEMORY);
tcc_add_file(s, "hello.c");
tcc_add_library(s, "curl");
tcc_relocate(s);
void *sym = tcc_get_symbol(s, "main");
((int(*)())sym)();

// Internal flow:
tcc_add_file("hello.c")
  → file_type = AFF_TYPE_C
  → tcc_compile(s, 0)
    → BufferedFile *bf = tcc_open(s, "hello.c")
    → set_idnum(s)
    → tccpp_new(s)
    → next()           // prime token stream
    → translation_unit(s, 0)  // tccgen.c:6840
      → while tok != TOK_EOF:
          external_decl(s)
            → parse 'int main()'
            → gen_function(main_sym)  // tccgen.c:6275
              → gfunc_prolog()    // x86_64-gen.c
              → gen_block()       // parse body
                → [printf call]
                  → gfunc_call()  // emit call insn
              → gfunc_epilog()    // ret insn
              → [machine code written to text_section->data]

tcc_add_library("curl")
  → tcc_add_dll(s, "libcurl.so", 0)
    → tcc_add_file_internal(s, "libcurl.so", AFF_TYPE_LIB)
      → tcc_load_dll(s, fd, "libcurl.so", LD_TOK_NAME)
        → dlopen("libcurl.so")
        → create DLLReference, store handle

tcc_relocate(s)
  → relocate_init(s)
  → size = tcc_relocate_ex(s, NULL, 0)  // get size
  → mem = alloc(size)
  → tcc_relocate_ex(s, mem, size)       // do relocation
    → layout_sections(s, mem)
      text_section → mem+0
      data_section → mem+text_size
      ...
    → bind_exe_dynsyms(s)
      → for each DLLReference:
          tcc_get_symbol(ref, "curl_easy_init")
            → dlsym(dll_handle, "curl_easy_init")
            → store address in symtab
    → relocate_syms(s, ...)
      → walk symtab, assign addresses
    → relocate_sections(s, rel)
      → for each relocation entry:
          patch code at offset with symbol address
          [e.g., call curl_easy_init becomes:
           call <dlsym-resolved-address>]

tcc_get_symbol(s, "main")
  → find_elf_sym(symtab, "main")
  → return sym->st_value  // address in allocated memory

// Execute:
int (*main_func)() = (void*)sym_address;
main_func();
  → CPU jumps to JIT'd code in memory
  → executes x86_64 instructions
  → calls dlsym-resolved curl functions
```

**Key Transformations:**
1. **Lexing**: C source → token stream (tccpp.c)
2. **Parsing/Codegen**: tokens → machine code in sections (tccgen.c + x86_64-gen.c)
3. **Linking**: sections → linear memory layout (tccelf.c)
4. **Symbol Resolution**: external refs → absolute addresses via dlsym
5. **Relocation**: patch call/jmp instructions with resolved addresses
6. **Execution**: function pointer → direct CPU execution

**Data State at Each Stage:**
- **Post-compile**: Sections with machine code + unresolved relocations
- **Post-link**: Continuous memory block with patched code
- **Runtime**: CPU executes from memory, calls into shared libs

---

## Ninja

### Data Model
**Core Structures:**

**State** (state.h:95-142): Global build graph
```cpp
struct State {
  Paths paths_;              // path → Node*
  vector<Edge*> edges_;      // all edges
  map<string, Pool*> pools_; // execution pools
  BindingEnv bindings_;      // variables
  vector<Node*> defaults_;   // default targets
};
```

**Node** (graph.h): File/phony target
```cpp
struct Node {
  string path_;
  TimeStamp mtime_;           // from disk
  Edge* in_edge_;             // edge that produces this
  vector<Edge*> out_edges_;   // edges that use this
  bool dirty_;                // needs rebuild?
  int id_;                    // for stable ordering
};
```

**Edge** (graph.h): Build command
```cpp
struct Edge {
  const Rule* rule_;          // how to build
  Pool* pool_;                // execution pool
  vector<Node*> inputs_;
  vector<Node*> outputs_;
  string command_;            // resolved from rule
  bool outputs_ready_;
  bool deps_loaded_;
};
```

**Plan** (build.h:41-143): Build execution state
```cpp
struct Plan {
  map<Edge*, Want> want_;     // which edges to build
  EdgePriorityQueue ready_;   // ready to execute
  int wanted_edges_;
  int command_edges_;
};
```

**Characteristics:**
- Pointer-based graph (nodes ↔ edges)
- Separation of concerns: State (graph), Plan (execution), Builder (orchestration)
- Nodes own lifetime (State::paths_ is source of truth)
- Topological relationships explicit (in_edge, out_edges)

### Disk I/O

**Read:** build.ninja manifest
```cpp
manifest_parser.cc:
  ManifestParser::Load()
    → Lexer tokenizes input
    → Parser builds State incrementally:
      ParseRule() → adds Rule to State::bindings_
      ParseEdge() → State::AddEdge()
        → State::AddIn/AddOut() creates Nodes
        → Nodes added to State::paths_
```

**Persistent State:**
- `.ninja_log`: Build log (timestamps, commands run)
  ```cpp
  BuildLog::Load() → map<path, BuildLog::Entry>
  BuildLog::Entry { start_time, end_time, mtime, command_hash }
  ```
- `.ninja_deps`: Dependency log (header deps from -M)
  ```cpp
  DepsLog::Load() → map<Node*, vector<Node*>>
  Records per-target header dependencies
  ```

**Write:**
- `.ninja_log`: Appended after each edge completes
- `.ninja_deps`: Written incrementally (mmap'd)

**Transform:**
build.ninja → State (graph) → dirty edges → Plan → execute → log results

### Execution Trace: `ninja target`

```cpp
main()  // ninja.cc
  → NinjaMain::RunBuild()
    // 1. Load manifest
    → ManifestParser::Load("build.ninja", &state, &err)
      → for each line:
        ParseRule/ParseEdge/ParseDefault
          → state.AddEdge(rule)
            → Edge* e = new Edge()
            → e->rule_ = rule
            → state.edges_.push_back(e)
          → state.AddIn(edge, "input.cc")
            → Node* n = state.GetNode("input.cc")
              [GetNode checks paths_, creates if new]
            → edge->inputs_.push_back(n)
            → n->out_edges_.push_back(edge)
          → state.AddOut(edge, "output.o")
            → Node* n = state.GetNode("output.o")
            → edge->outputs_.push_back(n)
            → n->in_edge_ = edge

    // 2. Load logs
    → BuildLog::Load(".ninja_log")
      [map<output_path, {mtime, command_hash}>]
    → DepsLog::Load(".ninja_deps")
      [map<Node*, vector<Node*>>]

    // 3. Build plan
    → Builder builder(&state, config, &build_log, &deps_log)
    → Plan plan(&builder)
    → Node* target = state.LookupNode("target")
    → plan.AddTarget(target, &err)
      → AddSubTarget(target, ...)
        → DependencyScan::RecomputeDirty(target, &err)
          → stat(target->path_) → node->mtime_
          → for each input:
              RecomputeDirty(input)
          → node->dirty_ = (NeedRecompile(edge))
            [compares mtimes, checks command hash]
        → if target->in_edge_:
            plan.want_[target->in_edge_] = kWantToStart
            EdgeWanted(target->in_edge_)
              → command_edges_++
              → wanted_edges_++
        → for each dep edge recursively

    → plan.PrepareQueue()
      → ComputeCriticalPath()
      → ScheduleInitialEdges()
        → for (edge, want) where want==kWantToStart:
            if inputs ready: ready_.push(edge)

    // 4. Execute
    → while plan.more_to_do():
        → Edge* edge = plan.FindWork()
          [pop from ready_ priority queue]
        → builder.StartEdge(edge)
          → compute command from rule + bindings
          → command_runner->StartCommand(edge)
            → subprocess.Start(command)
              [fork/exec on POSIX]

        → command_runner->WaitForCommand()
          [poll for subprocess completion]

        → plan.EdgeFinished(edge, result)
          → build_log_.RecordCommand(edge)
            [append to .ninja_log]
          → deps_log_.RecordDeps(edge)
            [write to .ninja_deps]
          → for each output:
              NodeFinished(output)
                → for each out_edge of output:
                    if all inputs ready:
                      ready_.push(out_edge)
```

**Data Flow:**
1. **Parse phase**: text → State graph
   - Nodes created on-demand in paths_
   - Edges link to nodes via pointers
2. **Scan phase**: State + disk → dirty flags
   - stat() each node → mtime_
   - Compare input/output mtimes
   - Check command hash vs log
3. **Plan phase**: dirty edges → ready queue
   - Topological sort via want_ map
   - Critical path priority
4. **Execute phase**: ready queue → subprocesses
   - Pop edge, run command, log, propagate ready
5. **Log phase**: results → .ninja_log

**Key Transformations:**
- `build.ninja` → in-memory graph (parse)
- Graph + filesystem → dirty bits (scan)
- Dirty bits → execution plan (plan)
- Plan → subprocesses → updated logs (execute)

### Data Robustness

**Strengths:**
- **Clear ownership**: State owns nodes/edges, Plan owns build state
- **Immutable graph**: Build doesn't modify State structure
- **Explicit dirty tracking**: dirty_ flags, not inferred
- **Stable persistent logs**: Binary format, append-only
- **Separation of concerns**:
  - State: graph structure
  - DependencyScan: dirty computation
  - Plan: execution scheduling
  - Builder: subprocess management

**Weaknesses:**
- **Pointer validity**: Manual lifetime management (no shared_ptr in older C++)
- **Global state**: Single State instance
- **Log corruption**: Binary logs not crash-safe (not transactional)
- **No incremental parse**: Full manifest re-parse on every run
- **Implicit deps**: Header deps loaded from separate log, not in graph

**State Clarity:** High
- Graph structure explicit and inspectable
- Dirty state cleanly separated (dirty_ flag)
- Want state tracked in Plan (kWantNothing/ToStart/ToFinish)
- Easy to dump: `state.Dump()`, `plan.Dump()`

**Extensibility:** Medium
- New rules: just manifest changes (no code)
- New generators: rules emit build.ninja
- Build system integration: link against libninja (not primary use)
- Adding features: C++ code changes required

**Error Resistance:** Medium-High
- Graceful command failures (continues if independent)
- Errors don't corrupt graph (immutable)
- Log append failures → build continues (just not recorded)
- Manifest parse errors → clean exit with message

**Partial Loading:** Yes (logs), No (manifest)
- Manifest always fully parsed
- Build log: only entries for touched nodes
- Deps log: mmap'd, pages loaded on-access
- Graph: always full in memory (no streaming)

---

## Comparison Summary

| Criterion | SPN | TCC | Ninja |
|-----------|-----|-----|-------|
| **Data Model Clarity** | Medium (flat structs, scattered state) | High (single TCCState) | High (explicit graph) |
| **State Predictability** | Low (filesystem-dependent) | High (in-memory only) | High (dirty flags explicit) |
| **Disk I/O Strategy** | TOML read/write | Source read, binary write | Manifest parse, log append |
| **Partial Loading** | No | N/A (stateless) | Yes (logs only) |
| **Robustness** | Low (aborts on error) | Medium (setjmp recovery) | High (graceful failures) |
| **Extensibility** | Low (monolith) | Medium (target arch) | High (rule-based) |
| **Error Resistance** | Low (fatals) | Medium (clean restart) | High (isolated failures) |
| **Ease of Reasoning** | Medium (simple model, complex state) | High (clear pipeline) | High (explicit graph) |
| **Concurrency** | Medium (threads, weak sync) | None | High (process-based) |

### Architectural Philosophy

**SPN:** Procedural, file-system-as-database, TCC-integrated
- State distributed across git repos, TOML, stamp files
- Errors are fatal (fail-fast)
- Build through callbacks executed by TCC

**TCC:** Single-pass, in-memory, stateless between runs
- No persistent state (recompile every time)
- Clean ownership (TCCState owns all)
- Error recovery via longjmp (nuclear)

**Ninja:** Declarative graph, explicit state machine, persistent logs
- State clearly separated: graph vs execution
- Robust to partial failures
- Optimized for incremental rebuilds

### Judgment on Data Model Quality

**For Reliability:** Ninja > TCC > SPN
- Ninja's explicit graph + dirty tracking is most robust
- TCC's stateless model prevents corruption but wastes work
- SPN's distributed state is fragile

**For Simplicity:** TCC > SPN > Ninja
- TCC: single struct, clear pipeline
- SPN: flat structs, but state scattered
- Ninja: pointer graph requires careful reasoning

**For Performance:** Ninja >> SPN > TCC
- Ninja: incremental, parallelizable
- SPN: caches builds, but weak incrementalism
- TCC: full recompile every time (but fast)

**For Correctness:** Ninja > TCC > SPN
- Ninja: explicit dependencies, reproducible
- TCC: deterministic (same input → same output)
- SPN: git refs + stamps can drift

**Overall Winner:** **Ninja**
- Best data model for a build system
- Clear separation of concerns
- Robust to errors
- Scales well
