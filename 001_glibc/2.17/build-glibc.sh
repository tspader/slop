#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_DIR="$SCRIPT_DIR/../../002_gcc-bootstrapping/build"
SOURCE_DIR="$SCRIPT_DIR/source"
BUILD_DIR="$SCRIPT_DIR/build"
INSTALL_DIR="$SCRIPT_DIR/store"

export PATH="$TOOLCHAIN_DIR/bin:$PATH"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

$SOURCE_DIR/configure \
    --prefix="$INSTALL_DIR" \
    --disable-werror \
    CC="$TOOLCHAIN_DIR/bin/gcc" \
    CXX="$TOOLCHAIN_DIR/bin/g++"

make -j32
make install
