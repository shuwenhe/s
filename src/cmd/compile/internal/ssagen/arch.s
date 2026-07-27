package compile.internal.ssagen

struct arch_profile {
    string name
    int int_arg_regs
    int stack_align
    int caller_saved
    int callee_saved
    bool has_simd
}

func lookup_arch(string arch) arch_profile {
    if arch == "amd64" {
        return arch_profile { name: arch, int_arg_regs: 6, stack_align: 16, caller_saved: 9, callee_saved: 5, has_simd: true }
    }
    if arch == "arm64" {
        return arch_profile { name: arch, int_arg_regs: 8, stack_align: 16, caller_saved: 18, callee_saved: 10, has_simd: true }
    }
    if arch == "riscv64" {
        return arch_profile { name: arch, int_arg_regs: 8, stack_align: 16, caller_saved: 15, callee_saved: 12, has_simd: false }
    }
    arch_profile { name: arch, int_arg_regs: 4, stack_align: 8, caller_saved: 8, callee_saved: 4, has_simd: false }
}

func arch_int_arg_regs(string arch) int {
    lookup_arch(arch).int_arg_regs
}

func arch_stack_align(string arch) int {
    lookup_arch(arch).stack_align
}

func arch_has_simd(string arch) bool {
    lookup_arch(arch).has_simd
}
