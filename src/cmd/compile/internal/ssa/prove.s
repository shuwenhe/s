package compile.internal.ssa

use std.vec.vec

struct prove_fact {
    int value_id
    bool known_zero
    bool known_non_zero
}

func fact_for(int id, bool z, bool nz) prove_fact {
    prove_fact {
        value_id: id,
        known_zero: z,
        known_non_zero: nz,
    }
}

func find_fact(vec[prove_fact] facts, int id) int {
    let i = 0
    while i < facts.len() {
        if facts[i].value_id == id {
            return i
        }
        i = i + 1
    }
    -1
}

func fact_zero(vec[prove_fact] facts, int id) bool {
    let i = find_fact(facts, id)
    i >= 0 && facts[i].known_zero
}

func fact_non_zero(vec[prove_fact] facts, int id) bool {
    let i = find_fact(facts, id)
    i >= 0 && facts[i].known_non_zero
}

func run_prove(ssa_func f) vec[prove_fact] {
    let facts = vec[prove_fact]()
    let i = 0
    while i < f.values.len() {
        let v = f.values[i]
        let z = false
        let nz = false
        if v.op == op_const() {
            z = v.literal == "0"
            nz = v.literal != "" && v.literal != "0"
        } else if v.op == op_mul() && v.args.len() == 2 {
            z = fact_zero(facts, v.args[0]) || fact_zero(facts, v.args[1])
        } else if v.op == op_add() && v.args.len() == 2 {
            z = fact_zero(facts, v.args[0]) && fact_zero(facts, v.args[1])
            nz = fact_non_zero(facts, v.args[0]) && fact_non_zero(facts, v.args[1])
        } else if v.op == op_sub() && v.args.len() == 2 {
            z = v.args[0] == v.args[1]
        }
        facts.push(fact_for(v.id, z, nz))
        i = i + 1
    }
    facts
}
