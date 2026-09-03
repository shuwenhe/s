package src.cmd.link.internal.ld

import (
	"src/encoding/binary"
	"src/os"
)


const (
	MACHO_MAGIC_64 = 0xfeedf00f
	MACHO_MAGIC_FAT = 0xcafebabe
)


enum macho_machine {
	CPU_TYPE_I386 = 7
	CPU_TYPE_X86 = 7
	CPU_TYPE_X86_64 = 0x07000003
	CPU_TYPE_ARM = 12
	CPU_TYPE_ARM64 = 0x0100000c
	CPU_TYPE_POWERPC = 18
	CPU_TYPE_POWERPC64 = 0x01000012
}


enum macho_file_type {
	MH_OBJECT = 0x1
	MH_EXECUTE = 0x2
	MH_FVMLIB = 0x3
	MH_CORE = 0x4
	MH_PRELOAD = 0x5
	MH_DYLIB = 0x6
	MH_DYLINKER = 0x7
	MH_BUNDLE = 0x8
	MH_DYLIB_STUB = 0x9
	MH_DSYM = 0xa
	MH_KEXT_BUNDLE = 0xb
}


struct macho_header {
	magic          u32
	cpu_type        i32
	cpu_subtype     i32
	file_type       u32
	num_commands    u32
	commands_size   u32
	flags          u32
	reserved       u32  
}


struct macho_load_command {
	cmd  u32
	size u32
	data u8[]
}


struct macho_segment {
	name         [16]u8
	vm_addr       u64
	vm_size       u64
	file_offset   u64
	file_size     u64
	max_prot      i32
	init_prot     i32
	num_sections  u32
	flags        u32
	sections macho_section[]
}


struct macho_section {
	name       [16]u8
	seg_name    [16]u8
	addr       u64
	size       u64
	offset     u32
	align      u32
	reloff     u32
	nreloc     u32
	flags      u32
	reserved1  u32
	reserved2  u32
	reserved3  u32
}


struct macho_object {
	header       macho_header
	load_commands macho_load_command[]
	segments macho_segment[]
	symbol_table macho_symbol[]
	strings u8[]
}


struct macho_symbol {
	name    string
	value   u64
	section u8
	desc    u16
	type    u8
}


func new_macho_object(cpuType macho_machine, filetype macho_file_type) macho_object {
	obj := macho_object{
		Header: macho_header{
			Magic: MACHO_MAGIC_64,
			CpuType: i32(cpuType),
			CpuSubtype: 0,
			FileType: u32(filetype),
			NumCommands: 0,
			CommandsSize: 0,
			Flags: 0,
			Reserved: 0,
		},
		LoadCommands: make(macho_load_command[], 0),
		Segments: make(macho_segment[], 0),
		SymbolTable: make(macho_symbol[], 0),
		Strings: make(u8[], 0),
	}

	obj
}


func (mo macho_object*) AddSegment(name string, vmAddr i64, vmSize i64) {
	seg := macho_segment{
		VmAddr: u64(vmAddr),
		VmSize: u64(vmSize),
		FileOffset: 0,
		FileSize: 0,
		MaxProt: 3,  
		InitProt: 1, 
		NumSections: 0,
		Flags: 0,
		Sections: make(macho_section[], 0),
	}

	
	nameBytes := u8[](name)
	for i := i32(0); i < 16 && i < i32(len(nameBytes)); i += 1 {
		seg.Name[i] = nameBytes[i]
	}

	mo.Segments = append(mo.Segments, seg)
}


func (mo macho_object*) AddSymbol(sym macho_symbol) {
	mo.SymbolTable = append(mo.SymbolTable, sym)
}


func ReadMachoObject(string filename) (macho_object, error) {
	file, err := os.Open(filename)
	if err != nil {
		macho_object{}, err
	}
	defer file.Close()

	
	hdrBuf := make(u8[], 32)
	_, err = file.Read(hdrBuf)
	if err != nil {
		macho_object{}, err
	}

	magic := binary.LittleEndian.Uint32(hdrBuf[0:4])
	if magic != MACHO_MAGIC_64 {
		macho_object{}, "invalid Mach-O magic"
	}

	obj := new_macho_object(macho_machine(binary.LittleEndian.Uint32(hdrBuf[4:8])), 
		macho_file_type(binary.LittleEndian.Uint32(hdrBuf[12:16])))

	obj.Header.CpuType = i32(binary.LittleEndian.Uint32(hdrBuf[4:8]))
	obj.Header.CpuSubtype = i32(binary.LittleEndian.Uint32(hdrBuf[8:12]))
	obj.Header.NumCommands = binary.LittleEndian.Uint32(hdrBuf[16:20])
	obj.Header.CommandsSize = binary.LittleEndian.Uint32(hdrBuf[20:24])
	obj.Header.Flags = binary.LittleEndian.Uint32(hdrBuf[24:28])

	obj, nil
}


func (macho_object* mo) WriteToFile(string filename) error {
	file, err := os.Create(filename)
	if err != nil {
		err
	}
	defer file.Close()

	
	hdrBuf := make(u8[], 32)

	binary.LittleEndian.PutUint32(hdrBuf[0:4], mo.Header.Magic)
	binary.LittleEndian.PutUint32(hdrBuf[4:8], u32(mo.Header.CpuType))
	binary.LittleEndian.PutUint32(hdrBuf[8:12], u32(mo.Header.CpuSubtype))
	binary.LittleEndian.PutUint32(hdrBuf[12:16], mo.Header.FileType)
	binary.LittleEndian.PutUint32(hdrBuf[16:20], mo.Header.NumCommands)
	binary.LittleEndian.PutUint32(hdrBuf[20:24], mo.Header.CommandsSize)
	binary.LittleEndian.PutUint32(hdrBuf[24:28], mo.Header.Flags)
	binary.LittleEndian.PutUint32(hdrBuf[28:32], mo.Header.Reserved)

	_, err = file.Write(hdrBuf)
	if err != nil {
		err
	}

	
	for _, cmd := range mo.LoadCommands {
		cmdBuf := make(u8[], 8)
		binary.LittleEndian.PutUint32(cmdBuf[0:4], cmd.Cmd)
		binary.LittleEndian.PutUint32(cmdBuf[4:8], cmd.Size)

		_, err = file.Write(cmdBuf)
		if err != nil {
			err
		}

		_, err = file.Write(cmd.Data)
		if err != nil {
			err
		}
	}

	nil
}
