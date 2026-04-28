#include "ir.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct ir_builder {
	IR *ir;
	compile_error *err;
	int temp_counter;
	int label_counter;
	char break_labels[64][64];
	char continue_labels[64][64];
	int loop_depth;
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
		case IR_ARG: return "ARG";
		case IR_CALL: return "CALL";
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

static int push_loop(ir_builder *b, const char *break_label, const char *continue_label) {
	if (b->loop_depth >= 64) {
		return 0;
	}
	snprintf(b->break_labels[b->loop_depth], 64, "%s", break_label);
	snprintf(b->continue_labels[b->loop_depth], 64, "%s", continue_label);
	b->loop_depth++;
	return 1;
}

static void pop_loop(ir_builder *b) {
	if (b->loop_depth > 0) {
		b->loop_depth--;
	}
}

static const char *current_break_label(ir_builder *b) {
	if (b->loop_depth <= 0) {
		return NULL;
	}
	return b->break_labels[b->loop_depth - 1];
}

static const char *current_continue_label(ir_builder *b) {
	if (b->loop_depth <= 0) {
		return NULL;
	}
	return b->continue_labels[b->loop_depth - 1];
}

static bool lower_expr(ir_builder *b, ast_node *expr, char out[64]);
static bool lower_stmt(ir_builder *b, ast_node *stmt);

static bool lower_array_literal(ir_builder *b, ast_node *expr, char out[64]) {
	size_t i;
	int written;
	size_t used = 0;

	if (!expr || expr->kind != AST_ARRAY_EXPR) {
		return false;
	}

	if (used + 2 >= 64) {
		error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "array literal too long for IR operand");
		return false;
	}
	out[used++] = '"';
	out[used++] = '[';

	for (i = 0; i < expr->as.array_expr.items.len; i++) {
		ast_node *item = expr->as.array_expr.items.data[i];
		char item_text[64];
		if (!item) {
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "invalid array literal item");
			return false;
		}
		switch (item->kind) {
			case AST_NUMBER_EXPR:
				snprintf(item_text, sizeof(item_text), "%s", item->as.number_expr.literal);
				break;
			case AST_BOOL_EXPR:
				snprintf(item_text, sizeof(item_text), "%s", item->as.bool_expr.value ? "true" : "false");
				break;
			case AST_STRING_EXPR:
				snprintf(item_text, sizeof(item_text), "\"%s\"", item->as.string_expr.literal);
				break;
			case AST_IDENT_EXPR:
				snprintf(item_text, sizeof(item_text), "%s", item->as.ident_expr.name);
				break;
			default:
				error_set(b->err, ERR_SEMANTIC, item->pos.line, item->pos.column,
					"array literal currently supports number/bool/string/identifier items in IR lowering");
				return false;
		}

		written = snprintf(out + used, 64 - used, "%s%s", (i == 0) ? "" : ", ", item_text);
		if (written < 0 || (size_t)written >= 64 - used) {
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "array literal too long for IR operand");
			return false;
		}
		used += (size_t)written;
	}

	if (used + 2 >= 64) {
		error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "array literal too long for IR operand");
		return false;
	}
	out[used++] = ']';
	out[used++] = '"';
	out[used] = '\0';
	return true;
}

static bool is_non_unit_return_type(const char *return_type) {
	return return_type && return_type[0] != '\0' && strcmp(return_type, "()") != 0;
}

static const char *fallback_return_literal(const char *return_type) {
	if (!return_type) {
		return "0";
	}
	if (strcmp(return_type, "string") == 0) {
		return "\"\"";
	}
	if (strcmp(return_type, "bool") == 0) {
		return "0";
	}
	if (strcmp(return_type, "int") == 0) {
		return "0";
	}
	return "0";
}

