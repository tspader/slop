# glibc 2.17 Build

Glibc 2.17 (released 2012-12-25) successfully built using GCC 4.9 from Ubuntu 14.04 archives.

## Requirements

glibc 2.17 configure script requires:
- GCC 4.3 through 4.9
- GNU Make 3.79 through 3.89 (patched to accept Make 4.x)

## Successful Build Approach

### Using Pre-built GCC 4.9 from Ubuntu Archives

1. **Install GCC 4.9**:
   ```bash
   ./setup-gcc49.sh
   ```
   This downloads and installs GCC 4.9.3 from Ubuntu 14.04 archives to `/opt/gcc49`

2. **Build glibc 2.17**:
   ```bash
   ./build.sh
   ```
   This configures, builds, and installs glibc 2.17 to the `store/` directory

### Required Patches

Two minimal patches were applied:

1. **configure** (line 4975): Accept Make 4.x versions
   ```bash
   3.79* | 3.[89]* | 4.*)  # Changed from: 3.79* | 3.[89]*)
   ```

2. **malloc/obstack.c** (line 119): Initialize _obstack_compat
   ```c
   struct obstack *_obstack_compat = 0;  // Changed from uninitialized
   ```
   This prevents "can't version common symbol" error with modern binutils

## Test Programs

Test programs in `tests/` directory verify the build:
- `hello-static`: Statically linked against glibc 2.17
- `hello-dynamic`: Dynamically linked against glibc 2.17

Both programs report: `GNU libc version: 2.17`

## Build Details

- Toolchain: GCC 4.9.3 (Ubuntu 4.9.3-5ubuntu1)
- Library dependencies: libcloog-isl4, libisl13 (from Ubuntu archives)
- Symlinked: libmpfr.so.4 → libmpfr.so.6, libmpc.so.2 → libmpc.so.3
- Build output: 950+ source files compiled
- Installation: Libraries and headers in `store/` directory

## Failed Approaches

### 1. Building GCC 4.8.5 from Source
Multiple attempts failed during GCC compilation stage

### 2. Modern GCC with Patched Configure
Failed with assembler error: `rtld.c:854: Error: operand type mismatch for 'movq'`
Issue: Inline assembly incompatibility between 2012 code and 2024 assemblers
