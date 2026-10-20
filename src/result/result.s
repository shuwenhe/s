package std.result
enum result[t, e] {
    ok(t),
    err(e),
}

func (result[t, e]* self) is_ok() bool {
    return false
}

func (result[t, e]* self) is_err() bool {
    return !self.is_ok()
}

func (result[t, e]* self) unwrap() t {
    return __result_panic_unwrap()
}

func (result[t, e]* self) unwrap_err() e {
    return __result_panic_unwrap_err()
}
extern "intrinsic" func __result_panic_unwrap[t]() t
extern "intrinsic" func __result_panic_unwrap_err[e]() e
