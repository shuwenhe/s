#define _GNU_SOURCE

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *NATIVE_RUNNER = "/app/s/bin/s-native";
enum { S_PATH_CAP = 4096 };

static int usage(void) {
    fprintf(stderr, "usage: s-selfhosted check <path> | s-selfhosted build <path> -o <output> | s-selfhosted run <path> [arg ...]\n");
    return 1;
}

static int run_child(char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) {
        perror("fork");
        return errno == 0 ? 127 : errno;
    }
    if (pid == 0) {
        execv(argv[0], argv);
        perror(argv[0]);
        _exit(errno == 0 ? 127 : errno);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        perror("waitpid");
        return errno == 0 ? 127 : errno;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return 1;
}

static int run_build(int argc, char **argv) {
    if (argc != 5 || strcmp(argv[3], "-o") != 0) {
        fprintf(stderr, "error: expected build <path> -o <output>\n");
        return 1;
    }
    char *build_argv[] = {
        (char *)NATIVE_RUNNER,
        "build",
        argv[2],
        "-o",
        argv[4],
        NULL,
    };
    return run_child(build_argv);
}

static int run_check(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "error: expected check <path>\n");
        return 1;
    }

    char temp_template[] = "/app/tmp/s-check-XXXXXX";
    char *temp_dir = mkdtemp(temp_template);
    if (temp_dir == NULL) {
        perror("mkdtemp");
        return errno == 0 ? 127 : errno;
    }

    char output_path[S_PATH_CAP];
    snprintf(output_path, sizeof(output_path), "%s/out", temp_dir);

    char *build_argv[] = {
        (char *)NATIVE_RUNNER,
        "build",
        argv[2],
        "-o",
        output_path,
        NULL,
    };
    int code = run_child(build_argv);
    if (code != 0) {
        return code;
    }

    printf("ok: %s\n", argv[2]);
    return 0;
}

static int run_program(char *path, int argc, char **argv) {
    char **run_argv = calloc((size_t)(argc + 1), sizeof(char *));
    if (run_argv == NULL) {
        perror("calloc");
        return errno == 0 ? 127 : errno;
    }
    run_argv[0] = path;
    for (int i = 3; i < argc; i++) {
        run_argv[i - 2] = argv[i];
    }
    run_argv[argc - 2] = NULL;

    execv(path, run_argv);
    perror(path);
    free(run_argv);
    return errno == 0 ? 127 : errno;
}

static int run_run(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "error: expected run <path> [arg ...]\n");
        return 1;
    }

    char temp_template[] = "/app/tmp/s-run-XXXXXX";
    char *temp_dir = mkdtemp(temp_template);
    if (temp_dir == NULL) {
        perror("mkdtemp");
        return errno == 0 ? 127 : errno;
    }

    char output_path[S_PATH_CAP];
    snprintf(output_path, sizeof(output_path), "%s/run-target", temp_dir);

    char *build_argv[] = {
        (char *)NATIVE_RUNNER,
        "build",
        argv[2],
        "-o",
        output_path,
        NULL,
    };
    int code = run_child(build_argv);
    if (code != 0) {
        return code;
    }
    return run_program(output_path, argc, argv);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        return usage();
    }
    if (access(NATIVE_RUNNER, X_OK) != 0) {
        fprintf(stderr, "error: native runner missing: %s\n", NATIVE_RUNNER);
        return errno == 0 ? 127 : errno;
    }
    if (strcmp(argv[1], "build") == 0) {
        return run_build(argc, argv);
    }
    if (strcmp(argv[1], "check") == 0) {
        return run_check(argc, argv);
    }
    if (strcmp(argv[1], "run") == 0) {
        return run_run(argc, argv);
    }
    return usage();
}
