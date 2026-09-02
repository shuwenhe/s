package middleend

// IR Value types
const IR_VALUE_CONST = 1
const IR_VALUE_VAR = 2
const IR_VALUE_PARAM = 3
const IR_VALUE_CALL = 4
const IR_VALUE_BINOP = 5
const IR_VALUE_UNOP = 6
const IR_VALUE_LOAD = 7
const IR_VALUE_STORE = 8
const IR_VALUE_ALLOCA = 9
const IR_VALUE_PHI = 10
const IR_VALUE_CAST = 11

// IR Operation codes for binary operations
const IR_OP_ADD = 100
const IR_OP_SUB = 101
const IR_OP_MUL = 102
const IR_OP_DIV = 103
const IR_OP_MOD = 104
const IR_OP_AND = 105
const IR_OP_OR = 106
const IR_OP_XOR = 107
const IR_OP_SHL = 108
const IR_OP_SHR = 109
const IR_OP_EQ = 110
const IR_OP_NE = 111
const IR_OP_LT = 112
const IR_OP_LE = 113
const IR_OP_GT = 114
const IR_OP_GE = 115
const IR_OP_LAND = 116
const IR_OP_LOR = 117

// IR Unary operations
const IR_OP_NEG = 200
const IR_OP_NOT = 201
const IR_OP_LNOT = 202

// IR Instruction types
const IR_INSTR_BINOP = 300
const IR_INSTR_UNOP = 301
const IR_INSTR_CALL = 302
const IR_INSTR_LOAD = 303
const IR_INSTR_STORE = 304
const IR_INSTR_ALLOCA = 305
const IR_INSTR_RETURN = 306
const IR_INSTR_BR = 307
const IR_INSTR_CONDBR = 308
const IR_INSTR_PHI = 309
const IR_INSTR_CAST = 310
const IR_INSTR_SWITCH = 311

struct ir_value {
    value_type int
    value_id int
    type_info string
    line int
    column int
    
    // 数据存储
    const_value string
    var_name string
    param_index int
}

struct ir_instruction {
    instr_type int
    result ir_value
    operands ir_value[]
    opcode int
    line int
    column int
    
    // 控制流相关
    branch_target_true int
    branch_target_false int
    branch_targets int[]
}

struct ir_basicblock {
    block_id int
    label string
    instructions ir_instruction[]
    terminator ir_instruction
    
    predecessors int[]
    successors int[]
}

struct ir_function {
    name string
    return_type string
    parameters ir_value[]
    basic_blocks ir_basicblock[]
    value_counter int
}

struct ir_module {
    functions ir_function[]
    global_vars ir_value[]
}

// IR 值构造函数
func ir_value_const(const_val string, type_info string) ir_value {
    ir_value {
        value_type: IR_VALUE_CONST, value_id 0, type_info type_info, const_value const_val, line 0, column 0
    }
}

func ir_value_var(name string, type_info string) ir_value {
    ir_value {
        value_type: IR_VALUE_VAR, value_id 0, type_info type_info, var_name name, line 0, column 0
    }
}

func ir_value_param(index int, type_info string) ir_value {
    ir_value {
        value_type: IR_VALUE_PARAM, value_id 0, type_info type_info, param_index index, line 0, column 0
    }
}

// IR 指令构造函数
func ir_instr_binop(op int, left ir_value, right ir_value, result_type string) ir_instruction {
    ir_instruction {
        instr_type: IR_INSTR_BINOP, opcode op,
        operands: [left, right], result ir_value { value_type: IR_VALUE_BINOP, type_info result_type }
    }
}

func ir_instr_unop(op int, operand ir_value, result_type string) ir_instruction {
    ir_instruction {
        instr_type: IR_INSTR_UNOP, opcode op,
        operands: [operand], result ir_value { value_type: IR_VALUE_UNOP, type_info result_type }
    }
}

func ir_instr_call(func_name string, args ir_value[], return_type string) ir_instruction {
    ir_instruction {
        instr_type: IR_INSTR_CALL, var_name func_name, operands args, result ir_value { value_type: IR_VALUE_CALL, type_info return_type }
    }
}

func ir_instr_return(value ir_value) ir_instruction {
    ir_instruction {
        instr_type: IR_INSTR_RETURN,
        operands: [value]
    }
}

func ir_instr_br(target_block_id int) ir_instruction {
    ir_instruction {
        instr_type: IR_INSTR_BR, branch_target_true target_block_id
    }
}

func ir_instr_condbr(cond ir_value, true_block int, false_block int) ir_instruction {
    ir_instruction {
        instr_type: IR_INSTR_CONDBR,
        operands: [cond], branch_target_true true_block, branch_target_false false_block
    }
}

func ir_instr_phi(operands ir_value[], operand_blocks int[]) ir_instruction {
    ir_instruction {
        instr_type: IR_INSTR_PHI, operands operands, branch_targets operand_blocks
    }
}

// 基本块构造函数
func ir_basicblock_new(block_id int, label string) ir_basicblock {
    ir_basicblock {
        block_id: block_id, label label
    }
}

func ir_basicblock_add_instr(block* ir_basicblock, instr ir_instruction) {
    block.instructions = append(block.instructions, instr)
}

func ir_basicblock_set_terminator(block* ir_basicblock, instr ir_instruction) {
    block.terminator = instr
}

func ir_basicblock_add_predecessor(block* ir_basicblock, pred_id int) {
    block.predecessors = append(block.predecessors, pred_id)
}

func ir_basicblock_add_successor(block* ir_basicblock, succ_id int) {
    block.successors = append(block.successors, succ_id)
}

// 函数构造函数
func ir_function_new(name string, return_type string) ir_function {
    ir_function {
        name: name, return_type return_type, value_counter 0
    }
}

func ir_function_add_param(func* ir_function, param ir_value) {
    func.parameters = append(func.parameters, param)
}

func ir_function_add_block(func* ir_function, block ir_basicblock) {
    func.basic_blocks = append(func.basic_blocks, block)
}

func ir_function_gen_value_id(func* ir_function) int {
    func.value_counter = func.value_counter + 1
    func.value_counter
}

// 模块构造函数
func ir_module_new() ir_module {
    ir_module {}
}

func ir_module_add_function(module* ir_module, func ir_function) {
    module.functions = append(module.functions, func)
}

func ir_module_add_global(module* ir_module, global ir_value) {
    module.global_vars = append(module.global_vars, global)
}

