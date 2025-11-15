#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENTOS_ENV="$SCRIPT_DIR/centos6_env.sh"

$CENTOS_ENV ./dist/usr/bin/gcc -static test/main.c -o test/hello_static
exit 0

echo "Building dynamic binary..."
$CENTOS_ENV ./dist/usr/bin/gcc test/main.c -o test/hello_dynamic

echo "=== Static binary ==="
readelf -p .comment test/hello_static | grep GCC

echo "=== Dynamic binary ==="
readelf -p .comment test/hello_dynamic | grep GCC

echo "=== Running static binary ==="
$CENTOS_ENV test/hello_static

echo "=== Running dynamic binary ==="
$CENTOS_ENV test/hello_dynamic

echo "=== Dynamic binary dependencies ==="
$CENTOS_ENV ./dist/usr/bin/readelf -d test/hello_dynamic | grep NEEDED
