package std.result

enum result[t, e] {
    ok(t),
    err(e),
}

func (self: result[t, e]) is_ok() bool {
        switch self {
            result::ok(_) : true,
            result::err(_) : false,
        }
    }

func (self: result[t, e]) is_err() bool {
        !self.is_ok()
    }

func (self: result[t, e]) unwrap() t {
        switch self {
            result::ok(value) : value,
            result::err(_) : __result_panic_unwrap(),
        }
    }

func (self: result[t, e]) unwrap_err() e {
        switch self {
            result::ok(_) : __result_panic_unwrap_err(),
            result::err(err) : err,
        }
    }

extern "intrinsic" func __result_panic_unwrap[t]() t

extern "intrinsic" func __result_panic_unwrap_err[e]() e
