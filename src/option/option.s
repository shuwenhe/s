package std.option
enum option[t] {
    some(t),
    none,
}
func (option[t]* self) is_some() bool {
        switch self {
            option::some(_) : true,
            option::none : false,
        }
    }

func (option[t]* self) is_none() bool {
        !self.is_some()
    }

func (option[t]* self) unwrap() t {
        switch self {
            option::some(value) : value,
            option::none : __option_panic_unwrap(),
        }
    }

func (option[t]* self) unwrap_or(t default) t {
        switch self {
            option::some(value) : value,
            option::none : default,
        }
    }
extern "intrinsic" func __option_panic_unwrap[t]() t
