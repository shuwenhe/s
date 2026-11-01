#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include "program.c"

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    char *end;
    int64_t value = strtoll(argv[1], &end, 10);
    if (*end) return 2;
    printf("%" PRId64 "\n", s_mir_entry(value));
    return 0;
}
