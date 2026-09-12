package macho_backend

const (
    MACHO_MAGIC_64 = 0xfeedf00d
    MACHO_MAGIC_ARM64 = 0xfeedf00d
    MACHO_CIGAM_64 = 0xcefaedfe

    CPU_TYPE_X86_64 = 7
    CPU_TYPE_ARM64 = 0x0100000c

    CPU_SUBTYPE_X86_64_ALL = 3
    CPU_SUBTYPE_ARM64_ALL = 0

    MH_EXECUTE = 2
    MH_OBJECT = 1

    LC_SEGMENT = 0x1
    LC_SEGMENT_64 = 0x19
    LC_MAIN = 0x28
    LC_DYLD_INFO_ONLY = 0x22
    LC_SYMTAB = 0x2
    LC_DYSYMTAB = 0xb

    VM_PROT_READ = 1
    VM_PROT_WRITE = 2
    VM_PROT_EXECUTE = 4
)

struct macho_header {
    magic uint
    cpu_type uint
    cpu_subtype uint
    file_type uint
    n_cmds uint
    size_cmds uint
    flags uint
    reserved uint
}

struct macho_segment_64 {
    cmd uint
    cmd_size uint
    seg_name string
    vm_addr uint64
    vm_size uint64
    file_offset uint64
    file_size uint64
    prot_max uint
    prot_init uint
    n_sections uint
    flags uint
}

struct macho_section_64 {
    sect_name string
    seg_name string
    addr uint64
    size uint64
    offset uint
    align uint
    reloff uint
    nreloc uint
    flags uint
    reserved1 uint
    reserved2 uint
}

struct macho_symtab_cmd {
    cmd uint
    cmd_size uint
    symoff uint
    nsyms uint
    stroff uint
    strsize uint
}

struct macho_main_cmd {
    cmd uint
    cmd_size uint
    entry_off uint64
    stack_size uint64
}

struct macho_builder {
    arch string
    string[] code_text
    string[] data_text
    string[] rodata_text
    code_offset int
    data_offset int
    rodata_offset int
    string[] symbols
    symbol_count int
}

func macho_builder_new() macho_builder* {
    builder := macho_builder {
        arch: "arm64",
        code_text: make(string[], 1024),
        data_text: make(string[], 1024),
        rodata_text: make(string[], 1024),
        code_offset: 0,
        data_offset: 0,
        rodata_offset: 0,
        symbols: make(string[], 256),
        symbol_count: 0,
    }
    return &builder
}

func (b* macho_builder) set_arch(string arch) {
    b.arch = arch
}

func (b* macho_builder) add_code(string asm) {
    if b.code_offset < len(b.code_text) {
        b.code_text[b.code_offset] = asm
        b.code_offset = b.code_offset + 1
    }
}

func (b* macho_builder) add_function_arm64(string name, string body) {

    func_asm := ".globl _" + name + "\n"
    func_asm = func_asm + "_" + name + ":\n"
    func_asm = func_asm + "    sub sp, sp, #16\n"
    func_asm = func_asm + body
    func_asm = func_asm + "    add sp, sp, #16\n"
    func_asm = func_asm + "    ret\n"
    b.add_code(func_asm)
}

func (b* macho_builder) add_function_x86_64(string name, string body) {

    func_asm := ".globl _" + name + "\n"
    func_asm = func_asm + "_" + name + ":\n"
    func_asm = func_asm + "    push rbp\n"
    func_asm = func_asm + "    mov rsp, rbp\n"
    func_asm = func_asm + body
    func_asm = func_asm + "    pop rbp\n"
    func_asm = func_asm + "    ret\n"
    b.add_code(func_asm)
}

func (b* macho_builder) add_symbol(string name) int {
    if b.symbol_count < len(b.symbols) {
        b.symbols[b.symbol_count] = name
        ret := b.symbol_count
        b.symbol_count = b.symbol_count + 1
        return ret
    }
    return -1
}

func macho_uint32_to_bytes(uint val) string {

    byte1 := val % 256
    byte2 := (val / 256) % 256
    byte3 := (val / 65536) % 256
    byte4 := (val / 16777216) % 256
    return chr(byte1) + chr(byte2) + chr(byte3) + chr(byte4)
}

func macho_uint64_to_bytes(uint64 val) string {

    low := uint(val % 4294967296)
    high := uint(val / 4294967296)
    return macho_uint32_to_bytes(low) + macho_uint32_to_bytes(high)
}

func chr(int b) string {

    if b < 0 || b > 255 { return "\x00" }
    chars := "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f" +
             "\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f" +
             "\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2a\x2b\x2c\x2d\x2e\x2f" +
             "\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3a\x3b\x3c\x3d\x3e\x3f" +
             "\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4a\x4b\x4c\x4d\x4e\x4f" +
             "\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5a\x5b\x5c\x5d\x5e\x5f" +
             "\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6a\x6b\x6c\x6d\x6e\x6f" +
             "\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7a\x7b\x7c\x7d\x7e\x7f" +
             "\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f" +
             "\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f" +
             "\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf" +
             "\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf" +
             "\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf" +
             "\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf" +
             "\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef" +
             "\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff"
    return chars[b:b+1]
}

func (b* macho_builder) pad_string(string s, int len) string {

    current_len := len(s)
    if current_len >= len { return s }
    padding := len - current_len
    pad := ""
    i := 0
    for i < padding {
        pad = pad + "\x00"
        i = i + 1
    }
    return s + pad
}

func (b* macho_builder) write_mach_header(string arch) string {

    header := ""

    header = header + macho_uint32_to_bytes(0xcefaedfe)

    if arch == "arm64" {
        header = header + macho_uint32_to_bytes(0x0100000c)
        header = header + macho_uint32_to_bytes(0)
    } else if arch == "x86_64" {
        header = header + macho_uint32_to_bytes(7)
        header = header + macho_uint32_to_bytes(3)
    }

    header = header + macho_uint32_to_bytes(2)

    header = header + macho_uint32_to_bytes(3)

    header = header + macho_uint32_to_bytes(200)

    header = header + macho_uint32_to_bytes(0x200085)

    header = header + macho_uint32_to_bytes(0)

    return header
}

func (b* macho_builder) generate_arm64_binary() string {

    binary := b.write_mach_header("arm64")

    return binary
}

func (b* macho_builder) generate_x86_64_binary() string {

    binary := b.write_mach_header("x86_64")

    return binary
}

func (b* macho_builder) generate_macho() string {
    if b.arch == "arm64" {
        return b.generate_arm64_binary()
    } else if b.arch == "x86_64" {
        return b.generate_x86_64_binary()
    }
    return ""
}