#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <ctype.h>
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#if defined(__linux__)
#include <sys/epoll.h>
#include <sys/sendfile.h>
#elif defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
#include <sys/event.h>
#include <sys/uio.h>
#endif

#include "../code/target.h"
#include "../intermediate/ir.h"
#include "../lexical/token.h"
#include "../semantic/scope.h"
#include "../syntax/ast.h"
#include "memory.h"

static int g_host_argc = 0;
static char **g_host_argv = NULL;
static int g_host_errno = 0;
static _Thread_local char g_last_recvfrom_ip[INET6_ADDRSTRLEN];
static _Thread_local int g_last_recvfrom_port = 0;

typedef struct runtime_profile_counter {
	char name[128];
	unsigned long long count;
} runtime_profile_counter;

static int g_runtime_profile_enabled = 0;
static unsigned long long g_runtime_profile_total_ops = 0;
static unsigned long long g_runtime_profile_max_ops = 0;
static runtime_profile_counter g_runtime_profile_fn[256];
static size_t g_runtime_profile_fn_len = 0;
static runtime_profile_counter g_runtime_profile_host[256];
static size_t g_runtime_profile_host_len = 0;
static runtime_profile_counter g_runtime_profile_op[256];
static size_t g_runtime_profile_op_len = 0;

typedef struct runtime_values runtime_values;

typedef enum runtime_value_kind {
	RUNTIME_INT = 0,
	RUNTIME_FLOAT,
	RUNTIME_STRING,
	RUNTIME_ARRAY,
} runtime_value_kind;

typedef struct runtime_data_value runtime_data_value;

typedef struct runtime_data_value {
	runtime_value_kind kind;
	long int_value;
	double float_value;
	char *str_value;
	runtime_data_value *array_items;
	size_t array_len;
} runtime_data_value;

static int resolve_value(const runtime_values *vals, const char *name, runtime_data_value *out);

static unsigned long long parse_ull_env(const char *text) {
	char *end = NULL;
	unsigned long long value = 0;
	if (!text || !*text) {
		return 0;
	}
	value = strtoull(text, &end, 10);
	if (!end || *end != '\0') {
		return 0;
	}
	return value;
}

static void runtime_profile_reset(void) {
	g_runtime_profile_total_ops = 0;
	g_runtime_profile_fn_len = 0;
	g_runtime_profile_host_len = 0;
	g_runtime_profile_op_len = 0;
	memset(g_runtime_profile_fn, 0, sizeof(g_runtime_profile_fn));
	memset(g_runtime_profile_host, 0, sizeof(g_runtime_profile_host));
	memset(g_runtime_profile_op, 0, sizeof(g_runtime_profile_op));
}

static void runtime_profile_init_from_env(void) {
	const char *enabled = getenv("S_RUNTIME_PROFILE");
	const char *max_ops = getenv("S_RUNTIME_PROFILE_MAX_OPS");
	g_runtime_profile_enabled = enabled && enabled[0] != '\0' && strcmp(enabled, "0") != 0;
	g_runtime_profile_max_ops = parse_ull_env(max_ops);
	runtime_profile_reset();
}

static void runtime_profile_bump(runtime_profile_counter *counters, size_t *len, size_t cap, const char *name) {
	size_t i;
	if (!name || !*name) {
		return;
	}
	for (i = 0; i < *len; i++) {
		if (strcmp(counters[i].name, name) == 0) {
			counters[i].count++;
			return;
		}
	}
	if (*len >= cap) {
		return;
	}
	snprintf(counters[*len].name, sizeof(counters[*len].name), "%s", name);
	counters[*len].count = 1;
	(*len)++;
}

static void runtime_profile_dump_top(const char *label, runtime_profile_counter *counters, size_t len, size_t top_n) {
	size_t i;
	size_t used[16];
	size_t limit = top_n < 16 ? top_n : 16;
	for (i = 0; i < limit; i++) {
		used[i] = (size_t)-1;
	}
	fprintf(stderr, "runtime profile %s:\n", label);
	for (i = 0; i < limit; i++) {
		size_t j;
		size_t best = (size_t)-1;
		unsigned long long best_count = 0;
		size_t k;
		for (j = 0; j < len; j++) {
			int already_used = 0;
			for (k = 0; k < i; k++) {
				if (used[k] == j) {
					already_used = 1;
					break;
				}
			}
			if (already_used) {
				continue;
			}
			if (counters[j].count > best_count) {
				best = j;
				best_count = counters[j].count;
			}
		}
		if (best == (size_t)-1) {
			break;
		}
		used[i] = best;
		fprintf(stderr, "  %s: %llu\n", counters[best].name, counters[best].count);
	}
}

static void runtime_profile_dump_summary(void) {
	if (!g_runtime_profile_enabled) {
		return;
	}
	fprintf(stderr, "runtime profile total_ops: %llu\n", g_runtime_profile_total_ops);
	runtime_profile_dump_top("functions", g_runtime_profile_fn, g_runtime_profile_fn_len, 10);
	runtime_profile_dump_top("host_calls", g_runtime_profile_host, g_runtime_profile_host_len, 10);
	runtime_profile_dump_top("ir_ops", g_runtime_profile_op, g_runtime_profile_op_len, 10);
}

static runtime_data_value value_make_int(long v) {
	runtime_data_value out;
	out.kind = RUNTIME_INT;
	out.int_value = v;
	out.float_value = (double)v;
	out.str_value = NULL;
	out.array_items = NULL;
	out.array_len = 0;
	return out;
}

static runtime_data_value value_make_float(double v) {
	runtime_data_value out;
	out.kind = RUNTIME_FLOAT;
	out.int_value = (long)v;
	out.float_value = v;
	out.str_value = NULL;
	out.array_items = NULL;
	out.array_len = 0;
	return out;
}

static runtime_data_value value_make_string_owned(char *s) {
	runtime_data_value out;
	out.kind = RUNTIME_STRING;
	out.int_value = 0;
	out.float_value = 0.0;
	out.str_value = s;
	out.array_items = NULL;
	out.array_len = 0;
	return out;
}

static runtime_data_value value_make_array_owned(runtime_data_value *items, size_t len) {
	runtime_data_value out;
	out.kind = RUNTIME_ARRAY;
	out.int_value = 0;
	out.float_value = 0.0;
	out.str_value = NULL;
	out.array_items = items;
	out.array_len = len;
	return out;
}

static runtime_data_value value_make_string_copy(const char *s) {
	char *dup;
	if (!s) {
		s = "";
	}
	dup = (char *)malloc(strlen(s) + 1);
	if (!dup) {
		return value_make_string_owned(NULL);
	}
	strcpy(dup, s);
	return value_make_string_owned(dup);
}

static void value_clear(runtime_data_value *v) {
	if (!v) {
		return;
	}
	if (v->kind == RUNTIME_STRING) {
		free(v->str_value);
	} else if (v->kind == RUNTIME_ARRAY) {
		size_t i;
		for (i = 0; i < v->array_len; i++) {
			value_clear(&v->array_items[i]);
		}
		free(v->array_items);
	}
	v->kind = RUNTIME_INT;
	v->int_value = 0;
	v->float_value = 0.0;
	v->str_value = NULL;
	v->array_items = NULL;
	v->array_len = 0;
}

static int value_copy(runtime_data_value *dst, const runtime_data_value *src) {
	size_t i;
	if (src->kind == RUNTIME_INT) {
		*dst = value_make_int(src->int_value);
		return 1;
	}
	if (src->kind == RUNTIME_FLOAT) {
		*dst = value_make_float(src->float_value);
		return 1;
	}
	if (src->kind == RUNTIME_ARRAY) {
		runtime_data_value *items = NULL;
		if (src->array_len > 0) {
			items = (runtime_data_value *)calloc(src->array_len, sizeof(runtime_data_value));
			if (!items) {
				return 0;
			}
			for (i = 0; i < src->array_len; i++) {
				if (!value_copy(&items[i], &src->array_items[i])) {
					size_t j;
					for (j = 0; j < i; j++) {
						value_clear(&items[j]);
					}
					free(items);
					return 0;
				}
			}
		}
		*dst = value_make_array_owned(items, src->array_len);
		return 1;
	}
	*dst = value_make_string_copy(src->str_value ? src->str_value : "");
	return dst->str_value != NULL;
}

static int is_string_literal(const char *s) {
	size_t n;
	if (!s) {
		return 0;
	}
	n = strlen(s);
	return n >= 2 && s[0] == '"' && s[n - 1] == '"';
}

static runtime_data_value parse_string_literal(const char *s) {
	char *buf;
	size_t i;
	size_t n;
	size_t o = 0;

	if (!is_string_literal(s)) {
		return value_make_string_copy("");
	}
	n = strlen(s);
	buf = (char *)malloc(n + 1);
	if (!buf) {
		return value_make_string_owned(NULL);
	}
	for (i = 1; i + 1 < n; i++) {
		if (s[i] == '\\' && i + 1 < n - 1) {
			i++;
			switch (s[i]) {
				case 'n': buf[o++] = '\n'; break;
				case 't': buf[o++] = '\t'; break;
				case 'r': buf[o++] = '\r'; break;
				case '\\': buf[o++] = '\\'; break;
				case '"': buf[o++] = '"'; break;
				default: buf[o++] = s[i]; break;
			}
		} else {
			buf[o++] = s[i];
		}
	}
	buf[o] = '\0';
	return value_make_string_owned(buf);
}

static int value_truthy(const runtime_data_value *v) {
	if (v->kind == RUNTIME_INT) {
		return v->int_value != 0;
	}
	if (v->kind == RUNTIME_FLOAT) {
		return v->float_value != 0.0;
	}
	if (v->kind == RUNTIME_ARRAY) {
		return v->array_len > 0;
	}
	return v->str_value && v->str_value[0] != '\0';
}

static int value_render(const runtime_data_value *v, char **out);

static int value_as_cstr(const runtime_data_value *v, char *tmp, size_t tmp_size, const char **out) {
	if (v->kind == RUNTIME_STRING) {
		*out = v->str_value ? v->str_value : "";
		return 1;
	}
	if (v->kind == RUNTIME_ARRAY) {
		char *rendered = NULL;
		if (!value_render(v, &rendered)) {
			return 0;
		}
		if (snprintf(tmp, tmp_size, "%s", rendered ? rendered : "") < 0) {
			free(rendered);
			return 0;
		}
		free(rendered);
		*out = tmp;
		return 1;
	}
	if (v->kind == RUNTIME_FLOAT) {
		if (snprintf(tmp, tmp_size, "%.17g", v->float_value) < 0) {
			return 0;
		}
		*out = tmp;
		return 1;
	}
	if (snprintf(tmp, tmp_size, "%ld", v->int_value) < 0) {
		return 0;
	}
	*out = tmp;
	return 1;
}

static int value_render(const runtime_data_value *v, char **out) {
	size_t i;
	size_t total = 0;
	char *buf;
	char tmp[64];
	const char *text = NULL;

	*out = NULL;
	if (v->kind != RUNTIME_ARRAY) {
		if (!value_as_cstr(v, tmp, sizeof(tmp), &text)) {
			return 0;
		}
		buf = (char *)malloc(strlen(text) + 1);
		if (!buf) {
			return 0;
		}
		strcpy(buf, text);
		*out = buf;
		return 1;
	}

	total = 2;
	for (i = 0; i < v->array_len; i++) {
		char *item_text = NULL;
		if (!value_render(&v->array_items[i], &item_text)) {
			return 0;
		}
		total += strlen(item_text);
		if (i + 1 < v->array_len) {
			total += 2;
		}
		free(item_text);
	}

	buf = (char *)malloc(total + 1);
	if (!buf) {
		return 0;
	}
	buf[0] = '[';
	buf[1] = '\0';
	for (i = 0; i < v->array_len; i++) {
		char *item_text = NULL;
		if (!value_render(&v->array_items[i], &item_text)) {
			free(buf);
			return 0;
		}
		strcat(buf, item_text);
		free(item_text);
		if (i + 1 < v->array_len) {
			strcat(buf, ", ");
		}
	}
	strcat(buf, "]");
	*out = buf;
	return 1;
}

static int value_concat(runtime_data_value *out, const runtime_data_value *lhs, const runtime_data_value *rhs) {
	char ltmp[64];
	char rtmp[64];
	const char *ls;
	const char *rs;
	char *buf;
	size_t ln;
	size_t rn;

	if (!value_as_cstr(lhs, ltmp, sizeof(ltmp), &ls) || !value_as_cstr(rhs, rtmp, sizeof(rtmp), &rs)) {
		return 0;
	}
	ln = strlen(ls);
	rn = strlen(rs);
	buf = (char *)malloc(ln + rn + 1);
	if (!buf) {
		return 0;
	}
	memcpy(buf, ls, ln);
	memcpy(buf + ln, rs, rn);
	buf[ln + rn] = '\0';
	*out = value_make_string_owned(buf);
	return 1;
}

static char *join_args_text(const runtime_data_value *args, size_t argc) {
	size_t i;
	size_t total = 0;
	char *msg = NULL;
	char *out;
	size_t used = 0;
	for (i = 0; i < argc; i++) {
		if (!value_render(&args[i], &msg)) {
			return NULL;
		}
		total += strlen(msg);
		free(msg);
	}
	out = (char *)malloc(total + 1);
	if (!out) {
		return NULL;
	}
	for (i = 0; i < argc; i++) {
		if (!value_render(&args[i], &msg)) {
			free(out);
			return NULL;
		}
		memcpy(out + used, msg, strlen(msg));
		used += strlen(msg);
		free(msg);
	}
	out[used] = '\0';
	return out;
}

static char *trim_copy(const char *text) {
	size_t start = 0;
	size_t end;
	char *out;
	if (!text) {
		return value_make_string_copy("").str_value;
	}
	end = strlen(text);
	while (start < end && isspace((unsigned char)text[start])) {
		start++;
	}
	while (end > start && isspace((unsigned char)text[end - 1])) {
		end--;
	}
	out = (char *)malloc(end - start + 1);
	if (!out) {
		return NULL;
	}
	memcpy(out, text + start, end - start);
	out[end - start] = '\0';
	return out;
}

static char *lower_copy(const char *text) {
	size_t i;
	size_t n;
	char *out;
	if (!text) {
		return value_make_string_copy("").str_value;
	}
	n = strlen(text);
	out = (char *)malloc(n + 1);
	if (!out) {
		return NULL;
	}
	for (i = 0; i < n; i++) {
		out[i] = (char)tolower((unsigned char)text[i]);
	}
	out[n] = '\0';
	return out;
}

static int read_source_text_file(const char *path, char **out_text, compile_error *err) {
	FILE *fp;
	long n;
	size_t read_n;
	char *buf;

	*out_text = NULL;
	fp = fopen(path, "rb");
	if (!fp) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open input: %s", path);
		return 0;
	}
	if (fseek(fp, 0, SEEK_END) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to seek input: %s", path);
		return 0;
	}
	n = ftell(fp);
	if (n < 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to tell input size: %s", path);
		return 0;
	}
	if (fseek(fp, 0, SEEK_SET) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to rewind input: %s", path);
		return 0;
	}

	buf = (char *)malloc((size_t)n + 1);
	if (!buf) {
		fclose(fp);
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return 0;
	}

	read_n = fread(buf, 1, (size_t)n, fp);
	fclose(fp);
	if (read_n != (size_t)n) {
		free(buf);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to read input: %s", path);
		return 0;
	}
	buf[n] = '\0';
	*out_text = buf;
	return 1;
}

