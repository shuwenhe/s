package src.reflect

const kind_invalid = 0
const kind_bool = 1
const kind_int = 2
const kind_string = 3
const kind_struct = 4
const kind_array = 5
const kind_function = 6

struct field {
    string name
    int offset
    int size
    int type_id
    bool exported
}

struct type {
    int id
    string name
    int kind
    int size
    int align
    field[] fields
}

func invalid_type() type {
    type { id: 0, name: "", kind kind_invalid, size 0, align 1, fields field[]() }
}

func new_type(int id, string name, int kind, int size, int align) type {
    type { id: id, name: name, kind kind, size size, align align, fields field[]() }
}

func (type* self) add_field(string name, int offset, int size, int type_id, bool exported) () {
    self.fields.push(field { name: name, offset: offset, size: size, type_id: type_id, exported: exported })
}

func (type* self) field_count() int { len(self.fields) }

func (type* self) field_at(int index) field {
    if index < 0 || index >= len(self.fields) {
        return field { name: "", offset: -1, size: 0, type_id: 0, exported: false }
    }
    self.fields[index]
}

func (type* self) is_assignable_to(type target) bool {
    self.id == target.id
}

func type_unit_name() string {
    "src/reflect/type"
}
func type_unit_name() string {
    "src/reflect/type"
}

func type_unit_ready() int {
    1
}
