#include <stdio.h>

#include "../intermediate/ir.h"
#include "target.h"

static const char *nz(const char *s) {
    return (s && s[0] != '\0') ? s : "_";
}

static void emit_record(FILE *out, const char *op, const char *result, const char *op1, const char *op2) {
    fprintf(out, "%s|%s|%s|%s\n", op, nz(result), nz(op1), nz(op2));
}

void generate_code(IR *ir, FILE *output) {
    int i;

    if (!ir || !output) {
        fprintf(stderr, "invalid input to code generator\n");
        return;
    }

    fprintf(output, "SSEED-TARGET-V1\n");

    for (i = 0; i < ir->instruction_count; i++) {
        const IRInstruction *instr = &ir->instructions[i];

        switch (instr->type) {
            case IR_NOP:
                emit_record(output, "NOP", "", "", "");
                break;
            case IR_FUNC_BEGIN:
                emit_record(output, "FUNC_BEGIN", instr->result, "", "");
                break;
            case IR_FUNC_END:
                emit_record(output, "FUNC_END", instr->result, "", "");
                break;
            case IR_LABEL:
                emit_record(output, "LABEL", instr->result, "", "");
                break;
            case IR_JUMP:
                emit_record(output, "JUMP", instr->result, "", "");
                break;
            case IR_JUMP_IF_FALSE:
                emit_record(output, "JUMP_IF_FALSE", instr->result, instr->operand1, "");
                break;
            case IR_PARAM:
                emit_record(output, "PARAM", instr->result, "", "");
                break;
            case IR_MOV:
                emit_record(output, "MOV", instr->result, instr->operand1, "");
                break;
            case IR_ADD:
                emit_record(output, "ADD", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_SUB:
                emit_record(output, "SUB", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_MUL:
                emit_record(output, "MUL", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_DIV:
                emit_record(output, "DIV", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_EQ:
                emit_record(output, "CMP_EQ", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_NE:
                emit_record(output, "CMP_NE", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_LT:
                emit_record(output, "CMP_LT", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_LE:
                emit_record(output, "CMP_LE", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_GT:
                emit_record(output, "CMP_GT", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_CMP_GE:
                emit_record(output, "CMP_GE", instr->result, instr->operand1, instr->operand2);
                break;
            case IR_RET:
                emit_record(output, "RET", instr->result, "", "");
                break;
            default:
                fprintf(stderr, "unknown IR instruction at #%d (op=%d)\n", i, (int)instr->type);
                break;
        }
    }
}