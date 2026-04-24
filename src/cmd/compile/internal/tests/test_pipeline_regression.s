package compile.internal.tests.test_pipeline_regression

use compile.internal.backend_elf64.build_abi_emit_plan
use compile.internal.backend_elf64.build_wasm_toolchain_plan
use compile.internal.backend_elf64.run_midend_pipeline
use compile.internal.ir.lower.from_syntax_checked
use compile.internal.ir.lower.lower_main_to_mir
use compile.internal.ssa_core.build_pipeline_with_graph_hints
use compile.internal.ssa_core.dump_pipeline
use compile.internal.syntax.parse_source
use compile.internal.ir.ast as ir_ast
use compile.internal.mir.mir_graph
use compile.internal.mir.mir_basic_block
use compile.internal.mir.mir_local_slot
use compile.internal.mir.mir_statement
use compile.internal.mir.mir_eval_stmt
use compile.internal.mir.mir_terminator
use compile.internal.mir.mir_control_edge
use compile.internal.mir.dump_graph
use std.prelude.slice
use std.vec.vec

func run_pipeline_regression_suite() int32 {
    var source = "package demo.reg\nconst (\n  A = 1\n  B\n)\nfunc helper() int32 {\n  1\n}\nfunc main() int32 {\n  var arr = [int32]{1, 2}\n  var mp = [string]int32{\"k\": 1}\n  var idx = arr[0]\n  var bx = { idx + 1 }\n  idx = idx + bx\n  for (var i := 0; i < 1; i++) {\n    idx = idx + arr[i]\n  }\n  B + mp[\"k\"]\n}"

    var parsed = parse_source(source)
    if parsed.is_err() {
        return 1
    }

    var lowered_checked = from_syntax_checked(parsed.unwrap())
    if lowered_checked.is_err() {
        return 1
    }
    var lowered = lowered_checked.unwrap()
    if count_const_decls(lowered) != 2 {
        return 1
    }
    if !has_const_decl(lowered, "A", "1") {
        return 1
    }
    if !has_const_decl(lowered, "B", "1") {
        return 1
    }

    var const_only_source = "package demo.constonly\nconst (\n  A = 1\n  B\n)\nfunc main() int32 {\n  B\n}"
    var const_only_parsed = parse_source(const_only_source)
    if const_only_parsed.is_err() {
        return 1
    }
    var const_only_lowered = from_syntax_checked(const_only_parsed.unwrap())
    if const_only_lowered.is_err() {
        return 1
    }
    if !main_final_is_int_literal(const_only_lowered.unwrap(), 1) {
        return 1
    }

    var features = collect_ir_package_features(lowered)
    if (features & 1) == 0 {
        return 1
    }
    if (features & 2) == 0 {
        return 1
    }
    if (features & 4) == 0 {
        return 1
    }
    if (features & 8) == 0 {
        return 1
    }
    if (features & 16) == 0 {
        return 1
    }

    var graph_result = lower_main_to_mir(parsed.unwrap())
    if graph_result.is_err() {
        return 1
    }
    var graph = graph_result.unwrap()
    var graph_text = dump_graph(graph)
    if !contains(graph_text, "yield 1") {
        return 1
    }
    if contains(graph_text, "yield B") {
        return 1
    }

    var saw_pkg_functions = false
    var ti = 0
    while ti < graph.trace.len() {
        if starts_with(graph.trace[ti], "package.functions=") {
            saw_pkg_functions = true
        }
        ti = ti + 1
    }
    if !saw_pkg_functions {
        return 1
    }

    var midend = run_midend_pipeline(graph)
    if !contains(midend.report, "inline_sites=") {
        return 1
    }
    if !contains(midend.report, "escape_sites=") {
        return 1
    }
    if !contains(midend.report, "devirtualized=") {
        return 1
    }
    if !contains(midend.report, "pass_rm_unreachable=") {
        return 1
    }
    if !contains(midend.report, "pass_fold_branch=") {
        return 1
    }
    if !contains(midend.report, "const_fold_hits=") {
        return 1
    }

    var hinted = build_pipeline_with_graph_hints(graph, midend.optimized_mir_text, "amd64")
    var hinted_dump = dump_pipeline(hinted)
    if !contains(hinted_dump, "blocks=") {
        return 1
    }
    if !contains(hinted_dump, "dbg_lines=") {
        return 1
    }

    var abi_plan = build_abi_emit_plan("riscv64", parsed.unwrap())
    if !contains(abi_plan, "abi-emit version=1 arch=riscv64") {
        return 1
    }

    var wasm_plan = build_wasm_toolchain_plan("/tmp/in.c", "/tmp/out.o", "/tmp/out.wasm")
    if !contains(wasm_plan, "clang --target=wasm32-wasi -c") {
        return 1
    }
    if !contains(wasm_plan, "wasm-ld --no-entry --export=_start") {
        return 1
    }

    0
}

func count_const_decls(ir_ast.package_ir pkg) int32 {
    var count = 0
    var i = 0
    while i < pkg.decls.len() {
        switch pkg.decls[i] {
            ir_ast.decl_ir::const(_) : count = count + 1,
            _ : (),
        }
        i = i + 1
    }
    count
}

func has_const_decl(ir_ast.package_ir pkg, string name, string value) bool {
    var i = 0
    while i < pkg.decls.len() {
        switch pkg.decls[i] {
            ir_ast.decl_ir::const(cd) : {
                if cd.name == name && cd.value == value {
                    return true
                }
            }
            _ : (),
        }
        i = i + 1
    }
    false
}

