package src.cmd.link.internal.ld

import (
	"src/fmt"
	"src/os"
	"src/testing"
)

func test_elf_object_parsing(t testing.T) {

	obj := NewELFObject(0x3e) 

	data := make(u8[], 100)
	for i := i32(0); i < 100; i += 1 {
		data[i] = u8(i)
	}

	text_idx := obj.add_section(".text", 1, 0x6, data)
	if text_idx != 0 {
		t.errorf("Expected section index 0, got %d", text_idx)
	}

	sym := SymbolEntry{
		Name: "main",
		Value: 0,
		Size: 100,
		Binding: 1,    
		Type: 2,       
		Visibility: 0, 
		SectionIndex: 0,
		IsGlobal: true,
		IsWeak: false,
	}

	sym_idx := obj.add_symbol(sym)
	if sym_idx != 0 {
		t.errorf("Expected symbol index 0, got %d", sym_idx)
	}

	fmt.printf("ELF object creation test passed!\n")
}

func test_symbol_resolution(t testing.T) {
	sm := NewSymbolManager()

	global_sym := SymbolEntry{
		Name: "global_func",
		Value: 0x1000,
		Size: 50,
		Binding: 1,    
		Type: 2,       
		Visibility: 0, 
		SectionIndex: 0,
		IsGlobal: true,
		IsWeak: false,
	}

	err := sm.add_symbol(global_sym)
	if err != nil {
		t.errorf("Failed to add global symbol: %v", err)
	}

	weak_sym := SymbolEntry{
		Name: "global_func",
		Value: 0x2000,
		Size: 30,
		Binding: 2,    
		Type: 2,       
		Visibility: 0, 
		SectionIndex: 0,
		IsGlobal: false,
		IsWeak: true,
	}

	err = sm.add_symbol(weak_sym)
	if err != nil {
		t.errorf("Failed to add weak symbol: %v", err)
	}

	resolved, found := sm.lookup_symbol("global_func")
	if !found {
		t.errorf("Symbol not found")
	}

	if resolved.Value != 0x1000 {
		t.errorf("Expected value 0x1000, got 0x%x", resolved.Value)
	}

	fmt.printf("Symbol resolution test passed!\n")
}

func test_relocations(t testing.T) {
	rp := NewRelocProcessor()

	sym := SymbolEntry{
		Name: "printf",
		Value: 0x1000,
		Size: 50,
		Binding: 1,    
		Type: 2,       
		Visibility: 0, 
		SectionIndex: 0,
		IsGlobal: true,
		IsWeak: false,
	}

	sym_idx := rp.add_symbol(sym)

	reloc := Relocation{
		Offset: 0x1000,
		Type: RELOC_GOT,
		SymIndex: sym_idx,
		Addend: 0,
	}

	rp.add_relocation(reloc)

	err := rp.validate_relocations()
	if err != nil {
		t.errorf("Validation failed: %v", err)
	}

	if len(rp.Relocs) != 1 {
		t.errorf("Expected 1 relocation, got %d", len(rp.Relocs))
	}

	fmt.printf("Relocation test passed!\n")
}

func test_got_allocation(t testing.T) {
	gm := NewGOTManager()

	addr1 := gm.add_entry(0, RELOC_GLOB_DAT)
	if addr1 != 0 {
		t.errorf("Expected first GOT address 0, got %d", addr1)
	}

	addr2 := gm.add_entry(1, RELOC_GLOB_DAT)
	if addr2 != 8 {
		t.errorf("Expected second GOT address 8, got %d", addr2)
	}

	gm.resolve_entry(addr1, 0x1000)
	gm.resolve_entry(addr2, 0x2000)

	data := gm.generate_gotdata()
	if len(data) != 16 {
		t.errorf("Expected GOT data size 16, got %d", len(data))
	}

	fmt.printf("GOT allocation test passed!\n")
}

func test_plt_generation(t testing.T) {
	pm := NewPLTManager()

	addr1 := pm.add_entry(0, 0x3000)
	if addr1 != 0 {
		t.errorf("Expected first PLT address 0, got %d", addr1)
	}

	addr2 := pm.add_entry(1, 0x3008)
	if addr2 != 16 {
		t.errorf("Expected second PLT address 16, got %d", addr2)
	}

	code := pm.generate_pltcode()
	if len(code) != 32 {
		t.errorf("Expected PLT code size 32, got %d", len(code))
	}

	fmt.printf("PLT generation test passed!\n")
}

