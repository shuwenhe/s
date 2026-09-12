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
	u32 magic
	i32 cpu_type
	i32 cpu_subtype
	u32 file_type
	u32 num_commands
	u32 commands_size
	u32 flags
	u32 reserved
}

struct macho_load_command {
	u32 cmd
	u32 size
	u8[] data
}

struct macho_segment {
	[16]u8 name
	u64 vm_addr
	u64 vm_size
	u64 file_offset
	u64 file_size
	i32 max_prot
	i32 init_prot
	u32 num_sections
	u32 flags
	macho_section[] sections
}

struct macho_section {
	[16]u8 name
	[16]u8 seg_name
	u64 addr
	u64 size
	u32 offset
	u32 align
	u32 reloff
	u32 nreloc
	u32 flags
	u32 reserved1
	u32 reserved2
	u32 reserved3
}

struct macho_object {
	macho_header header
	macho_load_command[] load_commands
	macho_segment[] segments
	macho_symbol[] symbol_table
	u8[] strings
}

struct macho_symbol {
	string name
	u64 value
	u8 section
	u16 desc
	u8 type
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

func (mo macho_object*) add_segment(string name, vmAddr i64, vmSize i64) {
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

	name_bytes := u8[](name)
	for i := i32(0); i < 16 && i < i32(len(name_bytes)); i += 1 {
		seg.Name[i] = name_bytes[i]
	}

	mo.Segments = append(mo.Segments, seg)
}

func (mo macho_object*) add_symbol(sym macho_symbol) {
	mo.SymbolTable = append(mo.SymbolTable, sym)
}

func read_macho_object(string filename) (macho_object, error) {
	file, err := os.open(filename)
	if err != nil {
		macho_object{}, err
	}
	defer file.close()

	hdr_buf := make(u8[], 32)
	_, err = file.read(hdr_buf)
	if err != nil {
		macho_object{}, err
	}

	magic := binary.LittleEndian.uint32(hdr_buf[0:4])
	if magic != MACHO_MAGIC_64 {
		macho_object{}, "invalid Mach-O magic"
	}

	obj := new_macho_object(macho_machine(binary.LittleEndian.uint32(hdr_buf[4:8])), 
		macho_file_type(binary.LittleEndian.uint32(hdr_buf[12:16])))

	obj.Header.CpuType = i32(binary.LittleEndian.uint32(hdr_buf[4:8]))
	obj.Header.CpuSubtype = i32(binary.LittleEndian.uint32(hdr_buf[8:12]))
	obj.Header.NumCommands = binary.LittleEndian.uint32(hdr_buf[16:20])
	obj.Header.CommandsSize = binary.LittleEndian.uint32(hdr_buf[20:24])
	obj.Header.Flags = binary.LittleEndian.uint32(hdr_buf[24:28])

	obj, nil
}

func (macho_object* mo) write_to_file(string filename) error {
	file, err := os.create(filename)
	if err != nil {
		err
	}
	defer file.close()

	hdr_buf := make(u8[], 32)

	binary.LittleEndian.put_uint32(hdr_buf[0:4], mo.Header.Magic)
	binary.LittleEndian.put_uint32(hdr_buf[4:8], u32(mo.Header.CpuType))
	binary.LittleEndian.put_uint32(hdr_buf[8:12], u32(mo.Header.CpuSubtype))
	binary.LittleEndian.put_uint32(hdr_buf[12:16], mo.Header.FileType)
	binary.LittleEndian.put_uint32(hdr_buf[16:20], mo.Header.NumCommands)
	binary.LittleEndian.put_uint32(hdr_buf[20:24], mo.Header.CommandsSize)
	binary.LittleEndian.put_uint32(hdr_buf[24:28], mo.Header.Flags)
	binary.LittleEndian.put_uint32(hdr_buf[28:32], mo.Header.Reserved)

	_, err = file.write(hdr_buf)
	if err != nil {
		err
	}

	for _, cmd := range mo.LoadCommands {
		cmd_buf := make(u8[], 8)
		binary.LittleEndian.put_uint32(cmd_buf[0:4], cmd.Cmd)
		binary.LittleEndian.put_uint32(cmd_buf[4:8], cmd.Size)

		_, err = file.write(cmd_buf)
		if err != nil {
			err
		}

		_, err = file.write(cmd.Data)
		if err != nil {
			err
		}
	}

	nil
}