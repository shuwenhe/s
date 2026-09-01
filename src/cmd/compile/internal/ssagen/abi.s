package compile.internal.ssagen
use std.slices
struct abi_location {
    bool in_reg
    string place
    int stack_offset
}

struct abi_layout {
    abi_location[] params
    abi_location[] results
    int spill_size
}

func assign_abi_layout(string arch, int params, int results) abi_layout {
    int_regs := arch_int_arg_regs(arch)
    out_params := abi_location[]()
    out_results := abi_location[]()
    stack_off := 0
    i := 0
    for i < params {
        if i < int_regs {
            out_params = append(out_params, abi_location { in_reg: true, place: "r" + to_string(i), stack_offset: -1 })
        } else {
            out_params = append(out_params, abi_location { in_reg: false, place: "stack", stack_offset: stack_off })
            stack_off = stack_off + 8
        }
        i = i + 1
    }
    j := 0
    for j < results {
        if j < int_regs {
            out_results = append(out_results, abi_location { in_reg: true, place: "ret" + to_string(j), stack_offset: -1 })
        } else {
            out_results = append(out_results, abi_location { in_reg: false, place: "stack", stack_offset: stack_off })
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
