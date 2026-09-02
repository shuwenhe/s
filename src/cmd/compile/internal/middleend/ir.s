package middleend

const ir_value_const = 1
const ir_value_var = 2
const ir_value_param = 3
const ir_value_call = 4
const ir_value_binop = 5
const ir_value_unop = 6
const ir_value_load = 7
const ir_value_store = 8
const ir_value_alloca = 9
const ir_value_phi = 10
const ir_value_cast = 11

const ir_op_add = 100
const ir_op_sub = 101
const ir_op_mul = 102
const ir_op_div = 103
const ir_op_mod = 104
const ir_op_and = 105
const ir_op_or = 106
const ir_op_xor = 107
const ir_op_shl = 108
const ir_op_shr = 109
const ir_op_eq = 110
const ir_op_ne = 111
const ir_op_lt = 112
const ir_op_le = 113
const ir_op_gt = 114
const ir_op_ge = 115
const ir_op_land = 116
const ir_op_lor = 117

const ir_op_neg = 200
const ir_op_not = 201
const ir_op_lnot = 202

const ir_instr_binop = 300
const ir_instr_unop = 301
const ir_instr_call = 302
const ir_instr_load = 303
const ir_instr_store = 304
const ir_instr_alloca = 305
const ir_instr_return = 306
const ir_instr_br = 307
const ir_instr_condbr = 308
const ir_instr_phi = 309
const ir_instr_cast = 310
const ir_instr_switch = 311

struct ir_value {
    value_type int
    value_id int
    type_info string
    line int
    column int


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

func ir_value_const(string const_val, string type_info) ir_value {
    ir_value {
        value_type: ir_value_const, value_id 0, type_info type_info, const_value const_val, line 0, column 0
    }
}

func ir_value_var(string name, string type_info) ir_value {
    ir_value {
        value_type: ir_value_var, value_id 0, type_info type_info, var_name name, line 0, column 0
    }
}

func ir_value_param(int index, string type_info) ir_value {
    ir_value {
        value_type: ir_value_param, value_id 0, type_info type_info, param_index index, line 0, column 0
    }
}

func ir_instr_binop(int op, ir_value left, ir_value right, string result_type) ir_instruction {
    ir_instruction {
        instr_type: ir_instr_binop, opcode op,
        operands: [left, right], result ir_value { value_type: ir_value_binop, type_info result_type }
    }
}

func ir_instr_unop(int op, ir_value operand, string result_type) ir_instruction {
    ir_instruction {
        instr_type: ir_instr_unop, opcode op,
        operands: [operand], result ir_value { value_type: ir_value_unop, type_info result_type }
    }
}

func ir_instr_call(string func_name, ir_value[] args, string return_type) ir_instruction {
    ir_instruction {
        instr_type: ir_instr_call, var_name func_name, operands args, result ir_value { value_type: ir_value_call, type_info return_type }
    }
}

func ir_instr_return(ir_value value) ir_instruction {
    ir_instruction {
        instr_type: ir_instr_return,
        operands: [value]
    }
}

func ir_instr_br(int target_block_id) ir_instruction {
    ir_instruction {
        instr_type: ir_instr_br, branch_target_true target_block_id
    }
}

func ir_instr_condbr(ir_value cond, int true_block, int false_block) ir_instruction {
    ir_instruction {
        instr_type: ir_instr_condbr,
        operands: [cond], branch_target_true true_block, branch_target_false false_block
    }
}

func ir_instr_phi(ir_value[] operands, int[] operand_blocks) ir_instruction {
    ir_instruction {
        instr_type: ir_instr_phi, operands operands, branch_targets operand_blocks
    }
}

func ir_basicblock_new(int block_id, string label) ir_basicblock {
    ir_basicblock {
        block_id: block_id, label label
    }
}

func ir_basicblock_add_instr(ir_basicblock block*, ir_instruction instr) {
    block.instructions = append(block.instructions, instr)
}

func ir_basicblock_set_terminator(ir_basicblock block*, ir_instruction instr) {
    block.terminator = instr
}

func ir_basicblock_add_predecessor(ir_basicblock block*, int pred_id) {
    block.predecessors = append(block.predecessors, pred_id)
}

func ir_basicblock_add_successor(ir_basicblock block*, int succ_id) {
    block.successors = append(block.successors, succ_id)
}

func ir_function_new(string name, string return_type) ir_function {
    ir_function {
        name: name, return_type return_type, value_counter 0
    }
}

func ir_function_add_param(ir_function func*, ir_value param) {
    func.parameters = append(func.parameters, param)
}

func ir_function_add_block(ir_function func*, ir_basicblock block) {
    func.basic_blocks = append(func.basic_blocks, block)
}

func ir_function_gen_value_id(ir_function func*) int {
    func.value_counter = func.value_counter + 1
    func.value_counter
}

func ir_module_new() ir_module {
    ir_module {}
}

func ir_module_add_function(ir_module module*, ir_function func) {
    module.functions = append(module.functions, func)
}

func ir_module_add_global(ir_module module*, ir_value global) {
    module.global_vars = append(module.global_vars, global)
}

