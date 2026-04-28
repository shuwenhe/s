#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "memory.h"

typedef struct runtime_value {
	char name[64];
	long value;
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
	char result[64];
	char op1[64];
	char op2[64];
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
	free(vals->data);
	vals->data = NULL;
	vals->len = 0;
	vals->cap = 0;
}

static int values_set(runtime_values *vals, const char *name, long value) {
	size_t i;
	for (i = 0; i < vals->len; i++) {
		if (strcmp(vals->data[i].name, name) == 0) {
			vals->data[i].value = value;
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
	vals->data[vals->len].value = value;
	vals->len++;
	return 1;
}

static int values_get(const runtime_values *vals, const char *name, long *out) {
	size_t i;
	for (i = 0; i < vals->len; i++) {
		if (strcmp(vals->data[i].name, name) == 0) {
			*out = vals->data[i].value;
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
	snprintf(labels->data[labels->len].name, sizeof(labels->data[labels->len].name), "%s", name);
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
	char tmp[320];
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

static int resolve_value(const runtime_values *vals, const char *name, long *out) {
	if (is_int_literal(name)) {
		*out = strtol(name, NULL, 10);
		return 1;
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
			snprintf(fn.name, sizeof(fn.name), "%s", prog->data[i].result);
			j = i + 1;
			while (j < prog->len && strcmp(prog->data[j].op, "PARAM") == 0) {
				if (fn.param_count >= 32) {
					error_set(err, ERR_SEMANTIC, 0, 0, "too many params in function: %s", fn.name);
					return 0;
				}
				snprintf(fn.params[fn.param_count], sizeof(fn.params[fn.param_count]), "%s", prog->data[j].result);
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
	const long *args,
	size_t argc,
	long *out_return,
	compile_error *err,
	int depth
) {
	runtime_values vals = {0};
	long pending_args[128];
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
		if (!values_set(&vals, fn->params[i], args[i])) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			values_free(&vals);
			return 0;
		}
	}

	while (pc < fn->end_pc) {
		runtime_ins *ins = &prog->data[pc];
		long a = 0;
		long b = 0;

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
				values_free(&vals);
				return 0;
			}
			if (a == 0) {
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
			} else {
				pc++;
			}
			continue;
		}
		if (strcmp(ins->op, "MOV") == 0) {
			if (!resolve_value(&vals, ins->op1, &a)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown value: %s", ins->op1);
				values_free(&vals);
				return 0;
			}
			if (!values_set(&vals, ins->result, a)) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				values_free(&vals);
				return 0;
			}
			pc++;
			continue;
		}
		if (strcmp(ins->op, "ADD") == 0 || strcmp(ins->op, "SUB") == 0 || strcmp(ins->op, "MUL") == 0 || strcmp(ins->op, "DIV") == 0 ||
			strcmp(ins->op, "CMP_EQ") == 0 || strcmp(ins->op, "CMP_NE") == 0 || strcmp(ins->op, "CMP_LT") == 0 || strcmp(ins->op, "CMP_LE") == 0 ||
			strcmp(ins->op, "CMP_GT") == 0 || strcmp(ins->op, "CMP_GE") == 0) {
			long r = 0;
			if (!resolve_value(&vals, ins->op1, &a) || !resolve_value(&vals, ins->op2, &b)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown value in op: %s", ins->op);
				values_free(&vals);
				return 0;
			}
			if (strcmp(ins->op, "ADD") == 0) r = a + b;
			else if (strcmp(ins->op, "SUB") == 0) r = a - b;
			else if (strcmp(ins->op, "MUL") == 0) r = a * b;
			else if (strcmp(ins->op, "DIV") == 0) {
				if (b == 0) {
					error_set(err, ERR_SEMANTIC, 0, 0, "division by zero");
					values_free(&vals);
					return 0;
				}
				r = a / b;
			} else if (strcmp(ins->op, "CMP_EQ") == 0) r = (a == b);
			else if (strcmp(ins->op, "CMP_NE") == 0) r = (a != b);
			else if (strcmp(ins->op, "CMP_LT") == 0) r = (a < b);
			else if (strcmp(ins->op, "CMP_LE") == 0) r = (a <= b);
			else if (strcmp(ins->op, "CMP_GT") == 0) r = (a > b);
			else if (strcmp(ins->op, "CMP_GE") == 0) r = (a >= b);
			if (!values_set(&vals, ins->result, r)) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				values_free(&vals);
				return 0;
			}
			pc++;
			continue;
		}
		if (strcmp(ins->op, "ARG") == 0) {
			if (!resolve_value(&vals, ins->result, &a)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown arg value: %s", ins->result);
				values_free(&vals);
				return 0;
			}
			if (pending_len >= 128) {
				error_set(err, ERR_SEMANTIC, 0, 0, "too many pending call arguments");
				values_free(&vals);
				return 0;
			}
			pending_args[pending_len++] = a;
			pc++;
			continue;
		}
		if (strcmp(ins->op, "CALL") == 0) {
			size_t call_argc = 0;
			long callee_ret = 0;
			const runtime_function *callee;
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
			callee = functions_find(funcs, ins->op1);
			if (!callee) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unknown function: %s", ins->op1);
				values_free(&vals);
				return 0;
			}
			if (!execute_function(prog, labels, funcs, callee, &pending_args[pending_len - call_argc], call_argc, &callee_ret, err, depth + 1)) {
				values_free(&vals);
				return 0;
			}
			pending_len -= call_argc;
			if (!values_set(&vals, ins->result, callee_ret)) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				values_free(&vals);
				return 0;
			}
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

	*out_return = 0;
	values_free(&vals);
	return 1;
}

bool runtime_execute_text(const char *target_text, const char *entry_function, long *out_return, compile_error *err) {
	runtime_program prog = {0};
	runtime_labels labels = {0};
	runtime_functions funcs = {0};
	const runtime_function *entry = NULL;
	const char *entry_name = entry_function;
	long no_args[1] = {0};
	int ok;

	error_clear(err);
	if (!target_text || !out_return) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid runtime input");
		return false;
	}

	if (!parse_program_text(target_text, &prog, &labels, err)) {
		program_free(&prog);
		labels_free(&labels);
		return false;
	}

	if (!build_function_table(&prog, &funcs, err)) {
		program_free(&prog);
		labels_free(&labels);
		functions_free(&funcs);
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
		return false;
	}

	ok = execute_function(&prog, &labels, &funcs, entry, no_args, 0, out_return, err, 0);
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