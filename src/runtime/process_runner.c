#define _posix_c_source 200809l

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static int wait_for_child(pid_t pid) {
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        return errno == 0 ? 127 : errno;
    }
    if (wifexited(status)) {
        return wexitstatus(status);
    }
    if (wifsignaled(status)) {
        return 128 + wtermsig(status);
    }
    return 1;
}

int process_runner_run_argv(size_t argc, const char *const *argv) {
    if (argc == 0 || argv == null || argv[0] == null) {
        return 127;
    }

    pid_t pid = fork();
    if (pid < 0) {
        return errno == 0 ? 127 : errno;
    }
    if (pid == 0) {
        execvp(argv[0], (char *const *)argv);
        _exit(errno == 0 ? 127 : errno);
    }
    return wait_for_child(pid);
}

int process_runner_run_shell(const char *command) {
    if (command == null || command[0] == '\0') {
        return 127;
    }

    pid_t pid = fork();
    if (pid < 0) {
        return errno == 0 ? 127 : errno;
    }
    if (pid == 0) {
        execl("/bin/sh", "sh", "-c", command, (char *)null);
        _exit(errno == 0 ? 127 : errno);
    }
    return wait_for_child(pid);
}

