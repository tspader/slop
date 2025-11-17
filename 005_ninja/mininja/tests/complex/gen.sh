#!/bin/bash
# Generate deep dependency chain: 100 C files where each calls the previous

N=100

# Generate func_0.c (base case)
cat > func_0.c << 'EOF'
int func_0() {
    return 1;
}
EOF

# Generate func_1 through func_99
for i in $(seq 1 $((N-1))); do
    prev=$((i-1))
    cat > func_$i.c << EOF
int func_$prev();

int func_$i() {
    return func_$prev() + 1;
}
EOF
done

# Generate main.c
cat > main.c << 'EOF'
#include <stdio.h>

int func_99();

int main() {
    printf("Deep chain result: %d\n", func_99());
    return 0;
}
EOF

# Generate build.txt
{
    echo "# Complex test: 100 C files in deep dependency chain"

    # Object file rules
    for i in $(seq 0 $((N-1))); do
        echo "func_$i.o: func_$i.c | gcc -c -o func_$i.o func_$i.c"
    done
    echo "main.o: main.c | gcc -c -o main.o main.c"

    # Final link rule
    echo -n "program: main.o"
    for i in $(seq 0 $((N-1))); do
        echo -n " func_$i.o"
    done
    echo -n " | gcc -o program main.o"
    for i in $(seq 0 $((N-1))); do
        echo -n " func_$i.o"
    done
    echo
} > build.txt

echo "Generated $N C files + main.c + build.txt"
