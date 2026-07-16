#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>

typedef int64_t (*add_fn)(int64_t, int64_t);
typedef const char *(*last_error_fn)(void);

int main(int argc, char **argv) {
    void *library;
    add_fn add;
    last_error_fn last_error;
    int64_t result;

    if (argc != 2) {
        fprintf(stderr, "usage: %s <S shared library>\n", argv[0]);
        return 2;
    }
    library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return 1;
    }
    add = (add_fn)dlsym(library, "neurx_add");
    last_error = (last_error_fn)dlsym(library, "s_abi_last_error");
    if (!add || !last_error) {
        fprintf(stderr, "required ABI symbol is missing\n");
        dlclose(library);
        return 1;
    }
    result = add(19, 23);
    if (result != 42 || last_error()[0] != '\0') {
        fprintf(stderr, "C ABI call failed: result=%lld error=%s\n", (long long)result, last_error());
        dlclose(library);
        return 1;
    }
    dlclose(library);
    printf("S C ABI integration passed: neurx_add(19, 23) = %lld\n", (long long)result);
    return 0;
}
