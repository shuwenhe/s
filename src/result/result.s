package std.result

enum result[t, e] {
    ok(t),
    err(e),
}

impl result[t, e] {
    func is_ok(self) bool {
        switch self {
            result::ok(_) : true,
            result::err(_) : false,
        }
    }

    func is_err(self) bool {
        !self.is_ok()
    }

    func unwrap(self) t {
        switch self {
            result::ok(value) : value,
            result::err(_) : __result_panic_unwrap(),
        }
    }

    func unwrap_err(self) e {
        switch self {
            result::ok(_) : __result_panic_unwrap_err(),
            result::err(err) : err,
        }
    }
}

extern "intrinsic" func __result_panic_unwrap[t]() t

extern "intrinsic" func __result_panic_unwrap_err[e]() e
