package compile.internal.backend

use std.fs.MakeTempDir
use std.io.println
use std.process.RunProcess
use std.result.Result
use std.vec.Vec

struct CliError {
    String message,
}

func Build(String path, String output) -> Result[(), CliError] {
    // The S frontend is in place; native runner remains the backend bridge.
    var argv = Vec[String]()
    argv.push("/app/s/bin/s-native")
    argv.push("build")
    argv.push(path)
    argv.push("-o")
    argv.push(output)

    match RunProcess(argv) {
        Result::Ok(_) => {
            println("built: " + output)
            Result::Ok(())
        }
        Result::Err(err) => Result::Err(CliError {
            message: "backend build failed: " + err.message,
        }),
    }
}

func Run(String path) -> Result[(), CliError] {
    var temp_dir =
        match MakeTempDir("s-compile-") {
            Result::Ok(dir) => dir,
            Result::Err(err) => {
                return Result::Err(CliError {
                    message: "failed to create temp dir: " + err.message,
                })
            }
        }
    var output = temp_dir + "/a.out"
    Build(path, output)?

    var argv = Vec[String]()
    argv.push(output)

    match RunProcess(argv) {
        Result::Ok(_) => Result::Ok(()),
        Result::Err(err) => Result::Err(CliError {
            message: "failed to run compiled program: " + err.message,
        }),
    }
}
