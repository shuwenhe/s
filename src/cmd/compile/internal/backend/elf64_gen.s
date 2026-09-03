package backend
struct elf64_header {
    string magic
    int ei_class
    int ei_data
    int ei_version
    int ei_osabi
    int e_type
    int e_machine
    int e_version
    int e_entry
    int e_phoff
    int e_shoff
    int e_flags
    int e_ehsize
    int e_phentsize
    int e_phnum
    int e_shentsize
    int e_shnum
    int e_shstrndx
}

struct elf64_section {
    int sh_name
    int sh_type
    int sh_flags
    int sh_addr
    int sh_offset
    int sh_size
    int sh_link
    int sh_info
    int sh_addralign
    int sh_entsize
    string name
    []int data
}

struct elf64_writer {
    elf64_header* header
    elf64_section* sections
    int section_count
    int file_offset
}

func make_elf64_writer() elf64_writer {
    writer: elf64_writer
    writer.header = nil
    writer.sections = nil
    writer.section_count = 0
    writer.file_offset = 64
    writer
}

func (w* elf64_writer) add_section(string name, int sh_type, []int data) {
    section: elf64_section
    section.name = name
    section.sh_type = sh_type
    section.sh_offset = w.file_offset
    section.sh_size = len(data)
    section.data = data
    w.sections = &section
    w.section_count = w.section_count + 1
    w.file_offset = w.file_offset + section.sh_size
}

func (w* elf64_writer) add_text_section(string code) {
    data := []int()
    i := 0
    while i < len(code) {
        ch := code[i]
        if ch != ' ' && ch != '\t' && ch != '\n' {
            data = append(data, ch)
        }
        i = i + 1
    }
    w.add_section(".text", 1, data)
}

func (w* elf64_writer) write_header() string {
    header := ""
    header = header + "\x7fELF"
    header = header + "\x02"
    header = header + "\x01"
    header = header + "\x01"
    header = header + "\x00"
    header
}

func (w* elf64_writer) generate_elf() string {
    result := w.write_header()
    i := 0
    while i < w.section_count {
        result = result + ""
        i = i + 1
    }
    result
}
