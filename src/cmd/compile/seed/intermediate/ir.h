    #ifndef S_SEED_IR_H
#define S_SEED_IR_H

#include <stdbool.h>

#include "../error/error.h"
#include "../syntax/ast.h"

typedef enum ir_op {
	IR_NOP = 0,
	IR_FUNC_BEGIN,
	IR_FUNC_END,
	IR_LABEL,
	IR_JUMP,
	IR_JUMP_IF_FALSE,
	IR_PARAM,
	IR_MOV,
	IR_ADD,
	IR_SUB,
	IR_MUL,
	IR_DIV,
	IR_CMP_EQ,
	IR_CMP_NE,
	IR_CMP_LT,
	IR_CMP_LE,
	IR_CMP_GT,
	IR_CMP_GE,
	IR_RET,
} ir_op;

typedef struct IRInstruction {
	ir_op type;
	char result[64];
	char operand1[64];
	char operand2[64];
} IRInstruction;

typedef struct IR {
	IRInstruction *instructions;
	int instruction_count;
	int capacity;
} IR;

void ir_init(IR *ir);
void ir_free(IR *ir);

bool ir_emit(IR *ir, ir_op type, const char *result, const char *operand1, const char *operand2);
const char *ir_op_name(ir_op op);

bool ir_generate_from_ast(ast_node *root, IR *ir, compile_error *err);

#endif