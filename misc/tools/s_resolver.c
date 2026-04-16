/* Simple S dependency resolver prototype
 * Usage: s_resolver <repo_root> <entry.s>
 * Scans `use` statements and attempts to locate source files under repo_root/src
 * This is a best-effort tool to build a dependency graph for bootstrapping.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>

#define MAX_PATH 4096

// Simple linked list for visited files
typedef struct Node {
    char *path;
    struct Node *next;
} Node;

static int visited(Node *head, const char *path) {
    for (Node *n = head; n; n = n->next) {
        if (strcmp(n->path, path) == 0) return 1;
    }
    return 0;
}

static void add(Node **head, const char *path) {
    Node *n = malloc(sizeof(Node));
    n->path = malloc(strlen(path) + 1);
    if (n->path) strcpy(n->path, path);
    n->next = *head;
    *head = n;
}

static char *join_path(const char *a, const char *b) {
    char *out = malloc(MAX_PATH);
    snprintf(out, MAX_PATH, "%s/%s", a, b);
    return out;
}

// try heuristics to map module name to a file path
static int resolve_module(const char *repo_root, const char *module, char *out_path, size_t out_sz) {
    // try repo_root/src/<module with dots replaced>.s
    char buf[MAX_PATH];
    snprintf(buf, sizeof(buf), "%s/src/%s.s", repo_root, module);
    for (char *p = buf; *p; ++p) if (*p == '.') *p = '/';
    struct stat st;
    if (stat(buf, &st) == 0) {
        strncpy(out_path, buf, out_sz);
        return 0;
    }

    // try repo_root/src/<module prefix>.s (drop last segment)
    char tmp[MAX_PATH];
    strncpy(tmp, module, sizeof(tmp));
    char *last = strrchr(tmp, '.');
    if (last) {
        *last = '\0';
        snprintf(buf, sizeof(buf), "%s/src/%s.s", repo_root, tmp);
        for (char *p = buf; *p; ++p) if (*p == '.') *p = '/';
        if (stat(buf, &st) == 0) {
            strncpy(out_path, buf, out_sz);
            return 0;
        }
    }

    // fallback: search all .s files under repo_root/src for occurrence of last token
    const char *last_tok = last ? last + 1 : module;
    // naive directory walk at depth 2+ using opendir
    char dirpath[MAX_PATH];
    snprintf(dirpath, sizeof(dirpath), "%s/src", repo_root);
    DIR *d = opendir(dirpath);
    if (!d) return -1;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (ent->d_name[0] == '.') continue;
        // recurse into directories
        char subdir[MAX_PATH];
        snprintf(subdir, sizeof(subdir), "%s/%s", dirpath, ent->d_name);
        struct stat st2;
        if (stat(subdir, &st2) == 0 && S_ISDIR(st2.st_mode)) {
            DIR *d2 = opendir(subdir);
            if (!d2) continue;
            struct dirent *e2;
            while ((e2 = readdir(d2)) != NULL) {
                if (e2->d_name[0] == '.') continue;
                size_t len = strlen(e2->d_name);
                if (len > 2 && strcmp(e2->d_name + len - 2, ".s") == 0) {
                    char fpath[MAX_PATH];
                    snprintf(fpath, sizeof(fpath), "%s/%s", subdir, e2->d_name);
                    FILE *f = fopen(fpath, "rb");
                    if (!f) continue;
                    char line[1024];
                    int found = 0;
                    while (fgets(line, sizeof(line), f)) {
                        if (strstr(line, last_tok)) { found = 1; break; }
                    }
                    fclose(f);
                    if (found) {
                        strncpy(out_path, fpath, out_sz);
                        closedir(d2);
                        closedir(d);
                        return 0;
                    }
                }
            }
            closedir(d2);
        } else {
            // also check .s files in src root
            size_t len = strlen(ent->d_name);
            if (len > 2 && strcmp(ent->d_name + len - 2, ".s") == 0) {
                char fpath[MAX_PATH];
                snprintf(fpath, sizeof(fpath), "%s/%s", dirpath, ent->d_name);
                FILE *f = fopen(fpath, "rb");
                if (!f) continue;
                char line[1024];
                int found = 0;
                while (fgets(line, sizeof(line), f)) {
                    if (strstr(line, last_tok)) { found = 1; break; }
                }
                fclose(f);
                if (found) {
                    strncpy(out_path, fpath, out_sz);
                    closedir(d);
                    return 0;
                }
            }
        }
    }
    closedir(d);
    return -1;
}

static void resolve_rec(const char *repo_root, const char *path, Node **out_head) {
    if (visited(*out_head, path)) return;
    add(out_head, path);

    FILE *f = fopen(path, "rb");
    if (!f) return;
    char line[1024];
    while (fgets(line, sizeof(line), f)) {
        // trim leading whitespace
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (strncmp(p, "use ", 4) == 0) {
            p += 4;
            // read token until space or newline
            char token[512] = {0};
            int i = 0;
            while (*p && *p != '\n' && *p != ' ' && *p != '\t') {
                if (i < (int)sizeof(token)-1) token[i++] = *p;
                p++;
            }
            token[i] = '\0';
            if (strlen(token) == 0) continue;
            char target[MAX_PATH];
            if (resolve_module(repo_root, token, target, sizeof(target)) == 0) {
                resolve_rec(repo_root, target, out_head);
            }
        }
    }
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <repo_root> <entry.s>\n", argv[0]);
        return 2;
    }
    const char *repo_root = argv[1];
    const char *entry = argv[2];
    char entry_path[MAX_PATH];
    if (entry[0] == '/') strncpy(entry_path, entry, MAX_PATH); else snprintf(entry_path, MAX_PATH, "%s/%s", repo_root, entry);

    Node *head = NULL;
    resolve_rec(repo_root, entry_path, &head);

    // print dependency list in reverse order (visited stack)
    for (Node *n = head; n; n = n->next) {
        printf("%s\n", n->path);
    }
    return 0;
}
