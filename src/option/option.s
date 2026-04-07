package std.option

enum Option[T] {
    Some(T),
    None,
}

impl Option[T] {
    func is_some(self) bool {
        match self {
            Option::Some(_) => true,
            Option::None => false,
        }
    }

    func is_none(self) bool {
        !self.is_some()
    }

    func unwrap(self) T {
        match self {
            Option::Some(value) => value,
            Option::None => __option_panic_unwrap(),
        }
    }

    func unwrap_or(self, T default) T {
        match self {
            Option::Some(value) => value,
            Option::None => default,
        }
    }
}

extern "intrinsic" func __option_panic_unwrap[T]() T