static bool lower_binary(ir_builder *b, ast_node *expr, char out[64]) {
	char lhs[64];
	char rhs[64];
	ir_op op;
	if (!lower_expr(b, expr->as.binary_expr.left, lhs)) {
		return false;
	}
	if (expr->as.binary_expr.op == TOKEN_OR_OR || expr->as.binary_expr.op == TOKEN_AND_AND) {
		char lhs_bool[64];
		char rhs_bool[64];
		char eval_rhs_label[64];
		char false_label[64];
		char end_label[64];
		next_temp(b, lhs_bool);
		next_temp(b, rhs_bool);
		next_temp(b, out);
		next_label(b, eval_rhs_label);
		next_label(b, false_label);
		next_label(b, end_label);
		if (!emit_ins(b, IR_CMP_NE, lhs_bool, lhs, "0", expr->pos)) {
			return false;
		}
		if (expr->as.binary_expr.op == TOKEN_OR_OR) {
			if (!emit_ins(b, IR_JUMP_IF_FALSE, eval_rhs_label, lhs_bool, "", expr->pos)) {
				return false;
			}
			if (!emit_ins(b, IR_MOV, out, "1", "", expr->pos)) {
				return false;
			}
			if (!emit_ins(b, IR_JUMP, end_label, "", "", expr->pos)) {
				return false;
			}
			if (!emit_ins(b, IR_LABEL, eval_rhs_label, "", "", expr->pos)) {
				return false;
			}
			if (!lower_expr(b, expr->as.binary_expr.right, rhs)) {
				return false;
			}
			if (!emit_ins(b, IR_CMP_NE, rhs_bool, rhs, "0", expr->pos)) {
				return false;
			}
			if (!emit_ins(b, IR_MOV, out, rhs_bool, "", expr->pos)) {
				return false;
			}
			return emit_ins(b, IR_LABEL, end_label, "", "", expr->pos);
		}
		if (!emit_ins(b, IR_JUMP_IF_FALSE, false_label, lhs_bool, "", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_JUMP, eval_rhs_label, "", "", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_LABEL, eval_rhs_label, "", "", expr->pos)) {
			return false;
		}
		if (!lower_expr(b, expr->as.binary_expr.right, rhs)) {
			return false;
		}
		if (!emit_ins(b, IR_CMP_NE, rhs_bool, rhs, "0", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_MOV, out, rhs_bool, "", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_JUMP, end_label, "", "", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_LABEL, false_label, "", "", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_MOV, out, "0", "", expr->pos)) {
			return false;
		}
		return emit_ins(b, IR_LABEL, end_label, "", "", expr->pos);
	}
	if (!lower_expr(b, expr->as.binary_expr.right, rhs)) {
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
		case AST_BOOL_EXPR:
			snprintf(out, 64, "%d", expr->as.bool_expr.value ? 1 : 0);
			return true;
		case AST_STRING_EXPR:
			snprintf(out, 64, "\"%s\"", expr->as.string_expr.literal);
			return true;
		case AST_ARRAY_EXPR:
			return lower_array_literal(b, expr, out);
		case AST_IDENT_EXPR:
			snprintf(out, 64, "%s", expr->as.ident_expr.name);
			return true;
		case AST_MEMBER_EXPR: {
			char object_name[64];
			if (!lower_expr(b, expr->as.member_expr.object, object_name)) {
				return false;
			}
			if (snprintf(out, 64, "%s.%s", object_name, expr->as.member_expr.member) >= 64) {
				error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "member expression too long for IR operand");
				return false;
			}
			return true;
		}
		case AST_UNARY_EXPR: {
			char rhs[64];
			if (!lower_expr(b, expr->as.unary_expr.operand, rhs)) {
				return false;
			}
			next_temp(b, out);
			if (expr->as.unary_expr.op == TOKEN_MINUS) {
				return emit_ins(b, IR_SUB, out, "0", rhs, expr->pos);
			}
			if (expr->as.unary_expr.op == TOKEN_BANG) {
				return emit_ins(b, IR_CMP_EQ, out, rhs, "0", expr->pos);
			}
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "unsupported unary operator for IR");
			return false;
		}
		case AST_BINARY_EXPR:
			return lower_binary(b, expr, out);
		case AST_ASSIGN_EXPR:
			if (!lower_expr(b, expr->as.assign_expr.value, out)) {
				return false;
			}
			if (!emit_ins(b, IR_MOV, expr->as.assign_expr.name, out, "", expr->pos)) {
				return false;
			}
			snprintf(out, 64, "%s", expr->as.assign_expr.name);
			return true;
			case AST_CALL_EXPR: {
				size_t i;
				char callee[64] = "call";
				char argc_text[64];
				for (i = 0; i < expr->as.call_expr.args.len; i++) {
					char arg_tmp[64];
					if (!lower_expr(b, expr->as.call_expr.args.data[i], arg_tmp)) {
						return false;
					}
					if (!emit_ins(b, IR_ARG, arg_tmp, "", "", expr->pos)) {
						return false;
					}
				}
				if (expr->as.call_expr.callee && expr->as.call_expr.callee->kind == AST_IDENT_EXPR) {
					snprintf(callee, sizeof(callee), "%s", expr->as.call_expr.callee->as.ident_expr.name);
				}
				snprintf(argc_text, sizeof(argc_text), "%zu", expr->as.call_expr.args.len);
				next_temp(b, out);
				return emit_ins(b, IR_CALL, out, callee, argc_text, expr->pos);
			}
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
	if (!push_loop(b, end_label, start_label)) {
		error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "loop nesting too deep");
		return false;
	}
	if (!lower_stmt(b, stmt->as.while_stmt.body)) {
		pop_loop(b);
		return false;
	}
	pop_loop(b);
	if (!emit_ins(b, IR_JUMP, start_label, "", "", stmt->pos)) {
		return false;
	}
	return emit_ins(b, IR_LABEL, end_label, "", "", stmt->pos);
}

