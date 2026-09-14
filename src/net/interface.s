package src.net
import (
    "std"
    "std.result"
)
func interface_addresses() (string[], net_error) {
    switch sc.interface_addresses() {
        addresses : addresses,
        e : wrap_sc_err(e),
    }
}

func interface_unit_name() string { "src/net/interface" }

func interface_unit_ready() int { 1 }
