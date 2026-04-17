package std.option

enum Option[T] {
    Some(T),
    None,
}

impl Option[T] {
    func isSome(self) bool {
        match self {
            Option::Some(_) => true,
            Option::None => false,
        }
    }

    func isNone(self) bool {
        !self.isSome()
    }

    func unwrap(self) T {
        match self {
            Option::Some(value) => value,
            Option::None => __option_panic_unwrap(),
        }
    }

    func unwrapOr(self, T default) T {
        match self {
            Option::Some(value) => value,
            Option::None => default,
        }
    }
}

extern "intrinsic" func __option_panic_unwrap[T]() T
