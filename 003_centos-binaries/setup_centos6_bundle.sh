#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RPM_DIR="$SCRIPT_DIR/rpm"
DIST_DIR="$SCRIPT_DIR/dist"
BASE_URL="https://vault.centos.org/6.10/os/x86_64/Packages"

PACKAGES=(
    "glibc-2.12-1.212.el6.x86_64.rpm"
    "gcc-4.4.7-23.el6.x86_64.rpm"
    "glibc-devel-2.12-1.212.el6.x86_64.rpm"
    "binutils-2.20.51.0.2-5.48.el6.x86_64.rpm"
)

mkdir -p "$RPM_DIR"
mkdir -p "$DIST_DIR"

cd "$RPM_DIR"

for package in "${PACKAGES[@]}"; do
    if [ ! -f "$package" ]; then
        wget -q "$BASE_URL/$package"
    fi
done

cd "$DIST_DIR"

for package in "${PACKAGES[@]}"; do
    if [ ! -f ".extracted_$package" ]; then
        rpm2cpio "$RPM_DIR/$package" | cpio -idmv
        touch ".extracted_$package"
    fi
done

echo "Bundle ready at: $DIST_DIR"