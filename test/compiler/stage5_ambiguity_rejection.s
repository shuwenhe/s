package stage5_ambiguity_rejection

import (
    "std.io"
)

func helper() int {
    return 7;
}

func helper() int {
    return 8;
}

func main() int {
    return helper();
}
