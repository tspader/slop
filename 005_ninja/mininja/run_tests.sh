#!/bin/bash
set -e

cd "$(dirname "$0")"

# Rebuild mininja
gcc -o mininja mininja.c -DSP_IMPLEMENTATION

echo "================================"
echo "MININJA TEST SUITE"
echo "================================"
echo

# Test 1: Simple
echo ">>> TEST 1: Simple (single C file)"
echo "---"
cd tests/simple
rm -f hello
../../mininja build.txt
./hello
echo
cd ../..

# Test 2: Medium
echo ">>> TEST 2: Medium (3 C files with dependencies)"
echo "---"
cd tests/medium
rm -f *.o program
../../mininja build.txt
./program
echo

# Test incremental build (touch source, rebuild)
echo ">>> TEST 2b: Incremental rebuild (touch func_a.c)"
echo "---"
sleep 1
touch func_a.c
../../mininja build.txt
echo
cd ../..

# Test 3: Complex
echo ">>> TEST 3: Complex (100 C files, deep dependency chain)"
echo "---"
cd tests/complex
rm -f *.o program
time ../../mininja build.txt
./program
echo
cd ../..

echo "================================"
echo "ALL TESTS PASSED"
echo "================================"
