package std.result

enum Result[T, E] {
    Ok(T),
    Err(E),
}

impl Result[T, E] {
    func is_ok(self) bool {
        switch self {
            Result::Ok(_) : true,
            Result::Err(_) : false,
        }
    }

    func is_err(self) bool {
        !self.is_ok()
    }

    func unwrap(self) T {
        switch self {
            Result::Ok(value) : value,
            Result::Err(_) : __result_panic_unwrap(),
        }
    }

    func unwrap_err(self) E {
        switch self {
            Result::Ok(_) : __result_panic_unwrap_err(),
            Result::Err(err) : err,
        }
    }
}

extern "intrinsic" func __result_panic_unwrap[T]() T

extern "intrinsic" func __result_panic_unwrap_err[E]() E
