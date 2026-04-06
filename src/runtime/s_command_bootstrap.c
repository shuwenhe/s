#include <errno.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    (void)argc;

    execv("/usr/local/bin/s", argv);
    execv("/app/s/bin/s", argv);

    perror("s command launcher");
    return errno == 0 ? 127 : errno;
}
