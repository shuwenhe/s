package src.net

use src.syscall as sc
use std.result.result
use std.vec.vec

// The hosted resolver uses getaddrinfo, which selects the platform's native
// NSS/cgo resolver path. AF_UNSPEC returns both IPv4 and IPv6 addresses.
func lookup_host_native(string host) result[vec[string], net_error] {
    switch sc.resolve_ip(host, sc.AF_UNSPEC) {
        result::ok(addresses) : result::ok(addresses),
        result::err(e) : result::err(wrap_sc_err(e)),
    }
}

func cgo_unix_cgo_unit_name() string { "src/net/cgo_unix_cgo" }
func cgo_unix_cgo_unit_ready() int { 1 }
