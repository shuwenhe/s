

package cmd.compile.backend.selfhost

import (
    "cmd.compile.backend.selfhost.elf_slices"
    "cmd.compile.backend.selfhost.asm_amd64"
    "cmd.compile.backend.selfhost.asm_arm64"
    "cmd.compile.backend.selfhost.c_emit"
)

func init_backend() {
    elf_slices.init_elf()
    
}

type BackendContext struct {
    
}

func (bc *BackendContext) codegen() {
    
    c_emit.emit_c_code()
}
