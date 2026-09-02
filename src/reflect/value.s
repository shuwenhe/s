package src.reflect

struct value {
    int address
    type type_info
    int int_value
    bool bool_value
    string string_value
}

func int_value(int number, type value_type) value {
    value { address: 0, type_info: value_type, int_value: number, bool_value: false, string_value: "" }
}

func bool_value(bool flag, type value_type) value {
    value { address: 0, type_info: value_type, int_value: 0, bool_value: flag, string_value: "" }
}

func string_value(string text, type value_type) value {
    value { address: 0, type_info: value_type, int_value: 0, bool_value: false, string_value: text }
}

func address_value(int address, type value_type) value {
    value { address: address, type_info: value_type, int_value: 0, bool_value: false, string_value: "" }
}

func (value* self) type_of() type { self.type_info }
func (value* self) can_int() bool { self.type_info.kind == kind_int }
func (value* self) can_bool() bool { self.type_info.kind == kind_bool }
func (value* self) can_string() bool { self.type_info.kind == kind_string }

func (value* self) as_int() int {
    if !self.can_int() {
        return 0
    }
    self.int_value
}

func (value* self) as_bool() bool {
    if !self.can_bool() {
        return false
    }
    self.bool_value
}

func (value* self) as_string() string {
    if !self.can_string() {
        return ""
    }
    self.string_value
}

func value_unit_name() string {
    "src/reflect/value"
}

func value_unit_ready() int {
    1
}
