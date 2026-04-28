#include <stdio.h>

#include "../intermediate/ir.h"
#include "target.h"

static const char *nz(const char *s) {
    return (s && s[0] != '\0') ? s : "_";
}

static void emit_op0(FILE *out, const char *op) {
    fprintf(out, "%-14s\n", op);
}

static void emit_op1(FILE *out, const char *op, const char *a) {
    fprintf(out, "%-14s %s\n", op, nz(a));
}

static void emit_op2(FILE *out, const char *op, const char *a, const char *b) {
    fprintf(out, "%-14s %s, %s\n", op, nz(a), nz(b));
}

static void emit_op3(FILE *out, const char *op, const char *dst, const char *lhs, const char *rhs) {
    fprintf(out, "%-14s %s, %s, %s\n", op, nz(dst), nz(lhs), nz(rhs));
}

void generate_code(IR *ir, FILE *output) {
    int i;

    if (!ir || !output) {
        fprintf(stderr, "invalid input to code generator\n");
        return;
    }

    for (i = 0; i < ir->instruction_count; i++) {
        const IRInstruction *instr = &ir->instructions[i];

        switch (instr->type) {
            case IR_NOP:
                emit_op0(output, "NOP");
                break;
            case IR_FUNC_BEGIN:
                emit_op1(output, "FUNC_BEGIN", instr->result);
                break;
            case IR_FUNC_END:
                emit_op1(output, "FUNC_END", instr->result);
                break;
            case IR_LABEL:
                emit_op1(output, "LABEL", instr->result);
                break;
            case IR_JUMP:
                emit_op1(output, "JUMP", instr->result);
                break;
            case IR_JUMP_IF_FALSE:
                emit_op2(output, "JUMP_IF_FALSE", instr->operand1, instr->result);
                break;
            case IR_PARAM:
                emit_op1(output, "PARAM", instr->result);
                break;
            case IR_MOV:
                emit_op2(output, "MOV", instr->result, instr->operand1);
                break;
            case IR_ADD:
                emit_op3(output, "ADD", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_SUB:
                emit_op3(output, "SUB", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_MUL:
                emit_op3(output, "MUL", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_DIV:
                emit_op3(output, "DIV", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_EQ:
                emit_op3(output, "CMP_EQ", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_NE:
                emit_op3(output, "CMP_NE", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_LT:
                emit_op3(output, "CMP_LT", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_LE:
                emit_op3(output, "CMP_LE", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_GT:
                emit_op3(output, "CMP_GT", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_GE:
                emit_op3(output, "CMP_GE", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_RET:
                emit_op1(output, "RET", instr->result);
                break;
            default:
                fprintf(stderr, "unknown IR instruction at #%d (op=%d)\n", i, (int)instr->type);
                break;
        }
    }
}