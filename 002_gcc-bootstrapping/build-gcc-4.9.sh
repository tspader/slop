#!/bin/bash
set -e

# Build script for GCC 4.9.4 from source using modern GCC
# This script builds stock GCC 4.9.4 with minimal patches for modern toolchain compatibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${SCRIPT_DIR}/build"
SOURCES_DIR="${BUILD_ROOT}/sources"
BUILD_DIR="${BUILD_ROOT}/work"
INSTALL_DIR="${BUILD_ROOT}/install/gcc-4.9"

# Create directory structure
echo "[1/9] Creating build directory structure..."
mkdir -p "${SOURCES_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${INSTALL_DIR}"

# Download GCC 4.9.4 source
echo "[2/9] Downloading GCC 4.9.4 source..."
cd "${SOURCES_DIR}"
if [ ! -f gcc-4.9.4.tar.bz2 ]; then
    wget -c https://gcc.gnu.org/pub/gcc/releases/gcc-4.9.4/gcc-4.9.4.tar.bz2
fi

if [ ! -d gcc-4.9.4 ]; then
    echo "Extracting GCC 4.9.4..."
    tar xf gcc-4.9.4.tar.bz2
fi

# Download prerequisites
echo "[3/9] Downloading GCC prerequisites..."
cd gcc-4.9.4
./contrib/download_prerequisites

# Apply patches
echo "[4/9] Applying compatibility patches..."

# Patch 1: GMP configure - fix implicit function declarations
echo "  - Patching GMP configure for modern GCC..."
sed -i 's/cat >conftest\.c <<EOF\nint\nmain ()/cat >conftest.c <<EOF\n#include <stdlib.h>\nint\nmain ()/g' gmp/configure

# Patch 2: reload.h - fix C++17 bool increment issue
echo "  - Patching reload.h for C++17 compatibility..."
sed -i 's/bool x_spill_indirect_levels;/int x_spill_indirect_levels;/g' gcc/reload.h

# Patch 3: linux-unwind.h - fix ucontext_t for modern glibc
echo "  - Patching linux-unwind.h for modern glibc..."
sed -i 's/struct ucontext \*uc_/ucontext_t *uc_/g' libgcc/config/i386/linux-unwind.h
sed -i 's/struct ucontext uc;/ucontext_t uc;/g' libgcc/config/i386/linux-unwind.h

# Remove embedded library symlinks (we'll use system libraries)
echo "[5/9] Removing embedded library symlinks..."
rm -f gmp mpfr mpc isl cloog

# Configure
echo "[6/9] Configuring GCC 4.9.4..."
cd "${BUILD_DIR}"
"${SOURCES_DIR}/gcc-4.9.4/configure" \
    --prefix="${INSTALL_DIR}" \
    --enable-languages=c,c++ \
    --disable-multilib \
    --disable-bootstrap \
    --with-gmp=/usr \
    --with-mpfr=/usr \
    --with-mpc=/usr \
    --disable-libsanitizer

# Build
echo "[7/9] Building GCC 4.9.4 (this will take 30-60 minutes)..."
NPROC=$(nproc)
echo "Using ${NPROC} parallel jobs..."
make -j${NPROC}

# Install
echo "[8/9] Installing GCC 4.9.4 to ${INSTALL_DIR}..."
make install

# Verify
echo "[9/9] Verifying installation..."
echo ""
echo "=== GCC Version ==="
"${INSTALL_DIR}/bin/gcc" --version
echo ""

# Test 1: Hello World
echo "=== Test 1: Hello World (dynamic linking) ==="
cat > /tmp/test_gcc49_hello.c <<'EOF'
#include <stdio.h>
int main() {
    printf("Hello from GCC 4.9.4!\n");
    return 0;
}
EOF
"${INSTALL_DIR}/bin/gcc" /tmp/test_gcc49_hello.c -o /tmp/test_gcc49_hello
/tmp/test_gcc49_hello
rm -f /tmp/test_gcc49_hello /tmp/test_gcc49_hello.c
echo "✓ Dynamic linking test passed"
echo ""

# Test 2: Static linking
echo "=== Test 2: Static linking test ==="
cat > /tmp/test_gcc49_static.c <<'EOF'
#include <stdio.h>
int main() {
    printf("Static binary from GCC 4.9.4!\n");
    return 0;
}
EOF
"${INSTALL_DIR}/bin/gcc" -static /tmp/test_gcc49_static.c -o /tmp/test_gcc49_static
/tmp/test_gcc49_static
echo "Binary type: $(file /tmp/test_gcc49_static | grep -o 'statically linked')"
rm -f /tmp/test_gcc49_static /tmp/test_gcc49_static.c
echo "✓ Static linking test passed"
echo ""

# Test 3: C++ Hello World
echo "=== Test 3: C++ Hello World ==="
cat > /tmp/test_gcc49_cpp.cpp <<'EOF'
#include <iostream>
int main() {
    std::cout << "C++ Hello from GCC 4.9.4!" << std::endl;
    return 0;
}
EOF
"${INSTALL_DIR}/bin/g++" /tmp/test_gcc49_cpp.cpp -o /tmp/test_gcc49_cpp
/tmp/test_gcc49_cpp
rm -f /tmp/test_gcc49_cpp /tmp/test_gcc49_cpp.cpp
echo "✓ C++ test passed"
echo ""

echo "=== BUILD COMPLETE ==="
echo ""
echo "GCC 4.9.4 successfully installed to: ${INSTALL_DIR}"
echo ""
echo "To use this compiler:"
echo "  export PATH=${INSTALL_DIR}/bin:\$PATH"
echo "  gcc --version"
echo ""
echo "Or use directly:"
echo "  ${INSTALL_DIR}/bin/gcc myprogram.c -o myprogram"
echo ""
