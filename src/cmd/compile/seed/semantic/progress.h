#ifndef S_SEED_PROGRESS_H
#define S_SEED_PROGRESS_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static inline void seed_work_progress(const char *phase, size_t done, size_t total, const char *unit, const char *name) {
    const char *enabled = getenv("S_BOOTSTRAP_PROGRESS");
    if (!enabled || strcmp(enabled, "1")) return;
    fprintf(stderr, "%s  %zu / %zu %s  current=%s\n", phase, done, total, unit, name ? name : "declaration");
    fflush(stderr);
}
#endif
