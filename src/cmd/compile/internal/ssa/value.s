package compile.internal.ssa

use std.vec.vec

struct ssa_value {
    int id
    string name
    string op
    string ty
    vec[int] args
    int uses
    bool removed
    string literal
}

func make_value(int id, string name, string op, string ty, vec[int] args, string literal) ssa_value {
    ssa_value {
        id: id,
        name: name,
        op: op,
        ty: ty,
        args: args,
        uses: 0,
        removed: false,
        literal: literal,
    }
}

func value_is_const_zero(ssa_value v) bool {
    v.op == op_const() && v.literal == "0"
}

func value_key(ssa_value v) string {
    let key = v.op + "|" + v.ty + "|" + v.literal
    let i = 0
    while i < v.args.len() {
        key = key + "#" + to_string(v.args[i])
        i = i + 1
    }
    key
}
