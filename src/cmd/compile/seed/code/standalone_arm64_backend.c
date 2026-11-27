#if !defined(__APPLE__) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif
#include <ctype.h>
#include <errno.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include "target.h"

#define ARM64_MAX_INS 262144
#define ARM64_MAX_FUNCS 4096
#define ARM64_MAX_LOCALS 8192
#define ARM64_MAX_ARGS 16
#define ARM64_TEXT_CAP 1024

typedef struct arm64_ir_ins {
	char op[32];
	char result[ARM64_TEXT_CAP];
	char operand1[ARM64_TEXT_CAP];
	char operand2[ARM64_TEXT_CAP];
} arm64_ir_ins;

typedef struct arm64_ir_program {
	arm64_ir_ins ins[ARM64_MAX_INS];
	size_t len;
} arm64_ir_program;

typedef struct arm64_local_slot {
	char name[ARM64_TEXT_CAP];
	int offset;
} arm64_local_slot;

typedef struct arm64_function {
	char name[ARM64_TEXT_CAP];
	size_t begin;
	size_t end;
	arm64_local_slot locals[ARM64_MAX_LOCALS];
	size_t local_count;
	int frame_size;
} arm64_function;

typedef struct arm64_module {
	arm64_ir_program ir;
	arm64_function functions[ARM64_MAX_FUNCS];
	size_t function_count;
} arm64_module;

static void arm64_copy_text(char *dst, size_t cap, const char *src) {
	size_t i = 0;
	if (!src) src = "";
	if (cap == 0) return;
	for (; i + 1 < cap && src[i] != '\0'; i++) dst[i] = src[i];
	dst[i] = '\0';
}

static bool arm64_split_ir_record(char *line, char *fields[4]) {
	size_t count = 0;
	char *read = line;
	char *write = line;
	fields[count++] = write;
	for (;;) {
		char ch = *read++;
		if (ch == '\\') {
			char escaped = *read++;
			if (escaped == '\0') return false;
			if (escaped == 'n') ch = '\n';
			else if (escaped == 'r') ch = '\r';
			else if (escaped == 't') ch = '\t';
			else ch = escaped;
			*write++ = ch;
			continue;
		}
		if (ch == '|') {
			if (count >= 4) return false;
			*write++ = '\0';
			fields[count++] = write;
			continue;
		}
		if (ch == '\0' || ch == '\n' || ch == '\r') {
			*write = '\0';
			break;
		}
		*write++ = ch;
	}
	return count == 4;
}

static bool arm64_load_ir(const char *path, arm64_ir_program *ir, compile_error *err) {
	FILE *fp = NULL;
	char *line = NULL;
	size_t cap = 0;
	ssize_t n;
	bool saw_header = false;
	ir->len = 0;
	fp = fopen(path, "rb");
	if (!fp) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open standalone IR input: %s", path);
		return false;
	}
	while ((n = getline(&line, &cap, fp)) >= 0) {
		char *fields[4];
		arm64_ir_ins *ins;
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
		if (ir->len >= ARM64_MAX_INS || !arm64_split_ir_record(line, fields)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "invalid or oversized standalone IR");
			free(line);
			fclose(fp);
			return false;
		}
		ins = &ir->ins[ir->len++];
		arm64_copy_text(ins->op, sizeof(ins->op), fields[0]);
		arm64_copy_text(ins->result, sizeof(ins->result), fields[1]);
		arm64_copy_text(ins->operand1, sizeof(ins->operand1), fields[2]);
		arm64_copy_text(ins->operand2, sizeof(ins->operand2), fields[3]);
	}
	free(line);
	if (fclose(fp) != 0 || !saw_header) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed reading standalone IR input: %s", path);
		return false;
	}
	return true;
}

static int arm64_integer_base(const char *text) {
	const char *digits = text;
	if (*digits == '+' || *digits == '-') digits++;
	return digits[0] == '0' && (digits[1] == 'x' || digits[1] == 'X') ? 16 : 10;
}

static bool arm64_is_integer(const char *text) {
	char *end = NULL;
	if (!text || !*text) return false;
	errno = 0;
	(void)strtoll(text, &end, arm64_integer_base(text));
	return errno == 0 && end && *end == '\0';
}

static bool arm64_is_literal(const char *text) {
	if (!text || !*text) return false;
	if (arm64_is_integer(text)) return true;
	if (strcmp(text, "true") == 0 || strcmp(text, "false") == 0) return true;
	return false;
}

static void arm64_symbol_text(const char *src, char *dst, size_t cap) {
	size_t i = 0;
	if (!src) src = "";
	if (cap == 0) return;
	for (; src[i] != '\0' && i + 1 < cap; i++) {
		unsigned char ch = (unsigned char)src[i];
		if (isalnum(ch) || ch == '_') dst[i] = (char)ch;
		else dst[i] = '_';
	}
	dst[i] = '\0';
}

