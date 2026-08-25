package compile.internal.ssagen
use std.vec.vec

struct phi_input {
    int pred
    int value
}

struct lowered_phi {
    int target
    vec[int] incoming
    bool trivial
    int chosen
}

func lower_phi(int target, vec[phi_input] inputs) lowered_phi {
    incoming := vec[int]()
    i := 0
    for i < inputs.len() {
        incoming.push(inputs[i].value)
        i = i + 1
    }
    trivial := true
    chosen := -1
    if incoming.len() > 0 {
        chosen = incoming[0]
        k := 1
        for k < incoming.len() {
            if incoming[k] != chosen {
                trivial = false
                break
            }
            k = k + 1
        }
    } else {
        trivial = false
    }
    lowered_phi {
        target: target,
        incoming: incoming,
        trivial: trivial,
        chosen: chosen,
    }
}

func phi_is_trivial(lowered_phi p) bool {
    p.trivial
}