static char *run_command_capture_output(const char *command, compile_error *err) {
	FILE *pipe = NULL;
	char *captured = NULL;
	size_t used = 0;
	size_t cap = 0;
	char chunk[4096];
	size_t nread = 0;
	size_t sc_len = strlen(command) + 6;
	char *stream_command = (char *)malloc(sc_len);
	if (!stream_command) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return NULL;
	}
	snprintf(stream_command, sc_len, "%s 2>&1", command);
	FILE *dbg = fopen("/tmp/last_run_command.txt", "w");
	if (dbg) {
		fwrite(stream_command, 1, strlen(stream_command), dbg);
		fclose(dbg);
	}
	pipe = popen(stream_command, "r");
	if (!pipe) {
		free(stream_command);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to run command");
		return NULL;
	}
	while ((nread = fread(chunk, 1, sizeof(chunk), pipe)) > 0) {
		if (fwrite(chunk, 1, nread, stdout) != nread) {
			pclose(pipe);
			free(stream_command);
			free(captured);
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to stream command output");
			return NULL;
		}
		fflush(stdout);
		if (used + nread + 1 > cap) {
			size_t new_cap = cap == 0 ? 8192 : cap * 2;
			while (new_cap < used + nread + 1) {
				new_cap *= 2;
			}
			char *grown = (char *)realloc(captured, new_cap);
			if (!grown) {
				pclose(pipe);
				free(stream_command);
				free(captured);
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				return NULL;
			}
			captured = grown;
			cap = new_cap;
		}
		memcpy(captured + used, chunk, nread);
		used += nread;
	}
	if (pclose(pipe) != 0) {
		free(stream_command);
		free(captured);
		error_set(err, ERR_SEMANTIC, 0, 0, "command failed");
		return NULL;
	}
	free(stream_command);
	if (!captured) {
		captured = (char *)calloc(1, 1);
		if (!captured) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return NULL;
		}
	} else {
		captured[used] = '\0';
	}
	return captured;
}

static int host_file_exists(const char *path) {
	FILE *fp;
	if (!path || !*path) {
		return 0;
	}
	fp = fopen(path, "rb");
	if (!fp) {
		return 0;
	}
	fclose(fp);
	return 1;
}

static char *host_read_text_file(const char *path, compile_error *err) {
	FILE *fp;
	long len;
	size_t read_len;
	char *buf;

	if (!path || !*path) {
		return value_make_string_copy("").str_value;
	}
	fp = fopen(path, "rb");
	if (!fp) {
		return value_make_string_copy("").str_value;
	}
	if (fseek(fp, 0, SEEK_END) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to seek file: %s", path);
		return NULL;
	}
	len = ftell(fp);
	if (len < 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to stat file: %s", path);
		return NULL;
	}
	if (fseek(fp, 0, SEEK_SET) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to rewind file: %s", path);
		return NULL;
	}
	buf = (char *)malloc((size_t)len + 1);
	if (!buf) {
		fclose(fp);
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return NULL;
	}
	read_len = fread(buf, 1, (size_t)len, fp);
	fclose(fp);
	if (read_len != (size_t)len) {
		free(buf);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to read file: %s", path);
		return NULL;
	}
	buf[len] = '\0';
	return buf;
}

static int host_write_text_file(const char *path, const char *contents) {
	FILE *fp;
	size_t len;
	if (!path || !*path || !contents) {
		g_host_errno = EINVAL;
		return -1;
	}
	fp = fopen(path, "wb");
	if (!fp) {
		g_host_errno = errno;
		return -1;
	}
	len = strlen(contents);
	if (fwrite(contents, 1, len, fp) != len || fclose(fp) != 0) {
		g_host_errno = errno ? errno : EIO;
		return -1;
	}
	g_host_errno = 0;
	return 0;
}

static char *host_make_temp_dir(const char *prefix) {
	const char *base = (prefix && *prefix) ? prefix : "s";
	char *path;
	size_t len = strlen(base) + 20;
	path = (char *)malloc(len);
	if (!path) {
		g_host_errno = ENOMEM;
		return NULL;
	}
	snprintf(path, len, "/tmp/%s-XXXXXX", base);
	if (!mkdtemp(path)) {
		g_host_errno = errno;
		free(path);
		return NULL;
	}
	g_host_errno = 0;
	return path;
}

static int host_native_family(int family) {
	if (family == 0) return AF_UNSPEC;
	if (family == 2) return AF_INET;
	if (family == 10) return AF_INET6;
	return family;
}

static int host_native_sockopt_level(int level) {
	if (level == 1) return SOL_SOCKET;
	if (level == 6) return IPPROTO_TCP;
	if (level == 17) return IPPROTO_UDP;
	return level;
}

static int host_native_sockopt_name(int level, int option) {
	if (level != 1) return option;
	switch (option) {
		case 2: return SO_REUSEADDR;
		case 7: return SO_SNDBUF;
		case 8: return SO_RCVBUF;
		case 9: return SO_KEEPALIVE;
#ifdef SO_REUSEPORT
		case 15: return SO_REUSEPORT;
#endif
		default: return option;
	}
}

static int host_sockaddr(const char *ip, int port, int family, struct sockaddr_storage *storage, socklen_t *len) {
	struct addrinfo hints;
	struct addrinfo *resolved = NULL;
	char service[16];
	int gai_rc;
	memset(storage, 0, sizeof(*storage));
	int native_family = host_native_family(family);
	if (native_family != AF_INET && native_family != AF_INET6) {
		g_host_errno = EAFNOSUPPORT;
		return 0;
	}
	memset(&hints, 0, sizeof(hints));
	hints.ai_family = native_family;
	hints.ai_socktype = 0;
	hints.ai_flags = AI_NUMERICSERV | ((!ip || !*ip) ? AI_PASSIVE : 0);
	snprintf(service, sizeof(service), "%d", port);
	gai_rc = getaddrinfo((ip && *ip) ? ip : NULL, service, &hints, &resolved);
	if (gai_rc == 0 && resolved && resolved->ai_addrlen <= sizeof(*storage)) {
		memcpy(storage, resolved->ai_addr, resolved->ai_addrlen);
		*len = (socklen_t)resolved->ai_addrlen;
		freeaddrinfo(resolved);
		g_host_errno = 0;
		return 1;
	}
	if (resolved) freeaddrinfo(resolved);
	if (native_family == AF_INET) {
		struct sockaddr_in *addr = (struct sockaddr_in *)storage;
		addr->sin_family = AF_INET;
		addr->sin_port = htons((unsigned short)port);
		if (!ip || !*ip || strcmp(ip, "0.0.0.0") == 0) {
			addr->sin_addr.s_addr = htonl(INADDR_ANY);
		} else if (inet_pton(AF_INET, ip, &addr->sin_addr) != 1) {
			g_host_errno = EINVAL;
			return 0;
		}
		*len = sizeof(*addr);
		return 1;
	}
	if (native_family == AF_INET6) {
		struct sockaddr_in6 *addr = (struct sockaddr_in6 *)storage;
		addr->sin6_family = AF_INET6;
		addr->sin6_port = htons((unsigned short)port);
		if (!ip || !*ip || strcmp(ip, "::") == 0) {
			addr->sin6_addr = in6addr_any;
		} else if (inet_pton(AF_INET6, ip, &addr->sin6_addr) != 1) {
			g_host_errno = EINVAL;
			return 0;
		}
		*len = sizeof(*addr);
		return 1;
	}
	g_host_errno = EAFNOSUPPORT;
	return 0;
}

static int host_connect_deadline(int fd, const char *host, int port, int family, int timeout_ms) {
	struct sockaddr_storage addr;
	socklen_t addr_len;
	struct pollfd pfd;
	int old_flags;
	int rc;
	int socket_error = 0;
	socklen_t error_len = sizeof(socket_error);
	if (timeout_ms < 0 || !host_sockaddr(host, port, family, &addr, &addr_len)) {
		if (timeout_ms < 0) g_host_errno = EINVAL;
		return -1;
	}
	old_flags = fcntl(fd, F_GETFL, 0);
	if (old_flags < 0 || fcntl(fd, F_SETFL, old_flags | O_NONBLOCK) < 0) {
		g_host_errno = errno;
		return -1;
	}
	rc = connect(fd, (struct sockaddr *)&addr, addr_len);
	if (rc < 0 && errno == EINPROGRESS) {
		pfd.fd = fd;
		pfd.events = POLLOUT;
		pfd.revents = 0;
		do {
			rc = poll(&pfd, 1, timeout_ms);
		} while (rc < 0 && errno == EINTR);
		if (rc == 0) {
			socket_error = ETIMEDOUT;
			rc = -1;
		} else if (rc > 0) {
			if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &socket_error, &error_len) < 0) socket_error = errno;
			rc = socket_error == 0 ? 0 : -1;
		}
	} else if (rc < 0) {
		socket_error = errno;
	}
	(void)fcntl(fd, F_SETFL, old_flags);
	g_host_errno = rc < 0 ? (socket_error ? socket_error : errno) : 0;
	return rc;
}

static int host_sockaddr_text(const struct sockaddr *addr, char *ip, size_t ip_cap, int *port) {
	if (!addr || !ip || ip_cap == 0) return 0;
	if (addr->sa_family == AF_INET) {
		const struct sockaddr_in *v4 = (const struct sockaddr_in *)addr;
		if (!inet_ntop(AF_INET, &v4->sin_addr, ip, (socklen_t)ip_cap)) return 0;
		if (port) *port = (int)ntohs(v4->sin_port);
		return 1;
	}
	if (addr->sa_family == AF_INET6) {
		const struct sockaddr_in6 *v6 = (const struct sockaddr_in6 *)addr;
		if (!inet_ntop(AF_INET6, &v6->sin6_addr, ip, (socklen_t)ip_cap)) return 0;
		if (port) *port = (int)ntohs(v6->sin6_port);
		return 1;
	}
	return 0;
}

static int host_int_arg(const runtime_data_value *arg, long *out) {
	if (arg->kind != RUNTIME_INT) {
		return 0;
	}
	*out = arg->int_value;
	return 1;
}

static int host_socket_name(int fd, int peer, char *ip, size_t ip_cap, int *port) {
	struct sockaddr_storage storage;
	socklen_t len = sizeof(storage);
	int rc;
	memset(&storage, 0, sizeof(storage));
	rc = peer ? getpeername(fd, (struct sockaddr *)&storage, &len)
	          : getsockname(fd, (struct sockaddr *)&storage, &len);
	if (rc < 0) {
		g_host_errno = errno;
		return 0;
	}
	if (storage.ss_family == AF_INET) {
		const struct sockaddr_in *addr = (const struct sockaddr_in *)&storage;
		if (ip && ip_cap > 0 && !inet_ntop(AF_INET, &addr->sin_addr, ip, (socklen_t)ip_cap)) {
			g_host_errno = errno;
			return 0;
		}
		if (port) *port = (int)ntohs(addr->sin_port);
	} else if (storage.ss_family == AF_INET6) {
		const struct sockaddr_in6 *addr = (const struct sockaddr_in6 *)&storage;
		if (ip && ip_cap > 0 && !inet_ntop(AF_INET6, &addr->sin6_addr, ip, (socklen_t)ip_cap)) {
			g_host_errno = errno;
			return 0;
		}
		if (port) *port = (int)ntohs(addr->sin6_port);
	} else {
		g_host_errno = EAFNOSUPPORT;
		return 0;
	}
	g_host_errno = 0;
	return 1;
}

static int host_set_socket_deadline(int fd, int read_timeout_ms, int write_timeout_ms) {
	struct timeval read_timeout;
	struct timeval write_timeout;
	int rc;
	if (read_timeout_ms < 0 || write_timeout_ms < 0) {
		g_host_errno = EINVAL;
		return -1;
	}
	read_timeout.tv_sec = read_timeout_ms / 1000;
	read_timeout.tv_usec = (read_timeout_ms % 1000) * 1000;
	write_timeout.tv_sec = write_timeout_ms / 1000;
	write_timeout.tv_usec = (write_timeout_ms % 1000) * 1000;
	rc = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &read_timeout, sizeof(read_timeout));
	if (rc == 0) rc = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &write_timeout, sizeof(write_timeout));
	g_host_errno = rc < 0 ? errno : 0;
	return rc;
}