static bool lower_for(ir_builder *b, ast_node *stmt) {
	char start_label[64];
	char post_label[64];
	char end_label[64];
	char cond[64];
	if (stmt->as.for_stmt.init && !lower_stmt(b, stmt->as.for_stmt.init)) {
		return false;
	}
	next_label(b, start_label);
	next_label(b, post_label);
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
	if (!push_loop(b, end_label, post_label)) {
		error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "loop nesting too deep");
		return false;
	}
	if (!lower_stmt(b, stmt->as.for_stmt.body)) {
		pop_loop(b);
		return false;
	}
	pop_loop(b);
	if (!emit_ins(b, IR_LABEL, post_label, "", "", stmt->pos)) {
		return false;
	}
	if (stmt->as.for_stmt.post) {
		if (stmt->as.for_stmt.post->kind == AST_ASSIGN_STMT) {
			if (!lower_stmt(b, stmt->as.for_stmt.post)) {
				return false;
			}
		} else {
			char unused[64];
			if (!lower_expr(b, stmt->as.for_stmt.post, unused)) {
				return false;
			}
		}
	}
	if (!emit_ins(b, IR_JUMP, start_label, "", "", stmt->pos)) {
			return false;
		}
	return emit_ins(b, IR_LABEL, end_label, "", "", stmt->pos);
}

static bool lower_fn(ir_builder *b, ast_node *stmt) {
	size_t i;
	int has_tail_expr_return = 0;
	int non_unit = is_non_unit_return_type(stmt->as.fn_stmt.return_type);
	if (!emit_ins(b, IR_FUNC_BEGIN, stmt->as.fn_stmt.name, "", "", stmt->pos)) {
		return false;
	}
	for (i = 0; i < stmt->as.fn_stmt.param_count; i++) {
		if (!emit_ins(b, IR_PARAM, stmt->as.fn_stmt.params[i], "", "", stmt->pos)) {
			return false;
		}
	}
	if (stmt->as.fn_stmt.body && stmt->as.fn_stmt.body->kind == AST_BLOCK) {
		size_t n = stmt->as.fn_stmt.body->as.block.statements.len;
		for (i = 0; i < n; i++) {
			ast_node *child = stmt->as.fn_stmt.body->as.block.statements.data[i];
			if (non_unit && i + 1 == n && child && child->kind == AST_EXPR_STMT) {
				char ret_value[64];
				if (!lower_expr(b, child->as.expr_stmt.expr, ret_value)) {
					return false;
				}
				if (!emit_ins(b, IR_RET, ret_value, "", "", child->pos)) {
					return false;
				}
				has_tail_expr_return = 1;
				continue;
			}
			if (!lower_stmt(b, child)) {
				return false;
			}
		}
	} else {
		if (!lower_stmt(b, stmt->as.fn_stmt.body)) {
			return false;
		}
	}
	if (non_unit && !has_tail_expr_return) {
		if (!emit_ins(b, IR_RET, fallback_return_literal(stmt->as.fn_stmt.return_type), "", "", stmt->pos)) {
			return false;
		}
	}
	return emit_ins(b, IR_FUNC_END, stmt->as.fn_stmt.name, "", "", stmt->pos);
}

static bool lower_stmt(ir_builder *b, ast_node *stmt) {
	char value[64];
	if (!stmt) {
		return true;
	}
	switch (stmt->kind) {
			case AST_PACKAGE_DECL:
			case AST_USE_DECL:
				return true;
		case AST_BLOCK:
			return lower_block(b, stmt);
		case AST_LET_STMT:
			if (!lower_expr(b, stmt->as.let_stmt.value, value)) {
				return false;
			}
			return emit_ins(b, IR_MOV, stmt->as.let_stmt.name, value, "", stmt->pos);
		case AST_ASSIGN_STMT:
			if (!lower_expr(b, stmt->as.assign_stmt.value, value)) {
				return false;
			}
			return emit_ins(b, IR_MOV, stmt->as.assign_stmt.name, value, "", stmt->pos);
		case AST_RETURN_STMT:
			if (!lower_expr(b, stmt->as.return_stmt.value, value)) {
				return false;
			}
			return emit_ins(b, IR_RET, value, "", "", stmt->pos);
		case AST_BREAK_STMT: {
			const char *break_label = current_break_label(b);
			if (!break_label) {
				error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "break outside loop");
				return false;
			}
			return emit_ins(b, IR_JUMP, break_label, "", "", stmt->pos);
		}
		case AST_CONTINUE_STMT: {
			const char *continue_label = current_continue_label(b);
			if (!continue_label) {
				error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "continue outside loop");
				return false;
			}
			return emit_ins(b, IR_JUMP, continue_label, "", "", stmt->pos);
		}
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
	b.loop_depth = 0;
	return lower_stmt(&b, root);
}