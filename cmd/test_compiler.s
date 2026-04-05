package cmd

use std.io.eprintln
use std.io.println
use std.result.Result
use std.vec.Vec
use compiler.tests.run as run_golden_suite
use compiler.tests.run as run_mir_suite
use compiler.tests.run as run_semantic_suite

pub struct CliError {
    message: String,
}

pub fn main(args: Vec[String]) -> i32 {
    match run(args) {
        Result::Ok(()) => 0,
        Result::Err(err) => {
            eprintln("error: " + err.message)
            1
        }
    }
}

pub fn run(args: Vec[String]) -> Result[(), CliError] {
    let fixtures_root =
        if args.len() >= 2 {
            args[1]
        } else {
            "/app/s/compiler/tests/fixtures"
        }

    let golden = run_golden_suite(fixtures_root)
    let semantic = run_semantic_suite(fixtures_root)
    let mir = run_mir_suite()

    if golden.failed.len() > 0 {
        for failure in golden.failed {
            eprintln("golden failed: " + failure.name + ": " + failure.message)
        }
        return Result::Err(CliError {
            message: "golden suite failed",
        })
    }

    if semantic.len() > 0 {
        for failure in semantic {
            eprintln("semantic failed: " + failure.name + ": " + failure.message)
        }
        return Result::Err(CliError {
            message: "semantic suite failed",
        })
    }

    if mir.len() > 0 {
        for failure in mir {
            eprintln("mir failed: " + failure.name + ": " + failure.message)
        }
        return Result::Err(CliError {
            message: "mir suite failed",
        })
    }

    println("compiler test suites passed")
    Result::Ok(())
}