static int host_poller_create(void) {
#if defined(__linux__)
	int fd = epoll_create1(EPOLL_CLOEXEC);
#elif defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
	int fd = kqueue();
	if (fd >= 0) (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
#else
	int fd = -1;
	errno = ENOSYS;
#endif
	g_host_errno = fd < 0 ? errno : 0;
	return fd;
}

static int host_poller_change(int poller_fd, int fd, int events, int add) {
	int rc = -1;
#if defined(__linux__)
	struct epoll_event event;
	memset(&event, 0, sizeof(event));
	if (events & POLLIN) event.events |= EPOLLIN;
	if (events & POLLOUT) event.events |= EPOLLOUT;
	event.events |= EPOLLERR | EPOLLHUP;
	event.data.fd = fd;
	rc = epoll_ctl(poller_fd, add ? EPOLL_CTL_ADD : EPOLL_CTL_DEL, fd, add ? &event : NULL);
#elif defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
	struct kevent changes[2];
	int count = 0;
	if ((events & POLLIN) || !add) EV_SET(&changes[count++], fd, EVFILT_READ, add ? EV_ADD : EV_DELETE, 0, 0, NULL);
	if ((events & POLLOUT) || !add) EV_SET(&changes[count++], fd, EVFILT_WRITE, add ? EV_ADD : EV_DELETE, 0, 0, NULL);
	rc = kevent(poller_fd, changes, count, NULL, 0, NULL);
	if (!add && rc < 0 && errno == ENOENT) rc = 0;
#else
	(void)poller_fd; (void)fd; (void)events; (void)add;
	errno = ENOSYS;
#endif
	g_host_errno = rc < 0 ? errno : 0;
	return rc;
}

static int host_poller_wait(int poller_fd, int max_events, int timeout_ms, runtime_data_value *out) {
	runtime_data_value *items = NULL;
	int n = -1;
	int i;
	if (max_events <= 0 || timeout_ms < -1) {
		g_host_errno = EINVAL;
		return 0;
	}
	items = (runtime_data_value *)calloc((size_t)max_events, sizeof(*items));
	if (!items) return 0;
#if defined(__linux__)
	{
		struct epoll_event *events = (struct epoll_event *)calloc((size_t)max_events, sizeof(*events));
		if (!events) { free(items); return 0; }
		n = epoll_wait(poller_fd, events, max_events, timeout_ms);
		if (n >= 0) for (i = 0; i < n; i++) items[i] = value_make_int(events[i].data.fd);
		free(events);
	}
#elif defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
	{
		struct kevent *events = (struct kevent *)calloc((size_t)max_events, sizeof(*events));
		struct timespec timeout;
		struct timespec *timeout_ptr = NULL;
		if (!events) { free(items); return 0; }
		if (timeout_ms >= 0) {
			timeout.tv_sec = timeout_ms / 1000;
			timeout.tv_nsec = (timeout_ms % 1000) * 1000000L;
			timeout_ptr = &timeout;
		}
		n = kevent(poller_fd, NULL, 0, events, max_events, timeout_ptr);
		if (n >= 0) for (i = 0; i < n; i++) items[i] = value_make_int((long)events[i].ident);
		free(events);
	}
#else
	(void)poller_fd; (void)timeout_ms; (void)i;
	errno = ENOSYS;
#endif
	if (n < 0) {
		g_host_errno = errno;
		free(items);
		return 0;
	}
	g_host_errno = 0;
	*out = value_make_array_owned(items, (size_t)n);
	return 1;
}

static int host_dispatch_libc_ffi(const char *name, const runtime_data_value *args, size_t argc,
	runtime_data_value *out, compile_error *err) {
	char spec[IR_OPERAND_CAP];
	char *abi;
	char *symbol;
	char *return_type;
	char *param_types;
	char *save = NULL;
	void *address;
	uintptr_t av[6] = {0, 0, 0, 0, 0, 0};
	uintptr_t result;
	size_t i;
	if (strncmp(name, "__ffi_", 6) != 0) return 0;
	if (argc > 6 || strlen(name + 6) >= sizeof(spec)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "libc FFI supports at most 6 arguments");
		return -1;
	}
	snprintf(spec, sizeof(spec), "%s", name + 6);
	abi = strtok_r(spec, "$", &save);
	symbol = strtok_r(NULL, "$", &save);
	return_type = strtok_r(NULL, "$", &save);
	param_types = strtok_r(NULL, "$", &save);
	(void)param_types;
	if (!abi || strcmp(abi, "libc") != 0 || !symbol || !return_type) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid libc FFI call descriptor");
		return -1;
	}
	address = dlsym(RTLD_DEFAULT, symbol);
	if (!address) {
		error_set(err, ERR_SEMANTIC, 0, 0, "libc symbol not found: %s", symbol);
		return -1;
	}
	for (i = 0; i < argc; i++) {
		if (args[i].kind == RUNTIME_STRING) av[i] = (uintptr_t)(args[i].str_value ? args[i].str_value : "");
		else if (args[i].kind == RUNTIME_INT) av[i] = (uintptr_t)args[i].int_value;
		else {
			error_set(err, ERR_SEMANTIC, 0, 0, "libc FFI argument %zu must be int, bool, or string", i + 1);
			return -1;
		}
	}
	switch (argc) {
		case 0: result = ((uintptr_t (*)(void))address)(); break;
		case 1: result = ((uintptr_t (*)(uintptr_t))address)(av[0]); break;
		case 2: result = ((uintptr_t (*)(uintptr_t, uintptr_t))address)(av[0], av[1]); break;
		case 3: result = ((uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t))address)(av[0], av[1], av[2]); break;
		case 4: result = ((uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t))address)(av[0], av[1], av[2], av[3]); break;
		case 5: result = ((uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t))address)(av[0], av[1], av[2], av[3], av[4]); break;
		default: result = ((uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t))address)(av[0], av[1], av[2], av[3], av[4], av[5]); break;
	}
	if (strcmp(return_type, "string") == 0) {
		*out = value_make_string_copy(result ? (const char *)result : "");
		if (!out->str_value) { error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory"); return -1; }
	} else {
		long signed_result = (long)(int32_t)(uint32_t)result;
		*out = value_make_int(signed_result);
		g_host_errno = signed_result < 0 ? errno : 0;
	}
	return 1;
}

bool seed_bootstrap_two_stage_check(const char *compiler_source_path, const char *output_dir, compile_error *err);

static int compile_s_file_to_ir(const char *input_path, const char *output_path, compile_error *err) {
	char *source_text = NULL;
	token_vec tokens;
	parse_result parsed;
	IR ir;
	FILE *out = NULL;
	int ok = 0;

	if (!read_source_text_file(input_path, &source_text, err)) {
		return 0;
	}
	if (!lexer_scan(source_text, &tokens, err)) {
		free(source_text);
		return 0;
	}
	parsed = parser_parse_tokens(&tokens, err);
	token_vec_free(&tokens);
	if (!parsed.root) {
		free(source_text);
		return 0;
	}
	if (!semantic_analyze(parsed.root, err)) {
		parser_parse_result_free(&parsed);
		free(source_text);
		return 0;
	}

	ir_init(&ir);
	if (!ir_generate_from_ast(parsed.root, &ir, err)) {
		ir_free(&ir);
		parser_parse_result_free(&parsed);
		free(source_text);
		return 0;
	}

	out = fopen(output_path, "wb");
	if (!out) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open output: %s", output_path);
		goto done;
	}
	generate_code(&ir, out);
	if (ferror(out)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing compiler output");
		goto done;
	}
	ok = 1;

done:
	if (out) {
		fclose(out);
	}
	ir_free(&ir);
	parser_parse_result_free(&parsed);
	free(source_text);
	return ok;
}

static void print_compile_error_local(const compile_error *err) {
	if (!err || !error_is_set(err)) {
		return;
	}
	fprintf(stderr, "error[%d] at %zu:%zu: %s\n", (int)err->code, err->line, err->column, err->message);
}

