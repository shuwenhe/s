package backend
struct assembly_generator {
    buffer: string
    current_section: string
    symbols: string[]
}

func new_assembly_generator() assembly_generator {
    gen: assembly_generator
    gen.buffer = ""
    gen.current_section = ""
    gen.symbols = make(string[])
    gen
}

func (assembly_generator* ag) emit_section( section string) {
    if ag.current_section != section {
        ag.buffer = ag.buffer + ".section\t." + section + "\n"
        ag.current_section = section
    }
}

func (assembly_generator* ag) emit_global_symbol( name string) {
    ag.buffer = ag.buffer + ".globl\t" + name + "\n"
    ag.buffer = ag.buffer + ".type\t" + name + ", @function\n"
    ag.symbols = append(ag.symbols, name)
}

func (assembly_generator* ag) emit_function_start( name string) {
    ag.emit_section("text")
    ag.buffer = ag.buffer + name + ":\n"
}

func (assembly_generator* ag) emit_instruction( inst string) {
    ag.buffer = ag.buffer + "\t" + inst + "\n"
}

func (assembly_generator* ag) emit_label( label string) {
    ag.buffer = ag.buffer + label + ":\n"
}

func (assembly_generator* ag) emit_data( name string, value string) {
    ag.emit_section("data")
    ag.buffer = ag.buffer + name + ":\n"
    ag.buffer = ag.buffer + "\t.quad\t" + value + "\n"
}

func (assembly_generator* ag) emit_string_literal( label string, value string) {
    ag.emit_section("rodata")
    ag.buffer = ag.buffer + label + ":\n"
    ag.buffer = ag.buffer + "\t.string\t\"" + value + "\"\n"
}

func (assembly_generator* ag) get_output() string {
    ag.buffer
}
