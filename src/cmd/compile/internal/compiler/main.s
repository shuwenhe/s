package compile.internal
import (
    "compile.internal.semantic"
    "compile.internal.syntax"
)

// Host intrinsic functions for file I/O
extern "intrinsic" func __host_read_to_string(string path) string
extern "intrinsic" func __host_write_text_file(string path, string data) int
extern "intrinsic" func __host_char_at(string s, int index) string
extern "intrinsic" func __host_slice(string s, int start, int end) string
extern "intrinsic" func host_args() string[]

func compiler_main(string[] args) int {
    if len(args) == 4 && args[1] == "--canonical-ast-check" {
        source := __host_read_to_string(args[2])
        if source == "" { eprintln("compiler: empty or unreadable input"); return 1 }
        parsed, parse_err := compile.internal.syntax.parse_source(source)
          if compile.internal.syntax.parse_source_status(source) != 0 {
              eprintln("canonical-ast-error: parse failed")
              return 1
          }
        semantic_result := compile.internal.semantic.check_source_file(parsed, source)
        if len(semantic_result.errors) > 0 {
            error := semantic_result.errors[0]
            eprintln("canonical-ast-error: semantic " + error.code + ": " + error.message)
            return 1
        }
        result := "canonical-ast package=" + parsed.pkg + " source_file=canonical semantic=checked"
        if __host_write_text_file(args[3], result + "\n") != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if len(args) == 4 && args[1] == "build" {
        return handle_build_command(args[2], args[3])
    }
    if len(args) == 5 && args[1] == "build" && args[3] == "-o" {
        return handle_build_command(args[2], args[4])
    }
    if len(args) == 4 && args[1] == "--emit-native-object" {
        return native_build_object(args[2], args[3])
    }
    if len(args) == 4 && (args[1] == "--emit-amd64" || args[1] == "--emit-amd64-executable") {
        return native_emit_asm_file(args[2], args[3], args[1] == "--emit-amd64-executable")
    }
    if len(args) >= 2 && args[1] == "--compile-unit" {
        return handle_compile_unit(args)
    }
    if len(args) >= 2 && args[1] == "--emit-bin" {
        return handle_emit_bin(args)
    }
    
    // Default mode: compile S source to IR
    // Usage: compiler <input.s> <output.ir>
    if len(args) == 3 {
        source := __host_read_to_string(args[1])
        if source == "" { eprintln("compiler: empty or unreadable input"); return 1 }
        ir := emit_canonical_mir_public(source)
        if compiler_starts_with_trimmed(ir, "mir-error:") {
            eprintln(ir)
            return 1
        }
        if __host_write_text_file(args[2], ir) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if len(args) != 4 || (args[1] != "stage5-name-resolution-proof" && args[1] != "declaration-ref-proof" && args[1] != "type-checking-proof" && args[1] != "type-facts-observation-proof" && args[1] != "canonical-type-ref-proof" && args[1] != "canonical-semantic-proof" && args[1] != "canonical-lowering-proof" && args[1] != "canonical-mir-verification-proof" && args[1] != "canonical-ownership-proof" && args[1] != "canonical-monomorphization-proof" && args[1] != "canonical-optimization-proof" && args[1] != "canonical-layout-proof" && args[1] != "canonical-abi-proof" && args[1] != "canonical-codegen-proof" && args[1] != "canonical-regalloc-proof" && args[1] != "--emit-c" && args[1] != "--emit-lowered-view" && args[1] != "--emit-mir" && args[1] != "--emit-mir-after-drop" && args[1] != "--emit-mir-place" && args[1] != "--emit-mir-movepath" && args[1] != "--emit-mir-partial-move" && args[1] != "--emit-mir-reinit" && args[1] != "--emit-mir-partial-drop" && args[1] != "--emit-mir-place-borrow" && args[1] != "--emit-mir-reference-liveness" && args[1] != "--emit-mir-loan-liveness" && args[1] != "--emit-mir-region-constraints" && args[1] != "--emit-mir-region-solver" && args[1] != "--emit-mir-nll-borrow-check" && args[1] != "--emit-mir-nll-shadow" && args[1] != "--emit-mir-nll-real-cfg" && args[1] != "--emit-mir-ownership-solver-check" && args[1] != "--emit-mir-nll-ownership") {
        eprintln("usage: s_compiler (stage5-name-resolution-proof|declaration-ref-proof|type-checking-proof|type-facts-observation-proof|canonical-type-ref-proof|canonical-semantic-proof|canonical-lowering-proof|canonical-mir-verification-proof|canonical-ownership-proof|canonical-monomorphization-proof|canonical-optimization-proof|canonical-layout-proof|canonical-abi-proof|canonical-codegen-proof|canonical-regalloc-proof|--emit-c|--emit-lowered-view|--emit-mir|--emit-mir-after-drop|--emit-mir-place|--emit-mir-movepath|--emit-mir-partial-move|--emit-mir-reinit|--emit-mir-partial-drop|--emit-mir-place-borrow|--emit-mir-reference-liveness|--emit-mir-loan-liveness|--emit-mir-region-constraints|--emit-mir-region-solver|--emit-mir-nll-borrow-check|--emit-mir-nll-shadow|--emit-mir-nll-real-cfg|--emit-mir-ownership-solver-check|--emit-mir-nll-ownership) input.s output")
        return 2
    }
    
    source := __host_read_to_string(args[2])
    if source == "" { eprintln("compiler: empty or unreadable input"); return 1 }
    if args[1] == "stage5-name-resolution-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage5_input_authority_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "declaration-ref-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage6_declaration_ref_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "type-checking-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage7_type_checking_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "type-facts-observation-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage7_observation_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "canonical-type-ref-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage8_canonical_type_ref_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "canonical-semantic-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage9_semantic_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "canonical-lowering-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage10_lowering_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "canonical-mir-verification-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage11_mir_verification_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "canonical-ownership-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage12_ownership_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "canonical-monomorphization-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage13_monomorphization_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "canonical-optimization-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage14_optimization_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "canonical-layout-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage15_layout_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "canonical-abi-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage16_abi_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "canonical-codegen-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage17_codegen_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "canonical-regalloc-proof" {
        if __host_write_text_file(args[3], compiler_emit_stage18_regalloc_proof(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-lowered-view" {
        if __host_write_text_file(args[3], compiler_emit_lowered_view(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-place" {
        if __host_write_text_file(args[3], compiler_emit_mir_place(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-movepath" {
        if __host_write_text_file(args[3], compiler_emit_mir_movepath(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-partial-move" {
        if __host_write_text_file(args[3], compiler_emit_mir_partial_move(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-reinit" {
        if __host_write_text_file(args[3], compiler_emit_mir_reinit(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-partial-drop" {
        if __host_write_text_file(args[3], compiler_emit_mir_partial_drop(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-place-borrow" {
        if __host_write_text_file(args[3], compiler_emit_mir_place_borrow(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-reference-liveness" {
        if __host_write_text_file(args[3], compiler_emit_mir_reference_liveness(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-loan-liveness" {
        if __host_write_text_file(args[3], compiler_emit_mir_loan_liveness(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-region-constraints" {
        if __host_write_text_file(args[3], compiler_emit_mir_region_constraints(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-region-solver" {
        if __host_write_text_file(args[3], compiler_emit_mir_region_solver(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-nll-borrow-check" {
        if __host_write_text_file(args[3], compiler_emit_mir_nll_borrow_check(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-nll-shadow" {
        if __host_write_text_file(args[3], compiler_emit_mir_nll_shadow(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-nll-real-cfg" {
        if __host_write_text_file(args[3], compiler_emit_mir_nll_real_cfg(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-ownership-solver-check" {
        if __host_write_text_file(args[3], compiler_emit_ownership_solver_check()) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir-nll-ownership" {
        if __host_write_text_file(args[3], compiler_emit_mir_nll_ownership(source)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    if args[1] == "--emit-mir" || args[1] == "--emit-mir-after-drop" {
        elaborate := args[1] == "--emit-mir-after-drop"
        if __host_write_text_file(args[3], compiler_emit_mir(source, elaborate)) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    result := compiler_compile(source)
    if result.error != "" { eprintln(result.error); return 1 }
    if __host_write_text_file(args[3], result.code) != 0 { eprintln("compiler: cannot write output"); return 1 }
    return 0
}

func compiler_remove_duplicate_packages(string source) string {
    // Remove all but the first 'package' declaration for multi-file compilation
    result := ""
    seen_package := false
    in_package_line := false
    line_start := 0
    i := 0
    while i <= len(source) {
        if i == len(source) || __host_char_at(source, i) == "\n" {
            line := ""
            if i > line_start {
                line = __host_slice(source, line_start, i)
            }
            if !in_package_line {
                if compiler_starts_with_trimmed(line, "package ") {
                    if seen_package {
                        in_package_line = true
                        line_start = i + 1
                        i = i + 1
                        continue
                    } else {
                        seen_package = true
                    }
                }
            } else if compiler_starts_with_trimmed(line, "package ") || (line != "" && !compiler_starts_with_trimmed(line, "//")) {
                if !compiler_starts_with_trimmed(line, "package ") {
                    in_package_line = false
                    line_start = line_start - 1
                    i = line_start
                    continue
                }
            }
            if !in_package_line {
                result = result + line
                if i < len(source) { result = result + "\n" }
            }
            line_start = i + 1
        }
        i = i + 1
    }
    return result
}

func compiler_starts_with_trimmed(string line, string prefix) bool {
    i := 0
    while i < len(line) && (__host_char_at(line, i) == " " || __host_char_at(line, i) == "\t") {
        i = i + 1
    }
    if i + len(prefix) > len(line) { return false }
    j := 0
    while j < len(prefix) {
        if __host_char_at(line, i + j) != __host_char_at(prefix, j) { return false }
        j = j + 1
    }
    return true
}

func handle_compile_unit(string[] args) int {
    if len(args) < 4 {
        eprintln("usage: --compile-unit <output.ir> <input.s>...")
        return 2
    }
    output := args[2]
    if output == "" { eprintln("compiler: empty output path"); return 2 }
    if !native_target_supported() { eprintln("native compiler: P0: supports Linux/amd64"); return 2 }
    sources := string[]()
    i := 3
    for i < len(args) {
        if args[i] == output || __host_same_file(args[i], output) {
            eprintln("native compiler: output must not overwrite input source")
            return 2
        }
        part := __host_read_source(args[i])
        if part == "" {
            eprintln("compiler: empty or unreadable input: " + args[i])
            return 1
        }
        sources.push(part)
        i = i + 1
    }
    if len(sources) == 0 {
        eprintln("compiler: empty compile unit")
        return 1
    }
    source := ""
    j := 0
    for j < len(sources) {
        source = source + sources[j] + "\n"
        j = j + 1
    }
    mirrored := canonical_source_to_mir(source)
    if mirrored.error != "" { eprintln(mirrored.error); return 1 }
    emitted := native_program_assembly(mirrored.program, true)
    if emitted.error != "" { eprintln(emitted.error); return 1 }
    // This: is target assembly, not seed IR or the legacy C backend's output.
    artifact := "# S-NATIVE-AMD64-V1\n" + emitted.assembly
    if __host_write_text_file(output, artifact) != 0 { eprintln("compiler: cannot write output"); return 1 }
    return 0
}

func handle_emit_bin(string[] args) int {
    if len(args) != 4 {
        eprintln("usage: --emit-bin <input.sasm> <output.bin>")
        return 2
    }
    artifact := __host_read_source(args[2])
    header := "# S-NATIVE-AMD64-V1\n"
    if len(artifact) <= len(header) || __host_slice(artifact, 0, len(header)) != header {
        eprintln("compiler: expected S-NATIVE-AMD64-V1 assembly artifact")
        return 1
    }
    return native_install_assembly(artifact, args[2], args[3], true)
}

func handle_build_command(string input, string output) int {
    return native_build(input, output, "", false)
}
