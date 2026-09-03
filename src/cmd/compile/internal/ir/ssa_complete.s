package compile.internal.ir.ssa
use std.conv.int_to_string

enum value_op {
    op_const,
    op_param,
    op_phi,
    op_add,
    op_sub,
    op_mul,
    op_div,
    op_mod,
    op_and,
    op_or,
    op_xor,
    op_shl,
    op_shr,
    op_load,
    op_store,
    op_call,
    op_return,
    op_branch,
    op_switch,
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
    bool removed
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
    bool removed
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
    block.removed = false
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
    val.removed = false
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
        from_block := f.blocks[from_id]
        from_block.successors = append(from_block.successors, to_id)
    }
    if to_id >= 0 && to_id < i32(len(f.blocks)) {
        to_block := f.blocks[to_id]
        to_block.predecessors = append(to_block.predecessors, from_id)
    }
}

func (f ssa_function*) build_ssa() {
    for i := i32(0); i < i32(len(f.blocks)); i += 1 {
        block := f.blocks[i]
        if len(block.predecessors) > 1 {
            for j := i32(0); j < i32(len(f.values)); j += 1 {
                val := f.values[j]
                if val.op == op_param {
                    phi := block.add_phi(val.id, val.type_str)
                    for _, pred := range block.predecessors {
                        phi.add_input(pred, val.id)
                    }
                }
            }
        }
    }
}

struct ssa_opt_stats {
    int constants_folded
    int cse_eliminated
    int dead_removed
    int branches_folded
    int blocks_merged
}

func ssa_value_at(ssa_function* f, int id) ssa_value* {
    if f == 0 || id < 0 || id >= len(f.values) {
        return 0
    }
    f.values[id]
}

func ssa_replace_uses(ssa_function* f, int old_id, int new_id) {
    for i := 0; i < len(f.values); i = i + 1 {
        value := f.values[i]
        for j := 0; j < len(value.args); j = j + 1 {
            if value.args[j] == old_id {
                value.args[j] = new_id
            }
        }
    }
    for i := 0; i < len(f.blocks); i = i + 1 {
        block := f.blocks[i]
        for j := 0; j < len(block.phis); j = j + 1 {
            phi := block.phis[j]
            for k := 0; k < len(phi.value_preds); k = k + 1 {
                if phi.value_preds[k] == old_id {
                    phi.value_preds[k] = new_id
                }
            }
        }
    }
}

func ssa_fold_constants(ssa_function* f) int {
    changed := 0
    for i := 0; i < len(f.values); i = i + 1 {
        value := f.values[i]
        if value.is_const || len(value.args) != 2 {
            continue
        }
        left := ssa_value_at(f, value.args[0])
        right := ssa_value_at(f, value.args[1])
        if left == 0 || right == 0 || !left.is_const || !right.is_const {
            continue
        }
        a := parse_int(left.const_value)
        b := parse_int(right.const_value)
        result := 0
        valid := true
        if value.op == op_add { result = a + b
        } else if value.op == op_sub { result = a - b
        } else if value.op == op_mul { result = a * b
        } else if value.op == op_div && b != 0 { result = a / b
        } else if value.op == op_mod && b != 0 { result = a % b
        } else { valid = false }
        if valid {
            value.op = op_const
            value.is_const = true
            value.const_value = int_to_string(result)
            value.args = int[]()
            changed = changed + 1
        }
    }
    changed
}

func ssa_apply_identities(ssa_function* f) int {
    changed := 0
    for i := 0; i < len(f.values); i = i + 1 {
        value := f.values[i]
        if len(value.args) != 2 || (value.op != op_add && value.op != op_sub && value.op != op_mul) {
            continue
        }
        right := ssa_value_at(f, value.args[1])
        if right == 0 || !right.is_const {
            continue
        }
        n := parse_int(right.const_value)
        if (value.op == op_add || value.op == op_sub) && n == 0 {
            ssa_replace_uses(f, value.id, value.args[0])
            value.removed = true
            changed = changed + 1
        } else if value.op == op_mul && n == 1 {
            ssa_replace_uses(f, value.id, value.args[0])
            value.removed = true
            changed = changed + 1
        }
    }
    changed
}

