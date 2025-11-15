#!/bin/bash
set -e

# glibc 2.17 Build Script
# This script builds glibc 2.17 from source using GCC 4.9

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/external/2.17"
BUILD_DIR="$SOURCE_DIR/build-glibc"
INSTALL_DIR="$SCRIPT_DIR/store"
GCC49_DIR="/opt/gcc49"

echo "==> Building glibc 2.17"

# Check if GCC 4.9 is installed
if [ ! -f "$GCC49_DIR/usr/bin/gcc-4.9" ]; then
    echo "Error: GCC 4.9 not found at $GCC49_DIR"
    echo "Please run setup-gcc49.sh first"
    exit 1
fi

# Set up environment for GCC 4.9
export PATH="$GCC49_DIR/usr/bin:$PATH"
export LD_LIBRARY_PATH="$GCC49_DIR/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu"

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure glibc 2.17
echo "==> Configuring glibc 2.17..."
../configure \
    --prefix="$INSTALL_DIR" \
    --enable-add-ons \
    --disable-werror

# Build glibc
echo "==> Building glibc 2.17..."
make -j$(nproc)

# Install glibc
echo "==> Installing glibc 2.17..."
make install-lib install-headers

# Create necessary symlinks
echo "==> Creating symlinks..."
cd "$INSTALL_DIR/lib"
ln -sf libc-2.17.so libc.so.6
ln -sf ld-2.17.so ld-linux-x86-64.so.2

echo "==> Build complete!"
echo "Installed to: $INSTALL_DIR"
