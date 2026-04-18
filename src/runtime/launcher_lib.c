#define _posix_c_source 200809l

#include <stddef.h>

int process_runner_run_argv(size_t argc, const char *const *argv);
int process_runner_run_shell(const char *command);

int launcher_run_argv(size_t argc, const char *const *argv) {
    return process_runner_run_argv(argc, argv);
}

int launcher_run_shell(const char *command) {
    return process_runner_run_shell(command);
}