static bool arm64_is_variable(const char *text) {
	return text && *text && strcmp(text, "_") != 0 && !arm64_is_literal(text);
}

static bool arm64_supported_op(const char *op) {
	return strcmp(op, "NOP") == 0 ||
		strcmp(op, "FUNC_BEGIN") == 0 ||
		strcmp(op, "FUNC_END") == 0 ||
		strcmp(op, "PARAM") == 0 ||
		strcmp(op, "LABEL") == 0 ||
		strcmp(op, "JUMP") == 0 ||
		strcmp(op, "JUMP_IF_FALSE") == 0 ||
		strcmp(op, "ARG") == 0 ||
		strcmp(op, "CALL") == 0 ||
		strcmp(op, "RET") == 0 ||
		strcmp(op, "MOV") == 0 ||
		strcmp(op, "ARRAY_NEW") == 0 ||
		strcmp(op, "INDEX_SET") == 0 ||
		strcmp(op, "UNIT") == 0 ||
		strcmp(op, "TRAP") == 0 ||
		strcmp(op, "ADD") == 0 ||
		strcmp(op, "SUB") == 0 ||
		strcmp(op, "MUL") == 0 ||
		strcmp(op, "DIV") == 0 ||
		strcmp(op, "MOD") == 0 ||
		strcmp(op, "CMP_EQ") == 0 ||
		strcmp(op, "CMP_NE") == 0 ||
		strcmp(op, "CMP_LT") == 0 ||
		strcmp(op, "CMP_LE") == 0 ||
		strcmp(op, "CMP_GT") == 0 ||
		strcmp(op, "CMP_GE") == 0;
}

static int arm64_find_slot(arm64_function *fn, const char *name) {
	size_t i;
	for (i = 0; i < fn->local_count; i++) {
		if (strcmp(fn->locals[i].name, name) == 0) return (int)i;
	}
	return -1;
}

static bool arm64_ensure_slot(arm64_function *fn, const char *name, compile_error *err) {
	if (!arm64_is_variable(name)) return true;
	if (arm64_find_slot(fn, name) >= 0) return true;
	if (fn->local_count >= ARM64_MAX_LOCALS) {
		error_set(err, ERR_SEMANTIC, 0, 0, "too many arm64 standalone locals in %s", fn->name);
		return false;
	}
	arm64_copy_text(fn->locals[fn->local_count].name, sizeof(fn->locals[fn->local_count].name), name);
	fn->locals[fn->local_count].offset = (int)(fn->local_count * 8);
	fn->local_count++;
	return true;
}

static bool arm64_analyze_module(arm64_module *module, compile_error *err) {
	size_t i;
	int current = -1;
	module->function_count = 0;
	for (i = 0; i < module->ir.len; i++) {
		arm64_ir_ins *ins = &module->ir.ins[i];
		if (!arm64_supported_op(ins->op)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone unsupported IR op: %s", ins->op);
			return false;
		}
		if (strcmp(ins->op, "FUNC_BEGIN") == 0) {
			if (module->function_count >= ARM64_MAX_FUNCS) {
				error_set(err, ERR_SEMANTIC, 0, 0, "too many arm64 standalone functions");
				return false;
			}
			current = (int)module->function_count++;
			memset(&module->functions[current], 0, sizeof(module->functions[current]));
			module->functions[current].begin = i;
			arm64_copy_text(module->functions[current].name, sizeof(module->functions[current].name), ins->result);
			continue;
		}
		if (strcmp(ins->op, "FUNC_END") == 0) {
			if (current < 0) {
				error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone malformed IR: FUNC_END without FUNC_BEGIN");
				return false;
			}
			module->functions[current].end = i;
			module->functions[current].frame_size = (int)(module->functions[current].local_count * 8);
			if ((module->functions[current].frame_size % 16) != 0) module->functions[current].frame_size += 8;
			if (module->functions[current].frame_size > 32760) {
				error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone frame too large in %s (limit 32760 bytes)", module->functions[current].name);
				return false;
			}
			current = -1;
			continue;
		}
		if (current < 0) continue;
		if (!arm64_ensure_slot(&module->functions[current], ins->result, err) ||
			!arm64_ensure_slot(&module->functions[current], ins->operand1, err) ||
			!arm64_ensure_slot(&module->functions[current], ins->operand2, err)) {
			return false;
		}
		if (strcmp(ins->op, "CALL") == 0 && !arm64_is_integer(ins->operand2)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone CALL requires integer arg count");
			return false;
		}
		if (strcmp(ins->op, "ARG") == 0 && !arm64_is_variable(ins->result) && !arm64_is_literal(ins->result)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone ARG requires literal or local variable");
			return false;
		}
	}
	if (current >= 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone malformed IR: missing FUNC_END");
		return false;
	}
	return true;
}

