package std.result

pub enum Result[T, E] {
    Ok(T),
    Err(E),
}

impl Result[T, E] {
    fn is_ok(self) -> bool {
        match self {
            Result::Ok(_) => true,
            Result::Err(_) => false,
        }
    }

    fn is_err(self) -> bool {
        !self.is_ok()
    }

    fn unwrap(self) -> T {
        match self {
            Result::Ok(value) => value,
            Result::Err(_) => __result_panic_unwrap(),
        }
    }

    fn unwrap_err(self) -> E {
        match self {
            Result::Ok(_) => __result_panic_unwrap_err(),
            Result::Err(err) => err,
        }
    }
}

extern "intrinsic" fn __result_panic_unwrap[T]() -> T

extern "intrinsic" fn __result_panic_unwrap_err[E]() -> E
