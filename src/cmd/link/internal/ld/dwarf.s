package src.cmd.link.internal.ld

import (
	"src/fmt"
	"src/time"
	"src/crypto/sha256"
)

const (
	DWARF_VERSION_2 = 2
	DWARF_VERSION_3 = 3
	DWARF_VERSION_4 = 4
	DWARF_VERSION_5 = 5
)

enum dwarf_tag {
	DW_TAG_COMPILE_UNIT = 0x11
	DW_TAG_TYPE_UNIT = 0x41
	DW_TAG_SUBPROGRAM = 0x2e
	DW_TAG_VARIABLE = 0x34
	DW_TAG_PARAMETER = 0x05
	DW_TAG_BASE_TYPE = 0x24
	DW_TAG_POINTER_TYPE = 0xf
	DW_TAG_ARRAY_TYPE = 0x01
	DW_TAG_STRUCTURE_TYPE = 0x13
	DW_TAG_UNION_TYPE = 0x17
	DW_TAG_ENUMERATION_TYPE = 0x04
	DW_TAG_CLASS_TYPE = 0x02
	DW_TAG_LEXICAL_BLOCK = 0x0b
	DW_TAG_NAMESPACE = 0x39
	DW_TAG_MODULE = 0x1d
}

enum dwarf_attribute {
	DW_AT_NAME = 0x03
	DW_AT_TYPE = 0x49
	DW_AT_LOCATION = 0x02
	DW_AT_BYTE_SIZE = 0x0b
	DW_AT_ENCODING = 0x0e
	DW_AT_DECL_FILE = 0x3a
	DW_AT_DECL_LINE = 0x3b
	DW_AT_DECL_COLUMN = 0x39
	DW_AT_PRODUCER = 0x25
	DW_AT_LANGUAGE = 0x13
	DW_AT_LOW_PC = 0x11
	DW_AT_HIGH_PC = 0x12
	DW_AT_RANGES = 0x55
	DW_AT_ACCESSIBILITY = 0x32
	DW_AT_ARTIFICIAL = 0x34
	DW_AT_EXTERNAL = 0x3f
}

enum dwarf_encoding {
	DW_ATE_ADDRESS = 0x1
	DW_ATE_BOOLEAN = 0x2
	DW_ATE_COMPLEX_FLOAT = 0x3
	DW_ATE_FLOAT = 0x4
	DW_ATE_SIGNED = 0x5
	DW_ATE_SIGNED_CHAR = 0x6
	DW_ATE_UNSIGNED = 0x7
	DW_ATE_UNSIGNED_CHAR = 0x8
	DW_ATE_IMAGINARY_FLOAT = 0x9
	DW_ATE_PACKED_DECIMAL = 0xa
	DW_ATE_NUMERIC_STRING = 0xb
	DW_ATE_EDITED = 0xc
	DW_ATE_SIGNED_FIXED = 0xd
	DW_ATE_UNSIGNED_FIXED = 0xe
	DW_ATE_DECIMAL_FLOAT = 0xf
	DW_ATE_UTF = 0x10
}

struct dwarf_die {
	dwarf_tag tag
	map[dwarf_attribute]dwarf_attribute_value attributes
	dwarf_die[] children
	i64 offset
}

enum dwarf_attribute_value {
	IntValue(i64)
	StringValue(string)
	RefValue(i64)
	BlockValue(u8[])
	AddressValue(i64)
	BoolValue(bool)
}

struct dwarf_compile_unit {
	i32 version
	i64 abbrev_offset
	i32 address_size
	i64 offset
	i32 unit_type
	dwarf_die die
	dwarf_line_info line_info
	DWARFLocationInfo[] location_info
}

struct dwarf_line_info {
	i32 min_instruction_length
	i32 line_base
	i32 line_range
	i32 opcode_base
	u8[] prologue
	string[] file_names
	string[] directory_names
	dwarf_line_statement[] statements
}

struct dwarf_line_statement {
	i64 address
	i32 file
	i32 line
	i32 column
	bool is_stmt
	bool basic_block
	bool end_sequence
}

struct DWARFLocationInfo {
	string variable
	i64 address
	i64 size
	i32 register
	i64 offset
}

struct dwarf_manager {
	dwarf_compile_unit[] compile_units
	map[i32]u8[] abbrev_table
	map[string]i64 str_offsets
	dwarf_line_info[] line_info
	i32 version
}

func new_dwarfmanager(version i32) dwarf_manager {
	dwarf_manager{
		CompileUnits: make(dwarf_compile_unit[], 0),
		AbbrevTable: make(map[i32]u8[]),
		StrOffsets: make(map[string]i64),
		LineInfo: make(dwarf_line_info[], 0),
		Version: version,
	}
}

