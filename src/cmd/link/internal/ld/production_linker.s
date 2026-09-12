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
	object_format format
	i16 machine
	string output_file
	string[] input_files
	i32 symbol_strip_mode
	i32 optimize_level
	bool generate_debug_info
	bool generate_build_id
	bool enable_relro
	bool enable_now
	bool pie
	bool pie_library
}

struct production_linker {
	linker_config config
	elf_object[] elf_objects
	macho_object[] macho_objects
	pe_object[] pe_objects
	symbol_manager symbol_manager
	reloc_processor reloc_processor
	dwarf_manager dwarf_manager
	unwind_manager unwind_manager
	build_id_manager build_id_manager
	got_manager got_manager
	plt_manager plt_manager
	tls_manager tls_manager
	dynamic_reloc_manager dynamic_reloc_manager
	map[string]section sections
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

func (production_linker* pl) load_object_file(string filename) error {
	fmt.printf("Loading %s...\n", filename)

	file, err := os.open(filename)
	if err != nil {
		err
	}
	defer file.close()

	magic := make(u8[], 4)
	_, err = file.read(magic)
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

func (pl production_linker*) link() error {
	fmt.printf("Linking %d object files...\n", len(pl.Config.InputFiles))

	for _, input_file := range pl.Config.InputFiles {
		err := pl.load_object_file(input_file)
		if err != nil {
			fmt.printf("Error loading %s: %v\n", input_file, err)
		}
	}

	err := pl.merge_symbols()
	if err != nil {
		err
	}

	err = pl.process_relocations()
	if err != nil {
		err
	}

	err = pl.generate_output()
	if err != nil {
		err
	}

	fmt.printf("Linking successful! Output: %s\n", pl.Config.OutputFile)
	nil
}

func (pl production_linker*) merge_symbols() error {

	for _, obj := range pl.elf_objects {
		for _, sym := range obj.Symbols {
			err := pl.symbol_manager.add_symbol(sym)
			if err != nil {
				fmt.printf("Warning: %v\n", err)
			}
		}
	}

	pl.symbol_manager.apply_visibility()

	nil
}

func (pl production_linker*) process_relocations() error {

	for objIdx, obj := range pl.elf_objects {
		for _, reloc := range obj.Relocations {

			if reloc.SymIndex >= 0 && reloc.SymIndex < i32(len(obj.Symbols)) {
				sym := obj.Symbols[reloc.SymIndex]

				switch reloc.Type {
				case RELOC_GOT:

					_ = pl.got_manager.add_entry(reloc.SymIndex, reloc.Type)

				case RELOC_PLT:

					got_addr := pl.got_manager.lookup_or_create(reloc.SymIndex, RELOC_GLOB_DAT)
					_ = pl.plt_manager.add_entry(reloc.SymIndex, got_addr)

				case RELOC_TLS_IE:

					_ = pl.tls_manager.add_variable(sym.Name, sym.Size, 8)

				default:

				}

				pl.reloc_processor.add_relocation(reloc)
			}
		}
	}

	for i, entry := range pl.got_manager.Entries {
		pl.dynamic_reloc_manager.add_relocation(entry.Address, 7, i32(i), 0)
	}

	nil
}

func (pl production_linker*) generate_output() error {

	switch pl.Config.Format {
	case format_elf:
		err := pl.generate_elf_output()
		if err != nil {
			err
		}

	case format_macho:
		err := pl.generate_macho_output()
		if err != nil {
			err
		}

	case format_pe:
		err := pl.generate_pe_output()
		if err != nil {
			err
		}

	default:
		"unsupported output format"
	}

	nil
}

func (pl production_linker*) generate_elf_output() error {

	output := NewELFObject(0x3e) 

	text_data := make(u8[], 0)
	text_idx := output.add_section(".text", 1, 0x6, text_data)

	data_data := make(u8[], 0)
	data_idx := output.add_section(".data", 1, 0x3, data_data)

	bss_data := make(u8[], 0)
	bss_idx := output.add_section(".bss", 8, 0x3, bss_data)

	symtab_data := make(u8[], 0)
	symtab_idx := output.add_section(".symtab", 2, 0, symtab_data)

	strtab_data := make(u8[], 0)
	strtab_idx := output.add_section(".strtab", 3, 0, strtab_data)

	rel_data := pl.reloc_processor.generate_relocation_data()
	rel_idx := output.add_section(".rel.text", 9, 0, rel_data)

	if pl.Config.GenerateDebugInfo {
		debug_info := pl.DwarfManager.generate_debug_line()
		output.add_section(".debug_info", 1, 0, debug_info)

		debug_line := pl.DwarfManager.generate_debug_line()
		output.add_section(".debug_line", 1, 0, debug_line)
	}

	if pl.Config.GenerateBuildID {
		note_data := pl.build_id_manager.generate_note_section()
		output.add_section(".note.gnu.build-id", 7, 0, note_data)
	}

	_ = symtab_idx
	_ = strtab_idx
	_ = rel_idx

	err := output.write_to_file(pl.Config.OutputFile)
	if err != nil {
		err
	}

	nil
}

func (pl production_linker*) generate_macho_output() error {
	output := NewMachoObject(CPU_TYPE_X86_64, MH_OBJECT)

	output.add_segment("__TEXT", 0, 0x1000)
	output.add_segment("__DATA", 0x1000, 0x1000)

	err := output.write_to_file(pl.Config.OutputFile)
	if err != nil {
		err
	}

	nil
}

func (pl production_linker*) generate_pe_output() error {
	output := NewPEObject(MACHINE_AMD64)

	code_data := make(u8[], 0)
	output.add_section(".text", code_data)

	data_data := make(u8[], 0)
	output.add_section(".data", data_data)

	err := output.write_to_file(pl.Config.OutputFile)
	if err != nil {
		err
	}

	nil
}

func (pl production_linker*) validate() error {

	err := pl.reloc_processor.validate_relocations()
	if err != nil {
		fmt.printf("Validation warning: %v\n", err)
	}

	for _, sym := range pl.symbol_manager.AllSymbols {
		if sym.IsGlobal && sym.Value == 0 {
			fmt.printf("Warning: Undefined symbol: %s\n", sym.Name)
		}
	}

	nil
}