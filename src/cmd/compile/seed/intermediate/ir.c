#include "ir.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct ir_builder {
	IR *ir;
	compile_error *err;
	int temp_counter;
	int label_counter;
} ir_builder;

static void copy_str(char dst[64], const char *src) {
	if (!src) {
		dst[0] = '\0';
		return;
	}
	snprintf(dst, 64, "%s", src);
}

void ir_init(IR *ir) {
	ir->instructions = NULL;
	ir->instruction_count = 0;
	ir->capacity = 0;
}

void ir_free(IR *ir) {
	free(ir->instructions);
	ir->instructions = NULL;
	ir->instruction_count = 0;
	ir->capacity = 0;
}

bool ir_emit(IR *ir, ir_op type, const char *result, const char *operand1, const char *operand2) {
	IRInstruction *ins;
	if (ir->instruction_count == ir->capacity) {
		int next_cap = (ir->capacity == 0) ? 32 : ir->capacity * 2;
		IRInstruction *next = (IRInstruction *)realloc(ir->instructions, (size_t)next_cap * sizeof(IRInstruction));
		if (!next) {
			return false;
		}
		ir->instructions = next;
		ir->capacity = next_cap;
	}
	ins = &ir->instructions[ir->instruction_count++];
	ins->type = type;
	copy_str(ins->result, result);
	copy_str(ins->operand1, operand1);
	copy_str(ins->operand2, operand2);
	return true;
}

const char *ir_op_name(ir_op op) {
	switch (op) {
		case IR_NOP: return "NOP";
		case IR_FUNC_BEGIN: return "FUNC_BEGIN";
		case IR_FUNC_END: return "FUNC_END";
		case IR_LABEL: return "LABEL";
		case IR_JUMP: return "JUMP";
		case IR_JUMP_IF_FALSE: return "JUMP_IF_FALSE";
		case IR_PARAM: return "PARAM";
		case IR_MOV: return "MOV";
		case IR_ADD: return "ADD";
		case IR_SUB: return "SUB";
		case IR_MUL: return "MUL";
		case IR_DIV: return "DIV";
		case IR_CMP_EQ: return "CMP_EQ";
		case IR_CMP_NE: return "CMP_NE";
		case IR_CMP_LT: return "CMP_LT";
		case IR_CMP_LE: return "CMP_LE";
		case IR_CMP_GT: return "CMP_GT";
		case IR_CMP_GE: return "CMP_GE";
		case IR_RET: return "RET";
	}
	return "UNKNOWN";
}

static bool emit_ins(ir_builder *b, ir_op type, const char *result, const char *op1, const char *op2, source_pos pos) {
	if (!ir_emit(b->ir, type, result, op1, op2)) {
		error_set(b->err, ERR_OUT_OF_MEMORY, pos.line, pos.column, "out of memory while emitting IR");
		return false;
	}
	return true;
}

static void next_temp(ir_builder *b, char out[64]) {
	snprintf(out, 64, "t%d", b->temp_counter++);
}

static void next_label(ir_builder *b, char out[64]) {
	snprintf(out, 64, "L%d", b->label_counter++);
}

static bool lower_expr(ir_builder *b, ast_node *expr, char out[64]);
static bool lower_stmt(ir_builder *b, ast_node *stmt);

static bool lower_binary(ir_builder *b, ast_node *expr, char out[64]) {
	char lhs[64];
	char rhs[64];
	ir_op op;
	if (!lower_expr(b, expr->as.binary_expr.left, lhs) || !lower_expr(b, expr->as.binary_expr.right, rhs)) {
		return false;
	}
	switch (expr->as.binary_expr.op) {
		case TOKEN_PLUS: op = IR_ADD; break;
		case TOKEN_MINUS: op = IR_SUB; break;
		case TOKEN_STAR: op = IR_MUL; break;
		case TOKEN_SLASH: op = IR_DIV; break;
		case TOKEN_EQ: op = IR_CMP_EQ; break;
		case TOKEN_NE: op = IR_CMP_NE; break;
		case TOKEN_LT: op = IR_CMP_LT; break;
		case TOKEN_LE: op = IR_CMP_LE; break;
		case TOKEN_GT: op = IR_CMP_GT; break;
		case TOKEN_GE: op = IR_CMP_GE; break;
		default:
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "unsupported binary operator for IR");
			return false;
	}
	next_temp(b, out);
	return emit_ins(b, op, out, lhs, rhs, expr->pos);
}

static bool lower_expr(ir_builder *b, ast_node *expr, char out[64]) {
	if (!expr) {
		out[0] = '\0';
		return true;
	}

	switch (expr->kind) {
		case AST_NUMBER_EXPR:
			snprintf(out, 64, "%s", expr->as.number_expr.literal);
			return true;
		case AST_STRING_EXPR:
			snprintf(out, 64, "\"%s\"", expr->as.string_expr.literal);
			return true;
		case AST_IDENT_EXPR:
			snprintf(out, 64, "%s", expr->as.ident_expr.name);
			return true;
		case AST_UNARY_EXPR: {
			char rhs[64];
			if (!lower_expr(b, expr->as.unary_expr.operand, rhs)) {
				return false;
			}
			next_temp(b, out);
			if (expr->as.unary_expr.op == TOKEN_MINUS) {
				return emit_ins(b, IR_SUB, out, "0", rhs, expr->pos);
			}
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "unsupported unary operator for IR");
			return false;
		}
		case AST_BINARY_EXPR:
			return lower_binary(b, expr, out);
		default:
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "unsupported expression in IR lowering");
			return false;
	}
}