func main_final_is_int_literal(ir_ast.package_ir pkg, int32 expected) bool {
    var i = 0
    while i < pkg.decls.len() {
        switch pkg.decls[i] {
            ir_ast.decl_ir::func(fd) : {
                if fd.name == "main" && fd.body.is_some() {
                    var body = fd.body.unwrap()
                    if body.final_expr.is_some() {
                        switch body.final_expr.unwrap() {
                            ir_ast.expr_ir::int(value) : {
                                return value == expected
                            }
                            _ : return false,
                        }
                    }
                    return false
                }
            }
            _ : (),
        }
        i = i + 1
    }
    false
}

func collect_ir_package_features(ir_ast.package_ir pkg) int32 {
    var features = 0
    var i = 0
    while i < pkg.decls.len() {
        switch pkg.decls[i] {
            ir_ast.decl_ir::func(fd) : {
                if fd.name == "main" && fd.body.is_some() {
                    var body = fd.body.unwrap()
                    var j = 0
                    while j < body.statements.len() {
                        switch body.statements[j] {
                            ir_ast.stmt_ir::expr(expr_stmt) : {
                                features = features | collect_ir_expr_features(expr_stmt.expr)
                            }
                            ir_ast.stmt_ir::var(var_stmt) : {
                                features = features | collect_ir_expr_features(var_stmt.value)
                            }
                            ir_ast.stmt_ir::assign(assign_stmt) : {
                                features = features | collect_ir_expr_features(assign_stmt.value)
                            }
                            ir_ast.stmt_ir::cfor(cfor_stmt) : {
                                features = features | 1
                                features = features | collect_ir_expr_features(cfor_stmt.condition)
                                features = features | collect_ir_block_features(cfor_stmt.body)
                            }
                            _ : (),
                        }
                        j = j + 1
                    }

                    if body.final_expr.is_some() {
                        features = features | collect_ir_expr_features(body.final_expr.unwrap())
                    }
                }
            }
            _ : (),
        }
        i = i + 1
    }

    features
}

func collect_ir_block_features(ir_ast.block_ir block) int32 {
    var features = 2
    var i = 0
    while i < block.statements.len() {
        switch block.statements[i] {
            ir_ast.stmt_ir::expr(expr_stmt) : {
                features = features | collect_ir_expr_features(expr_stmt.expr)
            }
            ir_ast.stmt_ir::var(var_stmt) : {
                features = features | collect_ir_expr_features(var_stmt.value)
            }
            ir_ast.stmt_ir::assign(assign_stmt) : {
                features = features | collect_ir_expr_features(assign_stmt.value)
            }
            ir_ast.stmt_ir::cfor(cfor_stmt) : {
                features = features | 1
                features = features | collect_ir_expr_features(cfor_stmt.condition)
                features = features | collect_ir_block_features(cfor_stmt.body)
            }
            _ : (),
        }
        i = i + 1
    }

    if block.final_expr.is_some() {
        features = features | collect_ir_expr_features(block.final_expr.unwrap())
    }
    features
}

func collect_ir_expr_features(ir_ast.expr_ir expression) int32 {
    var features = 0
    switch expression {
        ir_ast.expr_ir::name(name) : {
            if contains(name, "_unlowered") {
                return 0
            }
        }
        ir_ast.expr_ir::member(member_expr) : {
            features = features | 32
            features = features | collect_ir_expr_features(member_expr.target)
        }
        ir_ast.expr_ir::index(index_expr) : {
            features = features | 4
            features = features | collect_ir_expr_features(index_expr.target)
            features = features | collect_ir_expr_features(index_expr.index)
        }
        ir_ast.expr_ir::array(array_expr) : {
            features = features | 8
            var ai = 0
            while ai < array_expr.items.len() {
                features = features | collect_ir_expr_features(array_expr.items[ai])
                ai = ai + 1
            }
        }
        ir_ast.expr_ir::map(map_expr) : {
            features = features | 16
            var mi = 0
            while mi < map_expr.entries.len() {
                features = features | collect_ir_expr_features(map_expr.entries[mi].key)
                features = features | collect_ir_expr_features(map_expr.entries[mi].value)
                mi = mi + 1
            }
        }
        ir_ast.expr_ir::block(block_expr) : {
            features = features | collect_ir_block_features(block_expr)
        }
        ir_ast.expr_ir::call(call_expr) : {
            var i = 0
            while i < call_expr.args.len() {
                features = features | collect_ir_expr_features(call_expr.args[i])
                i = i + 1
            }
        }
        ir_ast.expr_ir::binary(binary_expr) : {
            features = features | collect_ir_expr_features(binary_expr.left)
            features = features | collect_ir_expr_features(binary_expr.right)
        }
        ir_ast.expr_ir::borrow(borrow_expr) : {
            features = features | collect_ir_expr_features(borrow_expr.target)
        }
        _ : (),
    }
    features
}

func starts_with(string text, string prefix) bool {
    if prefix == "" {
        return true
    }
    if text.len() < prefix.len() {
        return false
    }
    slice(text, 0, prefix.len()) == prefix
}

func contains(string text, string needle) bool {
    if needle == "" {
        return true
    }
    if text.len() < needle.len() {
        return false
    }

    var i = 0
    while i <= text.len() - needle.len() {
        if slice(text, i, i + needle.len()) == needle {
            return true
        }
        i = i + 1
    }
    false
}
