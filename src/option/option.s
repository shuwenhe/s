package std.option
enum option[t] {
    some(t),
    none,
}

func (option[t] self) is_some() bool {
    return switch self {
        option::some(_) : true,
        option::none : false,
    }
}

func (option[t] self) is_none() bool {
    return !self.is_some()
}

func (option[t] self) unwrap() t {
    switch self {
        option::some(value) : return value,
        option::none : {
            // Panic path - should never execute normally
            panic("called unwrap on a none option")
        }
    }
}

func (option[t] self) unwrap_or(t default) t {
    return switch self {
        option::some(value) : value,
        option::none : default,
    }
}
extern "intrinsic" func __option_panic_unwrap[t]() t
