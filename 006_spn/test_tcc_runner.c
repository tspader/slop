/* Test runner that uses libtcc to compile and run test_tcc_curl.c from memory */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tinycc/libtcc.h"

int main() {
    TCCState *s;
    int ret;

    printf("=== TCC Compile-to-Memory Trace ===\n\n");

    /* Create TCC state */
    printf("1. tcc_new() - Creating TCCState\n");
    s = tcc_new();
    if (!s) {
        fprintf(stderr, "Could not create tcc state\n");
        return 1;
    }

    /* Set output to memory */
    printf("2. tcc_set_output_type(TCC_OUTPUT_MEMORY) - Set output to memory\n");
    tcc_set_output_type(s, TCC_OUTPUT_MEMORY);

    /* Set lib path */
    printf("3. tcc_set_lib_path() - Set TCC library path\n");
    tcc_set_lib_path(s, "/home/user/slop/006_spn/tinycc");

    /* Add library path */
    printf("4. tcc_add_library_path() - Add library search paths\n");
    tcc_add_library_path(s, "/usr/lib");
    tcc_add_library_path(s, "/usr/lib/x86_64-linux-gnu");

    /* Add the source file */
    printf("5. tcc_add_file(test_tcc_curl.c) - Parse and compile source\n");
    printf("   - Lexical analysis (tokenization)\n");
    printf("   - Parsing (build AST)\n");
    printf("   - Semantic analysis\n");
    printf("   - Code generation (x86_64 machine code)\n");
    ret = tcc_add_file(s, "test_tcc_curl.c");
    if (ret < 0) {
        fprintf(stderr, "Could not add file\n");
        tcc_delete(s);
        return 1;
    }

    /* Link with curl */
    printf("6. tcc_add_library(curl) - Add dynamic library dependency\n");
    ret = tcc_add_library(s, "curl");
    if (ret < 0) {
        fprintf(stderr, "Could not link curl\n");
        tcc_delete(s);
        return 1;
    }

    /* Relocate the code */
    printf("7. tcc_relocate() - Allocate memory and perform relocations\n");
    printf("   - Allocate memory for code/data sections\n");
    printf("   - Apply relocations (fix up addresses)\n");
    printf("   - Resolve external symbols (libc, libcurl)\n");
    ret = tcc_relocate(s);
    if (ret < 0) {
        fprintf(stderr, "Could not relocate\n");
        tcc_delete(s);
        return 1;
    }

    /* Get main symbol */
    printf("8. tcc_get_symbol(main) - Lookup main() function pointer\n");
    int (*main_func)(void) = tcc_get_symbol(s, "main");
    if (!main_func) {
        fprintf(stderr, "Could not find main\n");
        tcc_delete(s);
        return 1;
    }

    /* Run the code */
    printf("9. Execute main() from memory\n");
    printf("   --------------------------------------------------\n");
    ret = main_func();
    printf("   --------------------------------------------------\n");
    printf("   Returned: %d\n\n", ret);

    /* Cleanup */
    printf("10. tcc_delete() - Free all resources\n");
    tcc_delete(s);

    return 0;
}