static int host_dispatch_call(
	const char *name,
	const runtime_data_value *args,
	size_t argc,
	runtime_data_value *out,
	compile_error *err
) {
	int ffi_status;
	if (g_runtime_profile_enabled) {
		runtime_profile_bump(g_runtime_profile_host, &g_runtime_profile_host_len, 256, name);
	}
	ffi_status = host_dispatch_libc_ffi(name, args, argc, out, err);
	if (ffi_status != 0) return ffi_status > 0;
	if (strcmp(name, "host_args") == 0) {
		size_t i;
		runtime_data_value *items = NULL;
		(void)args;
		if (argc != 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "host_args expects 0 args");
			return 0;
		}
		if (g_host_argc > 0) {
			items = (runtime_data_value *)calloc((size_t)g_host_argc, sizeof(runtime_data_value));
			if (!items) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				return 0;
			}
			for (i = 0; i < (size_t)g_host_argc; i++) {
				items[i] = value_make_string_copy(g_host_argv && g_host_argv[i] ? g_host_argv[i] : "");
				if (items[i].str_value == NULL) {
					size_t j;
					for (j = 0; j < i; j++) {
						value_clear(&items[j]);
					}
					free(items);
					error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
					return 0;
				}
			}
		}
		*out = value_make_array_owned(items, (size_t)(g_host_argc > 0 ? g_host_argc : 0));
		return 1;
	}
	if (strcmp(name, "buildcfg_goarch") == 0) {
		(void)args;
		if (argc != 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "buildcfg_goarch expects 0 args");
			return 0;
		}
		*out = value_make_string_copy("amd64");
		if (!out->str_value) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return 0;
		}
		return 1;
	}
	if (strcmp(name, "buildcfg_check") == 0) {
		(void)args;
		if (argc != 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "buildcfg_check expects 0 args");
			return 0;
		}
		*out = value_make_string_copy("");
		if (!out->str_value) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return 0;
		}
		return 1;
	}
	if (strcmp(name, "arch_dispatch_init") == 0) {
		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "arch_dispatch_init expects 1 arg");
			return 0;
		}
		*out = value_make_string_copy("");
		if (!out->str_value) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return 0;
		}
		return 1;
	}
	if (strcmp(name, "eprintln") == 0) {
		char *joined = join_args_text(args, argc);
		if (!joined) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "failed to render eprintln argument");
			return 0;
		}
		fprintf(stderr, "%s\n", joined);
		free(joined);
		*out = value_make_int(0);
		return 1;
	}
	if (strcmp(name, "print") == 0) {
		char *joined = join_args_text(args, argc);
		if (!joined) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "failed to render print argument");
			return 0;
		}
		printf("%s\n", joined);
		free(joined);
		*out = value_make_int(0);
		return 1;
	}
	if (strcmp(name, "println") == 0) {
		char *joined = join_args_text(args, argc);
		if (!joined) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "failed to render println argument");
			return 0;
		}
		printf("%s\n", joined);
		free(joined);
		*out = value_make_int(0);
		return 1;
	}
	if (strcmp(name, "__host_println") == 0) {
		char *joined = join_args_text(args, argc);
		if (!joined) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "failed to render __host_println argument");
			return 0;
		}
		printf("%s\n", joined);
		free(joined);
		*out = value_make_int(0);
		return 1;
	}
	if (strcmp(name, "__host_eprintln") == 0) {
		char *joined = join_args_text(args, argc);
		if (!joined) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "failed to render __host_eprintln argument");
			return 0;
		}
		fprintf(stderr, "%s\n", joined);
		free(joined);
		*out = value_make_int(0);
		return 1;
	}
	if (strcmp(name, "__host_read_to_string") == 0) {
		const char *path = NULL;
		char path_buf[256];
		char *content;
		if (argc != 1 || !value_as_cstr(&args[0], path_buf, sizeof(path_buf), &path)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__host_read_to_string expects a path");
			return 0;
		}
		content = host_read_text_file(path, err);
		if (!content) return 0;
		g_host_errno = content[0] == '\0' && !host_file_exists(path) ? ENOENT : 0;
		*out = value_make_string_owned(content);
		return 1;
	}
	if (strcmp(name, "__host_read_binary_file") == 0 || strcmp(name, "__host_read_binary_file_range") == 0) {
		const char *path = NULL;
		char path_buf[256];
		long start = 0;
		long count = -1;
		long file_size;
		size_t read_count;
		unsigned char *bytes = NULL;
		runtime_data_value *items = NULL;
		FILE *fp = NULL;
		size_t i;
		size_t expected = strcmp(name, "__host_read_binary_file_range") == 0 ? 3u : 1u;
		if (argc != expected || !value_as_cstr(&args[0], path_buf, sizeof(path_buf), &path) ||
		    (expected == 3u && (!host_int_arg(&args[1], &start) || !host_int_arg(&args[2], &count))) ||
		    start < 0 || count < -1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "%s received invalid arguments", name);
			return 0;
		}
		fp = fopen(path, "rb");
		if (!fp || fseek(fp, 0, SEEK_END) != 0 || (file_size = ftell(fp)) < 0) {
			if (fp) fclose(fp);
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to open binary file: %s", path);
			return 0;
		}
		if (start > file_size) start = file_size;
		if (count < 0 || count > file_size - start) count = file_size - start;
		if (fseek(fp, start, SEEK_SET) != 0) {
			fclose(fp);
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to seek binary file: %s", path);
			return 0;
		}
		if (count > 0) {
			bytes = (unsigned char *)malloc((size_t)count);
			items = (runtime_data_value *)calloc((size_t)count, sizeof(runtime_data_value));
			if (!bytes || !items) {
				free(bytes); free(items); fclose(fp);
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				return 0;
			}
			read_count = fread(bytes, 1, (size_t)count, fp);
			if (read_count != (size_t)count) {
				free(bytes); free(items); fclose(fp);
				error_set(err, ERR_SEMANTIC, 0, 0, "failed to read binary file: %s", path);
				return 0;
			}
			for (i = 0; i < (size_t)count; i++) items[i] = value_make_int(bytes[i]);
			free(bytes);
		}
		fclose(fp);
		*out = value_make_array_owned(items, (size_t)count);
		return 1;
	}
	if (strcmp(name, "__host_write_text_file") == 0) {
		const char *path = NULL;
		const char *contents = NULL;
		char path_buf[256], contents_buf[64];
		if (argc != 2 || !value_as_cstr(&args[0], path_buf, sizeof(path_buf), &path) ||
		    !value_as_cstr(&args[1], contents_buf, sizeof(contents_buf), &contents)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__host_write_text_file expects path and contents");
			return 0;
		}
		*out = value_make_int(host_write_text_file(path, contents));
		return 1;
	}
	if (strcmp(name, "__host_char_at") == 0) {
		const char *text = NULL;
		char text_buf[64];
		long index;
		char ch[2];
		if (argc != 2 || !value_as_cstr(&args[0], text_buf, sizeof(text_buf), &text) ||
		    !host_int_arg(&args[1], &index)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__host_char_at expects string and int");
			return 0;
		}
		if (index < 0 || (size_t)index >= strlen(text)) {
			*out = value_make_string_copy("");
			return out->str_value != NULL;
		}
		ch[0] = text[index];
		ch[1] = '\0';
		*out = value_make_string_copy(ch);
		return out->str_value != NULL;
	}
	if (strcmp(name, "__host_byte_at") == 0) {
		const char *text = NULL;
		char text_buf[64];
		long index;
		if (argc != 2 || !value_as_cstr(&args[0], text_buf, sizeof(text_buf), &text) ||
		    !host_int_arg(&args[1], &index)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__host_byte_at expects string and int");
			return 0;
		}
		if (index < 0 || (size_t)index >= strlen(text)) {
			*out = value_make_int(-1);
			return 1;
		}
		*out = value_make_int((unsigned char)text[index]);
		return 1;
	}
	if (strcmp(name, "__host_slice") == 0) {
		const char *text = NULL;
		char text_buf[64];
		long start, end;
		size_t text_len;
		char *slice;
		if (argc != 3 || !value_as_cstr(&args[0], text_buf, sizeof(text_buf), &text) ||
		    !host_int_arg(&args[1], &start) || !host_int_arg(&args[2], &end)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__host_slice expects string, start, and end");
			return 0;
		}
		text_len = strlen(text);
		if (start < 0 || end < start || (size_t)end > text_len) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__host_slice range is out of bounds");
			return 0;
		}
		slice = (char *)malloc((size_t)(end - start) + 1);
		if (!slice) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return 0;
		}
		memcpy(slice, text + start, (size_t)(end - start));
		slice[end - start] = '\0';
		*out = value_make_string_owned(slice);
		return 1;
	}
	if (strcmp(name, "__host_make_temp_dir") == 0) {
		const char *prefix = NULL;
		char prefix_buf[64];
		char *path;
		if (argc != 1 || !value_as_cstr(&args[0], prefix_buf, sizeof(prefix_buf), &prefix)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__host_make_temp_dir expects a prefix");
			return 0;
		}
		path = host_make_temp_dir(prefix);
		*out = path ? value_make_string_owned(path) : value_make_string_copy("");
		return 1;
	}
	if (strcmp(name, "__sys_errno") == 0) {
		if (argc != 0) { error_set(err, ERR_SEMANTIC, 0, 0, "__sys_errno expects 0 args"); return 0; }
		*out = value_make_int(g_host_errno);
		return 1;
	}
	if (strcmp(name, "__sys_strerror") == 0) {
		long code;
		if (argc != 1 || !host_int_arg(&args[0], &code)) { error_set(err, ERR_SEMANTIC, 0, 0, "__sys_strerror expects errno"); return 0; }
		*out = value_make_string_copy(strerror((int)code));
		return out->str_value != NULL;
	}
	if (strcmp(name, "__sys_socket") == 0) {
		long domain, type, protocol;
		int fd;
		if (argc != 3 || !host_int_arg(&args[0], &domain) || !host_int_arg(&args[1], &type) || !host_int_arg(&args[2], &protocol)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_socket expects 3 integer args"); return 0;
		}
		fd = socket(host_native_family((int)domain), (int)type, (int)protocol);
		g_host_errno = fd < 0 ? errno : 0;
		*out = value_make_int(fd);
		return 1;
	}
	if (strcmp(name, "__sys_bind") == 0 || strcmp(name, "__sys_connect") == 0) {
		long fd, port, family;
		const char *ip = NULL;
		char ip_buf[64];
		struct sockaddr_storage addr;
		socklen_t addr_len;
		int rc;
		if (argc != 4 || !host_int_arg(&args[0], &fd) || !value_as_cstr(&args[1], ip_buf, sizeof(ip_buf), &ip) ||
		    !host_int_arg(&args[2], &port) || !host_int_arg(&args[3], &family)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "%s expects fd, ip, port, family", name); return 0;
		}
		if (!host_sockaddr(ip, (int)port, (int)family, &addr, &addr_len)) rc = -1;
		else if (strcmp(name, "__sys_bind") == 0) rc = bind((int)fd, (struct sockaddr *)&addr, addr_len);
		else rc = connect((int)fd, (struct sockaddr *)&addr, addr_len);
		g_host_errno = rc < 0 && g_host_errno == 0 ? errno : (rc < 0 ? g_host_errno : 0);
		*out = value_make_int(rc);
		return 1;
	}
	if (strcmp(name, "__sys_connect_deadline") == 0) {
		long fd, port, family, timeout_ms;
		const char *host = NULL;
		char host_buf[256];
		int rc;
		if (argc != 5 || !host_int_arg(&args[0], &fd) ||
		    !value_as_cstr(&args[1], host_buf, sizeof(host_buf), &host) ||
		    !host_int_arg(&args[2], &port) || !host_int_arg(&args[3], &family) ||
		    !host_int_arg(&args[4], &timeout_ms)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_connect_deadline expects fd, host, port, family, timeout_ms"); return 0;
		}
		rc = host_connect_deadline((int)fd, host, (int)port, (int)family, (int)timeout_ms);
		*out = value_make_int(rc);
		return 1;
	}
	if (strcmp(name, "__sys_resolve_ip") == 0) {
		const char *host = NULL;
		char host_buf[256];
		long family;
		struct addrinfo hints;
		struct addrinfo *list = NULL, *it;
		runtime_data_value *items = NULL;
		size_t count = 0, cap = 0;
		int rc;
		if (argc != 2 || !value_as_cstr(&args[0], host_buf, sizeof(host_buf), &host) || !host_int_arg(&args[1], &family)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_resolve_ip expects host and family"); return 0;
		}
		memset(&hints, 0, sizeof(hints));
		hints.ai_family = host_native_family((int)family);
		hints.ai_socktype = SOCK_STREAM;
		rc = getaddrinfo(host, NULL, &hints, &list);
		if (rc != 0) {
			g_host_errno = EINVAL;
			*out = value_make_array_owned(NULL, 0);
			return 1;
		}
		for (it = list; it; it = it->ai_next) {
			char ip[INET6_ADDRSTRLEN];
			size_t i;
			int duplicate = 0;
			if (!host_sockaddr_text(it->ai_addr, ip, sizeof(ip), NULL)) continue;
			for (i = 0; i < count; i++) {
				if (items[i].str_value && strcmp(items[i].str_value, ip) == 0) { duplicate = 1; break; }
			}
			if (duplicate) continue;
			if (count == cap) {
				size_t next_cap = cap ? cap * 2 : 4;
				runtime_data_value *next = (runtime_data_value *)realloc(items, next_cap * sizeof(*items));
				if (!next) { freeaddrinfo(list); free(items); error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory"); return 0; }
				items = next; cap = next_cap;
			}
			items[count] = value_make_string_copy(ip);
			if (!items[count].str_value) { freeaddrinfo(list); free(items); error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory"); return 0; }
			count++;
		}
		freeaddrinfo(list);
		g_host_errno = 0;
		*out = value_make_array_owned(items, count);
		return 1;
	}
	if (strcmp(name, "__sys_local_port") == 0 || strcmp(name, "__sys_peer_port") == 0 ||
	    strcmp(name, "__sys_local_ip") == 0 || strcmp(name, "__sys_peer_ip") == 0) {
		long fd;
		char ip[INET6_ADDRSTRLEN];
		int port = 0;
		int peer = strstr(name, "peer") != NULL;
		int want_ip = strstr(name, "_ip") != NULL;
		if (argc != 1 || !host_int_arg(&args[0], &fd)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "%s expects an fd", name); return 0;
		}
		if (!host_socket_name((int)fd, peer, ip, sizeof(ip), &port)) {
			*out = want_ip ? value_make_string_copy("") : value_make_int(-1);
		} else {
			*out = want_ip ? value_make_string_copy(ip) : value_make_int(port);
		}
		return want_ip ? out->str_value != NULL : 1;
	}
	if (strcmp(name, "__sys_listen") == 0 || strcmp(name, "__sys_accept") == 0 || strcmp(name, "__sys_close") == 0) {
		long fd, arg = 0;
		int rc;
		size_t expected = strcmp(name, "__sys_listen") == 0 ? 2u : 1u;
		if (argc != expected || !host_int_arg(&args[0], &fd) || (expected == 2 && !host_int_arg(&args[1], &arg))) {
			error_set(err, ERR_SEMANTIC, 0, 0, "%s has invalid arguments", name); return 0;
		}
		if (strcmp(name, "__sys_listen") == 0) rc = listen((int)fd, (int)arg);
		else if (strcmp(name, "__sys_accept") == 0) rc = accept((int)fd, NULL, NULL);
		else rc = close((int)fd);
		g_host_errno = rc < 0 ? errno : 0;
		*out = value_make_int(rc);
		return 1;
	}
	if (strcmp(name, "__sys_read_string") == 0) {
		long fd, max_bytes;
		char *buf;
		ssize_t n;
		if (argc != 2 || !host_int_arg(&args[0], &fd) || !host_int_arg(&args[1], &max_bytes) || max_bytes < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_read_string expects fd and non-negative size"); return 0;
		}
		buf = (char *)malloc((size_t)max_bytes + 1);
		if (!buf) { error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory"); return 0; }
		n = read((int)fd, buf, (size_t)max_bytes);
		g_host_errno = n < 0 ? errno : 0;
		if (n < 0) n = 0;
		buf[n] = '\0';
		*out = value_make_string_owned(buf);
		return 1;
	}
	if (strcmp(name, "__sys_write_string") == 0) {
		long fd;
		const char *data = NULL;
		char data_buf[64];
		ssize_t n;
		if (argc != 2 || !host_int_arg(&args[0], &fd) || !value_as_cstr(&args[1], data_buf, sizeof(data_buf), &data)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_write_string expects fd and data"); return 0;
		}
		n = write((int)fd, data, strlen(data));
		g_host_errno = n < 0 ? errno : 0;
		*out = value_make_int((long)n);
		return 1;
	}
	if (strcmp(name, "__sys_sendto_string") == 0) {
		long fd, port, family;
		const char *data = NULL, *ip = NULL;
		char data_buf[64], ip_buf[64];
		struct sockaddr_storage addr;
		socklen_t addr_len;
		ssize_t n;
		if (argc != 5 || !host_int_arg(&args[0], &fd) ||
		    !value_as_cstr(&args[1], data_buf, sizeof(data_buf), &data) ||
		    !value_as_cstr(&args[2], ip_buf, sizeof(ip_buf), &ip) ||
		    !host_int_arg(&args[3], &port) || !host_int_arg(&args[4], &family)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_sendto_string expects fd, data, ip, port, family"); return 0;
		}
		if (!host_sockaddr(ip, (int)port, (int)family, &addr, &addr_len)) n = -1;
		else n = sendto((int)fd, data, strlen(data), 0, (struct sockaddr *)&addr, addr_len);
		g_host_errno = n < 0 && g_host_errno == 0 ? errno : (n < 0 ? g_host_errno : 0);
		*out = value_make_int((long)n);
		return 1;
	}
	if (strcmp(name, "__sys_recvfrom_string") == 0) {
		long fd, max_bytes;
		char *buf;
		struct sockaddr_storage peer;
		socklen_t peer_len = sizeof(peer);
		ssize_t n;
		if (argc != 2 || !host_int_arg(&args[0], &fd) || !host_int_arg(&args[1], &max_bytes) || max_bytes < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_recvfrom_string expects fd and non-negative size"); return 0;
		}
		buf = (char *)malloc((size_t)max_bytes + 1);
		if (!buf) { error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory"); return 0; }
		memset(&peer, 0, sizeof(peer));
		n = recvfrom((int)fd, buf, (size_t)max_bytes, 0, (struct sockaddr *)&peer, &peer_len);
		g_host_errno = n < 0 ? errno : 0;
		g_last_recvfrom_ip[0] = '\0';
		g_last_recvfrom_port = 0;
		if (n >= 0) (void)host_sockaddr_text((struct sockaddr *)&peer, g_last_recvfrom_ip, sizeof(g_last_recvfrom_ip), &g_last_recvfrom_port);
		if (n < 0) n = 0;
		buf[n] = '\0';
		*out = value_make_string_owned(buf);
		return 1;
	}
	if (strcmp(name, "__sys_last_recvfrom_ip") == 0) {
		if (argc != 0) { error_set(err, ERR_SEMANTIC, 0, 0, "__sys_last_recvfrom_ip expects no args"); return 0; }
		*out = value_make_string_copy(g_last_recvfrom_ip); return out->str_value != NULL;
	}
	if (strcmp(name, "__sys_last_recvfrom_port") == 0) {
		if (argc != 0) { error_set(err, ERR_SEMANTIC, 0, 0, "__sys_last_recvfrom_port expects no args"); return 0; }
		*out = value_make_int(g_last_recvfrom_port); return 1;
	}
	if (strcmp(name, "__sys_set_deadline_ms") == 0) {
		long fd, read_ms, write_ms;
		int rc;
		if (argc != 3 || !host_int_arg(&args[0], &fd) || !host_int_arg(&args[1], &read_ms) || !host_int_arg(&args[2], &write_ms)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_set_deadline_ms expects fd, read_ms, write_ms"); return 0;
		}
		rc = host_set_socket_deadline((int)fd, (int)read_ms, (int)write_ms);
		*out = value_make_int(rc);
		return 1;
	}
	if (strcmp(name, "__sys_shutdown") == 0) {
		long fd, how;
		int rc;
		if (argc != 2 || !host_int_arg(&args[0], &fd) || !host_int_arg(&args[1], &how)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_shutdown expects fd and how"); return 0;
		}
		rc = shutdown((int)fd, (int)how); g_host_errno = rc < 0 ? errno : 0; *out = value_make_int(rc); return 1;
	}
	if (strcmp(name, "__sys_poll_ready") == 0) {
		long fd, events, timeout;
		struct pollfd pfd;
		int rc;
		if (argc != 3 || !host_int_arg(&args[0], &fd) || !host_int_arg(&args[1], &events) || !host_int_arg(&args[2], &timeout)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_poll_ready expects fd, events, timeout"); return 0;
		}
		pfd.fd = (int)fd; pfd.events = (short)events; pfd.revents = 0;
		rc = poll(&pfd, 1, (int)timeout);
		g_host_errno = rc < 0 ? errno : 0;
		*out = value_make_int(rc);
		return 1;
	}
	if (strcmp(name, "__sys_fcntl") == 0) {
		long fd, cmd, arg;
		int rc;
		if (argc != 3 || !host_int_arg(&args[0], &fd) || !host_int_arg(&args[1], &cmd) || !host_int_arg(&args[2], &arg)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_fcntl expects fd, cmd, arg"); return 0;
		}
		rc = fcntl((int)fd, (int)cmd, (int)arg); g_host_errno = rc < 0 ? errno : 0; *out = value_make_int(rc); return 1;
	}
	if (strcmp(name, "__sys_setsockopt") == 0 || strcmp(name, "__sys_getsockopt") == 0) {
		long fd, level, option, value = 0;
		int option_value = 0;
		socklen_t value_len = sizeof(option_value);
		int rc;
		size_t expected = strcmp(name, "__sys_setsockopt") == 0 ? 4u : 3u;
		if (argc != expected || !host_int_arg(&args[0], &fd) || !host_int_arg(&args[1], &level) || !host_int_arg(&args[2], &option) ||
		    (expected == 4 && !host_int_arg(&args[3], &value))) {
			error_set(err, ERR_SEMANTIC, 0, 0, "%s has invalid arguments", name); return 0;
		}
		option_value = (int)value;
		{
			int native_level = host_native_sockopt_level((int)level);
			int native_option = host_native_sockopt_name((int)level, (int)option);
			if (expected == 4) rc = setsockopt((int)fd, native_level, native_option, &option_value, sizeof(option_value));
			else rc = getsockopt((int)fd, native_level, native_option, &option_value, &value_len);
		}
		g_host_errno = rc < 0 ? errno : 0; *out = value_make_int(rc < 0 ? -1 : (expected == 4 ? 0 : option_value)); return 1;
	}
	if (strcmp(name, "__sys_poller_create") == 0) {
		if (argc != 0) { error_set(err, ERR_SEMANTIC, 0, 0, "__sys_poller_create expects no args"); return 0; }
		*out = value_make_int(host_poller_create()); return 1;
	}
	if (strcmp(name, "__sys_poller_add") == 0 || strcmp(name, "__sys_poller_del") == 0) {
		long poller_fd, fd, events = 0;
		int add = strcmp(name, "__sys_poller_add") == 0;
		size_t expected = add ? 3u : 2u;
		if (argc != expected || !host_int_arg(&args[0], &poller_fd) || !host_int_arg(&args[1], &fd) ||
		    (add && !host_int_arg(&args[2], &events))) {
			error_set(err, ERR_SEMANTIC, 0, 0, "%s has invalid arguments", name); return 0;
		}
		*out = value_make_int(host_poller_change((int)poller_fd, (int)fd, (int)events, add)); return 1;
	}
	if (strcmp(name, "__sys_poller_wait") == 0) {
		long poller_fd, max_events, timeout_ms;
		if (argc != 3 || !host_int_arg(&args[0], &poller_fd) || !host_int_arg(&args[1], &max_events) ||
		    !host_int_arg(&args[2], &timeout_ms)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_poller_wait expects poller_fd, max_events, timeout_ms"); return 0;
		}
		if (!host_poller_wait((int)poller_fd, (int)max_events, (int)timeout_ms, out)) {
			if (g_host_errno == 0) error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "poller wait allocation failed");
			else *out = value_make_array_owned(NULL, 0);
		}
		return 1;
	}
	if (strcmp(name, "__sys_sendfile") == 0) {
		long out_fd, in_fd, offset, count;
		ssize_t sent = -1;
		if (argc != 4 || !host_int_arg(&args[0], &out_fd) || !host_int_arg(&args[1], &in_fd) ||
		    !host_int_arg(&args[2], &offset) || !host_int_arg(&args[3], &count) || offset < 0 || count < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_sendfile expects out_fd, in_fd, offset, count"); return 0;
		}
#if defined(__linux__)
		{
			off_t off = (off_t)offset;
			sent = sendfile((int)out_fd, (int)in_fd, &off, (size_t)count);
		}
#elif defined(__APPLE__)
		{
			off_t len = (off_t)count;
			int rc = sendfile((int)in_fd, (int)out_fd, (off_t)offset, &len, NULL, 0);
			sent = (rc == 0 || len > 0) ? (ssize_t)len : -1;
		}
#else
		errno = ENOSYS;
#endif
		g_host_errno = sent < 0 ? errno : 0;
		*out = value_make_int((long)sent);
		return 1;
	}
	if (strcmp(name, "__sys_open_read") == 0) {
		const char *path = NULL;
		char path_buf[512];
		int fd;
		if (argc != 1 || !value_as_cstr(&args[0], path_buf, sizeof(path_buf), &path)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_open_read expects a path"); return 0;
		}
		fd = open(path, O_RDONLY);
		g_host_errno = fd < 0 ? errno : 0;
		*out = value_make_int(fd);
		return 1;
	}
	if (strcmp(name, "__sys_splice") == 0) {
		long in_fd, out_fd, count;
		ssize_t moved = -1;
		if (argc != 3 || !host_int_arg(&args[0], &in_fd) || !host_int_arg(&args[1], &out_fd) ||
		    !host_int_arg(&args[2], &count) || count < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__sys_splice expects in_fd, out_fd, count"); return 0;
		}
#if defined(__linux__)
		moved = splice((int)in_fd, NULL, (int)out_fd, NULL, (size_t)count, SPLICE_F_MOVE | SPLICE_F_MORE);
#else
		errno = ENOSYS;
#endif
		g_host_errno = moved < 0 ? errno : 0;
		*out = value_make_int((long)moved);
		return 1;
	}
	if (strcmp(name, "__sys_interface_addresses") == 0) {
		struct ifaddrs *interfaces = NULL, *it;
		runtime_data_value *items = NULL;
		size_t count = 0, cap = 0;
		if (argc != 0) { error_set(err, ERR_SEMANTIC, 0, 0, "__sys_interface_addresses expects no args"); return 0; }
		if (getifaddrs(&interfaces) < 0) {
			g_host_errno = errno; *out = value_make_array_owned(NULL, 0); return 1;
		}
		for (it = interfaces; it; it = it->ifa_next) {
			char ip[INET6_ADDRSTRLEN];
			char entry[IFNAMSIZ + INET6_ADDRSTRLEN + 2];
			if (!it->ifa_addr || (it->ifa_addr->sa_family != AF_INET && it->ifa_addr->sa_family != AF_INET6)) continue;
			if (!host_sockaddr_text(it->ifa_addr, ip, sizeof(ip), NULL)) continue;
			snprintf(entry, sizeof(entry), "%s|%s", it->ifa_name ? it->ifa_name : "", ip);
			if (count == cap) {
				size_t next_cap = cap ? cap * 2 : 8;
				runtime_data_value *next = (runtime_data_value *)realloc(items, next_cap * sizeof(*items));
				if (!next) { freeifaddrs(interfaces); free(items); error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory"); return 0; }
				items = next; cap = next_cap;
			}
			items[count] = value_make_string_copy(entry);
			if (!items[count].str_value) { freeifaddrs(interfaces); free(items); error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory"); return 0; }
			count++;
		}
		freeifaddrs(interfaces);
		g_host_errno = 0;
		*out = value_make_array_owned(items, count);
		return 1;
	}
	if (strcmp(name, "runtime_env_get") == 0) {
		const char *key = NULL;
		const char *fallback = NULL;
		char key_buf[64];
		char fallback_buf[64];
		const char *value = NULL;
		if (argc != 2) {
			error_set(err, ERR_SEMANTIC, 0, 0, "runtime_env_get expects 2 args");
			return 0;
		}
		if (!value_as_cstr(&args[0], key_buf, sizeof(key_buf), &key)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to render runtime_env_get key");
			return 0;
		}
		if (!value_as_cstr(&args[1], fallback_buf, sizeof(fallback_buf), &fallback)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to render runtime_env_get default");
			return 0;
		}
		value = getenv(key);
		*out = value_make_string_copy(value ? value : fallback);
		if (!out->str_value) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return 0;
		}
		return 1;
	}
	if (strcmp(name, "runtime_file_exists") == 0) {
		const char *path = NULL;
		char path_buf[256];
		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "runtime_file_exists expects 1 arg");
			return 0;
		}
		if (!value_as_cstr(&args[0], path_buf, sizeof(path_buf), &path)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to render runtime_file_exists path");
			return 0;
		}
		*out = value_make_int(host_file_exists(path) ? 1 : 0);
		return 1;
	}
	if (strcmp(name, "runtime_read_text_file") == 0) {
		const char *path = NULL;
		char path_buf[256];
		char *content;
		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "runtime_read_text_file expects 1 arg");
			return 0;
		}
		if (!value_as_cstr(&args[0], path_buf, sizeof(path_buf), &path)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to render runtime_read_text_file path");
			return 0;
		}
		content = host_read_text_file(path, err);
		if (!content) {
			return 0;
		}
		*out = value_make_string_owned(content);
		return 1;
	}
	if (strcmp(name, "runtime_run_command_output") == 0) {
		const char *command = NULL;
		char command_buf[64];
		char *captured;
		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "runtime_run_command_output expects 1 arg");
			return 0;
		}
		if (!value_as_cstr(&args[0], command_buf, sizeof(command_buf), &command)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to render runtime_run_command_output command");
			return 0;
		}
		captured = run_command_capture_output(command, err);
		if (!captured) {
			return 0;
		}
		*out = value_make_string_owned(captured);
		return 1;
	}
	if (strcmp(name, "trim") == 0) {
		const char *text = NULL;
		char text_buf[64];
		char *trimmed;
		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "trim expects 1 arg");
			return 0;
		}
		if (!value_as_cstr(&args[0], text_buf, sizeof(text_buf), &text)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to render trim argument");
			return 0;
		}
		trimmed = trim_copy(text);
		if (!trimmed) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return 0;
		}
		*out = value_make_string_owned(trimmed);
		return 1;
	}
	if (strcmp(name, "lower") == 0) {
		const char *text = NULL;
		char text_buf[64];
		char *lowered;
		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "lower expects 1 arg");
			return 0;
		}
		if (!value_as_cstr(&args[0], text_buf, sizeof(text_buf), &text)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to render lower argument");
			return 0;
		}
		lowered = lower_copy(text);
		if (!lowered) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return 0;
		}
		*out = value_make_string_owned(lowered);
		return 1;
	}
	if (strcmp(name, "len") == 0) {
		const char *text = NULL;
		char text_buf[64];
		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "len expects 1 arg");
			return 0;
		}
		if (args[0].kind == RUNTIME_ARRAY) {
			*out = value_make_int((long)args[0].array_len);
			return 1;
		}
		if (!value_as_cstr(&args[0], text_buf, sizeof(text_buf), &text)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to render len argument");
			return 0;
		}
		*out = value_make_int((long)strlen(text));
		return 1;
	}
	if (strcmp(name, "float") == 0) {
		const char *text = NULL;
		char text_buf[64];
		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "float expects 1 arg");
			return 0;
		}
		if (args[0].kind == RUNTIME_FLOAT) {
			*out = value_make_float(args[0].float_value);
			return 1;
		}
		if (args[0].kind == RUNTIME_INT) {
			*out = value_make_float((double)args[0].int_value);
			return 1;
		}
		if (args[0].kind == RUNTIME_STRING) {
			if (!value_as_cstr(&args[0], text_buf, sizeof(text_buf), &text)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "failed to render float argument");
				return 0;
			}
			*out = value_make_float(strtod(text, NULL));
			return 1;
		}
		error_set(err, ERR_SEMANTIC, 0, 0, "float expects numeric or string arg");
		return 0;
	}
	if (strcmp(name, "string") == 0) {
		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "string expects 1 arg");
			return 0;
		}
		if (args[0].kind == RUNTIME_STRING) {
			if (!value_copy(out, &args[0])) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				return 0;
			}
			return 1;
		}
		if (args[0].int_value >= 0 && args[0].int_value <= 255) {
			char buf[2];
			buf[0] = (char)args[0].int_value;
			buf[1] = '\0';
			*out = value_make_string_copy(buf);
		} else {
			*out = value_make_string_copy("");
		}
		if (!out->str_value) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return 0;
		}
		return 1;
	}
	if (strcmp(name, "__index_get") == 0) {
		if (argc != 2) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__index_get expects 2 args");
			return 0;
		}
		if (args[1].kind != RUNTIME_INT) {
			error_set(err, ERR_SEMANTIC, 0, 0, "__index_get expects int index");
			return 0;
		}
		if (args[0].kind == RUNTIME_ARRAY) {
			if (args[1].int_value < 0 || (size_t)args[1].int_value >= args[0].array_len) {
				*out = value_make_int(0);
				return 1;
			}
			if (!value_copy(out, &args[0].array_items[args[1].int_value])) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				return 0;
			}
			return 1;
		}
		if (args[0].kind == RUNTIME_STRING) {
			size_t text_len;
			if (!args[0].str_value) {
				*out = value_make_int(0);
				return 1;
			}
			text_len = strlen(args[0].str_value);
			if (args[1].int_value < 0 || (size_t)args[1].int_value >= text_len) {
				*out = value_make_int(0);
				return 1;
			}
			*out = value_make_int((unsigned char)args[0].str_value[args[1].int_value]);
			return 1;
		}
		error_set(err, ERR_SEMANTIC, 0, 0, "__index_get expects array or string target");
		return 0;
	}
	if (strcmp(name, "build_main") == 0) {
		compile_error compile_err;
		char **s_argv = NULL;
		int s_argc = 0;

		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "build_main expects 1 arg");
			return 0;
		}

		s_argc = g_host_argc;
		s_argv = g_host_argv;

		if (s_argc >= 2 && strcmp(s_argv[1], "mod") == 0) {
		}

		if (s_argc >= 2 && strcmp(s_argv[1], "--emit-bin") == 0) {
			if (s_argc != 4) {
				fprintf(stderr, "usage: --emit-bin <input.ir> <output.bin>\n");
				*out = value_make_int(2);
				return 1;
			}
			error_clear(&compile_err);
			if (!emit_native_from_ir_file(s_argv[2], s_argv[3], &compile_err)) {
				print_compile_error_local(&compile_err);
				*out = value_make_int(1);
				return 1;
			}
			*out = value_make_int(0);
			return 1;
		}

		if (s_argc >= 2 && strcmp(s_argv[1], "--bootstrap") == 0) {
			const char *out_dir = ".";
			if (s_argc < 3 || s_argc > 4) {
				fprintf(stderr, "usage: --bootstrap <compiler_source.s> [output_dir]\n");
				*out = value_make_int(2);
				return 1;
			}
			if (s_argc == 4) {
				out_dir = s_argv[3];
			}
			error_clear(&compile_err);
			if (!seed_bootstrap_two_stage_check(s_argv[2], out_dir, &compile_err)) {
				print_compile_error_local(&compile_err);
				*out = value_make_int(1);
				return 1;
			}
			*out = value_make_int(0);
			return 1;
		}

		if (s_argc == 3) {
			error_clear(&compile_err);
			if (!compile_s_file_to_ir(s_argv[1], s_argv[2], &compile_err)) {
				print_compile_error_local(&compile_err);
				*out = value_make_int(1);
				return 1;
			}
			*out = value_make_int(0);
			return 1;
		}

		fprintf(stderr, "usage:\n  s <input.s> <output.ir>\n  s --emit-bin <input.ir> <output.bin>\n  s --bootstrap <compiler_source.s> [output_dir]\n  s mod index <dir>\n");
		*out = value_make_int(2);
		return 1;
	}

	error_set(err, ERR_SEMANTIC, 0, 0, "unknown function: %s", name);
	return 0;
}

