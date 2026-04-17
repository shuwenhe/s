package compile.internal.build.parse

use std.result.Result
use std.vec.Vec
use vec.new_vec

struct CompileOptions {
    string command,
    string path,
    string output,
}

// ParseError struct not needed when using string-based errors

func ParseOptions(Vec[string] args) Result[Vec[string], string] {
    if args.len() < 2 {
        var v = new_vec[string]()
        v.push("help");
        v.push("");
        v.push("");
        return Result.Ok(v);
    }

    var command = args[1]
    if command == "help" || command == "--help" || command == "-h" {
        var v = new_vec[string]()
        v.push("help");
        v.push("");
        v.push("");
        return Result.Ok(v);
    }

    if command == "check" || command == "tokens" || command == "ast" {
        if args.len() < 3 {
            return Result.Err("usage: compile " + command + " <path>")
        }
        var v = new_vec[string]()
        v.push(command);
        v.push(args[2]);
        v.push("");
        return Result.Ok(v);
    }

    if command == "build" {
        if args.len() < 5 {
            return Result.Err("usage: compile build <path> -o <output>")
        }
        if args[3] != "-o" {
            return Result.Err("expected -o before output path")
        }
        var v = new_vec[string]()
        v.push(command);
        v.push(args[2]);
        v.push(args[4]);
        return Result.Ok(v);
    }

    if command == "run" {
        if args.len() < 3 {
            return Result.Err("usage: compile run <path>")
        }
        var v = new_vec[string]()
        v.push(command);
        v.push(args[2]);
        v.push("");
        return Result.Ok(v);
    }

    Result.Err("unknown command: " + command)
}

func Usage() string {
    "usage:\n"
        + "  compile check <path>\n"
        + "  compile tokens <path>\n"
        + "  compile ast <path>\n"
        + "  compile build <path> -o <output>\n"
        + "  compile run <path>\n"
}
