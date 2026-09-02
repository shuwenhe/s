package src.cmd.link.internal.ld

import (
	"src/encoding/binary"
	"src/os"
	"src/fmt"
)

// reloc_type 重定位类型定义
enum reloc_type {
	RELOC_NONE = 0
	RELOC_ABSOLUTE = 1
	RELOC_PC_RELATIVE = 2
	RELOC_GOT = 3
	RELOC_PLT = 4
	RELOC_TLS_LE = 5
	RELOC_TLS_IE = 6
	RELOC_TLS_LD = 7
	RELOC_COPY = 8
	RELOC_GLOB_DAT = 9
	RELOC_JUMP_SLOT = 10
	RELOC_RELATIVE = 11
	RELOC_TLSDESC = 12
	RELOC_IRELATIVE = 13
}

// relocation 表示一个重定位条目
struct relocation {
	offset    i64      // 在 section 中的偏移
	type      reloc_type // 重定位类型
	sym_index  i32      // 符号表索引
	addend    i64      // 加法常数
	section_index i32   // 源 section 索引
}

// reloc_processor 处理重定位
struct reloc_processor {
	relocs relocation[]
	symbol_table symbol_entry[]
	section_table section[]
	got_offset     i64
	plt_offset     i64
	tls_offset     i64
}

// symbol_entry 符号表条目（ELF）
struct symbol_entry {
	name      string
	value     i64
	size      i64
	binding   i32  // STB_LOCAL, STB_GLOBAL, STB_WEAK
	type      i32  // STT_NOTYPE, STT_OBJECT, STT_FUNC, etc.
	visibility i32 // STV_DEFAULT, STV_INTERNAL, STV_HIDDEN, STV_PROTECTED
	section_index i32
	is_comdat  bool
	is_weak    bool
	is_global  bool
}

// section 表示一个 ELF section
struct section {
	name          string
	type          i32
	flags         i64
	offset        i64
	size          i64
	alignment     i64
	link          i32
	info          i32
	entry_size     i64
	data u8[]
	relocs relocation[]
}

// 创建重定位处理器
func new_reloc_processor() reloc_processor {
	reloc_processor{
		Relocs: make(relocation[], 0),
		SymbolTable: make(symbol_entry[], 0),
		SectionTable: make(section[], 0),
		GOTOffset: 0,
		PLTOffset: 0,
		TLSOffset: 0,
	}
}

// 添加重定位
func (rp reloc_processor*) AddRelocation(r relocation) {
	rp.Relocs = append(rp.Relocs, r)
}

// 添加符号
func (rp reloc_processor*) AddSymbol(sym symbol_entry) i32 {
	idx := i32(len(rp.SymbolTable))
	rp.SymbolTable = append(rp.SymbolTable, sym)
	idx
}

// 申请 GOT 条目
func (rp reloc_processor*) AllocateGOTEntry(symIndex i32, relocType reloc_type) i64 {
	offset := rp.GOTOffset
	rp.GOTOffset += 8 // 64-bit GOT 条目

	// 添加 GOT 重定位
	reloc := relocation{
		Offset: offset,
		Type: relocType,
		SymIndex: symIndex,
		Addend: 0,
	}
	rp.AddRelocation(reloc)
	offset
}

// 申请 PLT 条目（x86-64）
func (rp reloc_processor*) AllocatePLTEntry(symIndex i32, gotIndex i64) i64 {
	// PLT 条目大小（x86-64 标准）
	pltSize := i64(16)
	offset := rp.PLTOffset
	rp.PLTOffset += pltSize

	// PLT stub: jmp [rip + offset]
	//           push symIndex
	//           jmp plt_resolver
	offset
}

// 申请 TLS 块
func (rp reloc_processor*) AllocateTLSBlock(size i64) i64 {
	offset := rp.TLSOffset
	rp.TLSOffset += size
	offset
}