typedef struct runtime_value {
	char name[64];
	runtime_data_value value;
} runtime_value;

typedef struct runtime_values {
	runtime_value *data;
	size_t len;
	size_t cap;
} runtime_values;

typedef struct runtime_label {
	char name[64];
	size_t pc;
} runtime_label;

typedef struct runtime_labels {
	runtime_label *data;
	size_t len;
	size_t cap;
} runtime_labels;

typedef struct runtime_ins {
	char op[32];
	char result[1024];
	char op1[1024];
	char op2[1024];
} runtime_ins;

typedef struct runtime_program {
	runtime_ins *data;
	size_t len;
	size_t cap;
} runtime_program;

typedef struct runtime_function {
	char name[64];
	size_t start_pc;
	size_t end_pc;
	char params[32][64];
	size_t param_count;
} runtime_function;

typedef struct runtime_functions {
	runtime_function *data;
	size_t len;
	size_t cap;
} runtime_functions;

static int is_blank(const char *s) {
	while (*s) {
		if (!isspace((unsigned char)*s)) {
			return 0;
		}
		s++;
	}
	return 1;
}

static int is_int_literal(const char *s) {
	if (!s || !*s) {
		return 0;
	}
	if (*s == '-') {
		s++;
	}
	if (!*s) {
		return 0;
	}
	while (*s) {
		if (!isdigit((unsigned char)*s)) {
			return 0;
		}
		s++;
	}
	return 1;
}

static int is_float_literal(const char *s) {
	char *end = NULL;
	if (!s || !*s) {
		return 0;
	}
	if (strchr(s, '.') == NULL && strchr(s, 'e') == NULL && strchr(s, 'E') == NULL) {
		return 0;
	}
	errno = 0;
	strtod(s, &end);
	return errno == 0 && end != NULL && *end == '\0';
}

static int is_array_literal(const char *s) {
	size_t n;
	if (!s) {
		return 0;
	}
	n = strlen(s);
	return n >= 2 && s[0] == '[' && s[n - 1] == ']';
}

static void values_free(runtime_values *vals) {
	size_t i;
	for (i = 0; i < vals->len; i++) {
		value_clear(&vals->data[i].value);
	}
	free(vals->data);
	vals->data = NULL;
	vals->len = 0;
	vals->cap = 0;
}

static int values_set(runtime_values *vals, const char *name, const runtime_data_value *value) {
	size_t i;
	for (i = 0; i < vals->len; i++) {
		if (strcmp(vals->data[i].name, name) == 0) {
			runtime_data_value tmp;
			if (!value_copy(&tmp, value)) {
				return 0;
			}
			value_clear(&vals->data[i].value);
			vals->data[i].value = tmp;
			return 1;
		}
	}
	if (vals->len == vals->cap) {
		size_t next_cap = vals->cap == 0 ? 32 : vals->cap * 2;
		runtime_value *next = (runtime_value *)realloc(vals->data, next_cap * sizeof(runtime_value));
		if (!next) {
			return 0;
		}
		vals->data = next;
		vals->cap = next_cap;
	}
	snprintf(vals->data[vals->len].name, sizeof(vals->data[vals->len].name), "%s", name);
	if (!value_copy(&vals->data[vals->len].value, value)) {
		return 0;
	}
	vals->len++;
	return 1;
}

static int values_get(const runtime_values *vals, const char *name, runtime_data_value *out) {
	size_t i;
	for (i = 0; i < vals->len; i++) {
		if (strcmp(vals->data[i].name, name) == 0) {
			return value_copy(out, &vals->data[i].value);
		}
	}
	return 0;
}

static runtime_data_value *values_get_ref(runtime_values *vals, const char *name) {
	size_t i;
	for (i = 0; i < vals->len; i++) {
		if (strcmp(vals->data[i].name, name) == 0) {
			return &vals->data[i].value;
		}
	}
	return NULL;
}

static int name_has_dotted_prefix(const char *name, const char *prefix) {
	size_t prefix_len;
	if (!name || !prefix) {
		return 0;
	}
	prefix_len = strlen(prefix);
	return prefix_len > 0 && strncmp(name, prefix, prefix_len) == 0 && name[prefix_len] == '.';
}

