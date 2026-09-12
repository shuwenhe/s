package src.cmd.link.internal.ld

import (
	"src/encoding/binary"
	"src/os"
)

const (
	PE_SIGNATURE = 0x00004550 
	PE_MAGIC_PE32 = 0x10b
	PE_MAGIC_PE32PLUS = 0x20b
)

enum pe_machine {
	MACHINE_UNKNOWN = 0x0
	MACHINE_I386 = 0x14c
	MACHINE_R3000 = 0x162
	MACHINE_R4000 = 0x166
	MACHINE_R10000 = 0x168
	MACHINE_WCEMIPSV2 = 0x169
	MACHINE_ALPHA = 0x184
	MACHINE_SH3 = 0x1a2
	MACHINE_SH3DSP = 0x1a3
	MACHINE_SH3E = 0x1a4
	MACHINE_SH4 = 0x1a6
	MACHINE_ARM = 0x1c0
	MACHINE_THUMB = 0x1c2
	MACHINE_ARMV7 = 0x1c4
	MACHINE_ARM64 = 0xaa64
	MACHINE_MIPS = 0x366
	MACHINE_MIPS16 = 0x366
	MACHINE_MIPSFIX = 0x870
	MACHINE_POWERPC = 0x1f0
	MACHINE_POWERPCFP = 0x1f1
	MACHINE_IA64 = 0x200
	MACHINE_AMD64 = 0x8664
	MACHINE_CHPE_X86_64 = 0x3a64
}

struct pe_file_header {
	u16 machine
	u16 number_of_sections
	u32 time_date_stamp
	u32 pointer_to_symbol_table
	u32 number_of_symbols
	u16 size_of_optional_header
	char u16acteristics
}

struct pe_optional_header {
	u16 magic
	u8 major_linker_version
	u8 minor_linker_version
	u32 size_of_code
	u32 size_of_initialized_data
	u32 size_of_uninitialized_data
	u32 address_of_entry_point
	u32 base_of_code
	u32 base_of_data
	u64 image_base
	u32 section_alignment
	u32 file_alignment
	u16 major_operating_system_version
	u16 minor_operating_system_version
	u16 major_image_version
	u16 minor_image_version
	u16 major_subsystem_version
	u16 minor_subsystem_version
	u32 win32_version_value
	u32 size_of_image
	u32 size_of_headers
	u32 check_sum
	u16 subsystem
	u16 dll_characteristics
	u64 size_of_stack_reserve
	u64 size_of_stack_commit
	u64 size_of_heap_reserve
	u64 size_of_heap_commit
	u32 loader_flags
	u32 number_of_rva_and_sizes
}

struct pe_section_header {
	[8]u8 name
	u32 virtual_size
	u32 virtual_address
	u32 size_of_raw_data
	u32 pointer_to_raw_data
	u32 pointer_to_relocations
	u32 pointer_to_linenumbers
	u16 number_of_relocations
	u16 number_of_linenumbers
	char u32acteristics
}

struct pe_object {
	[64]u8 dos_header
	u32 pe_signature
	pe_file_header file_header
	pe_optional_header optional_header
	pe_section_header[] sections
	map[i32]u8[] section_data
	pe_symbol[] symbol_table
	pe_relocation[] relocations
}

struct pe_symbol {
	string name
	u32 value
	i16 section_number
	u16 type
	u8 storage_class
	i32 aux_symbols
}

struct pe_relocation {
	u32 virtual_address
	u32 symbol_index
	u16 type
}

