#include <errno.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    (void)argc;

    execv("/app/s/bin/s", argv);

    perror("s selfhost bootstrap");
    return errno == 0 ? 127 : errno;
}
