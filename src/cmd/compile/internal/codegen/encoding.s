package compile.internal.codegen
use compile.internal.link
enum amd64_opcode {
    op_nop,
    op_mov,
    op_add,
    op_sub,
    op_mul,
    op_div,
    op_xor,
    op_and,
    op_or,
    op_shl,
    op_shr,
    op_jmp,
    op_je,
    op_jne,
    op_jl,
    op_jle,
    op_jg,
    op_jge,
    op_call,
    op_ret,
    op_cmp,
    op_test,
    op_push,
    op_pop,
    op_lea,
    op_imul,
    op_idiv,
}
struct amd64_operand {
    addr operand
}

struct amd64_instr {
    amd64_opcode opcode
    int prefix_count
    int8[] prefixes
    int rex_byte
    int opcode_byte1
    int opcode_byte2
    int modrm_byte
    int sib_byte
    int64 immediate
    bool has_immediate
    bool has_modrm
    bool has_sib
    int operand_size
    int address_size
}

func make_amd64_instr(amd64_opcode op) amd64_instr {
    amd64_instr {
        opcode: op, prefix_count 0,
        prefixes: int8[]()(), rex_byte 0, opcode_byte1 0, opcode_byte2 0, modrm_byte 0, sib_byte 0, immediate 0, has_immediate false, has_modrm false, has_sib false, operand_size 0, address_size 64,
    }
}

func (instr* amd64_instr) set_operand_size(int size) {
    instr.operand_size = size
    if size == 16 {
        instr.prefixes = append(instr.prefixes, 0x66 as int8)
        instr.prefix_count = instr.prefix_count + 1
    }
}

func (instr* amd64_instr) set_rex_byte(int w, int r, int x, int b) {
    instr.rex_byte = 0x40
    if w != 0 {
        instr.rex_byte = instr.rex_byte + 0x08
    }
    if r != 0 {
        instr.rex_byte = instr.rex_byte + 0x04
    }
    if x != 0 {
        instr.rex_byte = instr.rex_byte + 0x02
    }
    if b != 0 {
        instr.rex_byte = instr.rex_byte + 0x01
    }
}

func (instr* amd64_instr) set_modrm(int mod, int reg, int rm) {
    instr.modrm_byte = ((mod & 3) << 6) + ((reg & 7) << 3) + (rm & 7)
    instr.has_modrm = true
}

func (instr* amd64_instr) set_sib(int scale, int index, int base) {
    instr.sib_byte = ((scale & 3) << 6) + ((index & 7) << 3) + (base & 7)
    instr.has_sib = true
}

func (instr* amd64_instr) set_immediate(int64 imm, int size) {
    instr.immediate = imm
    instr.has_immediate = true
}

func encode_mov_reg_to_reg(int dest_reg, int src_reg) int8[] {
    result := int8[]()()
    instr := make_amd64_instr(op_mov)
    instr.set_operand_size(64)
    instr.set_rex_byte(1, (dest_reg >> 3) & 1, 0, (src_reg >> 3) & 1)
    instr.opcode_byte1 = 0x89
    instr.set_modrm(3, src_reg & 7, dest_reg & 7)
    result = append_bytes(result, instr.prefixes)
    result = append(result, (instr.rex_byte as int8))
    result = append(result, (instr.opcode_byte1 as int8))
    result = append(result, (instr.modrm_byte as int8))
    result
}

func encode_mov_imm_to_reg(int64 imm, int dest_reg) int8[] {
    result := int8[]()()
    instr := make_amd64_instr(op_mov)
    instr.set_operand_size(64)
    instr.set_rex_byte(1, 0, 0, (dest_reg >> 3) & 1)
    instr.opcode_byte1 = 0xb8 + (dest_reg & 7)
    instr.set_immediate(imm, 8)
    result = append_bytes(result, instr.prefixes)
    result = append(result, (instr.rex_byte as int8))
    result = append(result, (instr.opcode_byte1 as int8))
    i := 0
    for i < 8 {
        b := ((imm >> (i * 8)) & 0xff) as int8
        result = append(result, b)
        i = i + 1
    }
    result
}

