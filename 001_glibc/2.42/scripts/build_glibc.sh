#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GLIBC_DIR="$REPO_ROOT/001_glibc"
EXTERNAL="$GLIBC_DIR/external"
BUILD_DIR="$GLIBC_DIR/build"
STORE_DIR="$GLIBC_DIR/store"

cd "$REPO_ROOT"

if [ ! -d "$EXTERNAL/glibc/.git" ]; then
    rm -rf "$EXTERNAL/glibc"
    git clone https://sourceware.org/git/glibc.git "$EXTERNAL/glibc" --depth 1
fi

apt-get update
apt-get install -y gawk bison texinfo

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

../external/glibc/configure \
    --prefix="$STORE_DIR" \
    --disable-werror

make -j4
make install

echo "Build complete. glibc installed to $STORE_DIR"
