package src.net

use src.syscall as sc
use std.result.result
use std.vec.vec

func interface_addresses() result[vec[string], net_error] {
    switch sc.interface_addresses() {
        result::ok(addresses) : result::ok(addresses),
        result::err(e) : result::err(wrap_sc_err(e)),
    }
}

func interface_unit_name() string { "src/net/interface" }
func interface_unit_ready() int { 1 }