func new_pe_object(machine pe_machine) pe_object {
	obj := pe_object{
		PESignature: PE_SIGNATURE,
		FileHeader: pe_file_header{
			Machine: u16(machine),
			NumberOfSections: 0,
			TimeDateStamp: 0,
			PointerToSymbolTable: 0,
			NumberOfSymbols: 0,
			SizeOfOptionalHeader: 240, 
			Characteristics: 0x0002 | 0x0004 | 0x0008, 
		},
		OptionalHeader: pe_optional_header{
			Magic: PE_MAGIC_PE32PLUS,
			MajorLinkerVersion: 14,
			MinorLinkerVersion: 0,
			SizeOfCode: 0,
			SizeOfInitializedData: 0,
			SizeOfUninitializedData: 0,
			AddressOfEntryPoint: 0,
			BaseOfCode: 0,
			BaseOfData: 0,
			ImageBase: 0x140000000,
			SectionAlignment: 0x1000,
			FileAlignment: 0x200,
			MajorOperatingSystemVersion: 6,
			MinorOperatingSystemVersion: 0,
			MajorImageVersion: 0,
			MinorImageVersion: 0,
			MajorSubsystemVersion: 6,
			MinorSubsystemVersion: 0,
			Win32VersionValue: 0,
			SizeOfImage: 0,
			SizeOfHeaders: 0x400,
			CheckSum: 0,
			Subsystem: 3,  
			DllCharacteristics: 0,
			SizeOfStackReserve: 0x100000,
			SizeOfStackCommit: 0x1000,
			SizeOfHeapReserve: 0x100000,
			SizeOfHeapCommit: 0x1000,
			LoaderFlags: 0,
			NumberOfRvaAndSizes: 16,
		},
		Sections: make(pe_section_header[], 0),
		SectionData: make(map[i32]u8[]),
		SymbolTable: make(pe_symbol[], 0),
		Relocations: make(pe_relocation[], 0),
	}

	obj.DosHeader[0] = 0x4d
	obj.DosHeader[1] = 0x5a

	obj
}

func (po* pe_object) add_section(string name, data u8[]) i32 {
	idx := i32(len(po.Sections))

	shdr := pe_section_header{
		VirtualSize: u32(len(data)),
		VirtualAddress: 0,
		SizeOfRawData: u32((len(data) + 0x1ff) & ^0x1ff),
		PointerToRawData: 0,
		PointerToRelocations: 0,
		PointerToLinenumbers: 0,
		NumberOfRelocations: 0,
		NumberOfLinenumbers: 0,
		Characteristics: 0x60000020, 
	}

	name_bytes := u8[](name)
	for i := i32(0); i < 8 && i < i32(len(name_bytes)); i += 1 {
		shdr.Name[i] = name_bytes[i]
	}

	po.Sections = append(po.Sections, shdr)
	po.SectionData[idx] = data

	idx
}

func (po* pe_object) add_symbol(sym pe_symbol) {
	po.SymbolTable = append(po.SymbolTable, sym)
}

func (po* pe_object) add_relocation(reloc pe_relocation) {
	po.Relocations = append(po.Relocations, reloc)
}

func read_pe_object(string filename) (pe_object, error) {
	file, err := os.open(filename)
	if err != nil {
		pe_object{}, err
	}
	defer file.close()

	buf := make(u8[], 4096)
	n, err := file.read(buf)
	if err != nil || n < 64 {
		pe_object{}, "failed to read PE header"
	}

	if buf[0] != 0x4d || buf[1] != 0x5a {
		pe_object{}, "invalid DOS header"
	}

	pe_offset := i32(binary.LittleEndian.uint32(buf[60:64]))

	if pe_offset+4 > i32(n) {
		pe_object{}, "PE header offset out of bounds"
	}

	signature := binary.LittleEndian.uint32(buf[pe_offset : pe_offset+4])
	if signature != PE_SIGNATURE {
		pe_object{}, "invalid PE signature"
	}

	fh_offset := pe_offset + 4
	obj := new_pe_object(pe_machine(binary.LittleEndian.uint16(buf[fh_offset : fh_offset+2])))

	obj.FileHeader.Machine = binary.LittleEndian.uint16(buf[fh_offset : fh_offset+2])
	obj.FileHeader.NumberOfSections = binary.LittleEndian.uint16(buf[fh_offset+2 : fh_offset+4])
	obj.FileHeader.TimeDateStamp = binary.LittleEndian.uint32(buf[fh_offset+4 : fh_offset+8])
	obj.FileHeader.PointerToSymbolTable = binary.LittleEndian.uint32(buf[fh_offset+8 : fh_offset+12])
	obj.FileHeader.NumberOfSymbols = binary.LittleEndian.uint32(buf[fh_offset+12 : fh_offset+16])
	obj.FileHeader.SizeOfOptionalHeader = binary.LittleEndian.uint16(buf[fh_offset+16 : fh_offset+18])
	obj.FileHeader.Characteristics = binary.LittleEndian.uint16(buf[fh_offset+18 : fh_offset+20])

	obj, nil
}