static bool arm64_slot_offset(const arm64_function *fn, const char *name, int *offset_out) {
	int index = arm64_find_slot((arm64_function *)fn, name);
	if (index < 0) return false;
	*offset_out = fn->locals[index].offset;
	return true;
}

static bool arm64_emit_u64_immediate(FILE *out, const char *reg, uint64_t value, compile_error *err) {
	bool emitted = false;
	int shift = 0;
	if (value == 0) return fprintf(out, "    mov %s, xzr\n", reg) >= 0;
	for (shift = 0; shift < 64; shift += 16) {
		unsigned chunk = (unsigned)((value >> shift) & 0xffffu);
		if (chunk == 0) continue;
		if (!emitted) {
			if (fprintf(out, "    movz %s, #%u, lsl #%d\n", reg, chunk, shift) < 0) goto write_error;
			emitted = true;
		} else {
			if (fprintf(out, "    movk %s, #%u, lsl #%d\n", reg, chunk, shift) < 0) goto write_error;
		}
	}
	return true;
write_error:
	error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone assembly");
	return false;
}

static bool arm64_emit_load_literal(FILE *out, const char *literal, const char *reg, compile_error *err) {
	long long signed_value = 0;
	uint64_t value = 0;
	if (strcmp(literal, "true") == 0) literal = "1";
	if (strcmp(literal, "false") == 0) literal = "0";
	if (!arm64_is_integer(literal)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone unsupported literal: %s", literal);
		return false;
	}
	signed_value = strtoll(literal, NULL, arm64_integer_base(literal));
	value = (uint64_t)signed_value;
	return arm64_emit_u64_immediate(out, reg, value, err);
}

static bool arm64_emit_stack_load(FILE *out, const char *reg, int offset, compile_error *err) {
	if (offset >= 0 && offset <= 32760 && (offset % 8) == 0) {
		if (fprintf(out, "    ldr %s, [sp, #%d]\n", reg, offset) >= 0) return true;
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone assembly");
		return false;
	}
	if (!arm64_emit_u64_immediate(out, "x12", (uint64_t)(unsigned int)offset, err)) return false;
	if (fprintf(out, "    add x12, sp, x12\n    ldr %s, [x12]\n", reg) < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone assembly");
		return false;
	}
	return true;
}

static bool arm64_emit_stack_store(FILE *out, const char *reg, int offset, compile_error *err) {
	if (offset >= 0 && offset <= 32760 && (offset % 8) == 0) {
		if (fprintf(out, "    str %s, [sp, #%d]\n", reg, offset) >= 0) return true;
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone assembly");
		return false;
	}
	if (!arm64_emit_u64_immediate(out, "x12", (uint64_t)(unsigned int)offset, err)) return false;
	if (fprintf(out, "    add x12, sp, x12\n    str %s, [x12]\n", reg) < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone assembly");
		return false;
	}
	return true;
}

static bool arm64_emit_load_value(FILE *out, const arm64_function *fn, const char *operand, const char *reg, compile_error *err) {
	int offset = 0;
	if (!operand || !*operand || strcmp(operand, "_") == 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone missing operand");
		return false;
	}
	if (arm64_is_literal(operand)) {
		return arm64_emit_load_literal(out, operand, reg, err);
	}
	if (!arm64_slot_offset(fn, operand, &offset)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone unknown value %s in %s", operand, fn->name);
		return false;
	}
	return arm64_emit_stack_load(out, reg, offset, err);
}

static bool arm64_emit_store_value(FILE *out, const arm64_function *fn, const char *name, const char *reg, compile_error *err) {
	int offset = 0;
	if (!arm64_is_variable(name)) return true;
	if (!arm64_slot_offset(fn, name, &offset)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone unknown destination %s in %s", name, fn->name);
		return false;
	}
	return arm64_emit_stack_store(out, reg, offset, err);
}

static bool arm64_emit_adjust_sp(FILE *out, bool subtract, int bytes, compile_error *err) {
	if (bytes <= 0) return true;
	if (bytes <= 4095) {
		if (fprintf(out, "    %s sp, sp, #%d\n", subtract ? "sub" : "add", bytes) < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone assembly");
			return false;
		}
		return true;
	}
	if (!arm64_emit_u64_immediate(out, "x12", (uint64_t)(unsigned int)bytes, err)) return false;
	if (fprintf(out, "    %s sp, sp, x12\n", subtract ? "sub" : "add") < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone assembly");
		return false;
	}
	return true;
}

static const char *arm64_runtime_callee(const char *name) {
	const char *tail = strrchr(name, '.');
	if (tail != NULL) name = tail + 1;
	if (strcmp(name, "len") == 0 || strcmp(name, "__string_len") == 0 || strcmp(name, "__vec_len") == 0) return "s_value_len";
	if (strcmp(name, "__index_get") == 0) return "s_index_get";
	if (strcmp(name, "append") == 0 || strcmp(name, "__vec_push") == 0) return "s_array_append";
	if (strcmp(name, "__vec_set") == 0) return "s_index_set";
	return NULL;
}

