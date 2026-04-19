#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

static void try_exec_if_present(const char *path, char **argv) {
    if (path != NULL && path[0] != '\0' && access(path, X_OK) == 0) {
        execv(path, argv);
    }
}

int main(int argc, char **argv) {
    (void)argc;

    try_exec_if_present(getenv("S_SELFHOSTED"), argv);
    try_exec_if_present(getenv("s_selfhosted_runner"), argv);
    try_exec_if_present("/home/shuwen/s/bin/s-selfhosted", argv);
    try_exec_if_present("/app/s/bin/s-selfhosted", argv);

    perror("s command launcher");
    return errno == 0 ? 127 : errno;
}
