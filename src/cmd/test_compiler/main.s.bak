package cmd

use compile.internal.tests.testGolden.RunGoldenSuite
use compile.internal.tests.testMir.RunMirSuite
use compile.internal.tests.testSemantic.RunSemanticSuite
use std.env.Args as hostArgs
use std.env.Get
use std.io.eprintln
use std.io.println

func defaultFixturesRoot() string {
    var envRoot = Get("S_TEST_FIXTURES_ROOT")
    if envRoot.isSome() {
        return envRoot.unwrap()
    }
    "cmd/compile/internal/tests/fixtures"
}

func main() int32 {
    var args = hostArgs()
    if args.len() >= 2 {
        var command = args[1]
        if command == "-h" || command == "--help" {
            println("usage: testCompiler [fixturesRoot]");
            return 0
        }
    }

    var fixturesRoot = defaultFixturesRoot()
    if args.len() >= 2 {
        fixturesRoot = args[1]
    }

    var semanticResult = RunSemanticSuite(fixturesRoot)
    if semanticResult != 0 {
        eprintln("semantic suite failed");
        return semanticResult
    }

    var goldenResult = RunGoldenSuite(fixturesRoot)
    if goldenResult != 0 {
        eprintln("golden suite failed");
        return goldenResult
    }

    var mirResult = RunMirSuite()
    if mirResult != 0 {
        eprintln("mir suite failed");
        return mirResult
    }

    println("testCompiler: OK");
    0
}
