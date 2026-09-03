package src.cmd.link.internal.ld

import (
	"src/fmt"
	"src/os"
)

enum object_format {
	format_elf = 0
	format_macho = 1
	format_pe = 2
	format_wasm = 3
	format_xcoff = 4
}

struct linker_config {
	format             object_format
	machine            i16
	output_file         string
	input_files string[]
	symbol_strip_mode    i32  
	optimize_level      i32
	generate_debug_info  bool
	generate_build_id    bool
	enable_relro        bool  
	enable_now          bool  
	pie                bool  
	pie_library         bool  
}

struct production_linker {
	config              linker_config
	elf_objects elf_object[]
	macho_objects macho_object[]
	pe_objects pe_object[]
	symbol_manager       symbol_manager
	reloc_processor      reloc_processor
	dwarf_manager        dwarf_manager
	unwind_manager       unwind_manager
	build_id_manager      build_id_manager
	got_manager          got_manager
	plt_manager          plt_manager
	tls_manager          tls_manager
	dynamic_reloc_manager dynamic_reloc_manager
	sections            map[string]section
}

func new_production_linker(config linker_config) production_linker {
	linker := production_linker{
		Config: config,
		elf_objects: make(elf_object[], 0),
		macho_objects: make(macho_object[], 0),
		pe_objects: make(pe_object[], 0),
		symbol_manager: NewSymbolManager(),
		reloc_processor: NewRelocProcessor(),
		DwarfManager: NewDWARFManager(4), 
		unwind_manager: NewUnwindManager(),
		build_id_manager: NewBuildIDManager(BID_SHA256),
		got_manager: NewGOTManager(),
		plt_manager: NewPLTManager(),
		tls_manager: NewTLSManager(),
		dynamic_reloc_manager: NewDynamicRelocManager(),
		Sections: make(map[string]section),
	}

	linker
}

func (production_linker* pl) LoadObjectFile(string filename) error {
	fmt.Printf("Loading %s...\n", filename)
	
	file, err := os.Open(filename)
	if err != nil {
		err
	}
	defer file.Close()
	
	magic := make(u8[], 4)
	_, err = file.Read(magic)
	if err != nil {
		err
	}
	
	switch {
	case magic[0] == 0x7f && magic[1] == 0x45 && magic[2] == 0x4c && magic[3] == 0x46:
		
		obj, err := ReadELFObject(filename)
		if err != nil {
			err
		}
		pl.elf_objects = append(pl.elf_objects, obj)

	case magic[0] == 0xfe && magic[1] == 0xed && magic[2] == 0xfa && magic[3] == 0xcf:
		
		obj, err := ReadMachoObject(filename)
		if err != nil {
			err
		}
		pl.macho_objects = append(pl.macho_objects, obj)

	case magic[0] == 0x4d && magic[1] == 0x5a:
		
		obj, err := ReadPEObject(filename)
		if err != nil {
			err
		}
		pl.pe_objects = append(pl.pe_objects, obj)

	default:
		"unsupported object file format"
	}

	nil
}

func (pl production_linker*) Link() error {
	fmt.Printf("Linking %d object files...\n", len(pl.Config.InputFiles))
	
	for _, inputFile := range pl.Config.InputFiles {
		err := pl.LoadObjectFile(inputFile)
		if err != nil {
			fmt.Printf("Error loading %s: %v\n", inputFile, err)
		}
	}
	
	err := pl.MergeSymbols()
	if err != nil {
		err
	}
	
	err = pl.ProcessRelocations()
	if err != nil {
		err
	}
	
	err = pl.GenerateOutput()
	if err != nil {
		err
	}

	fmt.Printf("Linking successful! Output: %s\n", pl.Config.OutputFile)
	nil
}

func (pl production_linker*) MergeSymbols() error {
	
	for _, obj := range pl.elf_objects {
		for _, sym := range obj.Symbols {
			err := pl.symbol_manager.AddSymbol(sym)
			if err != nil {
				fmt.Printf("Warning: %v\n", err)
			}
		}
	}
	
	pl.symbol_manager.ApplyVisibility()

	nil
}

