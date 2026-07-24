#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "target.h"

#define STANDALONE_MAX_INS 8192
#define STANDALONE_MAX_FUNCS 256
#define STANDALONE_MAX_SLOTS 2048
#define STANDALONE_MAX_LITERALS 2048
#define STANDALONE_MAX_ARGS 6
#define STANDALONE_TEXT_CAP 1024

typedef struct standalone_ins {
	char op[32];
	char result[STANDALONE_TEXT_CAP];
	char operand1[STANDALONE_TEXT_CAP];
	char operand2[STANDALONE_TEXT_CAP];
} standalone_ins;

typedef struct standalone_ir {
	standalone_ins ins[STANDALONE_MAX_INS];
	size_t len;
} standalone_ir;

typedef struct standalone_slot {
	char name[STANDALONE_TEXT_CAP];
	int offset;
} standalone_slot;

typedef struct standalone_function {
	char name[STANDALONE_TEXT_CAP];
	size_t begin;
	size_t end;
	standalone_slot slots[STANDALONE_MAX_SLOTS];
	size_t slot_count;
	int frame_size;
} standalone_function;

typedef struct standalone_literal {
	char encoded[STANDALONE_TEXT_CAP];
	unsigned char bytes[STANDALONE_TEXT_CAP];
	size_t len;
} standalone_literal;

typedef struct standalone_module {
	standalone_ir ir;
	standalone_function funcs[STANDALONE_MAX_FUNCS];
	size_t func_count;
	standalone_literal literals[STANDALONE_MAX_LITERALS];
	size_t literal_count;
} standalone_module;

static void copy_text(char *dst, size_t cap, const char *src) {
	if (!src) src = "";
	snprintf(dst, cap, "%s", src);
}

static bool split_ir_record(char *line, char *fields[4]) {
	size_t count = 0;
	char *start = line;
	char *p;
	for (p = line; ; p++) {
		if (*p == '|' && (p == line || p[-1] != '\\')) {
			*p = '\0';
			if (count >= 4) return false;
			fields[count++] = start;
			start = p + 1;
			continue;
		}
		if (*p == '\0' || *p == '\n' || *p == '\r') {
			*p = '\0';
			if (count >= 4) return false;
			fields[count++] = start;
			break;
		}
	}
	return count == 4;
}

static bool load_ir(const char *path, standalone_ir *ir, compile_error *err) {
	FILE *fp = fopen(path, "rb");
	char *line = NULL;
	size_t cap = 0;
	ssize_t n;
	bool saw_header = false;
	ir->len = 0;
	if (!fp) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open standalone IR input: %s", path);
		return false;
	}
	while ((n = getline(&line, &cap, fp)) >= 0) {
		char *fields[4];
		standalone_ins *ins;
		(void)n;
		if (!saw_header) {
			saw_header = true;
			if (strncmp(line, "SSEED-TARGET-V1", 15) != 0) {
				error_set(err, ERR_SEMANTIC, 1, 1, "invalid standalone IR header");
				free(line);
				fclose(fp);
				return false;
			}
			continue;
		}
		if (line[0] == '\0' || line[0] == '\n' || line[0] == '\r') continue;
		if (ir->len >= STANDALONE_MAX_INS || !split_ir_record(line, fields)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "invalid or oversized standalone IR");
			free(line);
			fclose(fp);
			return false;
		}
		ins = &ir->ins[ir->len++];
		copy_text(ins->op, sizeof(ins->op), fields[0]);
		copy_text(ins->result, sizeof(ins->result), fields[1]);
		copy_text(ins->operand1, sizeof(ins->operand1), fields[2]);
		copy_text(ins->operand2, sizeof(ins->operand2), fields[3]);
	}
	free(line);
	if (fclose(fp) != 0 || !saw_header) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed reading standalone IR input: %s", path);
		return false;
	}
	return true;
}

