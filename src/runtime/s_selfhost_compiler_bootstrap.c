#define _posix_c_source 200809l

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

    try_exec_if_present(getenv("S_NATIVE"), argv);
    try_exec_if_present(getenv("s_native"), argv);
    try_exec_if_present("/home/shuwen/s/bin/s-native", argv);
    try_exec_if_present("/app/s/bin/s-native", argv);

    perror("s compiler launcher");
    return errno == 0 ? 127 : errno;
}
