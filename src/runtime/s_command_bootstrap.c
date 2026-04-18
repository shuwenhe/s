#include <errno.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    (void)argc;

    execv("/home/shuwen/s/bin/s-selfhosted", argv);
    execv("/home/shuwen/s/bin/s", argv);

    perror("s command launcher");
    return errno == 0 ? 127 : errno;
}
