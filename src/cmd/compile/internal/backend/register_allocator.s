package backend

struct register_allocator {
    available_regs: string[]
    allocated_regs: string[]
    variable_map: string[]
    spill_offset: int
}

func new_register_allocator() register_allocator {
    allocator: register_allocator
    allocator.available_regs = make(string[])
    allocator.available_regs = append(allocator.available_regs, "rax")
    allocator.available_regs = append(allocator.available_regs, "rcx")
    allocator.available_regs = append(allocator.available_regs, "rdx")
    allocator.available_regs = append(allocator.available_regs, "rsi")
    allocator.available_regs = append(allocator.available_regs, "rdi")
    allocator.available_regs = append(allocator.available_regs, "r8")
    allocator.available_regs = append(allocator.available_regs, "r9")
    allocator.available_regs = append(allocator.available_regs, "r10")
    allocator.available_regs = append(allocator.available_regs, "r11")
    allocator.allocated_regs = make(string[])
    allocator.variable_map = make(string[])
    allocator.spill_offset = 0
    allocator
}

func (ra* register_allocator) allocate_for_variable(var_name: string) string {
    if len(ra.available_regs) > 0 {
        reg := ra.available_regs[0]
        i := 1
        new_available := make(string[])
        for i < len(ra.available_regs) {
            new_available = append(new_available, ra.available_regs[i])
            i = i + 1
        }
        ra.available_regs = new_available
        ra.allocated_regs = append(ra.allocated_regs, reg)
        ra.variable_map = append(ra.variable_map, var_name + ":" + reg)
        reg
    } else {
        ra.spill_offset = ra.spill_offset - 8
        offset_str := ra.spill_offset as string
        ra.variable_map = append(ra.variable_map, var_name + ":[rbp" + offset_str + "]")
        "[rbp" + offset_str + "]"
    }
}

func (ra* register_allocator) get_variable_location(var_name: string) string {
    i := 0
    for i < len(ra.variable_map) {
        mapping := ra.variable_map[i]
        colon_idx := 0
        j := 0
        for j < len(mapping) {
            if mapping[j] == ':' {
                colon_idx = j
                break
            }
            j = j + 1
        }
        name := mapping[0:colon_idx]
        if name == var_name {
            j = colon_idx + 1
            mapping[j:]
        }
        i = i + 1
    }
    ""
}

func (ra* register_allocator) free_register(reg: string) {
    ra.available_regs = append(ra.available_regs, reg)
}

func (ra* register_allocator) get_stack_size() int {
    -ra.spill_offset + 16
}
