package std.result

enum Result[T, E] {
    Ok(T),
    Err(E),
}

impl Result[T, E] {
    func isOk(self) bool {
        match self {
            Result::Ok(_) => true,
            Result::Err(_) => false,
        }
    }

    func isErr(self) bool {
        !self.isOk()
    }

    func unwrap(self) T {
        match self {
            Result::Ok(value) => value,
            Result::Err(_) => __result_panic_unwrap(),
        }
    }

    func unwrapErr(self) E {
        match self {
            Result::Ok(_) => __result_panic_unwrap_err(),
            Result::Err(err) => err,
        }
    }
}

extern "intrinsic" func __result_panic_unwrap[T]() T

extern "intrinsic" func __result_panic_unwrap_err[E]() E
