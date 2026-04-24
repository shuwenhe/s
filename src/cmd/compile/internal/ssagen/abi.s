package compile.internal.ssagen

use std.vec.vec

struct abi_location {
    bool in_reg
    string place
    int stack_offset
}

struct abi_layout {
    vec[abi_location] params
    vec[abi_location] results
    int spill_size
}

func assign_abi_layout(string arch, int params, int results) abi_layout {
    var int_regs = arch_int_arg_regs(arch)
    var out_params = vec[abi_location]()
    var out_results = vec[abi_location]()

    var stack_off = 0
    var i = 0
    while i < params {
        if i < int_regs {
            out_params.push(abi_location { in_reg: true, place: "r" + to_string(i), stack_offset: -1 })
        } else {
            out_params.push(abi_location { in_reg: false, place: "stack", stack_offset: stack_off })
            stack_off = stack_off + 8
        }
        i = i + 1
    }

    var j = 0
    while j < results {
        if j < int_regs {
            out_results.push(abi_location { in_reg: true, place: "ret" + to_string(j), stack_offset: -1 })
        } else {
            out_results.push(abi_location { in_reg: false, place: "stack", stack_offset: stack_off })
            stack_off = stack_off + 8
        }
        j = j + 1
    }

    abi_layout {
        params: out_params,
        results: out_results,
        spill_size: align_stack(stack_off, arch_stack_align(arch)),
    }
}

func align_stack(int size, int align) int {
    if align <= 1 {
        return size
    }
    ((size + align - 1) / align) * align
}
