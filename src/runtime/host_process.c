#define _posix_c_source 200809l

#include <stddef.h>

int process_runner_run_argv(size_t argc, const char *const *argv);

int host_process_run_argv(size_t argc, const char *const *argv) {
    return process_runner_run_argv(argc, argv);
}