func ssa_eliminate_common_subexpressions(ssa_function* f) int {
    changed := 0
    for i := 0; i < len(f.values); i = i + 1 {
        current := f.values[i]
        if current.removed || !ssa_is_pure(current.op) {
            continue
        }
        for j := 0; j < i; j = j + 1 {
            previous := f.values[j]
            if previous.removed || previous.op != current.op || previous.type_str != current.type_str || len(previous.args) != len(current.args) {
                continue
            }
            same := true
            for k := 0; k < len(current.args); k = k + 1 {
                if current.args[k] != previous.args[k] {
                    same = false
                }
            }
            if same {
                ssa_replace_uses(f, current.id, previous.id)
                current.removed = true
                changed = changed + 1
                break
            }
        }
    }
    changed
}

func ssa_is_pure(value_op op) bool {
    value_op != op_store && value_op != op_call && value_op != op_return && value_op != op_branch && value_op != op_switch
}

func ssa_mark_live(ssa_function* f, int id, bool[] live) {
    if id < 0 || id >= len(f.values) || live[id] {
        return
    }
    live[id] = true
    for i := 0; i < len(f.values[id].args); i = i + 1 {
        ssa_mark_live(f, f.values[id].args[i], live)
    }
}

func ssa_eliminate_dead_values(ssa_function* f) int {
    bool[len(f.values)] live
    for i := 0; i < len(f.values); i = i + 1 {
        value := f.values[i]
        if value.op == op_store || value.op == op_call || value.op == op_return || value.op == op_branch || value.op == op_switch {
            ssa_mark_live(f, value.id, live)
        }
    }
    removed := 0
    for i := 0; i < len(f.blocks); i = i + 1 {
        kept := ssa_value*[]()
        for j := 0; j < len(f.blocks[i].values); j = j + 1 {
            value := f.blocks[i].values[j]
            if live[value.id] {
                kept = append(kept, value)
            } else {
                value.removed = true
                removed = removed + 1
            }
        }
        f.blocks[i].values = kept
    }
    removed
}

func ssa_fold_constant_branches(ssa_function* f) int {
    changed := 0
    for i := 0; i < len(f.values); i = i + 1 {
        branch := f.values[i]
        if branch.op != op_branch || len(branch.args) == 0 {
            continue
        }
        condition := ssa_value_at(f, branch.args[0])
        if condition == 0 || !condition.is_const || len(f.blocks[branch.block].successors) < 2 {
            continue
        }
        selected := parse_int(condition.const_value)
        target := f.blocks[branch.block].successors[0]
        if selected != 0 {
            target = f.blocks[branch.block].successors[1]
        }
        f.blocks[branch.block].successors = int[] { target }
        branch.op = op_branch
        changed = changed + 1
    }
    changed
}

func ssa_merge_trivial_blocks(ssa_function* f) int {
    merged := 0
    for i := 0; i < len(f.blocks); i = i + 1 {
        block := f.blocks[i]
        if block.removed || len(block.successors) != 1 {
            continue
        }
        target_id := block.successors[0]
        if target_id < 0 || target_id >= len(f.blocks) || target_id == block.id {
            continue
        }
        target := f.blocks[target_id]
        if target.removed || len(target.predecessors) != 1 || target_id == f.entry_block {
            continue
        }
        for j := 0; j < len(target.values); j = j + 1 {
            block.values = append(block.values, target.values[j])
            target.values[j].block = block.id
        }
        block.successors = target.successors
        target.removed = true
        merged = merged + 1
    }
    merged
}

func (f ssa_function*) optimize() ssa_opt_stats {
    stats := ssa_opt_stats {}
    stats.constants_folded = ssa_fold_constants(f)
    stats.constants_folded = stats.constants_folded + ssa_apply_identities(f)
    stats.cse_eliminated = ssa_eliminate_common_subexpressions(f)
    stats.branches_folded = ssa_fold_constant_branches(f)
    stats.dead_removed = ssa_eliminate_dead_values(f)
    stats.blocks_merged = ssa_merge_trivial_blocks(f)
    stats
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
