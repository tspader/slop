#!/bin/bash

echo "=== Custom glibc Build Verification ==="
echo
echo "Store directory: $(pwd)/store"
echo
echo "--- 1. Dynamic linking test ---"
./test_dynamic
echo
echo "--- 2. Static linking test ---"
./test_static
echo
echo "--- 3. Dynamic binary dependencies ---"
ldd test_dynamic | grep libc
echo
echo "--- 4. Verification: glibc version in dynamic binary ---"
strings test_dynamic | grep "glibc version" | head -1
echo
echo "--- 5. Verification: glibc version in static binary ---"
strings test_static | grep "glibc version" | head -1
echo
echo "--- 6. Store directory contents ---"
echo "Binaries: $(ls store/bin | wc -l) files"
echo "Headers: $(find store/include -name '*.h' | wc -l) files"
echo "Libraries: $(ls store/lib/*.so* 2>/dev/null | wc -l) shared objects"
echo "Static libs: $(ls store/lib/*.a 2>/dev/null | wc -l) archives"
echo
echo "=== Verification complete! ==="
