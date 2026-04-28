#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../code/target.h"
#include "../intermediate/ir.h"
#include "../lexical/token.h"
#include "../semantic/scope.h"
#include "../syntax/ast.h"
#include "memory.h"

static int g_host_argc = 0;
static char **g_host_argv = NULL;

typedef enum runtime_value_kind {
	RUNTIME_INT = 0,
	RUNTIME_STRING,
} runtime_value_kind;

typedef struct runtime_data_value {
	runtime_value_kind kind;
	long int_value;
	char *str_value;
} runtime_data_value;

static runtime_data_value value_make_int(long v) {
	runtime_data_value out;
	out.kind = RUNTIME_INT;
	out.int_value = v;
	out.str_value = NULL;
	return out;
}

static runtime_data_value value_make_string_owned(char *s) {
	runtime_data_value out;
	out.kind = RUNTIME_STRING;
	out.int_value = 0;
	out.str_value = s;
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
	}
	v->kind = RUNTIME_INT;
	v->int_value = 0;
	v->str_value = NULL;
}

static int value_copy(runtime_data_value *dst, const runtime_data_value *src) {
	if (src->kind == RUNTIME_INT) {
		*dst = value_make_int(src->int_value);
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
	return v->str_value && v->str_value[0] != '\0';
}

static int value_as_cstr(const runtime_data_value *v, char *tmp, size_t tmp_size, const char **out) {
	if (v->kind == RUNTIME_STRING) {
		*out = v->str_value ? v->str_value : "";
		return 1;
	}
	if (snprintf(tmp, tmp_size, "%ld", v->int_value) < 0) {
		return 0;
	}
	*out = tmp;
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

static void print_compile_error_local(const compile_error *err) {
	if (!err || !error_is_set(err)) {
		return;
	}
	fprintf(stderr, "error[%d] at %zu:%zu: %s\n", (int)err->code, err->line, err->column, err->message);
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

static int host_dispatch_call(
	const char *name,
	const runtime_data_value *args,
	size_t argc,
	runtime_data_value *out,
	compile_error *err
) {
	if (strcmp(name, "host_args") == 0) {
		(void)args;
		if (argc != 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "host_args expects 0 args");
			return 0;
		}
		*out = value_make_int(1);
		return 1;
	}
	if (strcmp(name, "buildcfg_goarch") == 0) {
		(void)args;
		if (argc != 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "buildcfg_goarch expects 0 args");
			return 0;
		}
		*out = value_make_string_copy("arm64");
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
		char num_buf[64];
		const char *msg = NULL;
		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "eprintln expects 1 arg");
			return 0;
		}
		if (!value_as_cstr(&args[0], num_buf, sizeof(num_buf), &msg)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to render eprintln argument");
			return 0;
		}
		fprintf(stderr, "%s\n", msg);
		*out = value_make_int(0);
		return 1;
	}
	if (strcmp(name, "build_main") == 0) {
		compile_error compile_err;
		if (argc != 1) {
			error_set(err, ERR_SEMANTIC, 0, 0, "build_main expects 1 arg");
			return 0;
		}
		if (g_host_argc != 3 || !g_host_argv) {
			fprintf(stderr, "usage:\n  <compiler> <input.s> <output.ir>\n");
			*out = value_make_int(2);
			return 1;
		}
		error_clear(&compile_err);
		if (!compile_s_file_to_ir(g_host_argv[1], g_host_argv[2], &compile_err)) {
			print_compile_error_local(&compile_err);
			*out = value_make_int(1);
			return 1;
		}
		printf("compiled %s -> %s\n", g_host_argv[1], g_host_argv[2]);
		*out = value_make_int(0);
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
	char *parts[4];
	char *p;
	int i;

	snprintf(tmp, sizeof(tmp), "%s", line);
	p = tmp;
	for (i = 0; i < 4; i++) {
		parts[i] = p;
		p = strchr(p, '|');
		if (!p && i < 3) {
			return 0;
		}
		if (p) {
			*p = '\0';
			p++;
		}
	}

	snprintf(out->op, sizeof(out->op), "%s", parts[0]);
	snprintf(out->result, sizeof(out->result), "%s", strcmp(parts[1], "_") == 0 ? "" : parts[1]);
	snprintf(out->op1, sizeof(out->op1), "%s", strcmp(parts[2], "_") == 0 ? "" : parts[2]);
	snprintf(out->op2, sizeof(out->op2), "%s", strcmp(parts[3], "_") == 0 ? "" : parts[3]);
	return 1;
}