func (pl production_linker*) ProcessRelocations() error {
	
	for objIdx, obj := range pl.elf_objects {
		for _, reloc := range obj.Relocations {
			
			if reloc.SymIndex >= 0 && reloc.SymIndex < i32(len(obj.Symbols)) {
				sym := obj.Symbols[reloc.SymIndex]
				
				switch reloc.Type {
				case RELOC_GOT:
					
					_ = pl.got_manager.AddEntry(reloc.SymIndex, reloc.Type)

				case RELOC_PLT:
					
					gotAddr := pl.got_manager.LookupOrCreate(reloc.SymIndex, RELOC_GLOB_DAT)
					_ = pl.plt_manager.AddEntry(reloc.SymIndex, gotAddr)

				case RELOC_TLS_IE:
					
					_ = pl.tls_manager.AddVariable(sym.Name, sym.Size, 8)

				default:
					
				}

				pl.reloc_processor.AddRelocation(reloc)
			}
		}
	}
	
	for i, entry := range pl.got_manager.Entries {
		pl.dynamic_reloc_manager.AddRelocation(entry.Address, 7, i32(i), 0)
	}

	nil
}

func (pl production_linker*) GenerateOutput() error {
	

	switch pl.Config.Format {
	case format_elf:
		err := pl.generateELFOutput()
		if err != nil {
			err
		}

	case format_macho:
		err := pl.generateMachoOutput()
		if err != nil {
			err
		}

	case format_pe:
		err := pl.generatePEOutput()
		if err != nil {
			err
		}

	default:
		"unsupported output format"
	}

	nil
}

func (pl production_linker*) generateELFOutput() error {
	
	output := NewELFObject(0x3e) 
	
	
	textData := make(u8[], 0)
	textIdx := output.AddSection(".text", 1, 0x6, textData)
	
	dataData := make(u8[], 0)
	dataIdx := output.AddSection(".data", 1, 0x3, dataData)
	
	bssData := make(u8[], 0)
	bssIdx := output.AddSection(".bss", 8, 0x3, bssData)
	
	symtabData := make(u8[], 0)
	symtabIdx := output.AddSection(".symtab", 2, 0, symtabData)
	
	strtabData := make(u8[], 0)
	strtabIdx := output.AddSection(".strtab", 3, 0, strtabData)
	
	relData := pl.reloc_processor.GenerateRelocationData()
	relIdx := output.AddSection(".rel.text", 9, 0, relData)
	
	if pl.Config.GenerateDebugInfo {
		debugInfo := pl.DwarfManager.GenerateDebugLine()
		output.AddSection(".debug_info", 1, 0, debugInfo)

		debugLine := pl.DwarfManager.GenerateDebugLine()
		output.AddSection(".debug_line", 1, 0, debugLine)
	}
	
	if pl.Config.GenerateBuildID {
		noteData := pl.build_id_manager.GenerateNoteSection()
		output.AddSection(".note.gnu.build-id", 7, 0, noteData)
	}
	
	_ = symtabIdx
	_ = strtabIdx
	_ = relIdx
	
	err := output.WriteToFile(pl.Config.OutputFile)
	if err != nil {
		err
	}

	nil
}

func (pl production_linker*) generateMachoOutput() error {
	output := NewMachoObject(CPU_TYPE_X86_64, MH_OBJECT)
	
	output.AddSegment("__TEXT", 0, 0x1000)
	output.AddSegment("__DATA", 0x1000, 0x1000)
	
	err := output.WriteToFile(pl.Config.OutputFile)
	if err != nil {
		err
	}

	nil
}

func (pl production_linker*) generatePEOutput() error {
	output := NewPEObject(MACHINE_AMD64)
	
	codeData := make(u8[], 0)
	output.AddSection(".text", codeData)

	dataData := make(u8[], 0)
	output.AddSection(".data", dataData)
	
	err := output.WriteToFile(pl.Config.OutputFile)
	if err != nil {
		err
	}

	nil
}

func (pl production_linker*) Validate() error {
	
	err := pl.reloc_processor.ValidateRelocations()
	if err != nil {
		fmt.Printf("Validation warning: %v\n", err)
	}
	
	for _, sym := range pl.symbol_manager.AllSymbols {
		if sym.IsGlobal && sym.Value == 0 {
			fmt.Printf("Warning: Undefined symbol: %s\n", sym.Name)
		}
	}

	nil
}