static bool lower_block(ir_builder *b, ast_node *block) {
	size_t i;
	for (i = 0; i < block->as.block.statements.len; i++) {
		if (!lower_stmt(b, block->as.block.statements.data[i])) {
			return false;
		}
	}
	return true;
}

static bool lower_if(ir_builder *b, ast_node *stmt) {
	char cond[64];
	char else_label[64];
	char end_label[64];
	if (!lower_expr(b, stmt->as.if_stmt.condition, cond)) {
		return false;
	}
	next_label(b, else_label);
	next_label(b, end_label);
	if (!emit_ins(b, IR_JUMP_IF_FALSE, else_label, cond, "", stmt->pos)) {
		return false;
	}
	if (!lower_stmt(b, stmt->as.if_stmt.then_branch)) {
		return false;
	}
	if (!emit_ins(b, IR_JUMP, end_label, "", "", stmt->pos)) {
		return false;
	}
	if (!emit_ins(b, IR_LABEL, else_label, "", "", stmt->pos)) {
		return false;
	}
	if (stmt->as.if_stmt.else_branch && !lower_stmt(b, stmt->as.if_stmt.else_branch)) {
		return false;
	}
	return emit_ins(b, IR_LABEL, end_label, "", "", stmt->pos);
}

static bool lower_while(ir_builder *b, ast_node *stmt) {
	char start_label[64];
	char end_label[64];
	char cond[64];
	next_label(b, start_label);
	next_label(b, end_label);
	if (!emit_ins(b, IR_LABEL, start_label, "", "", stmt->pos)) {
		return false;
	}
	if (!lower_expr(b, stmt->as.while_stmt.condition, cond)) {
		return false;
	}
	if (!emit_ins(b, IR_JUMP_IF_FALSE, end_label, cond, "", stmt->pos)) {
		return false;
	}
	if (!lower_stmt(b, stmt->as.while_stmt.body)) {
		return false;
	}
	if (!emit_ins(b, IR_JUMP, start_label, "", "", stmt->pos)) {
		return false;
	}
	return emit_ins(b, IR_LABEL, end_label, "", "", stmt->pos);
}

static bool lower_for(ir_builder *b, ast_node *stmt) {
	char start_label[64];
	char end_label[64];
	char cond[64];
	if (stmt->as.for_stmt.init && !lower_stmt(b, stmt->as.for_stmt.init)) {
		return false;
	}
	next_label(b, start_label);
	next_label(b, end_label);
	if (!emit_ins(b, IR_LABEL, start_label, "", "", stmt->pos)) {
		return false;
	}
	if (stmt->as.for_stmt.condition) {
		if (!lower_expr(b, stmt->as.for_stmt.condition, cond)) {
			return false;
		}
		if (!emit_ins(b, IR_JUMP_IF_FALSE, end_label, cond, "", stmt->pos)) {
			return false;
		}
	}
	if (!lower_stmt(b, stmt->as.for_stmt.body)) {
		return false;
	}
	if (stmt->as.for_stmt.post) {
		char unused[64];
		if (!lower_expr(b, stmt->as.for_stmt.post, unused)) {
			return false;
		}
	}
	if (!emit_ins(b, IR_JUMP, start_label, "", "", stmt->pos)) {
		return false;
	}
	return emit_ins(b, IR_LABEL, end_label, "", "", stmt->pos);
}

static bool lower_fn(ir_builder *b, ast_node *stmt) {
	size_t i;
	if (!emit_ins(b, IR_FUNC_BEGIN, stmt->as.fn_stmt.name, "", "", stmt->pos)) {
		return false;
	}
	for (i = 0; i < stmt->as.fn_stmt.param_count; i++) {
		if (!emit_ins(b, IR_PARAM, stmt->as.fn_stmt.params[i], "", "", stmt->pos)) {
			return false;
		}
	}
	if (!lower_stmt(b, stmt->as.fn_stmt.body)) {
		return false;
	}
	return emit_ins(b, IR_FUNC_END, stmt->as.fn_stmt.name, "", "", stmt->pos);
}

static bool lower_stmt(ir_builder *b, ast_node *stmt) {
	char value[64];
	if (!stmt) {
		return true;
	}
	switch (stmt->kind) {
		case AST_BLOCK:
			return lower_block(b, stmt);
		case AST_LET_STMT:
			if (!lower_expr(b, stmt->as.let_stmt.value, value)) {
				return false;
			}
			return emit_ins(b, IR_MOV, stmt->as.let_stmt.name, value, "", stmt->pos);
		case AST_RETURN_STMT:
			if (!lower_expr(b, stmt->as.return_stmt.value, value)) {
				return false;
			}
			return emit_ins(b, IR_RET, value, "", "", stmt->pos);
		case AST_EXPR_STMT:
			return lower_expr(b, stmt->as.expr_stmt.expr, value);
		case AST_IF_STMT:
			return lower_if(b, stmt);
		case AST_WHILE_STMT:
			return lower_while(b, stmt);
		case AST_FOR_STMT:
			return lower_for(b, stmt);
		case AST_FN_STMT:
			return lower_fn(b, stmt);
		case AST_PROGRAM: {
			size_t i;
			for (i = 0; i < stmt->as.program.statements.len; i++) {
				if (!lower_stmt(b, stmt->as.program.statements.data[i])) {
					return false;
				}
			}
			return true;
		}
		default:
			error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "unsupported statement in IR lowering");
			return false;
	}
}

bool ir_generate_from_ast(ast_node *root, IR *ir, compile_error *err) {
	ir_builder b;
	if (!root || !ir || !err) {
		return false;
	}
	error_clear(err);
	b.ir = ir;
	b.err = err;
	b.temp_counter = 0;
	b.label_counter = 0;
	return lower_stmt(&b, root);
}