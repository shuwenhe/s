package compile.pipeline

import (
    "compile.internal.backend_elf64"
)

use compile.internal.backend_elf64.build as backend_build

func pipeline_build(string input, string output, string ssa_margin_override, bool nostdlib) int {
    return backend_build(input, output, ssa_margin_override, nostdlib)
}
