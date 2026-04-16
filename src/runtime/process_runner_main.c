#include <stddef.h>
#include <stdio.h>
#include <string.h>

int process_runner_run_argv(size_t argc, const char *const *argv);
int process_runner_run_shell(const char *command);

static int usage(void) {
    fprintf(stderr, "usage: process_runner run-argv <program> [arg ...] | run-shell <command>\n");
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        return usage();
    }
    if (strcmp(argv[1], "run-argv") == 0) {
        if (argc < 3) {
            return usage();
        }
        return process_runner_run_argv((size_t)(argc - 2), (const char *const *)(argv + 2));
    }
    if (strcmp(argv[1], "run-shell") == 0) {
        if (argc != 3) {
            return usage();
        }
        return process_runner_run_shell(argv[2]);
    }
    return usage();
}

