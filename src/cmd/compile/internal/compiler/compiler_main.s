package compile.compiler

import (
    "compile.internal.parser.syntax"
    "compile.internal.semantic"
    "compile.internal.ir.lower"
    "compile.internal.mir"
)

use compile.internal.parser.syntax.parse_source as parse
use compile.internal.semantic.check_source_file as check_semantic
use compile.internal.ir.lower.lower_main_to_mir as lower
use compile.internal.mir.dump_graph as dump_mir

func main() {
    args := host_args()
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
        if __host_write_text_file(args[3], compiler_emit_mir(source, args[1] == "--emit-mir-after-drop")) != 0 { eprintln("compiler: cannot write output"); return 1 }
        return 0
    }
    result := compiler_compile(source)
    if result.error != "" { eprintln(result.error); return 1 }
    if __host_write_text_file(args[3], result.code) != 0 { eprintln("compiler: cannot write output"); return 1 }
    return 0
}
