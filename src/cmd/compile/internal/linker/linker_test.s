package linker

struct linker_test_result {
    test_name string
    passed int
    error_message string
}

func test_elf64_header_creation() linker_test_result {
    header := elf64_header_new()
    
    result := linker_test_result {
        test_name: "ELF64 Header Creation",
        passed: 1,
        error_message: ""
    }
    
    if header.magic != 0x7f454c46 {
        result.passed = 0
        result.error_message = "Invalid magic number"
        return result
    }
    
    if header.class != elfclass64 {
        result.passed = 0
        result.error_message = "Invalid class"
        return result
    }
    
    if header.machine != em_x86_64 {
        result.passed = 0
        result.error_message = "Invalid machine type"
        return result
    }
    
    result
}

func test_elf64_section_creation() linker_test_result {
    section := elf64_section_new(1, sht_progbits, shf_alloc | shf_execinstr)
    
    result := linker_test_result {
        test_name: "ELF64 Section Creation",
        passed: 1,
        error_message: ""
    }
    
    if section.type != sht_progbits {
        result.passed = 0
        result.error_message = "Invalid section type"
        return result
    }
    
    if section.size != 0 {
        result.passed = 0
        result.error_message = "Initial size should be 0"
        return result
    }
    
    result
}

func test_elf64_symbol_creation() linker_test_result {
    symbol := elf64_symbol_new(0, stb_global, stt_func, 1)
    
    result := linker_test_result {
        test_name: "ELF64 Symbol Creation",
        passed: 1,
        error_message: ""
    }
    
    if symbol.shndx != 1 {
        result.passed = 0
        result.error_message = "Invalid section index"
        return result
    }
    
    bind := (symbol.info >> 4) & 0xf
    if bind != stb_global {
        result.passed = 0
        result.error_message = "Invalid binding"
        return result
    }
    
    result
}

func test_relocation_creation() linker_test_result {
    reloc := elf64_relocation_new(0x1000, r_x86_64_64, 5)
    
    result := linker_test_result {
        test_name: "Relocation Creation",
        passed: 1,
        error_message: ""
    }
    
    if reloc.offset != 0x1000 {
        result.passed = 0
        result.error_message = "Invalid offset"
        return result
    }
    
    sym_idx := (reloc.info >> 32) & 0xffffffff
    if sym_idx != 5 {
        result.passed = 0
        result.error_message = "Invalid symbol index"
        return result
    }
    
    result
}

func test_relocation_resolve_64() linker_test_result {
    ctx := relocation_context {
        section_index: 0,
        symbol_index: 0,
        relocation_type: r_x86_64_64,
        offset: 0,
        addend: 0x100
    }
    
    result_val := relocation_resolve(&ctx, 0x1000, 0x400000)
    
    result := linker_test_result {
        test_name: "Relocation Resolve R_X86_64_64",
        passed: 1,
        error_message: ""
    }
    
    if result_val.success == 0 {
        result.passed = 0
        result.error_message = "Resolution failed"
        return result
    }
    
    expected := 0x1000 + 0x400000 + 0x100
    if result_val.resolved_address != expected {
        result.passed = 0
        result.error_message = "Wrong resolved address"
        return result
    }
    
    result
}

func test_relocation_resolve_pc32() linker_test_result {
    ctx := relocation_context {
        section_index: 0,
        symbol_index: 0,
        relocation_type: r_x86_64_pc32,
        offset: 0x500,
        addend: 0
    }
    
    result_val := relocation_resolve(&ctx, 0x1000, 0x400000)
    
    result := linker_test_result {
        test_name: "Relocation Resolve R_X86_64_PC32",
        passed: 1,
        error_message: ""
    }
    
    if result_val.success == 0 {
        result.passed = 0
        result.error_message = "Resolution failed"
        return result
    }
    
    pc := 0x400000 + 0x500
    expected := (0x1000 + 0x400000) - pc
    if result_val.resolved_address != expected {
        result.passed = 0
        result.error_message = "Wrong resolved address"
        return result
    }
    
    result
}

func test_linker_context_creation() linker_test_result {
    ctx := linker_context_new("output.o")
    
    result := linker_test_result {
        test_name: "Linker Context Creation",
        passed: 1,
        error_message: ""
    }
    
    if ctx.output_file != "output.o" {
        result.passed = 0
        result.error_message = "Invalid output file"
        return result
    }
    
    if ctx.object_files.len() != 0 {
        result.passed = 0
        result.error_message = "Should start with no object files"
        return result
    }
    
    result
}

func test_linker_add_object_file() linker_test_result {
    ctx := linker_context_new("output.o")
    linker_add_object_file(&ctx, "test.o")
    
    result := linker_test_result {
        test_name: "Linker Add Object File",
        passed: 1,
        error_message: ""
    }
    
    if ctx.object_files.len() != 1 {
        result.passed = 0
        result.error_message = "Failed to add object file"
        return result
    }
    
    if ctx.object_files[0].filename != "test.o" {
        result.passed = 0
        result.error_message = "Wrong filename"
        return result
    }
    
    result
}

func run_linker_tests() int {
    tests := linker_test_result[]()
    
    tests = append(tests, test_elf64_header_creation())
    tests = append(tests, test_elf64_section_creation())
    tests = append(tests, test_elf64_symbol_creation())
    tests = append(tests, test_relocation_creation())
    tests = append(tests, test_relocation_resolve_64())
    tests = append(tests, test_relocation_resolve_pc32())
    tests = append(tests, test_linker_context_creation())
    tests = append(tests, test_linker_add_object_file())
    
    passed := 0
    failed := 0
    
    for i := 0; i < tests.len(); i = i + 1 {
        test := tests[i]
        if test.passed != 0 {
            passed = passed + 1
        } else {
            failed = failed + 1
        }
    }
    
    failed
}