static const char *arm64_defined_function_name(const arm64_module *module, const char *name) {
	size_t i;
	const char *candidate = NULL;
	char normalized[ARM64_TEXT_CAP];
	arm64_symbol_text(name, normalized, sizeof(normalized));
	for (i = 0; i < module->function_count; i++) {
		if (strcmp(module->functions[i].name, name) == 0) return module->functions[i].name;
	}
	for (i = 0; i < module->function_count; i++) {
		char fn_symbol[ARM64_TEXT_CAP];
		arm64_symbol_text(module->functions[i].name, fn_symbol, sizeof(fn_symbol));
		if (strcmp(fn_symbol, normalized) == 0) return module->functions[i].name;
	}
	{
		const char *base = strrchr(name, '.');
		if (base != NULL && base[1] != '\0') {
			candidate = NULL;
			for (i = 0; i < module->function_count; i++) {
				const char *fn_base = strrchr(module->functions[i].name, '.');
				fn_base = fn_base ? fn_base + 1 : module->functions[i].name;
				if (strcmp(fn_base, base + 1) != 0) continue;
				if (candidate != NULL) return NULL;
				candidate = module->functions[i].name;
			}
			if (candidate != NULL) return candidate;
		}
	}
	return NULL;
}

static bool arm64_emit_instruction(FILE *out, const arm64_module *module, const arm64_function *fn, const arm64_ir_ins *ins, size_t ins_index, const char *label_prefix, char args[ARM64_MAX_ARGS][ARM64_TEXT_CAP], int *arg_count, compile_error *err) {
	char symbol[ARM64_TEXT_CAP];
	if (strcmp(ins->op, "NOP") == 0 || strcmp(ins->op, "FUNC_BEGIN") == 0 || strcmp(ins->op, "FUNC_END") == 0) return true;
	if (strcmp(ins->op, "PARAM") == 0) return true;
	if (strcmp(ins->op, "LABEL") == 0) {
		arm64_symbol_text(ins->result, symbol, sizeof(symbol));
		if (fprintf(out, ".L_%s_%s:\n", label_prefix, symbol) < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone label");
			return false;
		}
		return true;
	}
	if (strcmp(ins->op, "JUMP") == 0) {
		arm64_symbol_text(ins->result, symbol, sizeof(symbol));
		if (fprintf(out, "    b .L_%s_%s\n", label_prefix, symbol) < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone jump");
			return false;
		}
		return true;
	}
	if (strcmp(ins->op, "JUMP_IF_FALSE") == 0) {
		if (!arm64_emit_load_value(out, fn, ins->operand1, "x9", err)) return false;
		arm64_symbol_text(ins->result, symbol, sizeof(symbol));
		if (fprintf(out, "    cmp x9, #0\n    b.ne .L_%s_jf_cont_%zu\n    b .L_%s_%s\n.L_%s_jf_cont_%zu:\n", label_prefix, ins_index, label_prefix, symbol, label_prefix, ins_index) < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone conditional jump");
			return false;
		}
		return true;
	}
	if (strcmp(ins->op, "RET") == 0) {
		if (!arm64_emit_load_value(out, fn, ins->result, "x0", err)) return false;
		if (fprintf(out, "    b .L_%s_ret\n", label_prefix) < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone return");
			return false;
		}
		return true;
	}
	if (strcmp(ins->op, "ARG") == 0) {
		if (*arg_count >= ARM64_MAX_ARGS) {
			error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone too many pending call args");
			return false;
		}
		arm64_copy_text(args[*arg_count], ARM64_TEXT_CAP, ins->result);
		(*arg_count)++;
		return true;
	}
	if (strcmp(ins->op, "CALL") == 0) {
		const char *runtime = NULL;
		const char *defined = NULL;
		char callee_symbol[ARM64_TEXT_CAP];
		int expected = atoi(ins->operand2);
		int first_arg = 0;
		int stack_arg_count = 0;
		int stack_bytes = 0;
		int i;
		if (expected > *arg_count) {
			error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone CALL arg mismatch for %s: expected %d got %d", ins->operand1, expected, *arg_count);
			return false;
		}
		first_arg = *arg_count - expected;
		for (i = 0; i < expected && i < 8; i++) {
			char reg[8];
			snprintf(reg, sizeof(reg), "x%d", i);
			if (!arm64_emit_load_value(out, fn, args[first_arg + i], reg, err)) return false;
		}
		if (expected > 8) {
			stack_arg_count = expected - 8;
			stack_bytes = stack_arg_count * 8;
			if ((stack_bytes % 16) != 0) stack_bytes += 8;
			if (!arm64_emit_adjust_sp(out, true, stack_bytes, err)) return false;
			for (i = 0; i < stack_arg_count; i++) {
				if (!arm64_emit_load_value(out, fn, args[first_arg + 8 + i], "x9", err)) return false;
				if (fprintf(out, "    str x9, [sp, #%d]\n", i * 8) < 0) goto write_error;
			}
		}
		defined = arm64_defined_function_name(module, ins->operand1);
		if (!defined) runtime = arm64_runtime_callee(ins->operand1);
		if (runtime) {
			if (fprintf(out, "    bl %s\n", runtime) < 0) {
				error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone call");
				return false;
			}
		} else {
			arm64_symbol_text(defined ? defined : ins->operand1, callee_symbol, sizeof(callee_symbol));
			if (fprintf(out, "    bl s_fn_%s\n", callee_symbol) < 0) {
				error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone call");
				return false;
			}
		}
		if (stack_bytes > 0) {
			if (!arm64_emit_adjust_sp(out, false, stack_bytes, err)) return false;
		}
		*arg_count = first_arg;
		return arm64_emit_store_value(out, fn, ins->result, "x0", err);
	}
	if (strcmp(ins->op, "ARRAY_NEW") == 0) {
		if (fprintf(out, "    mov x0, #1\n    bl s_array_new\n") < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone call");
			return false;
		}
		return arm64_emit_store_value(out, fn, ins->result, "x0", err);
	}
	if (strcmp(ins->op, "INDEX_SET") == 0) {
		if (!arm64_emit_load_value(out, fn, ins->result, "x0", err)) return false;
		if (!arm64_emit_load_value(out, fn, ins->operand1, "x1", err)) return false;
		if (!arm64_emit_load_value(out, fn, ins->operand2, "x2", err)) return false;
		if (fprintf(out, "    bl s_index_set\n") < 0) goto write_error;
		return true;
	}
	if (strcmp(ins->op, "UNIT") == 0) {
		if (fprintf(out, "    mov x9, #1\n") < 0) goto write_error;
		return arm64_emit_store_value(out, fn, ins->result, "x9", err);
	}
	if (strcmp(ins->op, "TRAP") == 0) {
		if (fprintf(out, "    mov x0, #101\n    mov x8, #93\n    svc #0\n    brk #0\n") < 0) goto write_error;
		return true;
	}
	if (strcmp(ins->op, "MOV") == 0) {
		if (!arm64_emit_load_value(out, fn, ins->operand1, "x9", err)) return false;
		return arm64_emit_store_value(out, fn, ins->result, "x9", err);
	}
	if (!arm64_emit_load_value(out, fn, ins->operand1, "x9", err)) return false;
	if (!arm64_emit_load_value(out, fn, ins->operand2, "x10", err)) return false;
	if (strcmp(ins->op, "ADD") == 0) {
		if (fprintf(out, "    add x9, x9, x10\n") < 0) goto write_error;
	} else if (strcmp(ins->op, "SUB") == 0) {
		if (fprintf(out, "    sub x9, x9, x10\n") < 0) goto write_error;
	} else if (strcmp(ins->op, "MUL") == 0) {
		if (fprintf(out, "    mul x9, x9, x10\n") < 0) goto write_error;
	} else if (strcmp(ins->op, "DIV") == 0) {
		if (fprintf(out, "    cmp x10, #0\n    b.ne .L_%s_div_ok_%zu\n    mov x0, #86\n    mov x8, #93\n    svc #0\n.L_%s_div_ok_%zu:\n    sdiv x9, x9, x10\n", label_prefix, ins_index, label_prefix, ins_index) < 0) goto write_error;
	} else if (strcmp(ins->op, "MOD") == 0) {
		if (fprintf(out, "    cmp x10, #0\n    b.ne .L_%s_mod_ok_%zu\n    mov x0, #86\n    mov x8, #93\n    svc #0\n.L_%s_mod_ok_%zu:\n    sdiv x11, x9, x10\n    msub x9, x11, x10, x9\n", label_prefix, ins_index, label_prefix, ins_index) < 0) goto write_error;
	} else if (strcmp(ins->op, "CMP_EQ") == 0) {
		if (fprintf(out, "    cmp x9, x10\n    cset x9, eq\n") < 0) goto write_error;
	} else if (strcmp(ins->op, "CMP_NE") == 0) {
		if (fprintf(out, "    cmp x9, x10\n    cset x9, ne\n") < 0) goto write_error;
	} else if (strcmp(ins->op, "CMP_LT") == 0) {
		if (fprintf(out, "    cmp x9, x10\n    cset x9, lt\n") < 0) goto write_error;
	} else if (strcmp(ins->op, "CMP_LE") == 0) {
		if (fprintf(out, "    cmp x9, x10\n    cset x9, le\n") < 0) goto write_error;
	} else if (strcmp(ins->op, "CMP_GT") == 0) {
		if (fprintf(out, "    cmp x9, x10\n    cset x9, gt\n") < 0) goto write_error;
	} else if (strcmp(ins->op, "CMP_GE") == 0) {
		if (fprintf(out, "    cmp x9, x10\n    cset x9, ge\n") < 0) goto write_error;
	} else {
		error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone unsupported IR op: %s", ins->op);
		return false;
	}
	return arm64_emit_store_value(out, fn, ins->result, "x9", err);
write_error:
	error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone assembly");
	return false;
}