static bool is_integer(const char *text) {
	char *end = NULL;
	if (!text || !*text) return false;
	errno = 0;
	(void)strtoll(text, &end, 10);
	return errno == 0 && end && *end == '\0';
}

static bool is_string_literal(const char *text) {
	size_t n = text ? strlen(text) : 0;
	return n >= 2 && text[0] == '"' && text[n - 1] == '"';
}

static bool is_value_variable(const char *text) {
	if (!text || !*text || strcmp(text, "_") == 0) return false;
	if (is_integer(text) || is_string_literal(text)) return false;
	if (strcmp(text, "true") == 0 || strcmp(text, "false") == 0) return false;
	if (text[0] == '[') return false;
	return true;
}

static void symbol_text(const char *name, char *out, size_t cap) {
	size_t used = 0;
	const unsigned char *p = (const unsigned char *)name;
	while (*p && used + 1 < cap) {
		unsigned char ch = *p++;
		out[used++] = (isalnum(ch) || ch == '_') ? (char)ch : '_';
	}
	out[used] = '\0';
}

static int slot_index(standalone_function *fn, const char *name, bool create) {
	size_t i;
	for (i = 0; i < fn->slot_count; i++) {
		if (strcmp(fn->slots[i].name, name) == 0) return (int)i;
	}
	if (!create || fn->slot_count >= STANDALONE_MAX_SLOTS) return -1;
	copy_text(fn->slots[fn->slot_count].name, sizeof(fn->slots[fn->slot_count].name), name);
	fn->slots[fn->slot_count].offset = -(int)((fn->slot_count + 1) * 8);
	return (int)fn->slot_count++;
}

static bool collect_operand(standalone_function *fn, const char *operand, compile_error *err) {
	if (is_value_variable(operand) && slot_index(fn, operand, true) < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "too many standalone locals in %s", fn->name);
		return false;
	}
	return true;
}

static bool decode_literal(const char *encoded, standalone_literal *lit, compile_error *err) {
	size_t i;
	size_t n = strlen(encoded);
	lit->len = 0;
	copy_text(lit->encoded, sizeof(lit->encoded), encoded);
	for (i = 1; i + 1 < n; i++) {
		unsigned char ch = (unsigned char)encoded[i];
		if (ch == '\\' && i + 1 < n - 1) {
			unsigned char next = (unsigned char)encoded[++i];
			switch (next) {
			case 'n': ch = '\n'; break;
			case 'r': ch = '\r'; break;
			case 't': ch = '\t'; break;
			case '\\': ch = '\\'; break;
			case '"': ch = '"'; break;
			case '|': ch = '|'; break;
			default: ch = next; break;
			}
		}
		if (lit->len + 1 >= sizeof(lit->bytes)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "standalone string literal is too long");
			return false;
		}
		lit->bytes[lit->len++] = ch;
	}
	return true;
}

static int literal_index(standalone_module *module, const char *encoded, compile_error *err) {
	size_t i;
	for (i = 0; i < module->literal_count; i++) {
		if (strcmp(module->literals[i].encoded, encoded) == 0) return (int)i;
	}
	if (module->literal_count >= STANDALONE_MAX_LITERALS) {
		error_set(err, ERR_SEMANTIC, 0, 0, "too many standalone string literals");
		return -1;
	}
	if (!decode_literal(encoded, &module->literals[module->literal_count], err)) return -1;
	return (int)module->literal_count++;
}

