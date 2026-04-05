package cmd

use std.io.eprintln
use std.io.println
use std.result.Result
use std.vec.Vec
use compiler.tests.RunGoldenSuite
use compiler.tests.RunMirSuite
use compiler.tests.RunSemanticSuite

struct cliError {
    message: String,
}

fn Main(args: Vec[String]) -> i32 {
    match run(args) {
        Result::Ok(()) => 0,
        Result::Err(err) => {
            eprintln("error: " + err.message)
            1
        }
    }
}

fn run(args: Vec[String]) -> Result[(), cliError] {
    var fixtures_root =
        if args.len() >= 2 {
            args[1]
        } else {
            "/app/s/compiler/tests/fixtures"
        }

    var golden = RunGoldenSuite(fixtures_root)
    var semantic = RunSemanticSuite(fixtures_root)
    var mir = RunMirSuite()

    if golden.failed.len() > 0 {
        for failure in golden.failed {
            eprintln("golden failed: " + failure.name + ": " + failure.message)
        }
        return Result::Err(cliError {
            message: "golden suite failed",
        })
    }

    if semantic.len() > 0 {
        for failure in semantic {
            eprintln("semantic failed: " + failure.name + ": " + failure.message)
        }
        return Result::Err(cliError {
            message: "semantic suite failed",
        })
    }

    if mir.len() > 0 {
        for failure in mir {
            eprintln("mir failed: " + failure.name + ": " + failure.message)
        }
        return Result::Err(cliError {
            message: "mir suite failed",
        })
    }

    println("compiler test suites passed")
    Result::Ok(())
}
