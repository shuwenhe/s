package compile.internal.ssa

use std.vec.vec

struct ssa_func {
    string name
    int entry
    vec[ssa_block] blocks
    vec[ssa_value] values
    int next_block_id
    int next_value_id
}

func make_func(string name) ssa_func {
    var f = ssa_func {
        name: name,
        entry: -1,
        blocks: vec[ssa_block](),
        values: vec[ssa_value](),
        next_block_id: 0,
        next_value_id: 0,
    }
    var entry = make_block(f.next_block_id, "entry")
    f.next_block_id = f.next_block_id + 1
    f.entry = entry.id
    f.blocks.push(entry)
    f
}

func func_add_block(mut ssa_func f, string kind) int {
    var id = f.next_block_id
    f.next_block_id = f.next_block_id + 1
    f.blocks.push(make_block(id, kind))
    id
}

func func_add_value(mut ssa_func f, string name, string op, string ty, vec[int] args, string literal) int {
    var id = f.next_value_id
    f.next_value_id = f.next_value_id + 1
    f.values.push(make_value(id, name, op, ty, args, literal))
    id
}

func func_find_block_index(ssa_func f, int block_id) int {
    var i = 0
    while i < f.blocks.len() {
        if f.blocks[i].id == block_id {
            return i
        }
        i = i + 1
    }
    -1
}

func block_append_value(mut ssa_func f, int block_id, int value_id) {
    var bi = func_find_block_index(f, block_id)
    if bi >= 0 {
        f.blocks[bi].values.push(value_id)
    }
}
