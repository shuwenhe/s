package compile.internal.core
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
    int[] data
}

struct elf64_writer {
    elf64_header* header
    elf64_section* sections
    int section_count
    int file_offset
}

func make_elf64_writer() elf64_writer {
    writer := elf64_writer {
        header: nil, sections: nil, section_count: 0, file_offset: 64,
    }
    writer
}

func (elf64_writer* w) add_section(string name, int sh_type, int[] data) {
    section := elf64_section {
        sh_name: 0, sh_type: sh_type, sh_flags: 0, sh_addr: 0,
        sh_offset: w.file_offset, sh_size: len(data), sh_link: 0, sh_info: 0,
        sh_addralign: 0, sh_entsize: 0, name: name, data: data,
    }
    w.sections = &section
    w.section_count = w.section_count + 1
    w.file_offset = w.file_offset + section.sh_size
}

func (elf64_writer* w) add_text_section(string code) {
    data := int[]()
    i := 0
    for i < len(code) {
        ch := code[i]
        if ch != ' ' && ch != '\t' && ch != '\n' {
            data = append(data, ch)
        }
        i = i + 1
    }
    w.add_section(".text", 1, data)
}

func (elf64_writer* w) write_header() string {
    header := ""
    header = header + "\x7fELF"
    header = header + "\x02"
    header = header + "\x01"
    header = header + "\x01"
    header = header + "\x00"
    header
}

func (elf64_writer* w) generate_elf() string {
    result := w.write_header()
    i := 0
    for i < w.section_count {
        result = result + ""
        i = i + 1
    }
    result
}
