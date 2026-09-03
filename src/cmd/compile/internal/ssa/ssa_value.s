package internal.ssa

const op_const = 1
const op_add = 2
const op_sub = 3
const op_mul = 4
const op_div = 5
const op_rem = 6
const op_and = 7
const op_or = 8
const op_xor = 9
const op_shl = 10
const op_shr = 11
const op_neg = 12
const op_not = 13
const op_eq = 14
const op_ne = 15
const op_lt = 16
const op_le = 17
const op_gt = 18
const op_ge = 19
const op_load = 20
const op_store = 21
const op_call = 22
const op_return = 23
const op_if = 24
const op_phi = 25

struct ssa_value {
    int id
    int op
    int type_id
    int arg_count
    ssa_value*[] args
    long aux_int
    string aux_string
}

func ssa_value_new_const_int(int id, long value, int type_id) ssa_value* {
    v := ssa_value {
        id: id,
        op: op_const,
        type_id: type_id,
        arg_count: 0,
        args: ssa_value*[0],
        aux_int: value,
        aux_string: "",
    }
    v
}

func ssa_value_new_binary_op(int id, int op, ssa_value* left, ssa_value* right, int type_id) ssa_value* {
    v := ssa_value {
        id: id,
        op: op,
        type_id: type_id,
        arg_count: 2,
        args: ssa_value*[2],
        aux_int: 0,
        aux_string: "",
    }
    v.args[0] = left
    v.args[1] = right
    v
}

func ssa_value_new_unary_op(int id, int op, ssa_value* arg, int type_id) ssa_value* {
    v := ssa_value {
        id: id,
        op: op,
        type_id: type_id,
        arg_count: 1,
        args: ssa_value*[1],
        aux_int: 0,
        aux_string: "",
    }
    v.args[0] = arg
    v
}
