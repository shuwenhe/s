#define _POSIX_C_SOURCE 200809L

#include <limits.h>
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int resolve_target(char *buf, size_t size) {
    const char *env = getenv("S_SELFHOSTED_RUNNER");
    if (env != NULL && env[0] != '\0' && access(env, X_OK) == 0) {
        if (snprintf(buf, size, "%s", env) < (int)size) {
            return 1;
        }
    }

    char exe_path[PATH_MAX];
    ssize_t exe_len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
    if (exe_len > 0) {
        exe_path[exe_len] = '\0';
        char *slash = strrchr(exe_path, '/');
        if (slash != NULL) {
            *slash = '\0';
            if (snprintf(buf, size, "%s/s-native", exe_path) < (int)size && access(buf, X_OK) == 0) {
                return 1;
            }
        }
    }

    if (snprintf(buf, size, "/app/s/bin/s-native") < (int)size && access(buf, X_OK) == 0) {
        return 1;
    }
    if (snprintf(buf, size, "/app/s/bin/s") < (int)size && access(buf, X_OK) == 0) {
        return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    (void)argc;

    char target[PATH_MAX];
    if (resolve_target(target, sizeof(target))) {
        execv(target, argv);
    }

    perror("s-selfhosted launcher");
    return errno == 0 ? 127 : errno;
}
