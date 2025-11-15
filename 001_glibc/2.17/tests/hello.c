#include <stdio.h>
#include <gnu/libc-version.h>

int main(void) {
    printf("Hello from glibc!\n");
    printf("GNU libc version: %s\n", gnu_get_libc_version());
    printf("GNU libc release: %s\n", gnu_get_libc_release());
    return 0;
}
