package std.option

pub enum Option[T] {
    Some(T),
    None,
}

impl Option[T] {
    pub fn is_some(self) -> bool {
        match self {
            Option::Some(_) => true,
            Option::None => false,
        }
    }

    pub fn is_none(self) -> bool {
        !self.is_some()
    }

    pub fn unwrap(self) -> T {
        match self {
            Option::Some(value) => value,
            Option::None => __option_panic_unwrap(),
        }
    }

    pub fn unwrap_or(self, default: T) -> T {
        match self {
            Option::Some(value) => value,
            Option::None => default,
        }
    }
}

extern "intrinsic" fn __option_panic_unwrap[T]() -> T