static int values_have_prefixed(const runtime_values *vals, const char *prefix);

static int values_copy_prefixed_depth(const runtime_values *src, const char *old_prefix, runtime_values *dst, const char *new_prefix, int depth) {
	size_t i;
	size_t old_len;
	char mapped_name[256];

	if (!src || !old_prefix || !new_prefix || depth > 16) {
		return 0;
	}
	old_len = strlen(old_prefix);
	for (i = 0; i < src->len; i++) {
		if (!name_has_dotted_prefix(src->data[i].name, old_prefix)) {
			continue;
		}
		if (snprintf(mapped_name, sizeof(mapped_name), "%s%s", new_prefix, src->data[i].name + old_len) >= (int)sizeof(mapped_name)) {
			return 0;
		}
		if (!values_set(dst, mapped_name, &src->data[i].value)) {
			return 0;
		}
		if (src->data[i].value.kind == RUNTIME_STRING &&
		    src->data[i].value.str_value &&
		    src->data[i].value.str_value[0] != '\0' &&
		    values_have_prefixed(src, src->data[i].value.str_value) &&
		    !values_copy_prefixed_depth(src, src->data[i].value.str_value, dst, mapped_name, depth + 1)) {
			return 0;
		}
	}
	return 1;
}

static int values_copy_prefixed(const runtime_values *src, const char *old_prefix, runtime_values *dst, const char *new_prefix) {
	return values_copy_prefixed_depth(src, old_prefix, dst, new_prefix, 0);
}

static int values_have_prefixed(const runtime_values *vals, const char *prefix) {
	size_t i;
	if (!vals || !prefix || !*prefix) {
		return 0;
	}
	for (i = 0; i < vals->len; i++) {
		if (name_has_dotted_prefix(vals->data[i].name, prefix)) {
			return 1;
		}
	}
	return 0;
}

static void labels_free(runtime_labels *labels) {
	free(labels->data);
	labels->data = NULL;
	labels->len = 0;
	labels->cap = 0;
}

static int labels_add(runtime_labels *labels, const char *name, size_t pc) {
	if (labels->len == labels->cap) {
		size_t next_cap = labels->cap == 0 ? 16 : labels->cap * 2;
		runtime_label *next = (runtime_label *)realloc(labels->data, next_cap * sizeof(runtime_label));
		if (!next) {
			return 0;
		}
		labels->data = next;
		labels->cap = next_cap;
	}
	if (strlen(name) >= sizeof(labels->data[labels->len].name)) {
		return 0;
	}
	strcpy(labels->data[labels->len].name, name);
	labels->data[labels->len].pc = pc;
	labels->len++;
	return 1;
}

static int labels_find(const runtime_labels *labels, const char *name, size_t *pc) {
	size_t i;
	for (i = 0; i < labels->len; i++) {
		if (strcmp(labels->data[i].name, name) == 0) {
			*pc = labels->data[i].pc;
			return 1;
		}
	}
	return 0;
}

static void program_free(runtime_program *prog) {
	free(prog->data);
	prog->data = NULL;
	prog->len = 0;
	prog->cap = 0;
}

static void functions_free(runtime_functions *funcs) {
	free(funcs->data);
	funcs->data = NULL;
	funcs->len = 0;
	funcs->cap = 0;
}

static int functions_add(runtime_functions *funcs, const runtime_function *fn) {
	if (funcs->len == funcs->cap) {
		size_t next_cap = funcs->cap == 0 ? 16 : funcs->cap * 2;
		runtime_function *next = (runtime_function *)realloc(funcs->data, next_cap * sizeof(runtime_function));
		if (!next) {
			return 0;
		}
		funcs->data = next;
		funcs->cap = next_cap;
	}
	funcs->data[funcs->len++] = *fn;
	return 1;
}

static const runtime_function *functions_find(const runtime_functions *funcs, const char *name) {
	size_t i;
	for (i = 0; i < funcs->len; i++) {
		if (strcmp(funcs->data[i].name, name) == 0) {
			return &funcs->data[i];
		}
	}
	return NULL;
}

static int program_push(runtime_program *prog, const runtime_ins *ins) {
	if (prog->len == prog->cap) {
		size_t next_cap = prog->cap == 0 ? 32 : prog->cap * 2;
		runtime_ins *next = (runtime_ins *)realloc(prog->data, next_cap * sizeof(runtime_ins));
		if (!next) {
			return 0;
		}
		prog->data = next;
		prog->cap = next_cap;
	}
	prog->data[prog->len++] = *ins;
	return 1;
}

static int parse_record_line(const char *line, runtime_ins *out) {
	char tmp[4096];
	char parts[4][1024];
	int part = 0;
	size_t idx = 0;
	size_t i = 0;

	memset(parts, 0, sizeof(parts));
	snprintf(tmp, sizeof(tmp), "%s", line);
	while (tmp[i] != '\0') {
		char ch = tmp[i++];
		if (ch == '\\') {
			char esc = tmp[i++];
			if (esc == '\0') {
				return 0;
			}
			if (idx + 1 >= sizeof(parts[part])) {
				return 0;
			}
			if (esc == 'n') {
				parts[part][idx++] = '\n';
			} else if (esc == 'r') {
				parts[part][idx++] = '\r';
			} else if (esc == 't') {
				parts[part][idx++] = '\t';
			} else {
				parts[part][idx++] = esc;
			}
			continue;
		}
		if (ch == '|') {
			if (part >= 3) {
				return 0;
			}
			part++;
			idx = 0;
			continue;
		}
		if (idx + 1 >= sizeof(parts[part])) {
			return 0;
		}
		parts[part][idx++] = ch;
	}
	if (part != 3) {
		return 0;
	}

	if (strlen(parts[0]) >= sizeof(out->op) ||
	    strlen(strcmp(parts[1], "_") == 0 ? "" : parts[1]) >= sizeof(out->result) ||
	    strlen(strcmp(parts[2], "_") == 0 ? "" : parts[2]) >= sizeof(out->op1) ||
	    strlen(strcmp(parts[3], "_") == 0 ? "" : parts[3]) >= sizeof(out->op2)) {
		return 0;
	}
	strcpy(out->op, parts[0]);
	strcpy(out->result, strcmp(parts[1], "_") == 0 ? "" : parts[1]);
	strcpy(out->op1, strcmp(parts[2], "_") == 0 ? "" : parts[2]);
	strcpy(out->op2, strcmp(parts[3], "_") == 0 ? "" : parts[3]);
	return 1;
}

static int resolve_dotted_value(const runtime_values *vals, const char *name, runtime_data_value *out, int depth) {
	runtime_data_value base;
	char chained_name[256];
	const char *dot;

	if (depth > 8 || !name) {
		return 0;
	}
	if (values_get(vals, name, out)) {
		if (out->kind == RUNTIME_STRING && values_have_prefixed(vals, name)) {
			value_clear(out);
			*out = value_make_string_copy(name);
			return out->str_value != NULL;
		}
		return 1;
	}
	if (values_have_prefixed(vals, name)) {
		*out = value_make_string_copy(name);
		return out->str_value != NULL;
	}
	for (dot = strrchr(name, '.'); dot != NULL; ) {
		size_t prefix_len = (size_t)(dot - name);
		char prefix[128];
		char suffix[128];
		memset(&base, 0, sizeof(base));
		if (prefix_len > 0 && prefix_len < sizeof(prefix)) {
			memcpy(prefix, name, prefix_len);
			prefix[prefix_len] = '\0';
			snprintf(suffix, sizeof(suffix), "%s", dot + 1);
			if (resolve_dotted_value(vals, prefix, &base, depth + 1)) {
				if (base.kind == RUNTIME_STRING && base.str_value && base.str_value[0] != '\0') {
					if (snprintf(chained_name, sizeof(chained_name), "%s.%s", base.str_value, dot + 1) < (int)sizeof(chained_name)) {
						value_clear(&base);
						return resolve_dotted_value(vals, chained_name, out, depth + 1);
					}
				}
				if (base.kind == RUNTIME_ARRAY) {
					if (strcmp(suffix, "len") == 0) {
						long len_value = (long)base.array_len;
						value_clear(&base);
						*out = value_make_int(len_value);
						return 1;
					}
					if (is_int_literal(suffix)) {
						long index = strtol(suffix, NULL, 10);
						if (index >= 0 && (size_t)index < base.array_len) {
							int ok = value_copy(out, &base.array_items[index]);
							value_clear(&base);
							return ok;
						}
					}
				}
				value_clear(&base);
			}
		}
		{
			const char *scan = dot;
			dot = NULL;
			while (scan > name) {
				scan--;
				if (*scan == '.') {
					dot = scan;
					break;
				}
			}
		}
	}
	return 0;
}

static int split_array_items(const char *text, char ***out_items, size_t *out_len) {
	size_t i;
	size_t start;
	size_t len = 0;
	size_t cap = 0;
	int depth = 0;
	int in_string = 0;
	char **items = NULL;

	*out_items = NULL;
	*out_len = 0;
	if (!is_array_literal(text)) {
		return 0;
	}
	start = 1;
	for (i = 1; text[i] != '\0'; i++) {
		char ch = text[i];
		if (in_string) {
			if (ch == '\\' && text[i + 1] != '\0') {
				i++;
				continue;
			}
			if (ch == '"') {
				in_string = 0;
			}
			continue;
		}
		if (ch == '"') {
			in_string = 1;
			continue;
		}
		if (ch == '[') {
			depth++;
			continue;
		}
		if (ch == ']') {
			if (depth > 0) {
				depth--;
				continue;
			}
			if (i > start) {
				size_t raw_len = i - start;
				size_t left = 0;
				size_t right = raw_len;
				char *item;
				while (left < raw_len && isspace((unsigned char)text[start + left])) {
					left++;
				}
				while (right > left && isspace((unsigned char)text[start + right - 1])) {
					right--;
				}
				if (right > left) {
					item = (char *)malloc(right - left + 1);
					if (!item) {
						goto fail;
					}
					memcpy(item, text + start + left, right - left);
					item[right - left] = '\0';
					if (len == cap) {
						size_t next_cap = cap == 0 ? 4 : cap * 2;
						char **next_items = (char **)realloc(items, next_cap * sizeof(char *));
						if (!next_items) {
							free(item);
							goto fail;
						}
						items = next_items;
						cap = next_cap;
					}
					items[len++] = item;
				}
			}
			*out_items = items;
			*out_len = len;
			return 1;
		}
		if (ch == ',' && depth == 0) {
			size_t raw_len = i - start;
			size_t left = 0;
			size_t right = raw_len;
			char *item;
			while (left < raw_len && isspace((unsigned char)text[start + left])) {
				left++;
			}
			while (right > left && isspace((unsigned char)text[start + right - 1])) {
				right--;
			}
			item = (char *)malloc(right - left + 1);
			if (!item) {
				goto fail;
			}
			memcpy(item, text + start + left, right - left);
			item[right - left] = '\0';
			if (len == cap) {
				size_t next_cap = cap == 0 ? 4 : cap * 2;
				char **next_items = (char **)realloc(items, next_cap * sizeof(char *));
				if (!next_items) {
					free(item);
					goto fail;
				}
				items = next_items;
				cap = next_cap;
			}
			items[len++] = item;
			start = i + 1;
		}
	}

fail:
	if (items) {
		for (i = 0; i < len; i++) {
			free(items[i]);
		}
	}
	free(items);
	return 0;
}

static int parse_array_literal_value(const runtime_values *vals, const char *text, runtime_data_value *out) {
	char **items = NULL;
	size_t len = 0;
	size_t i;
	runtime_data_value *values = NULL;

	if (!split_array_items(text, &items, &len)) {
		return 0;
	}
	if (len > 0) {
		values = (runtime_data_value *)calloc(len, sizeof(runtime_data_value));
		if (!values) {
			goto fail;
		}
		for (i = 0; i < len; i++) {
			if (!resolve_value(vals, items[i], &values[i])) {
				goto fail;
			}
		}
	}
	for (i = 0; i < len; i++) {
		free(items[i]);
	}
	free(items);
	*out = value_make_array_owned(values, len);
	return 1;

fail:
	if (values) {
		for (i = 0; i < len; i++) {
			value_clear(&values[i]);
		}
		free(values);
	}
	if (items) {
		for (i = 0; i < len; i++) {
			free(items[i]);
		}
	}
	free(items);
	return 0;
}

static int resolve_value(const runtime_values *vals, const char *name, runtime_data_value *out) {
	if (is_int_literal(name)) {
		*out = value_make_int(strtol(name, NULL, 10));
		return 1;
	}
	if (is_float_literal(name)) {
		*out = value_make_float(strtod(name, NULL));
		return 1;
	}
	if (is_array_literal(name)) {
		return parse_array_literal_value(vals, name, out);
	}
	if (is_string_literal(name)) {
		*out = parse_string_literal(name);
		return out->str_value != NULL;
	}
	return resolve_dotted_value(vals, name, out, 0);
}

static int value_is_numeric(const runtime_data_value *v) {
	return v->kind == RUNTIME_INT || v->kind == RUNTIME_FLOAT;
}

static double value_as_double(const runtime_data_value *v) {
	if (v->kind == RUNTIME_FLOAT) {
		return v->float_value;
	}
	return (double)v->int_value;
}

static int value_equals(const runtime_data_value *a, const runtime_data_value *b) {
	size_t i;
	if (a->kind != b->kind) {
		if (value_is_numeric(a) && value_is_numeric(b)) {
			return value_as_double(a) == value_as_double(b);
		}
		return 0;
	}
	if (a->kind == RUNTIME_INT) {
		return a->int_value == b->int_value;
	}
	if (a->kind == RUNTIME_FLOAT) {
		return a->float_value == b->float_value;
	}
	if (a->kind == RUNTIME_STRING) {
		return strcmp(a->str_value ? a->str_value : "", b->str_value ? b->str_value : "") == 0;
	}
	if (a->array_len != b->array_len) {
		return 0;
	}
	for (i = 0; i < a->array_len; i++) {
		if (!value_equals(&a->array_items[i], &b->array_items[i])) {
			return 0;
		}
	}
	return 1;
}

static int array_set_index(runtime_data_value *array_value, long index, const runtime_data_value *value) {
	runtime_data_value copied;
	runtime_data_value *next_items;
	size_t i;
	size_t target_len;
	if (!array_value || array_value->kind != RUNTIME_ARRAY || index < 0) {
		return 0;
	}
	target_len = (size_t)index + 1;
	if (target_len > array_value->array_len) {
		next_items = (runtime_data_value *)realloc(array_value->array_items, target_len * sizeof(runtime_data_value));
		if (!next_items) {
			return 0;
		}
		array_value->array_items = next_items;
		for (i = array_value->array_len; i < target_len; i++) {
			array_value->array_items[i] = value_make_int(0);
		}
		array_value->array_len = target_len;
	}
	if (!value_copy(&copied, value)) {
		return 0;
	}
	value_clear(&array_value->array_items[index]);
	array_value->array_items[index] = copied;
	return 1;
}

static int name_has_suffix(const char *name, const char *suffix) {
	size_t name_len;
	size_t suffix_len;
	if (!name || !suffix) {
		return 0;
	}
	name_len = strlen(name);
	suffix_len = strlen(suffix);
	if (suffix_len > name_len) {
		return 0;
	}
	return strcmp(name + (name_len - suffix_len), suffix) == 0;
}

