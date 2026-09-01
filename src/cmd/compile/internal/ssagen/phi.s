package compile.internal.ssagen
use std.slices
struct phi_input {
    int pred
    int value
}

struct lowered_phi {
    int target
    int[] incoming
    bool trivial
    int chosen
}

func lower_phi(int target, phi_input[] inputs) lowered_phi {
    incoming := int[]()
    i := 0
    for i < len(inputs) {
        incoming = append(incoming, inputs[i].value)
        i = i + 1
    }
    trivial := true
    chosen := -1
    if len(incoming) > 0 {
        chosen = incoming[0]
        k := 1
        for k < len(incoming) {
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
