package compile.internal.build.parse

use std.vec.Vec

func parse_options(Vec[string] args)  Vec[string] {
    if args.len() < 2 {
        return make_options("help", "", "")
    }

    var command = args[1]
    if command == "help" || command == "--help" || command == "-h" {
        return make_options("help", "", "")
    }

    if command == "check" || command == "tokens" || command == "ast" {
        if args.len() < 3 {
            return make_options("help", "", "")
        }
        return make_options(command, args[2], "")
    }

    if command == "build" {
        if args.len() < 5 {
            return make_options("help", "", "")
        }
        if args[3] != "-o" {
            return make_options("help", "", "")
        }
        return make_options(command, args[2], args[4])
    }

    if command == "run" {
        if args.len() < 3 {
            return make_options("help", "", "")
        }
        return make_options(command, args[2], "")
    }

    make_options("help", "", "")
}

func Usage()  string {
    "usage:\n"
        + "  compile check <path>\n"
        + "  compile tokens <path>\n"
        + "  compile ast <path>\n"
        + "  compile build <path> -o <output>\n"
        + "  compile run <path>\n"
}

func make_options(string command, string path, string output)  Vec[string] {
    var options = Vec[string]()
    options.push(command);
    options.push(path);
    options.push(output);
    options
}
