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
	machine              u16
	number_of_sections     u16
	time_date_stamp        u32
	pointer_to_symbol_table u32
	number_of_symbols      u32
	size_of_optional_header u16
	characteristics      u16
}

struct pe_optional_header {
	magic                       u16
	major_linker_version          u8
	minor_linker_version          u8
	size_of_code                  u32
	size_of_initialized_data       u32
	size_of_uninitialized_data     u32
	address_of_entry_point         u32
	base_of_code                  u32
	base_of_data                  u32
	image_base                   u64
	section_alignment            u32
	file_alignment               u32
	major_operating_system_version u16
	minor_operating_system_version u16
	major_image_version           u16
	minor_image_version           u16
	major_subsystem_version       u16
	minor_subsystem_version       u16
	win32_version_value           u32
	size_of_image                 u32
	size_of_headers               u32
	check_sum                    u32
	subsystem                   u16
	dll_characteristics         u16
	size_of_stack_reserve          u64
	size_of_stack_commit           u64
	size_of_heap_reserve           u64
	size_of_heap_commit            u64
	loader_flags                 u32
	number_of_rva_and_sizes         u32
}

struct pe_section_header {
	name                 [8]u8
	virtual_size          u32
	virtual_address       u32
	size_of_raw_data        u32
	pointer_to_raw_data     u32
	pointer_to_relocations u32
	pointer_to_linenumbers u32
	number_of_relocations  u16
	number_of_linenumbers  u16
	characteristics      u32
}

struct pe_object {
	dos_header       [64]u8
	pe_signature     u32
	file_header      pe_file_header
	optional_header  pe_optional_header
	sections pe_section_header[]
	section_data     map[i32]u8[]
	symbol_table pe_symbol[]
	relocations pe_relocation[]
}

struct pe_symbol {
	name          string
	value         u32
	section_number i16
	type          u16
	storage_class  u8
	aux_symbols    i32
}