func test_tls_allocation(t testing.T) {
	tm := NewTLSManager()

	off1 := tm.add_variable("errno", 4, 4)
	if off1 != 0 {
		t.errorf("Expected first TLS offset 0, got %d", off1)
	}

	off2 := tm.add_variable("thread_id", 8, 8)

	if off2 != 8 {
		t.errorf("Expected second TLS offset 8, got %d", off2)
	}

	data := tm.generate_tlsdata()
	if i64(len(data)) != tm.get_tlssize() {
		t.errorf("TLS data size mismatch")
	}

	fmt.printf("TLS allocation test passed!\n")
}

func test_build_id_generation(t testing.T) {
	bm := NewBuildIDManager(BID_SHA256)

	data := u8[]{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
	bm.generate_build_id(data)

	bid_str := bm.get_build_idstring()
	if len(bid_str) != 64 { 
		t.errorf("Expected Build-ID string length 64, got %d", len(bid_str))
	}

	note_data := bm.generate_note_section()
	if len(note_data) == 0 {
		t.errorf("Note section data is empty")
	}

	fmt.printf("Build-ID generation test passed: %s\n", bid_str)
}

func test_production_linker_workflow(t testing.T) {

	config := LinkerConfig{
		Format: FORMAT_ELF,
		Machine: 0x3e, 
		OutputFile: "output.o",
		InputFiles: make(string[], 0),
		SymbolStripMode: 0,
		OptimizeLevel: 2,
		GenerateDebugInfo: true,
		GenerateBuildID: true,
		EnableRelro: true,
		EnableNow: false,
		PIE: false,
		PIELibrary: true,
	}

	linker := NewProductionLinker(config)

	obj := NewELFObject(0x3e)

	code_data := u8[]{0x55, 0x48, 0x89, 0xe5}
	obj.add_section(".text", 1, 0x6, code_data)

	sym := SymbolEntry{
		Name: "main",
		Value: 0,
		Size: 4,
		Binding: 1,
		Type: 2,
		Visibility: 0,
		SectionIndex: 0,
		IsGlobal: true,
		IsWeak: false,
	}
	obj.add_symbol(sym)

	linker.ElfObjects = append(linker.ElfObjects, obj)

	err := linker.merge_symbols()
	if err != nil {
		t.errorf("Symbol merge failed: %v", err)
	}

	err = linker.validate()
	if err != nil {
		t.errorf("Validation failed: %v", err)
	}

	fmt.printf("Production linker workflow test passed!\n")
}

func example_complete_linker_usage() {
	fmt.println("=== S Language Production Linker Example ===")
	fmt.println()

	config := LinkerConfig{
		Format: FORMAT_ELF,
		Machine: 0x3e,
		OutputFile: "program",
		InputFiles: string[]{"object1.o", "object2.o"},
		GenerateDebugInfo: true,
		GenerateBuildID: true,
		EnableRelro: true,
		PIE: true,
	}

	linker := NewProductionLinker(config)

	fmt.println("Linker Configuration:")
	fmt.printf("  Format: ELF\n")
	fmt.printf("  Machine: x86-64\n")
	fmt.printf("  Output: %s\n", config.OutputFile)
	fmt.printf("  Debug Info: %v\n", config.GenerateDebugInfo)
	fmt.printf("  Build-ID: %v\n", config.GenerateBuildID)
	fmt.println()

	fmt.println("Creating sample ELF objects...")

	obj1 := NewELFObject(0x3e)
	code_data := u8[]{
		0x55, 0x48, 0x89, 0xe5, 
		0xc9, 0xc3,              
	}
	obj1.add_section(".text", 1, 0x6, code_data)

	sym1 := SymbolEntry{
		Name: "hello",
		Value: 0,
		Size: 6,
		Binding: 1,
		Type: 2,
		Visibility: 0,
		SectionIndex: 0,
		IsGlobal: true,
		IsWeak: false,
	}
	obj1.add_symbol(sym1)

	linker.ElfObjects = append(linker.ElfObjects, obj1)

	fmt.println("Objects loaded")
	fmt.println()

	fmt.println("Processing symbols and relocations...")
	linker.merge_symbols()
	linker.process_relocations()
	fmt.println()

	fmt.println("Generating output...")
	fmt.printf("  GOT entries: %d\n", len(linker.GotManager.Entries))
	fmt.printf("  PLT entries: %d\n", len(linker.PltManager.Entries))
	fmt.printf("  TLS size: %d bytes\n", linker.TlsManager.get_tls_size())
	fmt.println()

	if config.GenerateBuildID {
		fmt.println("Generating Build-ID...")
		output_data := u8[]{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
		linker.BuildIDManager.generate_build_id(output_data)
		fmt.printf("  Build-ID: %s\n", linker.BuildIDManager.get_build_id_string())
	}
	fmt.println()

	fmt.println("=== Linking Complete ===")
}