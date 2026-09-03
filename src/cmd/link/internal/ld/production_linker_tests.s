package src.cmd.link.internal.ld

import (
	"src/fmt"
	"src/os"
	"src/testing"
)

func TestELFObjectParsing(t testing.T) {
	
	obj := NewELFObject(0x3e) 

	
	data := make([]u8, 100)
	for i := i32(0); i < 100; i += 1 {
		data[i] = u8(i)
	}

	textIdx := obj.AddSection(".text", 1, 0x6, data)
	if textIdx != 0 {
		t.Errorf("Expected section index 0, got %d", textIdx)
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

	symIdx := obj.AddSymbol(sym)
	if symIdx != 0 {
		t.Errorf("Expected symbol index 0, got %d", symIdx)
	}

	fmt.Printf("ELF object creation test passed!\n")
}

func TestSymbolResolution(t testing.T) {
	sm := NewSymbolManager()

	
	globalSym := SymbolEntry{
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

	err := sm.AddSymbol(globalSym)
	if err != nil {
		t.Errorf("Failed to add global symbol: %v", err)
	}

	
	weakSym := SymbolEntry{
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

	err = sm.AddSymbol(weakSym)
	if err != nil {
		t.Errorf("Failed to add weak symbol: %v", err)
	}

	
	resolved, found := sm.LookupSymbol("global_func")
	if !found {
		t.Errorf("Symbol not found")
	}

	if resolved.Value != 0x1000 {
		t.Errorf("Expected value 0x1000, got 0x%x", resolved.Value)
	}

	fmt.Printf("Symbol resolution test passed!\n")
}

func TestRelocations(t testing.T) {
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

	symIdx := rp.AddSymbol(sym)

	
	reloc := Relocation{
		Offset: 0x1000,
		Type: RELOC_GOT,
		SymIndex: symIdx,
		Addend: 0,
	}

	rp.AddRelocation(reloc)

	
	err := rp.ValidateRelocations()
	if err != nil {
		t.Errorf("Validation failed: %v", err)
	}

	if len(rp.Relocs) != 1 {
		t.Errorf("Expected 1 relocation, got %d", len(rp.Relocs))
	}

	fmt.Printf("Relocation test passed!\n")
}

func TestGOTAllocation(t testing.T) {
	gm := NewGOTManager()

	
	addr1 := gm.AddEntry(0, RELOC_GLOB_DAT)
	if addr1 != 0 {
		t.Errorf("Expected first GOT address 0, got %d", addr1)
	}

	addr2 := gm.AddEntry(1, RELOC_GLOB_DAT)
	if addr2 != 8 {
		t.Errorf("Expected second GOT address 8, got %d", addr2)
	}

	
	gm.ResolveEntry(addr1, 0x1000)
	gm.ResolveEntry(addr2, 0x2000)

	
	data := gm.GenerateGOTData()
	if len(data) != 16 {
		t.Errorf("Expected GOT data size 16, got %d", len(data))
	}

	fmt.Printf("GOT allocation test passed!\n")
}

func TestPLTGeneration(t testing.T) {
	pm := NewPLTManager()

	
	addr1 := pm.AddEntry(0, 0x3000)
	if addr1 != 0 {
		t.Errorf("Expected first PLT address 0, got %d", addr1)
	}

	addr2 := pm.AddEntry(1, 0x3008)
	if addr2 != 16 {
		t.Errorf("Expected second PLT address 16, got %d", addr2)
	}

	
	code := pm.GeneratePLTCode()
	if len(code) != 32 {
		t.Errorf("Expected PLT code size 32, got %d", len(code))
	}

	fmt.Printf("PLT generation test passed!\n")
}

func TestTLSAllocation(t testing.T) {
	tm := NewTLSManager()

	
	off1 := tm.AddVariable("errno", 4, 4)
	if off1 != 0 {
		t.Errorf("Expected first TLS offset 0, got %d", off1)
	}

	off2 := tm.AddVariable("thread_id", 8, 8)
	
	if off2 != 8 {
		t.Errorf("Expected second TLS offset 8, got %d", off2)
	}

	
	data := tm.GenerateTLSData()
	if i64(len(data)) != tm.GetTLSSize() {
		t.Errorf("TLS data size mismatch")
	}

	fmt.Printf("TLS allocation test passed!\n")
}

func TestBuildIDGeneration(t testing.T) {
	bm := NewBuildIDManager(BID_SHA256)

	
	data := []u8{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
	bm.GenerateBuildID(data)

	
	bidStr := bm.GetBuildIDString()
	if len(bidStr) != 64 { 
		t.Errorf("Expected Build-ID string length 64, got %d", len(bidStr))
	}

	
	noteData := bm.GenerateNoteSection()
	if len(noteData) == 0 {
		t.Errorf("Note section data is empty")
	}

	fmt.Printf("Build-ID generation test passed: %s\n", bidStr)
}

func TestProductionLinkerWorkflow(t testing.T) {
	
	config := LinkerConfig{
		Format: FORMAT_ELF,
		Machine: 0x3e, 
		OutputFile: "output.o",
		InputFiles: make([]string, 0),
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

	
	codeData := []u8{0x55, 0x48, 0x89, 0xe5} 
	obj.AddSection(".text", 1, 0x6, codeData)

	
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
	obj.AddSymbol(sym)

	
	linker.ElfObjects = append(linker.ElfObjects, obj)

	
	err := linker.MergeSymbols()
	if err != nil {
		t.Errorf("Symbol merge failed: %v", err)
	}

	
	err = linker.Validate()
	if err != nil {
		t.Errorf("Validation failed: %v", err)
	}

	fmt.Printf("Production linker workflow test passed!\n")
}

func ExampleCompleteLinkerUsage() {
	fmt.Println("=== S Language Production Linker Example ===")
	fmt.Println()

	
	config := LinkerConfig{
		Format: FORMAT_ELF,
		Machine: 0x3e,
		OutputFile: "program",
		InputFiles: []string{"object1.o", "object2.o"},
		GenerateDebugInfo: true,
		GenerateBuildID: true,
		EnableRelro: true,
		PIE: true,
	}

	
	linker := NewProductionLinker(config)

	fmt.Println("Linker Configuration:")
	fmt.Printf("  Format: ELF\n")
	fmt.Printf("  Machine: x86-64\n")
	fmt.Printf("  Output: %s\n", config.OutputFile)
	fmt.Printf("  Debug Info: %v\n", config.GenerateDebugInfo)
	fmt.Printf("  Build-ID: %v\n", config.GenerateBuildID)
	fmt.Println()

	
	fmt.Println("Creating sample ELF objects...")

	obj1 := NewELFObject(0x3e)
	codeData := []u8{
		0x55, 0x48, 0x89, 0xe5, 
		0xc9, 0xc3,              
	}
	obj1.AddSection(".text", 1, 0x6, codeData)

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
	obj1.AddSymbol(sym1)

	linker.ElfObjects = append(linker.ElfObjects, obj1)

	fmt.Println("Objects loaded")
	fmt.Println()

	
	fmt.Println("Processing symbols and relocations...")
	linker.MergeSymbols()
	linker.ProcessRelocations()
	fmt.Println()

	
	fmt.Println("Generating output...")
	fmt.Printf("  GOT entries: %d\n", len(linker.GotManager.Entries))
	fmt.Printf("  PLT entries: %d\n", len(linker.PltManager.Entries))
	fmt.Printf("  TLS size: %d bytes\n", linker.TlsManager.GetTLSSize())
	fmt.Println()

	
	if config.GenerateBuildID {
		fmt.Println("Generating Build-ID...")
		outputData := []u8{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
		linker.BuildIDManager.GenerateBuildID(outputData)
		fmt.Printf("  Build-ID: %s\n", linker.BuildIDManager.GetBuildIDString())
	}
	fmt.Println()

	fmt.Println("=== Linking Complete ===")
}
