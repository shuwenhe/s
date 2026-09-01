package backend

struct assembler {
    string asm_text
    string[] instructions
    string[] symbols
}

func make_assembler(string asm_text) assembler {
    asm: assembler
    asm.asm_text = asm_text
    asm.instructions = string[]()
    asm.symbols = string[]()
    asm
}

func (a* assembler) parse_asm() {
    i := 0
    current_line := ""
    
    while i < len(a.asm_text) {
        ch := a.asm_text[i]
        
        if ch == '\n' {
            if current_line != "" {
                a.instructions = append(a.instructions, current_line)
            }
            current_line = ""
        } else {
            current_line = current_line + ch
        }
        
        i = i + 1
    }
    
    if current_line != "" {
        a.instructions = append(a.instructions, current_line)
    }
}

func (a* assembler) extract_symbols() {
    i := 0
    while i < len(a.instructions) {
        instr := a.instructions[i]
        
        if instr[len(instr) - 1] == ':' {
            symbol := instr[0 : len(instr) - 1]
            a.symbols = append(a.symbols, symbol)
        }
        
        i = i + 1
    }
}

func (a* assembler) build_symbol_table() {
    a.parse_asm()
    a.extract_symbols()
}

func (a* assembler) assemble_to_bytecode() int[] {
    bytecode := int[]()
    
    i := 0
    while i < len(a.instructions) {
        instr := a.instructions[i]
        
        bytecode = append(bytecode, i)
        
        i = i + 1
    }
    
    bytecode
}