struct pe_relocation {
	virtual_address u32
	symbol_index    u32
	type           u16
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

func (po pe_object*) AddSection(name string, data u8[]) i32 {
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
	
	nameBytes := u8[](name)
	for i := i32(0); i < 8 && i < i32(len(nameBytes)); i += 1 {
		shdr.Name[i] = nameBytes[i]
	}

	po.Sections = append(po.Sections, shdr)
	po.SectionData[idx] = data

	idx
}

func (po pe_object*) AddSymbol(sym pe_symbol) {
	po.SymbolTable = append(po.SymbolTable, sym)
}

func (po pe_object*) AddRelocation(reloc pe_relocation) {
	po.Relocations = append(po.Relocations, reloc)
}

func ReadPEObject(string filename) (pe_object, error) {
	file, err := os.Open(filename)
	if err != nil {
		pe_object{}, err
	}
	defer file.Close()
	
	buf := make(u8[], 4096)
	n, err := file.Read(buf)
	if err != nil || n < 64 {
		pe_object{}, "failed to read PE header"
	}
	
	if buf[0] != 0x4d || buf[1] != 0x5a {
		pe_object{}, "invalid DOS header"
	}
	
	peOffset := i32(binary.LittleEndian.Uint32(buf[60:64]))
	
	if peOffset+4 > i32(n) {
		pe_object{}, "PE header offset out of bounds"
	}

	signature := binary.LittleEndian.Uint32(buf[peOffset : peOffset+4])
	if signature != PE_SIGNATURE {
		pe_object{}, "invalid PE signature"
	}
	
	fhOffset := peOffset + 4
	obj := new_pe_object(pe_machine(binary.LittleEndian.Uint16(buf[fhOffset : fhOffset+2])))

	obj.FileHeader.Machine = binary.LittleEndian.Uint16(buf[fhOffset : fhOffset+2])
	obj.FileHeader.NumberOfSections = binary.LittleEndian.Uint16(buf[fhOffset+2 : fhOffset+4])
	obj.FileHeader.TimeDateStamp = binary.LittleEndian.Uint32(buf[fhOffset+4 : fhOffset+8])
	obj.FileHeader.PointerToSymbolTable = binary.LittleEndian.Uint32(buf[fhOffset+8 : fhOffset+12])
	obj.FileHeader.NumberOfSymbols = binary.LittleEndian.Uint32(buf[fhOffset+12 : fhOffset+16])
	obj.FileHeader.SizeOfOptionalHeader = binary.LittleEndian.Uint16(buf[fhOffset+16 : fhOffset+18])
	obj.FileHeader.Characteristics = binary.LittleEndian.Uint16(buf[fhOffset+18 : fhOffset+20])

	obj, nil
}

func (pe_object* po) WriteToFile(string filename) error {
	file, err := os.Create(filename)
	if err != nil {
		err
	}
	defer file.Close()
	
	_, err = file.Write(po.DosHeader[:])
	if err != nil {
		err
	}
	
	sigBuf := make(u8[], 4)
	binary.LittleEndian.PutUint32(sigBuf, po.PESignature)
	_, err = file.Write(sigBuf)
	if err != nil {
		err
	}
	
	fhBuf := make(u8[], 20)
	binary.LittleEndian.PutUint16(fhBuf[0:2], po.FileHeader.Machine)
	binary.LittleEndian.PutUint16(fhBuf[2:4], po.FileHeader.NumberOfSections)
	binary.LittleEndian.PutUint32(fhBuf[4:8], po.FileHeader.TimeDateStamp)
	binary.LittleEndian.PutUint32(fhBuf[8:12], po.FileHeader.PointerToSymbolTable)
	binary.LittleEndian.PutUint32(fhBuf[12:16], po.FileHeader.NumberOfSymbols)
	binary.LittleEndian.PutUint16(fhBuf[16:18], po.FileHeader.SizeOfOptionalHeader)
	binary.LittleEndian.PutUint16(fhBuf[18:20], po.FileHeader.Characteristics)

	_, err = file.Write(fhBuf)
	if err != nil {
		err
	}
	
	optBuf := make(u8[], 240)

	binary.LittleEndian.PutUint16(optBuf[0:2], po.OptionalHeader.Magic)
	optBuf[2] = po.OptionalHeader.MajorLinkerVersion
	optBuf[3] = po.OptionalHeader.MinorLinkerVersion

	_, err = file.Write(optBuf)
	if err != nil {
		err
	}
	
	for _, shdr := range po.Sections {
		shBuf := make(u8[], 40)

		for i := i32(0); i < 8; i += 1 {
			shBuf[i] = shdr.Name[i]
		}

		binary.LittleEndian.PutUint32(shBuf[8:12], shdr.VirtualSize)
		binary.LittleEndian.PutUint32(shBuf[12:16], shdr.VirtualAddress)
		binary.LittleEndian.PutUint32(shBuf[16:20], shdr.SizeOfRawData)
		binary.LittleEndian.PutUint32(shBuf[20:24], shdr.PointerToRawData)
		binary.LittleEndian.PutUint32(shBuf[24:28], shdr.PointerToRelocations)
		binary.LittleEndian.PutUint32(shBuf[28:32], shdr.PointerToLinenumbers)
		binary.LittleEndian.PutUint16(shBuf[32:34], shdr.NumberOfRelocations)
		binary.LittleEndian.PutUint16(shBuf[34:36], shdr.NumberOfLinenumbers)
		binary.LittleEndian.PutUint32(shBuf[36:40], shdr.Characteristics)

		_, err = file.Write(shBuf)
		if err != nil {
			err
		}
	}
	
	for i, shdr := range po.Sections {
		if data, ok := po.SectionData[i32(i)]; ok {
			_, err = file.Write(data)
			if err != nil {
				err
			}
			
			padding := shdr.SizeOfRawData - u32(len(data))
			if padding > 0 {
				padBuf := make(u8[], padding)
				_, err = file.Write(padBuf)
				if err != nil {
					err
				}
			}
		}
	}

	nil
}
