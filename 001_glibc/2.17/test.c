#include <stdio.h>
#include <gnu/libc-version.h>

int main(void) {
    printf("glibc version: %s\n", gnu_get_libc_version());
    printf("Hello from custom glibc!\n");
    return 0;
}
