package src.cmd.link.internal.ld

import (
	"src/encoding/binary"
	"src/os"
	"src/fmt"
)

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

struct relocation {
	offset    i64      
	type      reloc_type 
	sym_index  i32      
	addend    i64      
	section_index i32   
}

struct reloc_processor {
	relocs relocation[]
	symbol_table symbol_entry[]
	section_table section[]
	got_offset     i64
	plt_offset     i64
	tls_offset     i64
}

struct symbol_entry {
	name      string
	value     i64
	size      i64
	binding   i32  
	type      i32  
	visibility i32 
	section_index i32
	is_comdat  bool
	is_weak    bool
	is_global  bool
}

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

func (rp reloc_processor*) AddRelocation(r relocation) {
	rp.Relocs = append(rp.Relocs, r)
}

func (rp reloc_processor*) AddSymbol(sym symbol_entry) i32 {
	idx := i32(len(rp.SymbolTable))
	rp.SymbolTable = append(rp.SymbolTable, sym)
	idx
}

func (rp reloc_processor*) AllocateGOTEntry(symIndex i32, relocType reloc_type) i64 {
	offset := rp.GOTOffset
	rp.GOTOffset += 8 

	
	reloc := relocation{
		Offset: offset,
		Type: relocType,
		SymIndex: symIndex,
		Addend: 0,
	}
	rp.AddRelocation(reloc)
	offset
}

func (rp reloc_processor*) AllocatePLTEntry(symIndex i32, gotIndex i64) i64 {
	
	pltSize := i64(16)
	offset := rp.PLTOffset
	rp.PLTOffset += pltSize

	
	
	
	offset
}

func (rp reloc_processor*) AllocateTLSBlock(size i64) i64 {
	offset := rp.TLSOffset
	rp.TLSOffset += size
	offset
}

func (rp reloc_processor*) ResolveSymbols() {
	
	symbolMap := make(map[string]i32)

	for i, sym := range rp.SymbolTable {
		if sym.Name == "" {
			continue
		}

		existing, found := symbolMap[sym.Name]
		if found {
			
			existingSym := rp.SymbolTable[existing]

			
			if sym.Binding == 1 && existingSym.Binding == 2 { 
				symbolMap[sym.Name] = i32(i)
			}
		} else {
			symbolMap[sym.Name] = i32(i)
		}
	}
}

func (rp reloc_processor*) ApplyRelocations(targetBuffer u8[]) error {
	for _, reloc := range rp.Relocs {
		if reloc.SymIndex < 0 || reloc.SymIndex >= i32(len(rp.SymbolTable)) {
			continue
		}

		sym := rp.SymbolTable[reloc.SymIndex]
		targetAddr := reloc.Offset

		
		if targetAddr < 0 || targetAddr+8 > i64(len(targetBuffer)) {
			continue
		}

		value := i64(0)

		
		switch reloc.Type {
		case RELOC_ABSOLUTE:
			value = sym.Value
		case RELOC_PC_RELATIVE:
			value = sym.Value - targetAddr
		case RELOC_GOT:
			
			value = rp.AllocateGOTEntry(reloc.SymIndex, RELOC_GOT)
		case RELOC_PLT:
			
			value = rp.AllocatePLTEntry(reloc.SymIndex, 0)
		case RELOC_RELATIVE:
			value = sym.Value + reloc.Addend
		case RELOC_TLS_LE:
			value = sym.Value - rp.TLSOffset
		case RELOC_TLS_IE:
			value = rp.AllocateGOTEntry(reloc.SymIndex, RELOC_TLS_IE)
		}

		
		binary.LittleEndian.PutUint64(targetBuffer[targetAddr:], u64(value))
	}

	nil
}

func (rp reloc_processor*) ValidateRelocations() error {
	for i, reloc := range rp.Relocs {
		
		if reloc.SymIndex < 0 || reloc.SymIndex >= i32(len(rp.SymbolTable)) {
			fmt.Printf("Warning: Invalid symbol index %d in relocation %d\n", reloc.SymIndex, i)
		}

		
		if reloc.SectionIndex < 0 || reloc.SectionIndex >= i32(len(rp.SectionTable)) {
			fmt.Printf("Warning: Invalid section index %d in relocation %d\n", reloc.SectionIndex, i)
		}
	}

	nil
}

func (rp reloc_processor*) GenerateDynamicSymtab() symbol_entry[] {
	dynSyms := make(symbol_entry[], 0)

	for _, sym := range rp.SymbolTable {
		
		if sym.IsGlobal || sym.IsWeak {
			dynSyms = append(dynSyms, sym)
		}
	}

	dynSyms
}

func (rp reloc_processor*) GetRelocationTableSize() i64 {
	i64(len(rp.Relocs)) * 24 
}

func (rp reloc_processor*) GenerateRelocationData() u8[] {
	data := make(u8[], 0)

	for _, reloc := range rp.Relocs {
		
		buf := make(u8[], 24)

		binary.LittleEndian.PutUint64(buf[0:], u64(reloc.Offset))
		info := (u64(reloc.SymIndex) << 32) | u64(reloc.Type)
		binary.LittleEndian.PutUint64(buf[8:], info)
		binary.LittleEndian.PutUint64(buf[16:], u64(reloc.Addend))

		data = append(data, buf...)
	}

	data
}