static bool analyze_module(standalone_module *module, compile_error *err) {
	size_t i;
	standalone_function *current = NULL;
	module->func_count = 0;
	module->literal_count = 0;
	for (i = 0; i < module->ir.len; i++) {
		standalone_ins *ins = &module->ir.ins[i];
		const char *values[3] = {ins->result, ins->operand1, ins->operand2};
		size_t v;
		if (strcmp(ins->op, "FUNC_BEGIN") == 0) {
			if (module->func_count >= STANDALONE_MAX_FUNCS) {
				error_set(err, ERR_SEMANTIC, 0, 0, "too many standalone functions");
				return false;
			}
			current = &module->funcs[module->func_count++];
			memset(current, 0, sizeof(*current));
			copy_text(current->name, sizeof(current->name), ins->result);
			current->begin = i + 1;
			continue;
		}
		if (strcmp(ins->op, "FUNC_END") == 0) {
			if (!current) {
				error_set(err, ERR_SEMANTIC, 0, 0, "FUNC_END without FUNC_BEGIN");
				return false;
			}
			current->end = i;
			current->frame_size = (int)(((current->slot_count * 8 + 15) / 16) * 16);
			current = NULL;
			continue;
		}
		for (v = 0; v < 3; v++) {
			if (is_string_literal(values[v]) && literal_index(module, values[v], err) < 0) return false;
		}
		if (!current) continue;
		if (strcmp(ins->op, "LABEL") == 0 || strcmp(ins->op, "JUMP") == 0 ||
			strcmp(ins->op, "EXPORT") == 0 || strcmp(ins->op, "NOP") == 0) continue;
		if (strcmp(ins->op, "JUMP_IF_FALSE") == 0) {
			if (!collect_operand(current, ins->operand1, err)) return false;
			continue;
		}
		if (strcmp(ins->op, "CALL") == 0) {
			if (!collect_operand(current, ins->result, err)) return false;
			continue;
		}
		if (strcmp(ins->op, "ARG") == 0 || strcmp(ins->op, "RET") == 0 || strcmp(ins->op, "PARAM") == 0) {
			if (!collect_operand(current, ins->result, err)) return false;
			continue;
		}
		if (!collect_operand(current, ins->result, err) ||
			!collect_operand(current, ins->operand1, err) ||
			!collect_operand(current, ins->operand2, err)) return false;
	}
	if (current) {
		error_set(err, ERR_SEMANTIC, 0, 0, "unterminated standalone function: %s", current->name);
		return false;
	}
	return module->func_count > 0;
}

static int find_literal(const standalone_module *module, const char *encoded) {
	size_t i;
	for (i = 0; i < module->literal_count; i++) {
		if (strcmp(module->literals[i].encoded, encoded) == 0) return (int)i;
	}
	return -1;
}

static bool emit_load(FILE *out, standalone_module *module, standalone_function *fn,
	const char *value, const char *reg, compile_error *err) {
	int slot;
	if (!value || !*value || strcmp(value, "_") == 0) {
		fprintf(out, "    mov $1, %s\n", reg);
		return true;
	}
	if (strcmp(value, "true") == 0) {
		fprintf(out, "    mov $3, %s\n", reg);
		return true;
	}
	if (strcmp(value, "false") == 0) {
		fprintf(out, "    mov $1, %s\n", reg);
		return true;
	}
	if (is_integer(value)) {
		long long raw = strtoll(value, NULL, 10);
		fprintf(out, "    mov $%lld, %s\n", raw * 2 + 1, reg);
		return true;
	}
	if (is_string_literal(value)) {
		int literal = find_literal(module, value);
		if (literal < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "missing standalone literal: %s", value);
			return false;
		}
		fprintf(out, "    lea .Ls_literal_%d(%%rip), %s\n", literal, reg);
		return true;
	}
	slot = slot_index(fn, value, false);
	if (slot < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "unknown standalone value %s in %s", value, fn->name);
		return false;
	}
	fprintf(out, "    mov %d(%%rbp), %s\n", fn->slots[slot].offset, reg);
	return true;
}

static bool emit_store(FILE *out, standalone_function *fn, const char *name, const char *reg, compile_error *err) {
	int slot;
	if (!name || !*name || strcmp(name, "_") == 0) return true;
	slot = slot_index(fn, name, false);
	if (slot < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "unknown standalone destination %s in %s", name, fn->name);
		return false;
	}
	fprintf(out, "    mov %s, %d(%%rbp)\n", reg, fn->slots[slot].offset);
	return true;
}

