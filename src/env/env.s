package std.env
use std.option.option
use std.slices
func args() string[] {
    __host_args()
}

func get(string key) option[string] {
    __host_get_env(key)
}
extern "intrinsic" func __host_args() string[]
extern "intrinsic" func __host_get_env(string key) option[string]
