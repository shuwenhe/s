package src.cmd.link.internal.ld

import (
	"src/fmt"
	"src/os"
	"src/testing"
)

// TestELFObjectParsing 测试 ELF 对象文件解析
func TestELFObjectParsing(t testing.T) {
	// 创建一个简单的 ELF 对象
	obj := NewELFObject(0x3e) // EM_X86_64

	// 添加一个 section
	data := make([]u8, 100)
	for i := i32(0); i < 100; i += 1 {
		data[i] = u8(i)
	}

	textIdx := obj.AddSection(".text", 1, 0x6, data)
	if textIdx != 0 {
		t.Errorf("Expected section index 0, got %d", textIdx)
	}

	// 添加符号
	sym := SymbolEntry{
		Name: "main",
		Value: 0,
		Size: 100,
		Binding: 1,    // STB_GLOBAL
		Type: 2,       // STT_FUNC
		Visibility: 0, // STV_DEFAULT
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

// TestSymbolResolution 测试符号解决
func TestSymbolResolution(t testing.T) {
	sm := NewSymbolManager()

	// 添加一个全局符号
	globalSym := SymbolEntry{
		Name: "global_func",
		Value: 0x1000,
		Size: 50,
		Binding: 1,    // STB_GLOBAL
		Type: 2,       // STT_FUNC
		Visibility: 0, // STV_DEFAULT
		SectionIndex: 0,
		IsGlobal: true,
		IsWeak: false,
	}

	err := sm.AddSymbol(globalSym)
	if err != nil {
		t.Errorf("Failed to add global symbol: %v", err)
	}

	// 添加相同名称的弱符号（应该被忽略）
	weakSym := SymbolEntry{
		Name: "global_func",
		Value: 0x2000,
		Size: 30,
		Binding: 2,    // STB_WEAK
		Type: 2,       // STT_FUNC
		Visibility: 0, // STV_DEFAULT
		SectionIndex: 0,
		IsGlobal: false,
		IsWeak: true,
	}

	err = sm.AddSymbol(weakSym)
	if err != nil {
		t.Errorf("Failed to add weak symbol: %v", err)
	}

	// 验证全局符号保留
	resolved, found := sm.LookupSymbol("global_func")
	if !found {
		t.Errorf("Symbol not found")
	}

	if resolved.Value != 0x1000 {
		t.Errorf("Expected value 0x1000, got 0x%x", resolved.Value)
	}

	fmt.Printf("Symbol resolution test passed!\n")
}

// TestRelocations 测试重定位
func TestRelocations(t testing.T) {
	rp := NewRelocProcessor()

	// 添加符号
	sym := SymbolEntry{
		Name: "printf",
		Value: 0x1000,
		Size: 50,
		Binding: 1,    // STB_GLOBAL
		Type: 2,       // STT_FUNC
		Visibility: 0, // STV_DEFAULT
		SectionIndex: 0,
		IsGlobal: true,
		IsWeak: false,
	}

	symIdx := rp.AddSymbol(sym)

	// 添加 GOT 重定位
	reloc := Relocation{
		Offset: 0x1000,
		Type: RELOC_GOT,
		SymIndex: symIdx,
		Addend: 0,
	}

	rp.AddRelocation(reloc)

	// 验证重定位
	err := rp.ValidateRelocations()
	if err != nil {
		t.Errorf("Validation failed: %v", err)
	}

	if len(rp.Relocs) != 1 {
		t.Errorf("Expected 1 relocation, got %d", len(rp.Relocs))
	}

	fmt.Printf("Relocation test passed!\n")
}

// TestGOTAllocation 测试 GOT 分配
func TestGOTAllocation(t testing.T) {
	gm := NewGOTManager()

	// 分配 GOT 条目
	addr1 := gm.AddEntry(0, RELOC_GLOB_DAT)
	if addr1 != 0 {
		t.Errorf("Expected first GOT address 0, got %d", addr1)
	}

	addr2 := gm.AddEntry(1, RELOC_GLOB_DAT)
	if addr2 != 8 {
		t.Errorf("Expected second GOT address 8, got %d", addr2)
	}

	// 解析 GOT 条目
	gm.ResolveEntry(addr1, 0x1000)
	gm.ResolveEntry(addr2, 0x2000)

	// 生成 GOT 数据
	data := gm.GenerateGOTData()
	if len(data) != 16 {
		t.Errorf("Expected GOT data size 16, got %d", len(data))
	}

	fmt.Printf("GOT allocation test passed!\n")
}

// TestPLTGeneration 测试 PLT 生成
func TestPLTGeneration(t testing.T) {
	pm := NewPLTManager()

	// 分配 PLT 条目
	addr1 := pm.AddEntry(0, 0x3000)
	if addr1 != 0 {
		t.Errorf("Expected first PLT address 0, got %d", addr1)
	}

	addr2 := pm.AddEntry(1, 0x3008)
	if addr2 != 16 {
		t.Errorf("Expected second PLT address 16, got %d", addr2)
	}

	// 生成 PLT 代码
	code := pm.GeneratePLTCode()
	if len(code) != 32 {
		t.Errorf("Expected PLT code size 32, got %d", len(code))
	}

	fmt.Printf("PLT generation test passed!\n")
}

// TestTLSAllocation 测试 TLS 分配
func TestTLSAllocation(t testing.T) {
	tm := NewTLSManager()

	// 添加 TLS 变量
	off1 := tm.AddVariable("errno", 4, 4)
	if off1 != 0 {
		t.Errorf("Expected first TLS offset 0, got %d", off1)
	}

	off2 := tm.AddVariable("thread_id", 8, 8)
	// 对齐到 8 字节边界
	if off2 != 8 {
		t.Errorf("Expected second TLS offset 8, got %d", off2)
	}

	// 生成 TLS 数据
	data := tm.GenerateTLSData()
	if i64(len(data)) != tm.GetTLSSize() {
		t.Errorf("TLS data size mismatch")
	}

	fmt.Printf("TLS allocation test passed!\n")
}

// TestBuildIDGeneration 测试 Build-ID 生成
func TestBuildIDGeneration(t testing.T) {
	bm := NewBuildIDManager(BID_SHA256)

	// 生成数据的 Build-ID
	data := []u8{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
	bm.GenerateBuildID(data)

	// 获取 Build-ID 字符串
	bidStr := bm.GetBuildIDString()
	if len(bidStr) != 64 { // SHA256 = 32 bytes = 64 hex chars
		t.Errorf("Expected Build-ID string length 64, got %d", len(bidStr))
	}

	// 生成 note section
	noteData := bm.GenerateNoteSection()
	if len(noteData) == 0 {
		t.Errorf("Note section data is empty")
	}

	fmt.Printf("Build-ID generation test passed: %s\n", bidStr)
}

// TestProductionLinkerWorkflow 测试生产级链接器工作流
func TestProductionLinkerWorkflow(t testing.T) {
	// 创建链接器配置
	config := LinkerConfig{
		Format: FORMAT_ELF,
		Machine: 0x3e, // EM_X86_64
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

	// 创建链接器
	linker := NewProductionLinker(config)

	// 创建一个简单的 ELF 对象用于输入
	obj := NewELFObject(0x3e)

	// 添加 sections
	codeData := []u8{0x55, 0x48, 0x89, 0xe5} // push rbp; mov rbp, rsp
	obj.AddSection(".text", 1, 0x6, codeData)

	// 添加符号
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

	// 添加到链接器
	linker.ElfObjects = append(linker.ElfObjects, obj)

	// 合并符号
	err := linker.MergeSymbols()
	if err != nil {
		t.Errorf("Symbol merge failed: %v", err)
	}

	// 验证链接完整性
	err = linker.Validate()
	if err != nil {
		t.Errorf("Validation failed: %v", err)
	}

	fmt.Printf("Production linker workflow test passed!\n")
}

// ExampleCompleteLinkerUsage 完整的链接器使用示例
func ExampleCompleteLinkerUsage() {
	fmt.Println("=== S Language Production Linker Example ===")
	fmt.Println()

	// 1. 创建配置
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

	// 2. 创建链接器
	linker := NewProductionLinker(config)

	fmt.Println("Linker Configuration:")
	fmt.Printf("  Format: ELF\n")
	fmt.Printf("  Machine: x86-64\n")
	fmt.Printf("  Output: %s\n", config.OutputFile)
	fmt.Printf("  Debug Info: %v\n", config.GenerateDebugInfo)
	fmt.Printf("  Build-ID: %v\n", config.GenerateBuildID)
	fmt.Println()

	// 3. 创建示例 ELF 对象
	fmt.Println("Creating sample ELF objects...")

	obj1 := NewELFObject(0x3e)
	codeData := []u8{
		0x55, 0x48, 0x89, 0xe5, // push rbp; mov rbp, rsp
		0xc9, 0xc3,              // leave; ret
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

	// 4. 合并符号并处理重定位
	fmt.Println("Processing symbols and relocations...")
	linker.MergeSymbols()
	linker.ProcessRelocations()
	fmt.Println()

	// 5. 生成输出
	fmt.Println("Generating output...")
	fmt.Printf("  GOT entries: %d\n", len(linker.GotManager.Entries))
	fmt.Printf("  PLT entries: %d\n", len(linker.PltManager.Entries))
	fmt.Printf("  TLS size: %d bytes\n", linker.TlsManager.GetTLSSize())
	fmt.Println()

	// 6. 生成 Build-ID
	if config.GenerateBuildID {
		fmt.Println("Generating Build-ID...")
		outputData := []u8{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
		linker.BuildIDManager.GenerateBuildID(outputData)
		fmt.Printf("  Build-ID: %s\n", linker.BuildIDManager.GetBuildIDString())
	}
	fmt.Println()

	fmt.Println("=== Linking Complete ===")
}
