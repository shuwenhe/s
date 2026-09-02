package seed.codegen
use std.vec.vec
struct stack_frame {
    base_offset: int
    current_offset: int
    locals: (string, int, int)[]
    param_count: int
}

func stack_frame_create(param_count: int) stack_frame {
    frame: stack_frame
    frame.base_offset = 0
    frame.current_offset = -(param_count * 8)
    frame.locals = vec[]()
    frame.param_count = param_count
    frame
}

func (sf* stack_frame) allocate_local(var_name: string, size: int) int {
    offset := sf.current_offset - size
    sf.locals.push((var_name, offset, size))
    sf.current_offset = offset
    offset
}

func (sf* stack_frame) get_local_offset(var_name: string) int {
    for i < sf.locals.len() {
        if sf.locals[i].0 == var_name {
            return sf.locals[i].1
        }
    }
    0
}

func (sf* stack_frame) get_frame_size() int {
    -sf.current_offset
}

func (sf* stack_frame) get_param_offset(param_index: int) int {
    (param_index + 1) * 8
}

func stack_frame_emit_prologue(sf* stack_frame, ctx* codegen_context, fn_name: string) {
    ctx.emit_label(fn_name)
    ctx.emit_line("    push %rbp")
    ctx.emit_line("    mov %rsp, %rbp")
    frame_size := sf.get_frame_size()
    if frame_size > 0 {
        ctx.emit_line("    sub $" + frame_size as string + ", %rsp")
    }
}

func stack_frame_emit_epilogue(ctx* codegen_context) {
    ctx.emit_line("    leave")
    ctx.emit_line("    ret")
}

func stack_frame_emit_spill(ctx* codegen_context, reg: string, offset: int) {
    ctx.emit_line("    mov %" + reg + ", " + offset as string + "(%rbp)")
}

func stack_frame_emit_restore(ctx* codegen_context, reg: string, offset: int) {
    ctx.emit_line("    mov " + offset as string + "(%rbp), %" + reg)
}