func (dm* dwarf_manager) add_compile_unit(cu dwarf_compile_unit) {
	dm.CompileUnits = append(dm.CompileUnits, cu)
}

func (dm* dwarf_manager) generate_debug_line() u8[] {
	data := make(u8[], 0)

	for _, line_info := range dm.LineInfo {

		len_offset := len(data)
		data = append(data, 0, 0, 0, 0, 0, 0, 0, 0)

		version_start := len(data)

		data = append(data, 4, 0) 

		hdr_len_offset := len(data)
		data = append(data, 0, 0, 0, 0, 0, 0, 0, 0)

		data = append(data, u8(line_info.MinInstructionLength))

		data = append(data, 1)

		data = append(data, 1)

		data = append(data,
			u8(line_info.LineBase),
			u8(line_info.LineBase >> 8),
			u8(line_info.LineBase >> 16),
			u8(line_info.LineBase >> 24))

		data = append(data, u8(line_info.LineRange))

		data = append(data, u8(line_info.OpcodeBase))

		for i := i32(1); i < line_info.OpcodeBase; i += 1 {
			data = append(data, 0)
		}

		for _, dir := range line_info.DirectoryNames {
			data = append(data, u8[](dir)...)
			data = append(data, 0)
		}
		data = append(data, 0) 

		for _, fname := range line_info.FileNames {
			data = append(data, u8[](fname)...)
			data = append(data, 0)
			data = append(data, 1) 
			data = append(data, 0) 
			data = append(data, 0) 
		}
		data = append(data, 0) 
	}

	data
}

struct UnwindInfo {
	i32 version
	i64 eh_frame_offset
	FrameDescriptionEntry[] fdes
	CommonInformationEntry[] cies
}

struct CommonInformationEntry {
	i32 length
	i32 cie_id
	i32 version
	string augmentation_string
	i32 code_alignment_factor
	i32 data_alignment_factor
	i32 return_address_register
	u8[] augmentation_data
}

struct FrameDescriptionEntry {
	i32 length
	i32 cie_pointer
	i64 pc_begin
	i64 pc_range
	u8[] augmentation_data
	u8[] instructions
}

struct unwind_manager {
	UnwindInfo unwind_info
}

func new_unwind_manager() unwind_manager {
	unwind_manager{
		UnwindInfo: UnwindInfo{
			Version: 1,
			EhFrameOffset: 0,
			Fdes: make(FrameDescriptionEntry[], 0),
			Cies: make(CommonInformationEntry[], 0),
		},
	}
}

func (um* unwind_manager) generate_eh_frame() u8[] {
	data := make(u8[], 0)

	for _, cie := range um.UnwindInfo.Cies {
		data = append(data,
			u8(cie.Length),
			u8(cie.Length >> 8),
			u8(cie.Length >> 16),
			u8(cie.Length >> 24))

		data = append(data,
			u8(cie.CieId),
			u8(cie.CieId >> 8),
			u8(cie.CieId >> 16),
			u8(cie.CieId >> 24))

		data = append(data, u8(cie.Version))
		data = append(data, u8[](cie.AugmentationString)...)
		data = append(data, 0)

		data = append(data, u8(cie.CodeAlignmentFactor))
		data = append(data, u8(cie.DataAlignmentFactor))
		data = append(data, u8(cie.ReturnAddressRegister))

		data = append(data, cie.AugmentationData...)
	}

	for _, fde := range um.UnwindInfo.Fdes {
		data = append(data,
			u8(fde.Length),
			u8(fde.Length >> 8),
			u8(fde.Length >> 16),
			u8(fde.Length >> 24))

		data = append(data,
			u8(fde.CiePointer),
			u8(fde.CiePointer >> 8),
			u8(fde.CiePointer >> 16),
			u8(fde.CiePointer >> 24))

		data = append(data,
			u8(fde.PcBegin),
			u8(fde.PcBegin >> 8),
			u8(fde.PcBegin >> 16),
			u8(fde.PcBegin >> 24),
			u8(fde.PcBegin >> 32),
			u8(fde.PcBegin >> 40),
			u8(fde.PcBegin >> 48),
			u8(fde.PcBegin >> 56))

		data = append(data,
			u8(fde.PcRange),
			u8(fde.PcRange >> 8),
			u8(fde.PcRange >> 16),
			u8(fde.PcRange >> 24),
			u8(fde.PcRange >> 32),
			u8(fde.PcRange >> 40),
			u8(fde.PcRange >> 48),
			u8(fde.PcRange >> 56))

		data = append(data, fde.AugmentationData...)
		data = append(data, fde.Instructions...)
	}

	data
}