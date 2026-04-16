#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdio.h>
#include <unistd.h>

#ifndef PROCESS_RUNNER_EXECUTABLE_PATH
#define PROCESS_RUNNER_EXECUTABLE_PATH "/home/shuwen/s/src/runtime/process_runner"
#endif

int main(int argc, char **argv) {
    (void)argc;

    execv(PROCESS_RUNNER_EXECUTABLE_PATH, argv);
    perror("launcher");
    return errno == 0 ? 127 : errno;
}