static bool arm64_emit_runtime_helpers(FILE *out, compile_error *err) {
	if (fprintf(out,
		".bss\n"
		".balign 16\n"
		".Ls_heap_storage:\n"
		"    .skip 8388608\n"
		".Ls_heap_storage_end:\n"
		".data\n"
		".balign 8\n"
		".Ls_heap_cursor:\n"
		"    .xword 0\n"
		".text\n"
		".global s_alloc\n"
		".type s_alloc, %%function\n"
		"s_alloc:\n"
		"    add x11, x0, #15\n"
		"    and x11, x11, #0xfffffffffffffff0\n"
		"    adrp x9, .Ls_heap_cursor\n"
		"    add x9, x9, :lo12:.Ls_heap_cursor\n"
		"    ldr x10, [x9]\n"
		"    cbnz x10, 1f\n"
		"    adrp x10, .Ls_heap_storage\n"
		"    add x10, x10, :lo12:.Ls_heap_storage\n"
		"1:\n"
		"    add x12, x10, x11\n"
		"    adrp x13, .Ls_heap_storage_end\n"
		"    add x13, x13, :lo12:.Ls_heap_storage_end\n"
		"    cmp x12, x13\n"
		"    b.hi 2f\n"
		"    str x12, [x9]\n"
		"    mov x0, x10\n"
		"    ret\n"
		"2:\n"
		"    mov x0, xzr\n"
		"    ret\n"
		".size s_alloc, .-s_alloc\n"
		".global s_value_len\n"
		".type s_value_len, %%function\n"
		"s_value_len:\n"
		"    tbnz x0, #0, 1f\n"
		"    cbz x0, 1f\n"
		"    ldr x1, [x0, #8]\n"
		"    lsl x1, x1, #1\n"
		"    add x0, x1, #1\n"
		"    ret\n"
		"1:\n"
		"    mov x0, #1\n"
		"    ret\n"
		".size s_value_len, .-s_value_len\n"
		".global s_array_new\n"
		".type s_array_new, %%function\n"
		"s_array_new:\n"
		"    stp x19, x30, [sp, #-16]!\n"
		"    asr x19, x0, #1\n"
		"    cmp x19, #0\n"
		"    b.lt 3f\n"
		"    mov x9, #16\n"
		"    add x0, x9, x19, lsl #3\n"
		"    bl s_alloc\n"
		"    cbz x0, 3f\n"
		"    mov x10, #4\n"
		"    str x10, [x0]\n"
		"    str x19, [x0, #8]\n"
		"    mov x11, #0\n"
		"4:\n"
		"    cmp x11, x19\n"
		"    b.ge 5f\n"
		"    mov x12, #1\n"
		"    str x12, [x0, #16]\n"
		"    add x0, x0, #8\n"
		"    add x11, x11, #1\n"
		"    b 4b\n"
		"5:\n"
		"    sub x0, x0, x19, lsl #3\n"
		"    ldp x19, x30, [sp], #16\n"
		"    ret\n"
		"3:\n"
		"    mov x0, xzr\n"
		"    ldp x19, x30, [sp], #16\n"
		"    ret\n"
		".size s_array_new, .-s_array_new\n"
		".global s_index_get\n"
		".type s_index_get, %%function\n"
		"s_index_get:\n"
		"    cbz x0, 6f\n"
		"    tbnz x0, #0, 6f\n"
		"    ldr x9, [x0]\n"
		"    cmp x9, #4\n"
		"    b.ne 6f\n"
		"    asr x1, x1, #1\n"
		"    cmp x1, #0\n"
		"    b.lt 6f\n"
		"    ldr x9, [x0, #8]\n"
		"    cmp x1, x9\n"
		"    b.hs 6f\n"
		"    add x10, x0, #16\n"
		"    ldr x0, [x10, x1, lsl #3]\n"
		"    ret\n"
		"6:\n"
		"    mov x0, #1\n"
		"    ret\n"
		".size s_index_get, .-s_index_get\n"
		".global s_index_set\n"
		".type s_index_set, %%function\n"
		"s_index_set:\n"
		"    cbz x0, 7f\n"
		"    tbnz x0, #0, 7f\n"
		"    ldr x9, [x0]\n"
		"    cmp x9, #4\n"
		"    b.ne 7f\n"
		"    asr x1, x1, #1\n"
		"    cmp x1, #0\n"
		"    b.lt 7f\n"
		"    ldr x9, [x0, #8]\n"
		"    cmp x1, x9\n"
		"    b.hs 7f\n"
		"    add x10, x0, #16\n"
		"    str x2, [x10, x1, lsl #3]\n"
		"    mov x0, x2\n"
		"    ret\n"
		"7:\n"
		"    mov x0, #1\n"
		"    ret\n"
		".size s_index_set, .-s_index_set\n"
		".global s_array_append\n"
		".type s_array_append, %%function\n"
		"s_array_append:\n"
		"    stp x19, x20, [sp, #-16]!\n"
		"    stp x21, x30, [sp, #-16]!\n"
		"    mov x19, x0\n"
		"    mov x20, x1\n"
		"    mov x21, #0\n"
		"    cbz x19, 8f\n"
		"    cmp x19, #1\n"
		"    b.eq 8f\n"
		"    tbnz x19, #0, 11f\n"
		"    ldr x9, [x19]\n"
		"    cmp x9, #4\n"
		"    b.ne 11f\n"
		"    ldr x21, [x19, #8]\n"
		"8:\n"
		"    add x0, x21, #1\n"
		"    lsl x0, x0, #1\n"
		"    add x0, x0, #1\n"
		"    bl s_array_new\n"
		"    cbz x0, 10f\n"
		"    mov x9, #0\n"
		"9:\n"
		"    cmp x9, x21\n"
		"    b.ge 12f\n"
		"    add x10, x19, #16\n"
		"    ldr x11, [x10, x9, lsl #3]\n"
		"    add x12, x0, #16\n"
		"    str x11, [x12, x9, lsl #3]\n"
		"    add x9, x9, #1\n"
		"    b 9b\n"
		"12:\n"
		"    add x10, x0, #16\n"
		"    str x20, [x10, x21, lsl #3]\n"
		"10:\n"
		"    ldp x21, x30, [sp], #16\n"
		"    ldp x19, x20, [sp], #16\n"
		"    ret\n"
		"11:\n"
		"    mov x0, xzr\n"
		"    b 10b\n"
		".size s_array_append, .-s_array_append\n") < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone runtime helpers");
		return false;
	}
	return true;
}

