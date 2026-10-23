package std.result
enum result[t, e] {
    ok(t),
    err(e),
}

func (result[t, e]* self) is_ok() bool {
    return switch self {
        result::ok(_)  : true,
        result::err(_) : false,
    }
}

func (result[t, e]* self) is_err() bool {
    return !self.is_ok()
}

func (result[t, e]* self) unwrap() t {
    switch self {
        result::ok(value) : return value,
        result::err(_)    : {
            // Panic path - should never execute normally
            panic("called unwrap on an error result")
        }
    }
}

func (result[t, e]* self) unwrap_err() e {
    switch self {
        result::ok(_)      : {
            // Panic path - should never execute normally
            panic("called unwrap_err on an ok result")
        }
        result::err(value) : return value,
    }
}
extern "intrinsic" func __result_panic_unwrap[t]() t
extern "intrinsic" func __result_panic_unwrap_err[e]() e
