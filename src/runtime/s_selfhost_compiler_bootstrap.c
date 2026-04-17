#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    (void)argc;

    execv("/app/s/bin/s-selfhosted", argv);
    execv("/app/s/bin/s", argv);

    perror("s-selfhosted launcher");
    return errno == 0 ? 127 : errno;
}