static int value_as_long_index(const runtime_data_value *v, long *out) {
	if (!v || !out) {
		return 0;
	}
	if (v->kind == RUNTIME_INT) {
		*out = v->int_value;
		return 1;
	}
	if (v->kind == RUNTIME_FLOAT) {
		*out = (long)v->float_value;
		return 1;
	}
	return 0;
}

static int native_fastpath_execute(const char *fn_name, const runtime_data_value *args, size_t argc, runtime_data_value *out) {
	size_t i;
	if (name_has_suffix(fn_name, "allocate_vector") && argc == 2) {
		long size = 0;
		runtime_data_value *items;
		if (!value_as_long_index(&args[0], &size) || size < 0) {
			return 0;
		}
		items = size > 0 ? (runtime_data_value *)calloc((size_t)size, sizeof(runtime_data_value)) : NULL;
		if (size > 0 && !items) {
			return 0;
		}
		for (i = 0; i < (size_t)size; i++) {
			if (!value_copy(&items[i], &args[1])) {
				size_t j;
				for (j = 0; j < i; j++) {
					value_clear(&items[j]);
				}
				free(items);
				return 0;
			}
		}
		*out = value_make_array_owned(items, (size_t)size);
		return 1;
	}
	if (name_has_suffix(fn_name, "copy_vector") && argc == 1 && args[0].kind == RUNTIME_ARRAY) {
		return value_copy(out, &args[0]);
	}
	if ((name_has_suffix(fn_name, "build_ramp") || name_has_suffix(fn_name, "fill_ramp")) && argc == 2) {
		long size = 0;
		double scale;
		runtime_data_value *items;
		if (!value_as_long_index(&args[0], &size) || size < 0 || !value_is_numeric(&args[1])) {
			return 0;
		}
		scale = value_as_double(&args[1]);
		items = size > 0 ? (runtime_data_value *)calloc((size_t)size, sizeof(runtime_data_value)) : NULL;
		if (size > 0 && !items) {
			return 0;
		}
		for (i = 0; i < (size_t)size; i++) {
			double value = scale * ((double)(i + 1)) / ((double)size + 1.0);
			items[i] = value_make_float(value);
		}
		*out = value_make_array_owned(items, (size_t)size);
		return 1;
	}
	if (name_has_suffix(fn_name, "matmul_flat") && argc == 5 && args[0].kind == RUNTIME_ARRAY && args[1].kind == RUNTIME_ARRAY) {
		long m = 0;
		long k = 0;
		long n = 0;
		runtime_data_value *items;
		size_t out_len;
		size_t row;
		if (!value_as_long_index(&args[2], &m) || !value_as_long_index(&args[3], &k) || !value_as_long_index(&args[4], &n) ||
		    m < 0 || k < 0 || n < 0) {
			return 0;
		}
		out_len = (size_t)m * (size_t)n;
		items = out_len > 0 ? (runtime_data_value *)calloc(out_len, sizeof(runtime_data_value)) : NULL;
		if (out_len > 0 && !items) {
			return 0;
		}
		for (row = 0; row < (size_t)m; row++) {
			size_t col;
			for (col = 0; col < (size_t)n; col++) {
				size_t inner;
				double sum = 0.0;
				for (inner = 0; inner < (size_t)k; inner++) {
					size_t a_index = row * (size_t)k + inner;
					size_t b_index = inner * (size_t)n + col;
					double av = 0.0;
					double bv = 0.0;
					if (a_index < args[0].array_len && value_is_numeric(&args[0].array_items[a_index])) {
						av = value_as_double(&args[0].array_items[a_index]);
					}
					if (b_index < args[1].array_len && value_is_numeric(&args[1].array_items[b_index])) {
						bv = value_as_double(&args[1].array_items[b_index]);
					}
					sum += av * bv;
				}
				items[row * (size_t)n + col] = value_make_float(sum);
			}
		}
		*out = value_make_array_owned(items, out_len);
		return 1;
	}
	return 0;
}

static int parse_size_t(const char *text, size_t *out) {
	char *end = NULL;
	long v;
	if (!text || !*text) {
		return 0;
	}
	v = strtol(text, &end, 10);
	if (*end != '\0' || v < 0) {
		return 0;
	}
	*out = (size_t)v;
	return 1;
}

static int parse_program_text(const char *target_text, runtime_program *prog, runtime_labels *labels, compile_error *err) {
	char *buf;
	char *cursor;
	size_t line_no = 0;

	buf = (char *)malloc(strlen(target_text) + 1);
	if (!buf) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return 0;
	}
	strcpy(buf, target_text);

	cursor = buf;
	while (*cursor) {
		runtime_ins ins;
		char *line = cursor;
		char *nl = strchr(cursor, '\n');
		if (nl) {
			*nl = '\0';
			cursor = nl + 1;
		} else {
			cursor += strlen(cursor);
		}
		line_no++;
		if (line_no == 1) {
			if (strcmp(line, "SSEED-TARGET-V1") != 0) {
				free(buf);
				error_set(err, ERR_SEMANTIC, 1, 1, "invalid target header");
				return 0;
			}
			continue;
		}
		if (is_blank(line)) {
			continue;
		}
		if (!parse_record_line(line, &ins)) {
			free(buf);
			error_set(err, ERR_SEMANTIC, line_no, 1, "invalid instruction record");
			return 0;
		}
		if (!program_push(prog, &ins)) {
			free(buf);
			error_set(err, ERR_OUT_OF_MEMORY, line_no, 1, "out of memory");
			return 0;
		}
	}
	free(buf);

	for (line_no = 0; line_no < prog->len; line_no++) {
		if (strcmp(prog->data[line_no].op, "LABEL") == 0) {
			if (!labels_add(labels, prog->data[line_no].result, line_no)) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				return 0;
			}
		}
	}

	return 1;
}

static int build_function_table(const runtime_program *prog, runtime_functions *funcs, compile_error *err) {
	size_t i = 0;
	while (i < prog->len) {
		if (strcmp(prog->data[i].op, "FUNC_BEGIN") == 0) {
			runtime_function fn;
			size_t j;
			size_t body_start;
			memset(&fn, 0, sizeof(fn));
			if (strlen(prog->data[i].result) >= sizeof(fn.name)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "function name too long");
				return 0;
			}
			strcpy(fn.name, prog->data[i].result);
			j = i + 1;
			while (j < prog->len && strcmp(prog->data[j].op, "PARAM") == 0) {
				if (fn.param_count >= 32) {
					error_set(err, ERR_SEMANTIC, 0, 0, "too many params in function: %s", fn.name);
					return 0;
				}
				if (strlen(prog->data[j].result) >= sizeof(fn.params[fn.param_count])) {
					error_set(err, ERR_SEMANTIC, 0, 0, "parameter name too long in function: %s", fn.name);
					return 0;
				}
				strcpy(fn.params[fn.param_count], prog->data[j].result);
				fn.param_count++;
				j++;
			}
			body_start = j;
			while (j < prog->len) {
				if (strcmp(prog->data[j].op, "FUNC_END") == 0 && strcmp(prog->data[j].result, fn.name) == 0) {
					fn.start_pc = body_start;
					fn.end_pc = j;
					if (!functions_add(funcs, &fn)) {
						error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
						return 0;
					}
					i = j + 1;
					break;
				}
				j++;
			}
			if (j >= prog->len) {
				error_set(err, ERR_SEMANTIC, 0, 0, "missing FUNC_END for function: %s", fn.name);
				return 0;
			}
			continue;
		}
		i++;
	}
	return 1;
}

