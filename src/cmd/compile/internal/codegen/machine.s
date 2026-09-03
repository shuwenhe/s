package compile.internal.codegen
use compile.internal.link
use compile.internal.obj
enum amd64_register {
    reg_rax = 0,
    reg_rcx = 1,
    reg_rdx = 2,
    reg_rbx = 3,
    reg_rsp = 4,
    reg_rbp = 5,
    reg_rsi = 6,
    reg_rdi = 7,
    reg_r8 = 8,
    reg_r9 = 9,
    reg_r10 = 10,
    reg_r11 = 11,
    reg_r12 = 12,
    reg_r13 = 13,
    reg_r14 = 14,
    reg_r15 = 15,
}
struct instr_stream {
    []int8 code
    int64 offset
    []string labels
    int64[] label_offsets
}

func make_instr_stream() instr_stream {
    instr_stream {
        code: []int8()(), offset 0, labels []string(), label_offsets int64[](),
    }
}

func (stream* instr_stream) emit_bytes([]int8 bytes) int64 {
    start := stream.offset
    i := 0
    for i < len(bytes) {
        stream.code = append(stream.code, bytes[i])
        stream.offset = stream.offset + 1
        i = i + 1
    }
    start
}

func (stream* instr_stream) emit_mov_reg_reg(int dest, int src) int64 {
    bytes := encode_mov_reg_to_reg(dest, src)
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) emit_mov_imm_reg(int64 imm, int dest) int64 {
    bytes := encode_mov_imm_to_reg(imm, dest)
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) emit_add_reg_reg(int dest, int src) int64 {
    bytes := encode_add_reg_to_reg(dest, src)
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) emit_sub_reg_reg(int dest, int src) int64 {
    bytes := encode_sub_reg_from_reg(dest, src)
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) emit_call(int64 target) int64 {
    bytes := encode_call(target)
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) emit_jmp(int64 target) int64 {
    bytes := encode_jmp(target)
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) emit_ret() int64 {
    bytes := encode_ret()
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) emit_syscall() int64 {
    bytes := encode_syscall()
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) emit_push_reg(int reg) int64 {
    bytes := encode_push_reg(reg)
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) emit_pop_reg(int reg) int64 {
    bytes := encode_pop_reg(reg)
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) emit_nop() int64 {
    bytes := encode_nop()
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) emit_raw_bytes([]int8 bytes) int64 {
    stream.emit_bytes(bytes)
}

func (stream* instr_stream) define_label(string label_name) int64 {
    pos := stream.offset
    stream.labels = append(stream.labels, label_name)
    stream.label_offsets = append(stream.label_offsets, pos)
    pos
}

func (stream* instr_stream) lookup_label(string label_name) (int64, bool) {
    i := 0
    for i < len(stream.labels) {
        if stream.labels[i] == label_name {
            return stream.label_offsets[i], true
        }
        i = i + 1
    }
    0, false
}

func (stream* instr_stream) get_code() []int8 {
    stream.code
}

struct machine_code_gen {
    instr_stream stream
    link_context* link_ctx
    relocation_context reloc_ctx
    int64 text_base
    int64 data_base
}

func make_machine_code_gen(link_context* ctx) machine_code_gen {
    machine_code_gen {
        stream: make_instr_stream(), link_ctx ctx, reloc_ctx make_relocation_context(), text_base 0x400000 as int64, data_base 0x600000 as int64,
    }
}

func (gen* machine_code_gen) allocate_text_space(int64 size) int64 {
    addr := gen.text_base + gen.link_ctx.text_size
    gen.link_ctx.text_size = gen.link_ctx.text_size + size
    addr
}

func (gen* machine_code_gen) allocate_data_space(int64 size) int64 {
    addr := gen.data_base + gen.link_ctx.data_size
    gen.link_ctx.data_size = gen.link_ctx.data_size + size
    addr
}

func (gen* machine_code_gen) emit_function_prologue() {
    gen.stream.emit_push_reg((reg_rbp as int))
    gen.stream.emit_mov_reg_reg((reg_rbp as int), (reg_rsp as int))
    gen.stream.emit_nop()
}

func (gen* machine_code_gen) emit_function_epilogue() {
    gen.stream.emit_mov_reg_reg((reg_rsp as int), (reg_rbp as int))
    gen.stream.emit_pop_reg((reg_rbp as int))
    gen.stream.emit_ret()
}

func (gen* machine_code_gen) emit_simple_func(string func_name) string {
    sym, err := gen.link_ctx.create_symbol(func_name, compile.internal.link.sym_type_text)
    if err != "" {
        return err
    }
    base := gen.stream.offset
    gen.emit_function_prologue()
    gen.stream.emit_mov_imm_reg(60 as int64, (reg_rax as int))
    gen.stream.emit_mov_imm_reg(42 as int64, (reg_rdi as int))
    gen.stream.emit_syscall()
    code_size := gen.stream.offset - base
    sym.size = code_size
    sym.is_defined = true
    ""
}

func (gen* machine_code_gen) emit_add_function() string {
    sym, err := gen.link_ctx.create_symbol("add", compile.internal.link.sym_type_text)
    if err != "" {
        return err
    }
    base := gen.stream.offset
    gen.emit_function_prologue()
    gen.stream.emit_mov_reg_reg((reg_rax as int), (reg_rdi as int))
    gen.stream.emit_add_reg_reg((reg_rax as int), (reg_rsi as int))
    gen.emit_function_epilogue()
    code_size := gen.stream.offset - base
    sym.size = code_size
    sym.is_defined = true
    ""
}

func (gen* machine_code_gen) get_code() []int8 {
    gen.stream.get_code()
}

func (gen* machine_code_gen) dump_assembly() string {
    result := "Machine Code:\n"
    code := gen.stream.get_code()
    i := 0
    for i < len(code) {
        b := code[i]
        hex := byte_to_hex(b)
        result = result + hex + " "
        if ((i + 1) % 16 == 0) {
            result = result + "\n"
        }
        i = i + 1
    }
    result + "\n"
}

func byte_to_hex(int8 b) string {
    hex_chars := "0123456789abcdef"
    ub := (b as int) & 0xff
    h1 := (ub >> 4) & 0xf
    h2 := ub & 0xf
    result := ""
    result = result + hex_chars[h1]
    result = result + hex_chars[h2]
    result
}
