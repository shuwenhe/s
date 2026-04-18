#define _posix_c_source 200809l

#include <errno.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    (void)argc;

    execv("/home/shuwen/s/bin/s-selfhosted", argv);
    execv("/home/shuwen/s/bin/s", argv);

    perror("s-selfhosted launcher");
    return errno == 0 ? 127 : errno;
}
