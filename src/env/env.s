package std.env

use std.option.option
use std.vec.vec

func args() vec[string] {
    __host_args()
}

func get(string key) option[string] {
    __host_get_env(key)
}

extern "intrinsic" func __host_args() vec[string]

extern "intrinsic" func __host_get_env(string key) option[string]