static int resolve_value(const runtime_values *vals, const char *name, runtime_data_value *out) {
	if (is_int_literal(name)) {
		*out = value_make_int(strtol(name, NULL, 10));
		return 1;
	}
	if (is_string_literal(name)) {
		*out = parse_string_literal(name);
		return out->str_value != NULL;
	}
	return values_get(vals, name, out);
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
	runtime_data_value *out_return,
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

	for (i = 0; i < argc; i++) {
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
			if (!resolve_value(&vals, ins->op1, &a)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown value: %s", ins->op1);
				value_clear(&a);
				values_free(&vals);
				return 0;
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
		if (strcmp(ins->op, "ADD") == 0 || strcmp(ins->op, "SUB") == 0 || strcmp(ins->op, "MUL") == 0 || strcmp(ins->op, "DIV") == 0 ||
			strcmp(ins->op, "CMP_EQ") == 0 || strcmp(ins->op, "CMP_NE") == 0 || strcmp(ins->op, "CMP_LT") == 0 || strcmp(ins->op, "CMP_LE") == 0 ||
			strcmp(ins->op, "CMP_GT") == 0 || strcmp(ins->op, "CMP_GE") == 0) {
			runtime_data_value r = value_make_int(0);
			int ok = 1;
			if (!resolve_value(&vals, ins->op1, &a) || !resolve_value(&vals, ins->op2, &b)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown value in op: %s", ins->op);
				value_clear(&a);
				value_clear(&b);
				values_free(&vals);
				return 0;
			}
			if (strcmp(ins->op, "ADD") == 0) {
				if (a.kind == RUNTIME_INT && b.kind == RUNTIME_INT) {
					r = value_make_int(a.int_value + b.int_value);
				} else if (!value_concat(&r, &a, &b)) {
					ok = 0;
				}
			} else if (strcmp(ins->op, "SUB") == 0) {
				if (a.kind != RUNTIME_INT || b.kind != RUNTIME_INT) {
					error_set(err, ERR_SEMANTIC, 0, 0, "SUB expects int operands");
					ok = 0;
				} else {
					r = value_make_int(a.int_value - b.int_value);
				}
			} else if (strcmp(ins->op, "MUL") == 0) {
				if (a.kind != RUNTIME_INT || b.kind != RUNTIME_INT) {
					error_set(err, ERR_SEMANTIC, 0, 0, "MUL expects int operands");
					ok = 0;
				} else {
					r = value_make_int(a.int_value * b.int_value);
				}
			} else if (strcmp(ins->op, "DIV") == 0) {
				if (a.kind != RUNTIME_INT || b.kind != RUNTIME_INT) {
					error_set(err, ERR_SEMANTIC, 0, 0, "DIV expects int operands");
					ok = 0;
				} else if (b.int_value == 0) {
					error_set(err, ERR_SEMANTIC, 0, 0, "division by zero");
					ok = 0;
				} else {
					r = value_make_int(a.int_value / b.int_value);
				}
			} else if (strcmp(ins->op, "CMP_EQ") == 0) {
				if (a.kind != b.kind) {
					error_set(err, ERR_SEMANTIC, 0, 0, "CMP_EQ expects operand types to match");
					ok = 0;
				} else if (a.kind == RUNTIME_INT) {
					r = value_make_int(a.int_value == b.int_value);
				} else {
					r = value_make_int(strcmp(a.str_value ? a.str_value : "", b.str_value ? b.str_value : "") == 0);
				}
			} else if (strcmp(ins->op, "CMP_NE") == 0) {
				if (a.kind != b.kind) {
					error_set(err, ERR_SEMANTIC, 0, 0, "CMP_NE expects operand types to match");
					ok = 0;
				} else if (a.kind == RUNTIME_INT) {
					r = value_make_int(a.int_value != b.int_value);
				} else {
					r = value_make_int(strcmp(a.str_value ? a.str_value : "", b.str_value ? b.str_value : "") != 0);
				}
			} else {
				int cmp;
				if (a.kind != b.kind) {
					error_set(err, ERR_SEMANTIC, 0, 0, "%s expects operand types to match", ins->op);
					ok = 0;
				} else {
					if (a.kind == RUNTIME_INT) {
						cmp = (a.int_value > b.int_value) - (a.int_value < b.int_value);
					} else {
						cmp = strcmp(a.str_value ? a.str_value : "", b.str_value ? b.str_value : "");
					}
					if (strcmp(ins->op, "CMP_LT") == 0) r = value_make_int(cmp < 0);
					else if (strcmp(ins->op, "CMP_LE") == 0) r = value_make_int(cmp <= 0);
					else if (strcmp(ins->op, "CMP_GT") == 0) r = value_make_int(cmp > 0);
					else if (strcmp(ins->op, "CMP_GE") == 0) r = value_make_int(cmp >= 0);
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
				if (!execute_function(prog, labels, funcs, callee, &pending_args[call_base], call_argc, &callee_ret, err, depth + 1)) {
					for (j = call_base; j < pending_len; j++) {
						value_clear(&pending_args[j]);
					}
					pending_len = call_base;
					values_free(&vals);
					return 0;
				}
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
			if (!resolve_value(&vals, ins->result, out_return)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown return value: %s", ins->result);
				values_free(&vals);
				return 0;
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

	ok = execute_function(&prog, &labels, &funcs, entry, no_args, 0, &ret, err, 0);
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