static const char *runtime_callee(const char *name) {
	if (strcmp(name, "len") == 0) return "s_value_len";
	if (strcmp(name, "host_args") == 0) return "s_host_args_value";
	if (strcmp(name, "eprintln") == 0) return "s_eprintln_value";
	if (strcmp(name, "__host_char_at") == 0) return "s_string_char_at";
	if (strcmp(name, "__host_byte_at") == 0) return "s_string_byte_at";
	if (strcmp(name, "__host_slice") == 0) return "s_string_slice";
	if (strcmp(name, "__index_get") == 0) return "s_index_get";
	if (strcmp(name, "__host_read_to_string") == 0) return "s_read_file_value";
	if (strcmp(name, "__host_write_text_file") == 0) return "s_write_file_value";
	return NULL;
}

static bool emit_function(FILE *out, standalone_module *module, standalone_function *fn, compile_error *err) {
	static const char *arg_regs[STANDALONE_MAX_ARGS] = {"%rdi", "%rsi", "%rdx", "%rcx", "%r8", "%r9"};
	const char *pending[STANDALONE_MAX_ARGS];
	size_t pending_count = 0;
	size_t param_count = 0;
	size_t i;
	char symbol[STANDALONE_TEXT_CAP];
	symbol_text(fn->name, symbol, sizeof(symbol));
	fprintf(out, ".global s_fn_%s\n.type s_fn_%s, @function\ns_fn_%s:\n", symbol, symbol, symbol);
	fprintf(out, "    push %%rbp\n    mov %%rsp, %%rbp\n");
	if (fn->frame_size > 0) fprintf(out, "    sub $%d, %%rsp\n", fn->frame_size);
	for (i = fn->begin; i < fn->end; i++) {
		standalone_ins *ins = &module->ir.ins[i];
		if (strcmp(ins->op, "PARAM") == 0) {
			if (param_count >= STANDALONE_MAX_ARGS) {
				error_set(err, ERR_SEMANTIC, 0, 0, "more than six parameters are not supported in %s", fn->name);
				return false;
			}
			if (!emit_store(out, fn, ins->result, arg_regs[param_count++], err)) return false;
		} else if (strcmp(ins->op, "ARG") == 0) {
			if (pending_count >= STANDALONE_MAX_ARGS) {
				error_set(err, ERR_SEMANTIC, 0, 0, "more than six call arguments are not supported in %s", fn->name);
				return false;
			}
			pending[pending_count++] = ins->result;
		} else if (strcmp(ins->op, "CALL") == 0) {
			const char *callee = runtime_callee(ins->operand1);
			char local_callee[STANDALONE_TEXT_CAP];
			size_t arg;
			for (arg = 0; arg < pending_count; arg++) {
				if (!emit_load(out, module, fn, pending[arg], arg_regs[arg], err)) return false;
			}
			if (!callee) {
				symbol_text(ins->operand1, local_callee, sizeof(local_callee));
				fprintf(out, "    call s_fn_%s\n", local_callee);
			} else {
				fprintf(out, "    call %s\n", callee);
			}
			if (!emit_store(out, fn, ins->result, "%rax", err)) return false;
			pending_count = 0;
		} else if (strcmp(ins->op, "MOV") == 0) {
			if (!emit_load(out, module, fn, ins->operand1, "%rax", err) ||
				!emit_store(out, fn, ins->result, "%rax", err)) return false;
		} else if (strcmp(ins->op, "ADD") == 0) {
			if (!emit_load(out, module, fn, ins->operand1, "%rdi", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rsi", err)) return false;
			fprintf(out, "    call s_value_add\n");
			if (!emit_store(out, fn, ins->result, "%rax", err)) return false;
		} else if (strcmp(ins->op, "SUB") == 0 || strcmp(ins->op, "MUL") == 0) {
			if (!emit_load(out, module, fn, ins->operand1, "%rax", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rcx", err)) return false;
			fprintf(out, "    sar $1, %%rax\n    sar $1, %%rcx\n");
			fprintf(out, strcmp(ins->op, "SUB") == 0 ? "    sub %%rcx, %%rax\n" : "    imul %%rcx, %%rax\n");
			fprintf(out, "    lea 1(%%rax,%%rax), %%rax\n");
			if (!emit_store(out, fn, ins->result, "%rax", err)) return false;
		} else if (strcmp(ins->op, "DIV") == 0 || strcmp(ins->op, "MOD") == 0) {
			if (!emit_load(out, module, fn, ins->operand1, "%rax", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rcx", err)) return false;
			fprintf(out, "    sar $1, %%rax\n    sar $1, %%rcx\n    cqo\n    idiv %%rcx\n");
			if (strcmp(ins->op, "MOD") == 0) fprintf(out, "    mov %%rdx, %%rax\n");
			fprintf(out, "    lea 1(%%rax,%%rax), %%rax\n");
			if (!emit_store(out, fn, ins->result, "%rax", err)) return false;
		} else if (strncmp(ins->op, "CMP_", 4) == 0) {
			const char *setcc = "sete";
			if (strcmp(ins->op, "CMP_NE") == 0) setcc = "setne";
			else if (strcmp(ins->op, "CMP_LT") == 0) setcc = "setl";
			else if (strcmp(ins->op, "CMP_LE") == 0) setcc = "setle";
			else if (strcmp(ins->op, "CMP_GT") == 0) setcc = "setg";
			else if (strcmp(ins->op, "CMP_GE") == 0) setcc = "setge";
			if (!emit_load(out, module, fn, ins->operand1, "%rdi", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rsi", err)) return false;
			fprintf(out, "    call s_value_cmp\n    cmp $0, %%rax\n    %s %%al\n    movzbq %%al, %%rax\n    lea 1(%%rax,%%rax), %%rax\n", setcc);
			if (!emit_store(out, fn, ins->result, "%rax", err)) return false;
		} else if (strcmp(ins->op, "JUMP_IF_FALSE") == 0) {
			char label[STANDALONE_TEXT_CAP];
			symbol_text(ins->result, label, sizeof(label));
			if (!emit_load(out, module, fn, ins->operand1, "%rax", err)) return false;
			fprintf(out, "    cmp $1, %%rax\n    je .Ls_%s_%s\n", symbol, label);
		} else if (strcmp(ins->op, "JUMP") == 0) {
			char label[STANDALONE_TEXT_CAP];
			symbol_text(ins->result, label, sizeof(label));
			fprintf(out, "    jmp .Ls_%s_%s\n", symbol, label);
		} else if (strcmp(ins->op, "LABEL") == 0) {
			char label[STANDALONE_TEXT_CAP];
			symbol_text(ins->result, label, sizeof(label));
			fprintf(out, ".Ls_%s_%s:\n", symbol, label);
		} else if (strcmp(ins->op, "INDEX_SET") == 0) {
			if (!emit_load(out, module, fn, ins->result, "%rdi", err) ||
				!emit_load(out, module, fn, ins->operand1, "%rsi", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rdx", err)) return false;
			fprintf(out, "    call s_index_set\n");
		} else if (strcmp(ins->op, "RET") == 0) {
			if (!emit_load(out, module, fn, ins->result, "%rax", err)) return false;
			fprintf(out, "    jmp .Ls_%s_return\n", symbol);
		} else if (strcmp(ins->op, "NOP") != 0 && strcmp(ins->op, "EXPORT") != 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "unsupported standalone opcode %s", ins->op);
			return false;
		}
	}
	fprintf(out, "    mov $1, %%rax\n.Ls_%s_return:\n    leave\n    ret\n.size s_fn_%s, .-s_fn_%s\n\n", symbol, symbol, symbol);
	return true;
}

static bool emit_assembly(FILE *out, standalone_module *module, compile_error *err) {
	size_t i;
	fprintf(out, ".section .text\n.global s_main\n.type s_main, @function\ns_main:\n    jmp s_fn_main\n.size s_main, .-s_main\n\n");
	for (i = 0; i < module->func_count; i++) {
		if (!emit_function(out, module, &module->funcs[i], err)) return false;
	}
	fprintf(out, ".section .rodata\n");
	for (i = 0; i < module->literal_count; i++) {
		size_t j;
		standalone_literal *lit = &module->literals[i];
		fprintf(out, ".balign 8\n.Ls_literal_%zu:\n    .quad 2\n    .quad %zu\n    .byte ", i, lit->len);
		for (j = 0; j < lit->len; j++) fprintf(out, "%s%u", j ? "," : "", (unsigned)lit->bytes[j]);
		fprintf(out, "%s0\n", lit->len ? "," : "");
	}
	fprintf(out, ".section .note.GNU-stack,\"\",@progbits\n");
	return !ferror(out);
}

static bool run_tool(char *const argv[], compile_error *err) {
	pid_t pid = fork();
	int status;
	if (pid < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to fork %s", argv[0]);
		return false;
	}
	if (pid == 0) {
		execvp(argv[0], argv);
		_exit(127);
	}
	if (waitpid(pid, &status, 0) < 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "standalone tool failed: %s", argv[0]);
		return false;
	}
	return true;
}

bool emit_standalone_amd64_from_ir_file(const char *input_ir_path, const char *output_binary_path, compile_error *err) {
	standalone_module *module = NULL;
	char asm_path[256];
	char obj_path[256];
	char runtime_obj_path[256];
	char runtime_source[1024];
	char linker_script[1024];
	const char *root = getenv("S_SOURCE_ROOT");
	FILE *out = NULL;
	bool ok = false;
	char *as_program[] = {"as", "--64", "-o", obj_path, asm_path, NULL};
	char *as_runtime[] = {"as", "--64", "-o", runtime_obj_path, runtime_source, NULL};
	char *ld_program[] = {"ld", "-static", "-T", linker_script, "-o", (char *)output_binary_path, runtime_obj_path, obj_path, NULL};

	error_clear(err);
	if (!input_ir_path || !output_binary_path) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid standalone backend input");
		return false;
	}
	if (!root || !*root) root = ".";
	snprintf(asm_path, sizeof(asm_path), "/tmp/s_standalone_%ld.s", (long)getpid());
	snprintf(obj_path, sizeof(obj_path), "/tmp/s_standalone_%ld.o", (long)getpid());
	snprintf(runtime_obj_path, sizeof(runtime_obj_path), "/tmp/s_standalone_runtime_%ld.o", (long)getpid());
	snprintf(runtime_source, sizeof(runtime_source), "%s/src/runtime/selfhost_linux_amd64.S", root);
	snprintf(linker_script, sizeof(linker_script), "%s/src/runtime/linker/nostdlib.ld", root);

	module = (standalone_module *)calloc(1, sizeof(*module));
	if (!module) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		goto done;
	}
	if (!load_ir(input_ir_path, &module->ir, err) || !analyze_module(module, err)) goto done;
	out = fopen(asm_path, "wb");
	if (!out) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to create standalone assembly");
		goto done;
	}
	if (!emit_assembly(out, module, err)) goto done;
	if (fclose(out) != 0) {
		out = NULL;
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close standalone assembly");
		goto done;
	}
	out = NULL;
	if (!run_tool(as_runtime, err) || !run_tool(as_program, err) || !run_tool(ld_program, err)) goto done;
	ok = true;

done:
	if (out) fclose(out);
	unlink(asm_path);
	unlink(obj_path);
	unlink(runtime_obj_path);
	free(module);
	return ok;
}
