package backend

struct stack_frame {
    function_name: string
    frame_size: int
    local_variables: string[]
    param_count: int
}

func new_stack_frame(name: string, param_count: int) stack_frame {
    frame: stack_frame
    frame.function_name = name
    frame.param_count = param_count
    frame.frame_size = 16
    frame.local_variables = make(string[])
    frame
}

func (sf* stack_frame) allocate_local(var_name: string, size: int) int {
    sf.local_variables = append(sf.local_variables, var_name)
    offset := sf.frame_size
    sf.frame_size = sf.frame_size + size
    offset
}

func (sf* stack_frame) get_frame_size() int {
    sf.frame_size
}

func (sf* stack_frame) align_frame_size() int {
    size := sf.get_frame_size()
    remainder := size % 16
    if remainder != 0 {
        size = size + (16 - remainder)
    }
    size
}

func (sf* stack_frame) emit_prologue(builder* machine_code_builder) {
    builder.emit_function_prologue(sf.function_name)
    if sf.align_frame_size() > 16 {
        offset := sf.align_frame_size() - 16
        builder.instructions = append(builder.instructions, "\tsub\t$" + offset as string + ", %rsp")
    }
}

func (sf* stack_frame) emit_epilogue(builder* machine_code_builder) {
    if sf.align_frame_size() > 16 {
        offset := sf.align_frame_size() - 16
        builder.instructions = append(builder.instructions, "\tadd\t$" + offset as string + ", %rsp")
    }
    builder.emit_function_epilogue()
}
