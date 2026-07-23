package std.option

enum option[t] {
    some(t),
    none,
}

func (self: option[t]) is_some() bool {
        switch self {
            option::some(_) : true,
            option::none : false,
        }
    }

func (self: option[t]) is_none() bool {
        !self.is_some()
    }

func (self: option[t]) unwrap() t {
        switch self {
            option::some(value) : value,
            option::none : __option_panic_unwrap(),
        }
    }

func (self: option[t]) unwrap_or(t default) t {
        switch self {
            option::some(value) : value,
            option::none : default,
        }
    }

extern "intrinsic" func __option_panic_unwrap[t]() t
