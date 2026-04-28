#include <stdio.h>
#include <stdlib.h>
#include "../intermediate/ir.h"
#include "target.h"

// Function to generate code from IR
void generate_code(IR *ir, FILE *output) {
    if (!ir || !output) {
        fprintf(stderr, "Invalid input to code generator\n");
        return;
    }

    // Example: Iterate over IR instructions and generate target code
    for (int i = 0; i < ir->instruction_count; i++) {
        IRInstruction *instr = &ir->instructions[i];
        switch (instr->type) {
            case IR_ADD:
                fprintf(output, "ADD %s, %s\n", instr->operand1, instr->operand2);
                break;
            case IR_SUB:
                fprintf(output, "SUB %s, %s\n", instr->operand1, instr->operand2);
                break;
            // Add more cases for other IR instructions
            default:
                fprintf(stderr, "Unknown IR instruction\n");
                break;
        }
    }
}