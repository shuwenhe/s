package std.env
import (
    "std"
    "std.option"
)
func args() string[] {
    __host_args()
}
func get(string key) option[string] {
    __host_get_env(key)
}
extern "intrinsic" func __host_args() string[]
