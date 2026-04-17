package std.env

use std.option.Option
use std.vec.Vec

func Args() Vec[string] {
    __host_args()
}

func Get(string key) Option[string] {
    __host_get_env(key)
}

extern "intrinsic" func __host_args() Vec[string]

extern "intrinsic" func __host_get_env(string key) Option[string]