static bool arm64_emit_assembly(FILE *out, const arm64_module *module, compile_error *err) {
	size_t i;
	if (fprintf(out, ".text\n") < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing arm64 standalone assembly");
		return false;
	}
	if (fprintf(out, ".global _start\n.type _start, %%function\n_start:\n") < 0) return false;
	if (fprintf(out, "    bl s_fn_main\n    mov x8, #93\n    svc #0\n") < 0) return false;
	if (fprintf(out, ".L_divzero:\n    mov x0, #86\n    mov x8, #93\n    svc #0\n") < 0) return false;
	if (!arm64_emit_runtime_helpers(out, err)) return false;
	for (i = 0; i < module->function_count; i++) {
		size_t j;
		int param_index = 0;
		char label_prefix[ARM64_TEXT_CAP];
		char fn_symbol[ARM64_TEXT_CAP];
		char pending_args[ARM64_MAX_ARGS][ARM64_TEXT_CAP];
		int pending_arg_count = 0;
		const arm64_function *fn = &module->functions[i];
		arm64_symbol_text(fn->name, fn_symbol, sizeof(fn_symbol));
		if (strlen(fn_symbol) + 5 >= sizeof(label_prefix)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone function symbol is too long: %s", fn->name);
			return false;
		}
		memcpy(label_prefix, "s_fn_", 5);
		strcpy(label_prefix + 5, fn_symbol);
		if (fprintf(out, ".global s_fn_%s\n.type s_fn_%s, %%function\ns_fn_%s:\n", fn_symbol, fn_symbol, fn_symbol) < 0) return false;
		if (fprintf(out, "    stp x29, x30, [sp, #-16]!\n    mov x29, sp\n") < 0) return false;
		if (!arm64_emit_adjust_sp(out, true, fn->frame_size, err)) return false;
		for (j = fn->begin + 1; j < fn->end; j++) {
			const arm64_ir_ins *ins = &module->ir.ins[j];
			if (strcmp(ins->op, "PARAM") == 0) {
				int offset = 0;
				if (!arm64_slot_offset(fn, ins->result, &offset)) {
					error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone unknown PARAM slot %s in %s", ins->result, fn->name);
					return false;
				}
				if (param_index < 8) {
					char reg[4];
					reg[0] = 'x';
					reg[1] = (char)('0' + param_index);
					reg[2] = '\0';
					if (!arm64_emit_stack_store(out, reg, offset, err)) return false;
				} else {
					int stack_offset = 16 + (param_index - 8) * 8;
					if (fprintf(out, "    ldr x9, [x29, #%d]\n", stack_offset) < 0) return false;
					if (!arm64_emit_stack_store(out, "x9", offset, err)) return false;
				}
				param_index++;
				continue;
			}
			if (!arm64_emit_instruction(out, module, fn, ins, j, label_prefix, pending_args, &pending_arg_count, err)) return false;
		}
		if (pending_arg_count != 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "arm64 standalone dangling ARG records in %s", fn->name);
			return false;
		}
		if (fprintf(out, ".L_%s_ret:\n", label_prefix) < 0) return false;
		if (!arm64_emit_adjust_sp(out, false, fn->frame_size, err)) return false;
		if (fprintf(out, "    ldp x29, x30, [sp], #16\n    ret\n") < 0) return false;
	}
	if (fprintf(out, ".section .note.GNU-stack,\"\",@progbits\n") < 0) return false;
	return true;
}

