#!/bin/bash
set -e

STORE="/home/user/slop/001_glibc/store"
GCC_OPTS="-I${STORE}/include"
LD_OPTS="-L${STORE}/lib -Wl,--rpath=${STORE}/lib -Wl,--dynamic-linker=${STORE}/lib/ld-linux-x86-64.so.2"

echo "Building dynamically linked test program..."
gcc ${GCC_OPTS} ${LD_OPTS} -o test_dynamic test.c

echo "Building statically linked test program..."
gcc ${GCC_OPTS} -static -L${STORE}/lib -o test_static test.c -lc

echo "Build complete!"