func encode_add_reg_to_reg(int dest_reg, int src_reg) int8[] {
    result := int8[]()()
    instr := make_amd64_instr(op_add)
    instr.set_operand_size(64)
    instr.set_rex_byte(1, (src_reg >> 3) & 1, 0, (dest_reg >> 3) & 1)
    instr.opcode_byte1 = 0x01
    instr.set_modrm(3, src_reg & 7, dest_reg & 7)
    result = append_bytes(result, instr.prefixes)
    result = append(result, (instr.rex_byte as int8))
    result = append(result, (instr.opcode_byte1 as int8))
    result = append(result, (instr.modrm_byte as int8))
    result
}

func encode_sub_reg_from_reg(int dest_reg, int src_reg) int8[] {
    result := int8[]()()
    instr := make_amd64_instr(op_sub)
    instr.set_operand_size(64)
    instr.set_rex_byte(1, (src_reg >> 3) & 1, 0, (dest_reg >> 3) & 1)
    instr.opcode_byte1 = 0x29
    instr.set_modrm(3, src_reg & 7, dest_reg & 7)
    result = append_bytes(result, instr.prefixes)
    result = append(result, (instr.rex_byte as int8))
    result = append(result, (instr.opcode_byte1 as int8))
    result = append(result, (instr.modrm_byte as int8))
    result
}

func encode_jmp(int64 offset) int8[] {
    result := int8[]()()
    instr := make_amd64_instr(op_jmp)
    instr.opcode_byte1 = 0xe9
    instr.set_immediate(offset - 5, 4)
    result = append(result, (instr.opcode_byte1 as int8))
    i := 0
    for i < 4 {
        b := (((offset - 5) >> (i * 8)) & 0xff) as int8
        result = append(result, b)
        i = i + 1
    }
    result
}

func encode_call(int64 offset) int8[] {
    result := int8[]()()
    instr := make_amd64_instr(op_call)
    instr.opcode_byte1 = 0xe8
    instr.set_immediate(offset - 5, 4)
    result = append(result, (instr.opcode_byte1 as int8))
    i := 0
    for i < 4 {
        b := (((offset - 5) >> (i * 8)) & 0xff) as int8
        result = append(result, b)
        i = i + 1
    }
    result
}

func encode_ret() int8[] {
    result := int8[]()()
    result = append(result, 0xc3 as int8)
    result
}

func encode_syscall() int8[] {
    result := int8[]()()
    result = append(result, 0x0f as int8)
    result = append(result, 0x05 as int8)
    result
}

func encode_push_reg(int reg) int8[] {
    result := int8[]()()
    instr := make_amd64_instr(op_push)
    if (reg >> 3) & 1 != 0 {
        instr.rex_byte = 0x41
        result = append(result, (instr.rex_byte as int8))
    }
    instr.opcode_byte1 = 0x50 + (reg & 7)
    result = append(result, (instr.opcode_byte1 as int8))
    result
}

func encode_pop_reg(int reg) int8[] {
    result := int8[]()()
    instr := make_amd64_instr(op_pop)
    if (reg >> 3) & 1 != 0 {
        instr.rex_byte = 0x41
        result = append(result, (instr.rex_byte as int8))
    }
    instr.opcode_byte1 = 0x58 + (reg & 7)
    result = append(result, (instr.opcode_byte1 as int8))
    result
}

func encode_nop() int8[] {
    result := int8[]()()
    result = append(result, 0x90 as int8)
    result
}

func append_bytes(int8[] dest, int8[] src) int8[] {
    result := dest
    i := 0
    for i < len(src) {
        result = append(result, src[i])
        i = i + 1
    }
    result
}

func opcode_name(amd64_opcode op) string {
    switch op {
        case op_nop: return "nop"
        case op_mov: return "mov"
        case op_add: return "add"
        case op_sub: return "sub"
        case op_mul: return "mul"
        case op_div: return "div"
        case op_xor: return "xor"
        case op_and: return "and"
        case op_or: return "or"
        case op_shl: return "shl"
        case op_shr: return "shr"
        case op_jmp: return "jmp"
        case op_je: return "je"
        case op_jne: return "jne"
        case op_jl: return "jl"
        case op_jle: return "jle"
        case op_jg: return "jg"
        case op_jge: return "jge"
        case op_call: return "call"
        case op_ret: return "ret"
        case op_cmp: return "cmp"
        case op_test: return "test"
        case op_push: return "push"
        case op_pop: return "pop"
        case op_lea: return "lea"
        case op_imul: return "imul"
        case op_idiv: return "idiv"
    }
    "unknown"
}
