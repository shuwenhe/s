package cmd

use compile.internal.tests.test_golden.RunGoldenSuite
use compile.internal.tests.test_mir.RunMirSuite
use compile.internal.tests.test_semantic.RunSemanticSuite
use std.env.Args as hostArgs
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
    var args = hostArgs()
    if args.len() >= 2 {
        var command = args[1]
        if command == "-h" || command == "--help" {
            println("usage: test_compiler [fixtures_root]");
            return 0
        }
    }

    var fixtures_root = default_fixtures_root()
    if args.len() >= 2 {
        fixtures_root = args[1]
    }

    var semantic_result = RunSemanticSuite(fixtures_root)
    if semantic_result != 0 {
        eprintln("semantic suite failed");
        return semantic_result
    }

    var golden_result = RunGoldenSuite(fixtures_root)
    if golden_result != 0 {
        eprintln("golden suite failed");
        return golden_result
    }

    var mir_result = RunMirSuite()
    if mir_result != 0 {
        eprintln("mir suite failed");
        return mir_result
    }

    println("test_compiler: OK");
    0
}
