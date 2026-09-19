package compile.internal.tests.probe_stage1_backend_elf64

import (
    "compile.internal.backend_elf64"
)

// Minimal probe to test whether seed compiler can compile
// the full transitive closure of backend_elf64
//
// This probe forms a real reference to backend_elf64.build
// to verify seed's compileability of the canonical backend module.

func probe_reference_backend_build() int {
    // Minimal reference: just return the result of calling backend_elf64.build
    // This forces seed compiler to:
    // 1. resolve the import
    // 2. traverse the full transitive closure
    // 3. compile all dependencies
    
    // Dummy values for the probe
    dummy_path := "probe.s"
    dummy_output := "probe.o"
    dummy_ssa_override := ""
    dummy_nostdlib := false
    
    // Real call to backend_elf64.build
    return compile.internal.backend_elf64.build(
        dummy_path,
        dummy_output,
        dummy_ssa_override,
        dummy_nostdlib
    )
}

func main() int {
    // Minimal main: just reference the probe function
    return probe_reference_backend_build()
}
