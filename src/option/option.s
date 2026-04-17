package std.option

enum Option[T] {
    Some(T),
    None,
}

impl Option[T] {
    func isSome(self) bool {
        switch self {
            Option::Some(_) : true,
            Option::None : false,
        }
    }

    func isNone(self) bool {
        !self.isSome()
    }

    func unwrap(self) T {
        switch self {
            Option::Some(value) : value,
            Option::None : __option_panic_unwrap(),
        }
    }

    func unwrapOr(self, T default) T {
        switch self {
            Option::Some(value) : value,
            Option::None : default,
        }
    }
}

extern "intrinsic" func __option_panic_unwrap[T]() T
