package src.net
import (
    "std"
    "std.result"
)
func lookup_host_native(string host) (string[], net_error) {
    switch sc.resolve_ip(host, sc.af_unspec) {
        addresses : addresses,
        e : wrap_sc_err(e),
    }
}

func cgo_unix_cgo_unit_name() string { "src/net/cgo_unix_cgo" }

func cgo_unix_cgo_unit_ready() int { 1 }
