package std.result

enum (t, e) {
    ok(t),
    err(e),
}

func ((t, e)* self) is_ok() bool {
    switch self {
        result::ok(_)  : true,
        result::err(_) : false,
    }
}

func ((t, e)* self) is_err() bool {
    !self.is_ok()
}

func ((t, e)* self) unwrap() t {
    switch self {
        result::ok(value) : value,
        result::err(_)    : __result_panic_unwrap(),
    }
}

func ((t, e)* self) unwrap_err() e {
    switch self {
        result::ok(_)    : __result_panic_unwrap_err(),
        result::err(err) : err,
    }
}

extern "intrinsic" func __result_panic_unwrap[t]() t
extern "intrinsic" func __result_panic_unwrap_err[e]() e
