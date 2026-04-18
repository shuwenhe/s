#define _posix_c_source 200809l

#include <errno.h>
#include <stdio.h>
#include <unistd.h>

#ifndef process_runner_executable_path
#define process_runner_executable_path "/home/shuwen/s/src/runtime/process_runner"
#endif

int main(int argc, char **argv) {
    (void)argc;

    execv(process_runner_executable_path, argv);
    perror("launcher");
    return errno == 0 ? 127 : errno;
}

