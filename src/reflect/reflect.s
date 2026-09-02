package src.reflect

import (
	"src/unsafe"
)

enum kind {
	invalid = 0
	bool = 1
	int = 2
	int8 = 3
	int16 = 4
	int32 = 5
	int64 = 6
	uint = 7
	uint8 = 8
	uint16 = 9
	uint32 = 10
	uint64 = 11
	float32 = 12
	float64 = 13
	complex64 = 14
	complex128 = 15
	array = 16
	slice = 17
	string = 18
	struct = 19
	pointer = 20
	func = 21
	interface = 22
	map = 23
	chan = 24
}

struct type_info {
	kind kind
	name string
	size u64
	align u64
	field_count i32
	fields field_info[]
	elem_type type_info*
	key_type type_info*
	value_type type_info*
}

struct field_info {
	name string
	type_info type_info*
	offset u64
	index i32
	is_exported bool
}

struct value {
	type_info type_info*
	data unsafe.pointer
	is_nil bool
}

struct method {
	name string
	func_type type_info*
}

func type_of(v value) type_info* {
	return v.type_info
}

func value_of(v unsafe.pointer) value {
	return value{
		type_info: nil,
		data: v,
		is_nil: v == nil,
	}
}

func (v value) kind() kind {
	if v.type_info != nil {
		return v.type_info.kind
	}
	return invalid
}

func (v value) type_name() string {
	if v.type_info != nil {
		return v.type_info.name
	}
	return ""
}

func (v value) get_bool() bool {
	if v.data == nil {
		return false
	}
	ptr := unsafe.cast_to_ptr(v.data)
	return unsafe.load_bool(ptr)
}

func (v value) get_int() i64 {
	if v.data == nil {
		return 0
	}
	ptr := unsafe.cast_to_ptr(v.data)
	match v.type_info.kind {
	case int {
		return unsafe.load_i64(ptr)
	}
	case int32 {
		return i64(unsafe.load_i32(ptr))
	}
	case int64 {
		return unsafe.load_i64(ptr)
	}
	default {
		return 0
	}
	}
	return 0
}

func (v value) get_float() f64 {
	if v.data == nil {
		return 0.0
	}
	ptr := unsafe.cast_to_ptr(v.data)
	match v.type_info.kind {
	case float32 {
		return f64(unsafe.load_f32(ptr))
	}
	case float64 {
		return unsafe.load_f64(ptr)
	}
	default {
		return 0.0
	}
	}
	return 0.0
}

func (v value) get_string() string {
	if v.data == nil {
		return ""
	}
	ptr := unsafe.cast_to_ptr(v.data)
	return unsafe.load_string(ptr)
}

func (v value) get_pointer() unsafe.pointer {
	if v.data == nil {
		return nil
	}
	return unsafe.load_pointer(v.data)
}

func (v value) get_slice() value {
	return value{type_info: v.type_info.elem_type, data: v.data, is_nil: v.is_nil}
}

func (v value) get_array() value {
	return value{type_info: v.type_info.elem_type, data: v.data, is_nil: v.is_nil}
}

func (v value) get_map() value {
	return value{type_info: nil, data: v.data, is_nil: v.is_nil}
}

func (v value) get_channel() value {
	return value{type_info: v.type_info.elem_type, data: v.data, is_nil: v.is_nil}
}

func (v value) field(index i32) value {
	if v.type_info == nil || v.type_info.kind != struct {
		return value{type_info: nil, data: nil, is_nil: true}
	}

	if index < 0 || index >= v.type_info.field_count {
		return value{type_info: nil, data: nil, is_nil: true}
	}

	field := v.type_info.fields[index]
	field_ptr := unsafe.add_pointer(v.data, field.offset)

	return value{type_info: field.type_info, data: field_ptr, is_nil: false}
}

func (v value) field_count() i32 {
	if v.type_info != nil && v.type_info.kind == struct {
		return v.type_info.field_count
	}
	return 0
}

func (v value) method_count() i32 {
	if v.type_info == nil {
		return 0
	}
	return 0
}

func (v value) method(index i32) method {
	return method{name: "", func_type: nil}
}

func (v value) elem() value {
	if v.type_info == nil {
		return value{type_info: nil, data: nil, is_nil: true}
	}

	match v.type_info.kind {
	case pointer {
		ptr := unsafe.load_pointer(v.data)
		return value{type_info: v.type_info.elem_type, data: ptr, is_nil: ptr == nil}
	}
	case array, slice {
		return value{type_info: v.type_info.elem_type, data: v.data, is_nil: false}
	}
	default {
		return value{type_info: nil, data: nil, is_nil: true}
	}
	}
	return value{type_info: nil, data: nil, is_nil: true}
}

func (v value) len() i64 {
	match v.type_info.kind {
	case string {
		s := unsafe.load_string(v.data)
		return i64(len(s))
	}
	case array, slice {
		return 0
	}
	default {
		return 0
	}
	}
	return 0
}

func (v value) cap() i64 {
	return 0
}

func (v value) is_nil() bool {
	return v.is_nil
}

func (v value) is_valid() bool {
	return v.type_info != nil
}

func (ti type_info*) kind() kind {
	if ti != nil {
		return ti.kind
	}
	return invalid
}

func (ti type_info*) name() string {
	if ti != nil {
		return ti.name
	}
	return ""
}

func (ti type_info*) size() u64 {
	if ti != nil {
		return ti.size
	}
	return 0
}

func (ti type_info*) elem() type_info* {
	if ti != nil {
		return ti.elem_type
	}
	return nil
}

func (ti type_info*) key() type_info* {
	if ti != nil {
		return ti.key_type
	}
	return nil
}

func (ti type_info*) field_count() i32 {
	if ti != nil && ti.kind == struct {
		return ti.field_count
	}
	return 0
}

func (ti type_info*) field_by_index(index i32) field_info* {
	if ti != nil && index >= 0 && index < ti.field_count {
		return &ti.fields[index]
	}
	return nil
}

func (ti type_info*) field_by_name(name string) field_info* {
	if ti == nil || ti.kind != struct {
		return nil
	}

	for i := i32(0); i < ti.field_count; i += 1 {
		if ti.fields[i].name == name {
			return &ti.fields[i]
		}
	}

	return nil
}