func (pe_object* po) write_to_file(string filename) error {
	file, err := os.create(filename)
	if err != nil {
		err
	}
	defer file.close()

	_, err = file.write(po.DosHeader[:])
	if err != nil {
		err
	}

	sig_buf := make(u8[], 4)
	binary.LittleEndian.put_uint32(sig_buf, po.PESignature)
	_, err = file.write(sig_buf)
	if err != nil {
		err
	}

	fh_buf := make(u8[], 20)
	binary.LittleEndian.put_uint16(fh_buf[0:2], po.FileHeader.Machine)
	binary.LittleEndian.put_uint16(fh_buf[2:4], po.FileHeader.NumberOfSections)
	binary.LittleEndian.put_uint32(fh_buf[4:8], po.FileHeader.TimeDateStamp)
	binary.LittleEndian.put_uint32(fh_buf[8:12], po.FileHeader.PointerToSymbolTable)
	binary.LittleEndian.put_uint32(fh_buf[12:16], po.FileHeader.NumberOfSymbols)
	binary.LittleEndian.put_uint16(fh_buf[16:18], po.FileHeader.SizeOfOptionalHeader)
	binary.LittleEndian.put_uint16(fh_buf[18:20], po.FileHeader.Characteristics)

	_, err = file.write(fh_buf)
	if err != nil {
		err
	}

	opt_buf := make(u8[], 240)

	binary.LittleEndian.put_uint16(opt_buf[0:2], po.OptionalHeader.Magic)
	opt_buf[2] = po.OptionalHeader.MajorLinkerVersion
	opt_buf[3] = po.OptionalHeader.MinorLinkerVersion

	_, err = file.write(opt_buf)
	if err != nil {
		err
	}

	for _, shdr := range po.Sections {
		sh_buf := make(u8[], 40)

		for i := i32(0); i < 8; i += 1 {
			sh_buf[i] = shdr.Name[i]
		}

		binary.LittleEndian.put_uint32(sh_buf[8:12], shdr.VirtualSize)
		binary.LittleEndian.put_uint32(sh_buf[12:16], shdr.VirtualAddress)
		binary.LittleEndian.put_uint32(sh_buf[16:20], shdr.SizeOfRawData)
		binary.LittleEndian.put_uint32(sh_buf[20:24], shdr.PointerToRawData)
		binary.LittleEndian.put_uint32(sh_buf[24:28], shdr.PointerToRelocations)
		binary.LittleEndian.put_uint32(sh_buf[28:32], shdr.PointerToLinenumbers)
		binary.LittleEndian.put_uint16(sh_buf[32:34], shdr.NumberOfRelocations)
		binary.LittleEndian.put_uint16(sh_buf[34:36], shdr.NumberOfLinenumbers)
		binary.LittleEndian.put_uint32(sh_buf[36:40], shdr.Characteristics)

		_, err = file.write(sh_buf)
		if err != nil {
			err
		}
	}

	for i, shdr := range po.Sections {
		if data, ok := po.SectionData[i32(i)]; ok {
			_, err = file.write(data)
			if err != nil {
				err
			}

			padding := shdr.SizeOfRawData - u32(len(data))
			if padding > 0 {
				pad_buf := make(u8[], padding)
				_, err = file.write(pad_buf)
				if err != nil {
					err
				}
			}
		}
	}

	nil
}