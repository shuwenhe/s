package middleend

func test_ir_basic_types() {

    const_val := ir_value_const("42", "int")
    if const_val.value_type != ir_value_const || const_val.const_value != "42" {
        panic("IR constant value creation failed")
    }

    var_val := ir_value_var("x", "int")
    if var_val.value_type != ir_value_var || var_val.var_name != "x" {
        panic("IR variable value creation failed")
    }

    print("✓ test_ir_basic_types passed\n")
}

func test_ir_instructions() {

    left := ir_value_const("10", "int")
    right := ir_value_const("20", "int")

    add_instr := ir_instr_binop(ir_op_add, left, right, "int")
    if add_instr.instr_type != ir_instr_binop || add_instr.opcode != ir_op_add {
        panic("IR binary operation instruction creation failed")
    }

    cond := ir_value_const("1", "bool")
    br_instr := ir_instr_condbr(cond, 1, 2)
    if br_instr.instr_type != ir_instr_condbr {
        panic("IR conditional branch instruction creation failed")
    }

    print("✓ test_ir_instructions passed\n")
}

func test_ir_basicblock() {

    block := ir_basicblock_new(0, "entry")
    if block.block_id != 0 || block.label != "entry" {
        panic("IR basic block creation failed")
    }

    instr := ir_instr_binop(ir_op_add,
                           ir_value_const("1", "int"),
                           ir_value_const("2", "int"),
                           "int")
    block.add_instr(instr)

    if block.instructions.len() != 1 {
        panic("IR basic block add instruction failed")
    }

    print("✓ test_ir_basicblock passed\n")
}

func test_ir_function() {

    func := ir_function_new("test_func", "int")
    if func.name != "test_func" || func.return_type != "int" {
        panic("IR function creation failed")
    }

    param := ir_value_param(0, "int")
    func.add_param(param)

    if func.parameters.len() != 1 {
        panic("IR function add parameter failed")
    }

    block := ir_basicblock_new(0, "entry")
    func.add_block(block)

    if func.basic_blocks.len() != 1 {
        panic("IR function add block failed")
    }

    print("✓ test_ir_function passed\n")
}

func test_int_set_operations() {

    set1 := int_set_new()
    set1.add(1)
    set1.add(2)
    set1.add(3)

    if set1.values.len() != 3 {
        panic("int_set_add failed")
    }

    if set1.contains(2) == 0 {
        panic("int_set_contains failed")
    }

    set2 := int_set_new()
    set2.add(2)
    set2.add(3)
    set2.add(4)

    union := int_set_union(set1, set2)
    if union.values.len() != 4 {
        panic("int_set_union failed")
    }

    intersect := int_set_intersect(set1, set2)
    if intersect.values.len() != 2 {
        panic("int_set_intersect failed")
    }

    diff := int_set_difference(set1, set2)
    if diff.values.len() != 1 {
        panic("int_set_difference failed")
    }

    print("✓ test_int_set_operations passed\n")
}

func test_cfg_construction() {

    func := ir_function_new("test", "int")

    block0 := ir_basicblock_new(0, "entry")
    block1 := ir_basicblock_new(1, "then")
    block2 := ir_basicblock_new(2, "merge")

    block0.successors = append(block0.successors, 1)
    block0.successors = append(block0.successors, 2)

    block1.predecessors = append(block1.predecessors, 0)
    block1.successors = append(block1.successors, 2)

    block2.predecessors = append(block2.predecessors, 0)
    block2.predecessors = append(block2.predecessors, 1)

    func.basic_blocks = append(func.basic_blocks, block0)
    func.basic_blocks = append(func.basic_blocks, block1)
    func.basic_blocks = append(func.basic_blocks, block2)

    cfg := cfg_new(func)

    if cfg.blocks.len() != 3 {
        panic("CFG construction failed")
    }

    print("✓ test_cfg_construction passed\n")
}

func test_cfg_dominators() {

    func := ir_function_new("test", "int")

    block0 := ir_basicblock_new(0, "entry")
    block1 := ir_basicblock_new(1, "then")
    block2 := ir_basicblock_new(2, "merge")

    block0.successors = append(block0.successors, 1)
    block0.successors = append(block0.successors, 2)

    block1.predecessors = append(block1.predecessors, 0)
    block1.successors = append(block1.successors, 2)

    block2.predecessors = append(block2.predecessors, 0)
    block2.predecessors = append(block2.predecessors, 1)

    func.basic_blocks = append(func.basic_blocks, block0)
    func.basic_blocks = append(func.basic_blocks, block1)
    func.basic_blocks = append(func.basic_blocks, block2)

    cfg := cfg_new(func)
    cfg.compute_dominators()

    if cfg.dominators.len() == 0 {
        panic("CFG dominator computation failed")
    }

    if cfg.dominators[2][0] == 0 {
        panic("CFG dominator relationship incorrect")
    }

    print("✓ test_cfg_dominators passed\n")
}

func test_optimization_constant_folding() {

    left := ir_value_const("10", "int")
    right := ir_value_const("20", "int")

    result := opt_fold_constant(ir_op_add, "10", "20")
    if result != "30" {
        panic("Constant folding addition failed")
    }

    result = opt_fold_constant(ir_op_mul, "5", "3")
    if result != "15" {
        panic("Constant folding multiplication failed")
    }

    print("✓ test_optimization_constant_folding passed\n")
}

func run_stage2_tests() {
    print("Running Stage 2 (Middle End) Tests...\n")
    print("=====================================\n")

    print("\n[IR Module Tests]\n")
    test_ir_basic_types()
    test_ir_instructions()
    test_ir_basicblock()
    test_ir_function()

    print("\n[CFG Module Tests]\n")
    test_cfg_construction()
    test_cfg_dominators()

    print("\n[Data Structure Tests]\n")
    test_int_set_operations()

    print("\n[Optimization Tests]\n")
    test_optimization_constant_folding()

    print("\n=====================================\n")
    print("✓ All Stage 2 tests passed!\n")
}