static int execute_function(
	const runtime_program *prog,
	const runtime_labels *labels,
	const runtime_functions *funcs,
	const runtime_function *fn,
	const runtime_data_value *args,
	size_t argc,
	const runtime_values *caller_vals,
	runtime_data_value *out_return,
	runtime_values *out_return_fields,
	compile_error *err,
	int depth
) {
	runtime_values vals = {0};
	runtime_data_value pending_args[128];
	size_t pending_len = 0;
	size_t pc = fn->start_pc;
	size_t i;

	if (depth > 256) {
		error_set(err, ERR_SEMANTIC, 0, 0, "call depth exceeded");
		return 0;
	}
	if (argc != fn->param_count) {
		error_set(err, ERR_SEMANTIC, 0, 0, "call arity mismatch for function: %s", fn->name);
		return 0;
	}
	if (native_fastpath_execute(fn->name, args, argc, out_return)) {
		return 1;
	}

	for (i = 0; i < argc; i++) {
		if (caller_vals && args[i].kind == RUNTIME_STRING && args[i].str_value && args[i].str_value[0] != '\0' &&
		    values_have_prefixed(caller_vals, args[i].str_value)) {
			runtime_data_value remapped_arg = value_make_string_copy(fn->params[i]);
			if (remapped_arg.str_value == NULL ||
			    !values_set(&vals, fn->params[i], &remapped_arg) ||
			    !values_copy_prefixed(caller_vals, args[i].str_value, &vals, fn->params[i])) {
				value_clear(&remapped_arg);
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				values_free(&vals);
				return 0;
			}
			value_clear(&remapped_arg);
			continue;
		}
		if (!values_set(&vals, fn->params[i], &args[i])) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			values_free(&vals);
			return 0;
		}
	}
	while (pc < fn->end_pc) {
		runtime_ins *ins = &prog->data[pc];
		runtime_data_value a = value_make_int(0);
		runtime_data_value b = value_make_int(0);
		if (g_runtime_profile_enabled) {
			g_runtime_profile_total_ops++;
			runtime_profile_bump(g_runtime_profile_fn, &g_runtime_profile_fn_len, 256, fn->name);
			runtime_profile_bump(g_runtime_profile_op, &g_runtime_profile_op_len, 256, ins->op);
			if (g_runtime_profile_max_ops > 0 && g_runtime_profile_total_ops > g_runtime_profile_max_ops) {
				error_set(err, ERR_SEMANTIC, 0, 0, "runtime op budget exceeded in function '%s' on op '%s'", fn->name, ins->op);
				runtime_profile_dump_summary();
				values_free(&vals);
				return 0;
			}
		}

		if (strcmp(ins->op, "NOP") == 0 || strcmp(ins->op, "LABEL") == 0 || strcmp(ins->op, "PARAM") == 0) {
			pc++;
			continue;
		}
		if (strcmp(ins->op, "JUMP") == 0) {
			size_t target;
			if (!labels_find(labels, ins->result, &target)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown label: %s", ins->result);
				values_free(&vals);
				return 0;
			}
			if (target < fn->start_pc || target >= fn->end_pc) {
				error_set(err, ERR_SEMANTIC, 0, 0, "jump out of function: %s", ins->result);
				values_free(&vals);
				return 0;
			}
			pc = target;
			continue;
		}
		if (strcmp(ins->op, "JUMP_IF_FALSE") == 0) {
			size_t target;
			if (!resolve_value(&vals, ins->op1, &a)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown value: %s", ins->op1);
				value_clear(&a);
				values_free(&vals);
				return 0;
			}
			if (!value_truthy(&a)) {
				if (!labels_find(labels, ins->result, &target)) {
					error_set(err, ERR_SEMANTIC, 0, 0, "unknown label: %s", ins->result);
					value_clear(&a);
					values_free(&vals);
					return 0;
				}
				if (target < fn->start_pc || target >= fn->end_pc) {
					error_set(err, ERR_SEMANTIC, 0, 0, "jump out of function: %s", ins->result);
					value_clear(&a);
					values_free(&vals);
					return 0;
				}
				pc = target;
			} else {
				pc++;
			}
			value_clear(&a);
			continue;
		}
		if (strcmp(ins->op, "MOV") == 0) {
			int remap_alias = 0;
			if (!resolve_value(&vals, ins->op1, &a)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown value: %s", ins->op1);
				value_clear(&a);
				values_free(&vals);
				return 0;
			}
			remap_alias = a.kind == RUNTIME_STRING && a.str_value && a.str_value[0] != '\0' &&
				values_have_prefixed(&vals, a.str_value);
			if (remap_alias) {
				runtime_data_value remapped_alias = value_make_string_copy(ins->result);
				if (remapped_alias.str_value == NULL) {
					error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
					value_clear(&a);
					values_free(&vals);
					return 0;
				}
				if (!values_set(&vals, ins->result, &remapped_alias) ||
				    !values_copy_prefixed(&vals, a.str_value, &vals, ins->result)) {
					error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
					value_clear(&remapped_alias);
					value_clear(&a);
					values_free(&vals);
					return 0;
				}
				value_clear(&remapped_alias);
				value_clear(&a);
				pc++;
				continue;
			}
			if (!values_set(&vals, ins->result, &a)) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				value_clear(&a);
				values_free(&vals);
				return 0;
			}
			value_clear(&a);
			pc++;
			continue;
		}
		if (strcmp(ins->op, "INDEX_SET") == 0) {
			runtime_data_value *target_array = values_get_ref(&vals, ins->result);
			if (!target_array) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown index-set target: %s", ins->result);
				values_free(&vals);
				return 0;
			}
			if (!resolve_value(&vals, ins->op1, &a) || a.kind != RUNTIME_INT) {
				error_set(err, ERR_SEMANTIC, 0, 0, "invalid index-set index: %s", ins->op1);
				value_clear(&a);
				values_free(&vals);
				return 0;
			}
			if (!resolve_value(&vals, ins->op2, &b)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "invalid index-set value: %s", ins->op2);
				value_clear(&a);
				value_clear(&b);
				values_free(&vals);
				return 0;
			}
			if (!array_set_index(target_array, a.int_value, &b)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "failed index-set on target: %s", ins->result);
				value_clear(&a);
				value_clear(&b);
				values_free(&vals);
				return 0;
			}
			value_clear(&a);
			value_clear(&b);
			pc++;
			continue;
		}
		if (strcmp(ins->op, "ADD") == 0 || strcmp(ins->op, "SUB") == 0 || strcmp(ins->op, "MUL") == 0 || strcmp(ins->op, "DIV") == 0 || strcmp(ins->op, "MOD") == 0 ||
			strcmp(ins->op, "CMP_EQ") == 0 || strcmp(ins->op, "CMP_NE") == 0 || strcmp(ins->op, "CMP_LT") == 0 || strcmp(ins->op, "CMP_LE") == 0 ||
			strcmp(ins->op, "CMP_GT") == 0 || strcmp(ins->op, "CMP_GE") == 0) {
			runtime_data_value r = value_make_int(0);
			int ok = 1;
			if (!resolve_value(&vals, ins->op1, &a)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown left operand '%s' in op: %s", ins->op1, ins->op);
				value_clear(&a);
				value_clear(&b);
				values_free(&vals);
				return 0;
			}
			if (!resolve_value(&vals, ins->op2, &b)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown right operand '%s' in op: %s", ins->op2, ins->op);
				value_clear(&a);
				value_clear(&b);
				values_free(&vals);
				return 0;
			}
			if (strcmp(ins->op, "ADD") == 0) {
				if (a.kind == RUNTIME_INT && b.kind == RUNTIME_INT) {
					r = value_make_int(a.int_value + b.int_value);
				} else if (value_is_numeric(&a) && value_is_numeric(&b)) {
					r = value_make_float(value_as_double(&a) + value_as_double(&b));
				} else if (!value_concat(&r, &a, &b)) {
					ok = 0;
				}
			} else if (strcmp(ins->op, "SUB") == 0) {
				if (!value_is_numeric(&a) || !value_is_numeric(&b)) {
					error_set(err, ERR_SEMANTIC, 0, 0, "SUB expects numeric operands");
					ok = 0;
				} else if (a.kind == RUNTIME_INT && b.kind == RUNTIME_INT) {
					r = value_make_int(a.int_value - b.int_value);
				} else {
					r = value_make_float(value_as_double(&a) - value_as_double(&b));
				}
			} else if (strcmp(ins->op, "MUL") == 0) {
				if (!value_is_numeric(&a) || !value_is_numeric(&b)) {
					error_set(err, ERR_SEMANTIC, 0, 0, "MUL expects numeric operands");
					ok = 0;
				} else if (a.kind == RUNTIME_INT && b.kind == RUNTIME_INT) {
					r = value_make_int(a.int_value * b.int_value);
				} else {
					r = value_make_float(value_as_double(&a) * value_as_double(&b));
				}
			} else if (strcmp(ins->op, "DIV") == 0) {
				if (!value_is_numeric(&a) || !value_is_numeric(&b)) {
					error_set(err, ERR_SEMANTIC, 0, 0, "DIV expects numeric operands");
					ok = 0;
				} else if (value_as_double(&b) == 0.0) {
					error_set(err, ERR_SEMANTIC, 0, 0, "division by zero");
					ok = 0;
				} else if (a.kind == RUNTIME_INT && b.kind == RUNTIME_INT) {
					r = value_make_int(a.int_value / b.int_value);
				} else {
					r = value_make_float(value_as_double(&a) / value_as_double(&b));
				}
			} else if (strcmp(ins->op, "MOD") == 0) {
				if (a.kind != RUNTIME_INT || b.kind != RUNTIME_INT) {
					error_set(err, ERR_SEMANTIC, 0, 0, "MOD requires integer operands");
					ok = 0;
				} else if (b.int_value == 0) {
					error_set(err, ERR_SEMANTIC, 0, 0, "modulo by zero");
					ok = 0;
				} else {
					r = value_make_int(a.int_value % b.int_value);
				}
			} else if (strcmp(ins->op, "CMP_EQ") == 0) {
				if (!value_is_numeric(&a) && !value_is_numeric(&b) && a.kind != b.kind) {
					error_set(err, ERR_SEMANTIC, 0, 0, "CMP_EQ expects operand types to match");
					ok = 0;
				} else {
					r = value_make_int(value_equals(&a, &b));
				}
			} else if (strcmp(ins->op, "CMP_NE") == 0) {
				if (!value_is_numeric(&a) && !value_is_numeric(&b) && a.kind != b.kind) {
					error_set(err, ERR_SEMANTIC, 0, 0, "CMP_NE expects operand types to match");
					ok = 0;
				} else {
					r = value_make_int(!value_equals(&a, &b));
				}
			} else {
				int cmp;
				if (a.kind != b.kind) {
					if (!value_is_numeric(&a) || !value_is_numeric(&b)) {
						error_set(err, ERR_SEMANTIC, 0, 0, "%s expects operand types to match", ins->op);
						ok = 0;
					} else {
						double ad = value_as_double(&a);
						double bd = value_as_double(&b);
						cmp = (ad > bd) - (ad < bd);
						if (strcmp(ins->op, "CMP_LT") == 0) r = value_make_int(cmp < 0);
						else if (strcmp(ins->op, "CMP_LE") == 0) r = value_make_int(cmp <= 0);
						else if (strcmp(ins->op, "CMP_GT") == 0) r = value_make_int(cmp > 0);
						else if (strcmp(ins->op, "CMP_GE") == 0) r = value_make_int(cmp >= 0);
					}
				} else {
					if (a.kind == RUNTIME_INT) {
						cmp = (a.int_value > b.int_value) - (a.int_value < b.int_value);
					} else if (a.kind == RUNTIME_FLOAT) {
						cmp = (a.float_value > b.float_value) - (a.float_value < b.float_value);
					} else if (a.kind == RUNTIME_STRING) {
						cmp = strcmp(a.str_value ? a.str_value : "", b.str_value ? b.str_value : "");
					} else {
						error_set(err, ERR_SEMANTIC, 0, 0, "%s does not support array operands", ins->op);
						ok = 0;
						cmp = 0;
					}
					if (ok) {
						if (strcmp(ins->op, "CMP_LT") == 0) r = value_make_int(cmp < 0);
						else if (strcmp(ins->op, "CMP_LE") == 0) r = value_make_int(cmp <= 0);
						else if (strcmp(ins->op, "CMP_GT") == 0) r = value_make_int(cmp > 0);
						else if (strcmp(ins->op, "CMP_GE") == 0) r = value_make_int(cmp >= 0);
					}
				}
			}
			if (!ok) {
				value_clear(&a);
				value_clear(&b);
				value_clear(&r);
				values_free(&vals);
				return 0;
			}
			if (!values_set(&vals, ins->result, &r)) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				value_clear(&a);
				value_clear(&b);
				value_clear(&r);
				values_free(&vals);
				return 0;
			}
			value_clear(&a);
			value_clear(&b);
			value_clear(&r);
			pc++;
			continue;
		}
		if (strcmp(ins->op, "ARG") == 0) {
			if (!resolve_value(&vals, ins->result, &a)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown arg value: %s", ins->result);
				value_clear(&a);
				values_free(&vals);
				return 0;
			}
			if (pending_len >= 128) {
				error_set(err, ERR_SEMANTIC, 0, 0, "too many pending call arguments");
				value_clear(&a);
				values_free(&vals);
				return 0;
			}
			pending_args[pending_len++] = a;
			pc++;
			continue;
		}
		if (strcmp(ins->op, "CALL") == 0) {
			size_t call_argc = 0;
			runtime_data_value callee_ret = value_make_int(0);
			const runtime_function *callee;
			size_t call_base;
			size_t j;
			if (!parse_size_t(ins->op2, &call_argc)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "invalid call argc: %s", ins->op2);
				values_free(&vals);
				return 0;
			}
			if (call_argc > pending_len) {
				error_set(err, ERR_SEMANTIC, 0, 0, "insufficient call arguments for: %s", ins->op1);
				values_free(&vals);
				return 0;
			}
			call_base = pending_len - call_argc;
			callee = functions_find(funcs, ins->op1);
			if (!callee) {
				if (!host_dispatch_call(ins->op1, &pending_args[call_base], call_argc, &callee_ret, err)) {
					for (j = call_base; j < pending_len; j++) {
						value_clear(&pending_args[j]);
					}
					pending_len = call_base;
					values_free(&vals);
					return 0;
				}
			} else {
				runtime_values callee_return_fields = {0};
				if (!execute_function(prog, labels, funcs, callee, &pending_args[call_base], call_argc, &vals, &callee_ret, &callee_return_fields, err, depth + 1)) {
					for (j = call_base; j < pending_len; j++) {
						value_clear(&pending_args[j]);
					}
					pending_len = call_base;
					values_free(&callee_return_fields);
					values_free(&vals);
					return 0;
				}
				if (callee_return_fields.len > 0 && callee_ret.kind == RUNTIME_STRING && callee_ret.str_value && callee_ret.str_value[0] != '\0') {
					runtime_data_value remapped_alias = value_make_string_copy(ins->result);
					if (remapped_alias.str_value == NULL) {
						for (j = call_base; j < pending_len; j++) {
							value_clear(&pending_args[j]);
						}
						pending_len = call_base;
						values_free(&callee_return_fields);
						value_clear(&callee_ret);
						values_free(&vals);
						error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
						return 0;
					}
					if (!values_set(&vals, ins->result, &remapped_alias) ||
					    !values_copy_prefixed(&callee_return_fields, callee_ret.str_value, &vals, ins->result)) {
						for (j = call_base; j < pending_len; j++) {
							value_clear(&pending_args[j]);
						}
						pending_len = call_base;
						values_free(&callee_return_fields);
						value_clear(&remapped_alias);
						value_clear(&callee_ret);
						values_free(&vals);
						error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
						return 0;
					}
					value_clear(&remapped_alias);
					values_free(&callee_return_fields);
					for (j = call_base; j < pending_len; j++) {
						value_clear(&pending_args[j]);
					}
					pending_len = call_base;
					value_clear(&callee_ret);
					pc++;
					continue;
				}
				values_free(&callee_return_fields);
			}
			for (j = call_base; j < pending_len; j++) {
				value_clear(&pending_args[j]);
			}
			pending_len = call_base;
			if (!values_set(&vals, ins->result, &callee_ret)) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				value_clear(&callee_ret);
				values_free(&vals);
				return 0;
			}
			value_clear(&callee_ret);
			pc++;
			continue;
		}
		if (strcmp(ins->op, "RET") == 0) {
			if (ins->result[0] == '\0') {
				*out_return = value_make_int(0);
			} else if (!resolve_value(&vals, ins->result, out_return)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown return value: %s", ins->result);
				values_free(&vals);
				return 0;
			}
			if (out_return_fields && out_return->kind == RUNTIME_STRING && out_return->str_value && out_return->str_value[0] != '\0') {
				if (!values_copy_prefixed(&vals, out_return->str_value, out_return_fields, out_return->str_value)) {
					error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
					values_free(&vals);
					return 0;
				}
			}
			values_free(&vals);
			return 1;
		}

		error_set(err, ERR_SEMANTIC, 0, 0, "unsupported runtime op: %s", ins->op);
		values_free(&vals);
		return 0;
	}

	*out_return = value_make_int(0);
	values_free(&vals);
	return 1;
}

bool runtime_execute_text_with_argv(
	const char *target_text,
	const char *entry_function,
	long *out_return,
	compile_error *err,
	int argc,
	char **argv
) {
	runtime_program prog = {0};
	runtime_labels labels = {0};
	runtime_functions funcs = {0};
	const runtime_function *entry = NULL;
	const char *entry_name = entry_function;
	runtime_data_value no_args[1] = { value_make_int(0) };
	runtime_data_value ret = value_make_int(0);
	int ok;

	error_clear(err);
	if (!target_text || !out_return) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid runtime input");
		return false;
	}
	runtime_profile_init_from_env();

	g_host_argc = argc;
	g_host_argv = argv;

	if (!parse_program_text(target_text, &prog, &labels, err)) {
		program_free(&prog);
		labels_free(&labels);
		g_host_argc = 0;
		g_host_argv = NULL;
		return false;
	}

	if (!build_function_table(&prog, &funcs, err)) {
		program_free(&prog);
		labels_free(&labels);
		functions_free(&funcs);
		g_host_argc = 0;
		g_host_argv = NULL;
		return false;
	}

	if (!entry_name || entry_name[0] == '\0') {
		entry_name = "main";
	}
	entry = functions_find(&funcs, entry_name);
	if (!entry) {
		error_set(err, ERR_SEMANTIC, 0, 0, "entry function not found: %s", entry_name);
		program_free(&prog);
		labels_free(&labels);
		functions_free(&funcs);
		g_host_argc = 0;
		g_host_argv = NULL;
		return false;
	}

	ok = execute_function(&prog, &labels, &funcs, entry, no_args, 0, NULL, &ret, NULL, err, 0);
	if (g_runtime_profile_enabled) {
		runtime_profile_dump_summary();
	}
	if (ok) {
		if (ret.kind == RUNTIME_INT) {
			*out_return = ret.int_value;
		} else {
			*out_return = ret.str_value ? (long)strlen(ret.str_value) : 0;
		}
	}
	value_clear(&ret);
	program_free(&prog);
	labels_free(&labels);
	functions_free(&funcs);
	g_host_argc = 0;
	g_host_argv = NULL;
	return ok ? true : false;
}

bool runtime_execute_text(const char *target_text, const char *entry_function, long *out_return, compile_error *err) {
	return runtime_execute_text_with_argv(target_text, entry_function, out_return, err, 0, NULL);
}

bool runtime_execute_text_i64(
	const char *target_text,
	const char *entry_function,
	const int64_t *args,
	size_t argc,
	int64_t *out_return,
	compile_error *err
) {
	runtime_program prog = {0};
	runtime_labels labels = {0};
	runtime_functions funcs = {0};
	const runtime_function *entry;
	runtime_data_value *runtime_args = NULL;
	runtime_data_value ret = value_make_int(0);
	size_t i;
	int ok;

	error_clear(err);
	if (!target_text || !entry_function || !out_return || (argc > 0 && !args)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid typed runtime input");
		return false;
	}
	if (argc > 0) {
		runtime_args = (runtime_data_value *)calloc(argc, sizeof(*runtime_args));
		if (!runtime_args) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return false;
		}
		for (i = 0; i < argc; i++) {
			if (args[i] < (int64_t)LONG_MIN || args[i] > (int64_t)LONG_MAX) {
				free(runtime_args);
				error_set(err, ERR_SEMANTIC, 0, 0, "C ABI integer argument is outside the S runtime range");
				return false;
			}
			runtime_args[i] = value_make_int(args[i]);
		}
	}
	if (!parse_program_text(target_text, &prog, &labels, err) ||
	    !build_function_table(&prog, &funcs, err)) {
		free(runtime_args);
		program_free(&prog);
		labels_free(&labels);
		functions_free(&funcs);
		return false;
	}
	entry = functions_find(&funcs, entry_function);
	if (!entry) {
		error_set(err, ERR_SEMANTIC, 0, 0, "entry function not found: %s", entry_function);
		free(runtime_args);
		program_free(&prog);
		labels_free(&labels);
		functions_free(&funcs);
		return false;
	}
	ok = execute_function(&prog, &labels, &funcs, entry, runtime_args, argc, NULL, &ret, NULL, err, 0);
	if (ok && ret.kind != RUNTIME_INT) {
		error_set(err, ERR_SEMANTIC, 0, 0, "C ABI i64 entry returned a non-integer value: %s", entry_function);
		ok = 0;
	}
	if (ok) {
		*out_return = (int64_t)ret.int_value;
	}
	value_clear(&ret);
	free(runtime_args);
	program_free(&prog);
	labels_free(&labels);
	functions_free(&funcs);
	return ok ? true : false;
}

bool runtime_execute_file(const char *target_path, const char *entry_function, long *out_return, compile_error *err) {
	FILE *fp;
	long n;
	size_t read_n;
	char *buf;
	bool ok;

	error_clear(err);
	if (!target_path || !out_return) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid runtime input");
		return false;
	}

	fp = fopen(target_path, "rb");
	if (!fp) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open target: %s", target_path);
		return false;
	}
	if (fseek(fp, 0, SEEK_END) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to seek target: %s", target_path);
		return false;
	}
	n = ftell(fp);
	if (n < 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to measure target: %s", target_path);
		return false;
	}
	if (fseek(fp, 0, SEEK_SET) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to rewind target: %s", target_path);
		return false;
	}

	buf = (char *)malloc((size_t)n + 1);
	if (!buf) {
		fclose(fp);
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return false;
	}
	read_n = fread(buf, 1, (size_t)n, fp);
	fclose(fp);
	if (read_n != (size_t)n) {
		free(buf);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to read target: %s", target_path);
		return false;
	}
	buf[n] = '\0';

	ok = runtime_execute_text(buf, entry_function, out_return, err);
	free(buf);
	return ok;
}
