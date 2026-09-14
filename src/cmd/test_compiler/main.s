package cmd
import (
    "compile.internal.mono_test"
    "compile.internal.tests.test_backend_abi"
    "compile.internal.tests.test_golden"
    "compile.internal.tests.test_mir"
    "compile.internal.tests.test_pipeline_regression"
    "compile.internal.tests.test_semantic"
    "compile.internal.tests.test_ssa"
    "compile.internal.tests.test_typesys"
    "std.env"
    "std.io"
)
func default_fixtures_root() string {
    env_root := std.env.get("s_test_fixtures_root")
    if env_root.is_some() {
        return env_root.unwrap(
    }
    "cmd/compile/internal/tests/fixtures"
}

func main() {
    args := host_args()
    if len(args) >= 2 {
        command := args[1]
        if command == "-h" || command == "--help" {
            std.io.println("usage: test_compiler [fixtures_root]");
            return 0
        }
    }
    fixtures_root := default_fixtures_root()
    if len(args) >= 2 {
        fixtures_root = args[1]
    }
    semantic_result := compile.internal.tests.test_semantic.run_semantic_suite(fixtures_root)
    if semantic_result != 0 {
        std.io.eprintln("semantic suite failed");
        return semantic_result
    }
    golden_result := compile.internal.tests.test_golden.run_golden_suite(fixtures_root)
    if golden_result != 0 {
        std.io.eprintln("golden suite failed");
        return golden_result
    }
    backend_abi_result := compile.internal.tests.test_backend_abi.run_backend_abi_suite()
    if backend_abi_result != 0 {
        std.io.eprintln("backend abi suite failed");
        return backend_abi_result
    }
    mir_result := compile.internal.tests.test_mir.run_mir_suite()
    if mir_result != 0 {
        std.io.eprintln("mir suite failed");
        return mir_result
    }
    ssa_result := compile.internal.tests.test_ssa.run_ssa_suite()
    if ssa_result != 0 {
        std.io.eprintln("ssa suite failed");
        return ssa_result
    }
    pipeline_result := compile.internal.tests.test_pipeline_regression.run_pipeline_regression_suite()
    if pipeline_result != 0 {
        std.io.eprintln("pipeline regression suite failed");
        return pipeline_result
    }
    typesys_result := compile.internal.tests.test_typesys.run_typesys_suite()
    if typesys_result != 0 {
        std.io.eprintln("typesys suite failed");
        return typesys_result
    }
    mono_result := compile.internal.mono_test.run_monomorphization_test()
    if mono_result != 0 {
        std.io.eprintln("monomorphization suite failed");
        return mono_result
    }
    std.io.println("test_compiler: ok");
    0
}
