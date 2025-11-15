# glibc Build from Source

Multi-version glibc builds.

## Structure

- `2.42/` - glibc 2.42.9000 (modern, builds successfully)
- `2.17/` - glibc 2.17 (requires older toolchain)
- `external/` - source repositories

## Building

### glibc 2.42

```bash
cd 2.42
./scripts/build_glibc.sh
```

Produces binaries, headers, and libraries in `2.42/store/`.

### glibc 2.17

Requires GCC 4.x era toolchain. See `2.17/README.md` for details.

Modern toolchains (GCC 13+) encounter assembler incompatibilities.