static bool arm64_run_tool(char *const argv[], compile_error *err) {
	pid_t pid;
	int status;
	pid = fork();
	if (pid < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to launch standalone tool: %s", strerror(errno));
		return false;
	}
	if (pid == 0) {
		execvp(argv[0], argv);
		fprintf(stderr, "failed to execute %s: %s\n", argv[0], strerror(errno));
		_exit(127);
	}
	if (waitpid(pid, &status, 0) < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed waiting for standalone tool: %s", strerror(errno));
		return false;
	}
	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "standalone tool failed: %s", argv[0]);
		return false;
	}
	return true;
}

bool emit_standalone_arm64_assembly_from_ir_file(const char *input_ir_path, const char *output_assembly_path, compile_error *err) {
	arm64_module *module = NULL;
	FILE *out = NULL;
	error_clear(err);
	if (!input_ir_path || !output_assembly_path) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid arm64 standalone assembly backend input");
		return false;
	}
	module = (arm64_module *)calloc(1, sizeof(*module));
	if (!module) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return false;
	}
	if (!arm64_load_ir(input_ir_path, &module->ir, err) || !arm64_analyze_module(module, err)) {
		free(module);
		return false;
	}
	out = fopen(output_assembly_path, "wb");
	if (!out) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to create arm64 standalone assembly output");
		free(module);
		return false;
	}
	if (!arm64_emit_assembly(out, module, err)) {
		fclose(out);
		free(module);
		return false;
	}
	if (fclose(out) != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close arm64 standalone assembly output");
		free(module);
		return false;
	}
	free(module);
	return true;
}

