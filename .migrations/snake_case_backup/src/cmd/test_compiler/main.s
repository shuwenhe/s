package cmd

use compile.internal.tests.test_golden.run_golden_suite
use compile.internal.tests.test_mir.run_mir_suite
use compile.internal.tests.test_semantic.run_semantic_suite
use std.env.Args as host_args
use std.env.Get
use std.io.eprintln
use std.io.println

func default_fixtures_root() string {
    var env_root = Get("S_TEST_FIXTURES_ROOT")
    if env_root.is_some() {
        return env_root.unwrap()
    }
    "cmd/compile/internal/tests/fixtures"
}

func main() int32 {
    var args = host_args()
    if args.len() >= 2 {
        var command = args[1]
        if command == "-h" || command == "--help" {
            println("usage: testCompiler [fixturesRoot]");
            return 0
        }
    }

    var fixtures_root = default_fixtures_root()
    if args.len() >= 2 {
        fixtures_root = args[1]
    }

    var semantic_result = run_semantic_suite(fixtures_root)
    if semantic_result != 0 {
        eprintln("semantic suite failed");
        return semantic_result
    }

    var golden_result = run_golden_suite(fixtures_root)
    if golden_result != 0 {
        eprintln("golden suite failed");
        return golden_result
    }

    var mir_result = run_mir_suite()
    if mir_result != 0 {
        eprintln("mir suite failed");
        return mir_result
    }

    println("testCompiler: OK");
    0
}
