# MININJA - Minimal Ninja Build System Clone

Minimal plain C implementation distilling Ninja's core build graph algorithms.
Written in **sp.h style** (tspader/sp conventions).

## BUILD

```bash
gcc -o mininja mininja.c -DSP_IMPLEMENTATION
```

## USAGE

```bash
./mininja <build_file>
```

**Build file format** (simplified):
```
output: input1 input2 | command
```

Example:
```
# Build C program
main.o: main.c | gcc -c -o main.o main.c
prog: main.o | gcc -o prog main.o
```

## TESTS

```bash
./run_tests.sh
```

### Test 1: Simple
Single C file → executable

### Test 2: Medium
3 C files → object files → executable
Demonstrates incremental rebuild

### Test 3: Complex
100 C files in deep dependency chain
func_99 → func_98 → ... → func_0

## ARCHITECTURE

See `ARCHITECTURE.md` for detailed breakdown of:
- Core data structures (Node, Edge, State)
- Graph construction algorithm
- Dirty checking via mtime propagation
- Build execution order

## KEY CONCEPTS FROM NINJA

### Node
File in dependency graph
- `path`: File path
- `mtime`: Modification time (-1=unknown, 0=missing, >0=exists)
- `dirty`: Needs rebuild
- `in_edge`: Edge that produces this file
- `out_edges[]`: Edges that consume this file

### Edge
Build command
- `command`: Shell command to execute
- `inputs[]`: Input files
- `outputs[]`: Output files
- `outputs_ready`: All outputs up-to-date

### Dirty Propagation
```
1. Stat all files (get mtime)
2. DFS from target node
3. Mark dirty if:
   - Output missing
   - Input newer than output
   - Any input dirty
4. Build only dirty subgraph
```

### Execution Order
```
1. Build ready queue (inputs satisfied)
2. Pop edge from queue
3. Execute command
4. Mark outputs ready
5. Check dependents → add newly ready edges
6. Repeat until queue empty
```

## WHAT'S STRIPPED

Full Ninja has:
- Manifest parser (build.ninja DSL)
- Pools (concurrency limits)
- Phony rules
- Depfiles (header dependency scanning)
- Build log (persistent timestamps)
- Critical path scheduling
- Parallel execution
- Status display

Mininja keeps:
- Core graph structure
- Mtime-based dirty checking
- Topological execution
- Incremental builds

**Purpose**: Educational - understand Ninja's algorithm at its simplest.

## FILE LAYOUT

```
mininja/
├── mininja.c           # 400 lines - complete implementation
├── run_tests.sh        # Test runner
├── ARCHITECTURE.md     # Algorithm deep-dive
├── README.md           # This file
└── tests/
    ├── simple/         # 1 file
    ├── medium/         # 3 files
    └── complex/        # 100 files (generated)
```

## IMPLEMENTATION NOTES

**Style**: Uses sp.h properly
- Types: `s32`/`u32`/`c8`/`sp_str_t` (NO C strings)
- Containers: `sp_da(T)` for dynamic arrays, `sp_ht(K,V)` for hash maps
- Strings: `sp_str_t` everywhere, `sp_str_split_c8()`, `sp_str_trim()`
- I/O: `sp_io_read_file()` instead of `FILE*`
- Logging: `SP_LOG()` instead of `printf`
- Memory: `sp_alloc()` only, data structures handle growth

**Graph storage**: `sp_ht(sp_str_t, node_t*)` (real Ninja uses custom hash map)
**Execution**: Sequential (real Ninja parallelizes)
**Scheduling**: FIFO queue (real Ninja uses critical path priority queue)

**Lines of code**:
- mininja.c: 358 LOC
- ninja src/: ~50,000 LOC

**Compression ratio**: 140x smaller
