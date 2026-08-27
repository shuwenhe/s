package compile.internal.ssa
use std.slices

struct ssa_func {
    string name
    int entry
    ssa_block[] blocks
    ssa_value[] values
    int next_block_id
    int next_value_id
}

func make_func(string name) ssa_func {
    f := ssa_func {
        name: name,
        entry: -1,
        blocks: ssa_block[](),
        values: ssa_value[](),
        next_block_id: 0,
        next_value_id: 0,
    }
    entry := make_block(f.next_block_id, "entry")
    f.next_block_id = f.next_block_id + 1
    f.entry = entry.id
    f.blocks = append(f.blocks, entry)
    f
}

func func_add_block(ssa_func f, string kind) int {
    id := f.next_block_id
    f.next_block_id = f.next_block_id + 1
    f.blocks = append(f.blocks, make_block(id, kind))
    id
}

func func_add_value(ssa_func f, string name, string op, string ty, int[] args, string literal) int {
    id := f.next_value_id
    f.next_value_id = f.next_value_id + 1
    f.values = append(f.values, make_value(id, name, op, ty, args, literal))
    id
}

func func_find_block_index(ssa_func f, int block_id) int {
    i := 0
    for i < len(f.blocks) {
        if f.blocks[i].id == block_id {
            return i
        }
        i = i + 1
    }
    -1
}

func block_append_value(ssa_func f, int block_id, int value_id) {
    bi := func_find_block_index(f, block_id)
    if bi >= 0 {
        f.blocks[bi].values = append(.values, value_id)
    }
}
