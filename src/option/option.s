package std.option

enum option[t] {
    some(t),
    none,
}

impl option[t] {
    func is_some(self) bool {
        switch self {
            option::some(_) : true,
            option::none : false,
        }
    }

    func is_none(self) bool {
        !self.is_some()
    }

    func unwrap(self) t {
        switch self {
            option::some(value) : value,
            option::none : __option_panic_unwrap(),
        }
    }

    func unwrap_or(self, t default) t {
        switch self {
            option::some(value) : value,
            option::none : default,
        }
    }
}

extern "intrinsic" func __option_panic_unwrap[t]() t
