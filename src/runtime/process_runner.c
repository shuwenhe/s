#define _POSIX_C_SOURCE 200809L

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
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return 1;
}

int process_runner_run_argv(size_t argc, const char *const *argv) {
    if (argc == 0 || argv == NULL || argv[0] == NULL) {
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
    if (command == NULL || command[0] == '\0') {
        return 127;
    }

    pid_t pid = fork();
    if (pid < 0) {
        return errno == 0 ? 127 : errno;
    }
    if (pid == 0) {
        execl("/bin/sh", "sh", "-c", command, (char *)NULL);
        _exit(errno == 0 ? 127 : errno);
    }
    return wait_for_child(pid);
}

