package std.env

use std.option.Option
use std.vec.Vec

func Args() Vec[String] {
    __host_args()
}

func Get(String key) Option[String] {
    __host_get_env(key)
}

extern "intrinsic" func __host_args() Vec[String]

extern "intrinsic" func __host_get_env(String key) Option[String]