// 处理符号冲突和可见性
func (rp reloc_processor*) ResolveSymbols() {
	// 处理弱符号和全局符号的冲突
	symbolMap := make(map[string]i32)

	for i, sym := range rp.SymbolTable {
		if sym.Name == "" {
			continue
		}

		existing, found := symbolMap[sym.Name]
		if found {
			// 符号冲突处理
			existingSym := rp.SymbolTable[existing]

			// 强符号优先
			if sym.Binding == 1 && existingSym.Binding == 2 { // STB_GLOBAL vs STB_WEAK
				symbolMap[sym.Name] = i32(i)
			}
		} else {
			symbolMap[sym.Name] = i32(i)
		}
	}
}

// 处理重定位
func (rp reloc_processor*) ApplyRelocations(targetBuffer u8[]) error {
	for _, reloc := range rp.Relocs {
		if reloc.SymIndex < 0 || reloc.SymIndex >= i32(len(rp.SymbolTable)) {
			continue
		}

		sym := rp.SymbolTable[reloc.SymIndex]
		targetAddr := reloc.Offset

		// 检查边界
		if targetAddr < 0 || targetAddr+8 > i64(len(targetBuffer)) {
			continue
		}

		value := i64(0)

		// 根据重定位类型计算值
		switch reloc.Type {
		case RELOC_ABSOLUTE:
			value = sym.Value
		case RELOC_PC_RELATIVE:
			value = sym.Value - targetAddr
		case RELOC_GOT:
			// GOT 偏移需要特殊处理
			value = rp.AllocateGOTEntry(reloc.SymIndex, RELOC_GOT)
		case RELOC_PLT:
			// PLT 偏移需要特殊处理
			value = rp.AllocatePLTEntry(reloc.SymIndex, 0)
		case RELOC_RELATIVE:
			value = sym.Value + reloc.Addend
		case RELOC_TLS_LE:
			value = sym.Value - rp.TLSOffset
		case RELOC_TLS_IE:
			value = rp.AllocateGOTEntry(reloc.SymIndex, RELOC_TLS_IE)
		}

		// 将值写入目标缓冲区
		binary.LittleEndian.PutUint64(targetBuffer[targetAddr:], u64(value))
	}

	nil
}

// 验证重定位的有效性
func (rp reloc_processor*) ValidateRelocations() error {
	for i, reloc := range rp.Relocs {
		// 检查符号索引
		if reloc.SymIndex < 0 || reloc.SymIndex >= i32(len(rp.SymbolTable)) {
			fmt.Printf("Warning: Invalid symbol index %d in relocation %d\n", reloc.SymIndex, i)
		}

		// 检查 section 索引
		if reloc.SectionIndex < 0 || reloc.SectionIndex >= i32(len(rp.SectionTable)) {
			fmt.Printf("Warning: Invalid section index %d in relocation %d\n", reloc.SectionIndex, i)
		}
	}

	nil
}

// 生成动态符号表
func (rp reloc_processor*) GenerateDynamicSymtab() symbol_entry[] {
	dynSyms := make(symbol_entry[], 0)

	for _, sym := range rp.SymbolTable {
		// 仅包含全局和弱符号
		if sym.IsGlobal || sym.IsWeak {
			dynSyms = append(dynSyms, sym)
		}
	}

	dynSyms
}

// 计算重定位表大小
func (rp reloc_processor*) GetRelocationTableSize() i64 {
	i64(len(rp.Relocs)) * 24 // x86-64 Elf64_Rela 大小
}

// 生成 relocation section 的二进制数据
func (rp reloc_processor*) GenerateRelocationData() u8[] {
	data := make(u8[], 0)

	for _, reloc := range rp.Relocs {
		// Elf64_Rela 结构
		buf := make(u8[], 24)

		binary.LittleEndian.PutUint64(buf[0:], u64(reloc.Offset))
		info := (u64(reloc.SymIndex) << 32) | u64(reloc.Type)
		binary.LittleEndian.PutUint64(buf[8:], info)
		binary.LittleEndian.PutUint64(buf[16:], u64(reloc.Addend))

		data = append(data, buf...)
	}

	data
}
