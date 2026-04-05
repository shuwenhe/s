package std.env

use std.vec.Vec

func Args() -> Vec[String] {
    __host_args()
}

extern "intrinsic" func __host_args() -> Vec[String]
