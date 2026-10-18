#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* Passing all eight arguments also exercises stack arguments on entry8. */
extern int64_t s_native_entry(int64_t, int64_t, int64_t, int64_t,
                              int64_t, int64_t, int64_t, int64_t);
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    char *end;
    errno = 0;
    int64_t input = strtoll(argv[1], &end, 10);
    if (errno || *end || end == argv[1]) return 2;
    register uint64_t a __asm__("rbx") = UINT64_C(0x123456789abcdef0);
    register uint64_t b __asm__("r12") = UINT64_C(0xfedcba9876543210);
    register uint64_t c __asm__("r13") = UINT64_C(0x55aa55aa55aa55aa);
    register uint64_t d __asm__("r14") = UINT64_C(0xaa55aa55aa55aa55);
    register uint64_t e __asm__("r15") = UINT64_C(0x1122334455667788);
    __asm__ volatile("" : "+r"(a), "+r"(b), "+r"(c), "+r"(d), "+r"(e));
    int64_t result = s_native_entry(input, 2, 3, 4, 5, 6, 7, 8);
    __asm__ volatile("" : "+r"(a), "+r"(b), "+r"(c), "+r"(d), "+r"(e));
    if (a != UINT64_C(0x123456789abcdef0) || b != UINT64_C(0xfedcba9876543210) ||
        c != UINT64_C(0x55aa55aa55aa55aa) || d != UINT64_C(0xaa55aa55aa55aa55) ||
        e != UINT64_C(0x1122334455667788)) return 90;
    printf("%" PRId64 "\n", result);
    return 0;
}