bool emit_standalone_arm64_object_from_ir_file(const char *input_ir_path, const char *output_object_path, compile_error *err) {
	char temp_dir[] = "/tmp/s_standalone_arm64_obj-XXXXXX";
	char asm_path[256];
	const char *assembler = getenv("S_BOOTSTRAP_AS");
	char *as_program[] = {(char *)(assembler && *assembler ? assembler : "as"), "-o", (char *)output_object_path, asm_path, NULL};
	if (!mkdtemp(temp_dir)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to create arm64 standalone object temporary directory: %s", strerror(errno));
		return false;
	}
	snprintf(asm_path, sizeof(asm_path), "%s/program.s", temp_dir);
	if (!emit_standalone_arm64_assembly_from_ir_file(input_ir_path, asm_path, err)) {
		unlink(asm_path);
		rmdir(temp_dir);
		return false;
	}
	if (!arm64_run_tool(as_program, err)) {
		unlink(asm_path);
		rmdir(temp_dir);
		return false;
	}
	unlink(asm_path);
	rmdir(temp_dir);
	return true;
}

bool emit_standalone_arm64_from_ir_file(const char *input_ir_path, const char *output_binary_path, compile_error *err) {
	char temp_dir[] = "/tmp/s_standalone_arm64-XXXXXX";
	char asm_path[256];
	char obj_path[256];
	const char *assembler = getenv("S_BOOTSTRAP_AS");
	const char *linker = getenv("S_BOOTSTRAP_LD");
	char *as_program[] = {(char *)(assembler && *assembler ? assembler : "as"), "-o", obj_path, asm_path, NULL};
	char *ld_program[] = {(char *)(linker && *linker ? linker : "ld"), "-static", "-nostdlib", "-e", "_start", "-o", (char *)output_binary_path, obj_path, NULL};
	if (!mkdtemp(temp_dir)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to create arm64 standalone temporary directory: %s", strerror(errno));
		return false;
	}
	snprintf(asm_path, sizeof(asm_path), "%s/program.s", temp_dir);
	snprintf(obj_path, sizeof(obj_path), "%s/program.o", temp_dir);
	if (!emit_standalone_arm64_assembly_from_ir_file(input_ir_path, asm_path, err)) {
		unlink(asm_path);
		unlink(obj_path);
		rmdir(temp_dir);
		return false;
	}
	if (!arm64_run_tool(as_program, err) || !arm64_run_tool(ld_program, err)) {
		unlink(asm_path);
		unlink(obj_path);
		rmdir(temp_dir);
		return false;
	}
	unlink(asm_path);
	unlink(obj_path);
	rmdir(temp_dir);
	return true;
}
