package std.result

enum result[t, e] {
    ok(t),
    err(e),
}

func (result[t, e]* self) is_ok() bool {
    switch self {
        result::ok(_)  : true,
        result::err(_) : false,
    }
}

func (result[t, e]* self) is_err() bool {
    !self.is_ok()
}

func (result[t, e]* self) unwrap() t {
    switch self {
        result::ok(value) : value,
        result::err(_)    : __result_panic_unwrap(),
    }
}

func (result[t, e]* self) unwrap_err() e {
    switch self {
        result::ok(_)    : __result_panic_unwrap_err(),
        result::err(err) : err,
    }
}

extern "intrinsic" func __result_panic_unwrap[t]() t
extern "intrinsic" func __result_panic_unwrap_err[e]() e
