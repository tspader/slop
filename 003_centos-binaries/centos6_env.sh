#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
BUSYBOX="$SCRIPT_DIR/busybox"

export PATH="$DIST_DIR/usr/bin:$DIST_DIR/bin:$DIST_DIR/usr/libexec/gcc/x86_64-redhat-linux/4.4.7"
export LD_LIBRARY_PATH="$DIST_DIR/lib64:$DIST_DIR/usr/lib64"

exec "$BUSYBOX" env -i PATH="$PATH" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" "$DIST_DIR/lib64/ld-linux-x86-64.so.2" "$@"