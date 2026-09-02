package compile.internal.ir.ssa

enum value_op {
    op_const
    op_param
    op_phi
    op_add
    op_sub
    op_mul
    op_div
    op_mod
    op_and
    op_or
    op_xor
    op_shl
    op_shr
    op_load
    op_store
    op_call
    op_return
    op_branch
    op_switch
}

struct ssa_value {
    i32 id
    string name
    value_op op
    i32[] args
    i32 block
    string type_str
    bool is_const
    string const_value
}

struct ssa_phi {
    i32 id
    i32 var_id
    i32[] block_preds
    i32[] value_preds
    string type_str
}

struct ssa_block {
    i32 id
    string label
    ssa_value*[] values
    i32[] predecessors
    i32[] successors
    ssa_phi*[] phis
}

struct ssa_function {
    string name
    ssa_block*[] blocks
    ssa_value*[] values
    i32 entry_block
    i32 exit_block
    i32 value_counter
    i32 block_counter
    map[string]i32 name_to_value
}

func new_ssa_function(name string) ssa_function* {
    f := new(ssa_function)
    f.name = name
    f.blocks = new ssa_block*[]()
    f.values = new ssa_value*[]()
    f.value_counter = 0
    f.block_counter = 0
    f.entry_block = 0
    f.exit_block = -1
    f.name_to_value = make(map[string]i32)
    f
}

func (f ssa_function*) new_block(label string) ssa_block* {
    block := new(ssa_block)
    block.id = f.block_counter
    block.label = label
    block.values = new ssa_value*[]()
    block.predecessors = new i32[]()
    block.successors = new i32[]()
    block.phis = new ssa_phi*[]()
    f.block_counter += 1
    f.blocks = append(f.blocks, block)
    block
}

func (f ssa_function*) new_value(op value_op, name string, type_str string) ssa_value* {
    val := new(ssa_value)
    val.id = f.value_counter
    val.op = op
    val.name = name
    val.type_str = type_str
    val.args = new i32[]()
    val.block = -1
    val.is_const = false
    f.value_counter += 1
    f.values = append(f.values, val)
    f.name_to_value[name] = val.id
    val
}

func (f ssa_function*) new_const_value(const_val string, type_str string) ssa_value* {
    val := f.new_value(op_const, "const_" + const_val, type_str)
    val.is_const = true
    val.const_value = const_val
    val
}

func (f ssa_function*) new_param_value(name string, type_str string) ssa_value* {
    val := f.new_value(op_param, name, type_str)
    val
}

func (b ssa_block*) add_value(val ssa_value*) {
    val.block = b.id
    b.values = append(b.values, val)
}

func (b ssa_block*) add_phi(var_id i32, type_str string) ssa_phi* {
    phi := new(ssa_phi)
    phi.id = i32(len(b.phis))
    phi.var_id = var_id
    phi.block_preds = new i32[]()
    phi.value_preds = new i32[]()
    phi.type_str = type_str
    b.phis = append(b.phis, phi)
    phi
}

func (phi ssa_phi*) add_input(pred_block i32, value_id i32) {
    phi.block_preds = append(phi.block_preds, pred_block)
    phi.value_preds = append(phi.value_preds, value_id)
}

func (f ssa_function*) add_edge(from_id i32, to_id i32) {
    if from_id >= 0 && from_id < i32(len(f.blocks)) {
        f.blocks[from_id].successors = append(f.blocks[from_id].successors, to_id)
    }
    if to_id >= 0 && to_id < i32(len(f.blocks)) {
        f.blocks[to_id].predecessors = append(f.blocks[to_id].predecessors, from_id)
    }
}

func (f ssa_function*) build_ssa() {
    for i := i32(0); i < i32(len(f.blocks)); i += 1 {
        block := f.blocks[i]
        if len(block.predecessors) > 1 {
            for j := i32(0); j < i32(len(f.values)); j += 1 {
                val := f.values[j]
                if val.op == op_param || val.op == op_load {
                    phi := block.add_phi(val.id, val.type_str)
                    for _, pred := range block.predecessors {
                        phi.add_input(pred, val.id)
                    }
                }
            }
        }
    }
}

func (f ssa_function*) get_value_by_name(name string) ssa_value* {
    if id, ok := f.name_to_value[name]; ok {
        if id >= 0 && id < i32(len(f.values)) {
            return f.values[id]
        }
    }
    nil
}

func (f ssa_function*) eliminate_dead_code() {
    live := make(map[i32]bool)
    
    for i := i32(0); i < i32(len(f.values)); i += 1 {
        val := f.values[i]
        if val.op == op_return || val.op == op_store {
            live[val.id] = true
        }
    }
    
    changed := true
    for changed {
        changed = false
        for i := i32(0); i < i32(len(f.values)); i += 1 {
            if live[i] {
                val := f.values[i]
                for _, arg := range val.args {
                    if !live[arg] {
                        live[arg] = true
                        changed = true
                    }
                }
            }
        }
    }
}

func (f ssa_function*) to_string() string {
    s := "SSA Function: " + f.name + "\n"
    for _, block := range f.blocks {
        s += "Block " + string(block.id) + ": " + block.label + "\n"
        for _, val := range block.values {
            s += "  " + val.name + " = " + string(val.op) + "\n"
        }
        for _, phi := range block.phis {
            s += "  phi_" + string(phi.id) + " = phi(...)\n"
        }
    }
    s
}
