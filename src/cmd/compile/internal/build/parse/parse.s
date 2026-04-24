package compile.internal.build.parse

use std.prelude.char_at
use std.prelude.slice
use std.vec.vec

func parse_options(vec[string] args)  vec[string] {
    if args.len() < 2 {
        return make_options("help", "", "", "")
    }

    var command = args[1]
    if command == "help" || command == "--help" || command == "-h" {
        return make_options("help", "", "", "")
    }

    if command == "check" || command == "tokens" || command == "ast" {
        if args.len() < 3 {
            return make_options("help", "", "", "")
        }
        return make_options(command, args[2], "", "")
    }

    if command == "build" {
        if args.len() < 5 {
            return make_options("help", "", "", "")
        }
        if args[3] != "-o" {
            return make_options("help", "", "", "")
        }
        var margin = parse_optional_margin(args, 5)
        if margin == "__invalid_margin__" {
            return make_options("help", "", "", "")
        }
        return make_options(command, args[2], args[4], margin)
    }

    if command == "run" {
        if args.len() < 3 {
            return make_options("help", "", "", "")
        }
        var margin = parse_optional_margin(args, 3)
        if margin == "__invalid_margin__" {
            return make_options("help", "", "", "")
        }
        return make_options(command, args[2], "", margin)
    }

    make_options("help", "", "", "")
}

func usage()  string {
    "usage:\n"
        + "  compile check <path>\n"
        + "  compile tokens <path>\n"
        + "  compile ast <path>\n"
        + "  compile build <path> -o <output> [--ssa-dominant-margin <n>|--ssa-dominant-margin=<n>]\n"
        + "  compile run <path> [--ssa-dominant-margin <n>|--ssa-dominant-margin=<n>]\n"
}

func make_options(string command, string path, string output, string ssa_margin)  vec[string] {
    var options = vec[string]()
    options.push(command);
    options.push(path);
    options.push(output);
    options.push(ssa_margin);
    options
}

func parse_optional_margin(vec[string] args, int32 start_index) string {
    if args.len() <= start_index {
        return ""
    }

    if args[start_index] == "--ssa-dominant-margin" {
        if args.len() <= start_index + 1 {
            return "__invalid_margin__"
        }
        var value = args[start_index + 1]
        if !is_non_negative_integer(value) {
            return "__invalid_margin__"
        }
        if args.len() > start_index + 2 {
            return "__invalid_margin__"
        }
        return value
    }

    if starts_with(args[start_index], "--ssa-dominant-margin=") {
        var value = slice_after(args[start_index], "--ssa-dominant-margin=")
        if !is_non_negative_integer(value) {
            return "__invalid_margin__"
        }
        if args.len() > start_index + 1 {
            return "__invalid_margin__"
        }
        return value
    }

    "__invalid_margin__"
}

func starts_with(string text, string prefix) bool {
    if text.len() < prefix.len() {
        return false
    }
    slice(text, 0, prefix.len()) == prefix
}

func slice_after(string text, string prefix) string {
    slice(text, prefix.len(), text.len())
}

func is_non_negative_integer(string text) bool {
    if text == "" {
        return false
    }

    var i = 0
    while i < text.len() {
        var ch = char_at(text, i)
        if !is_digit_char(ch) {
            return false
        }
        i = i + 1
    }
    true
}

func is_digit_char(string ch) bool {
    if ch == "0" || ch == "1" || ch == "2" || ch == "3" || ch == "4" {
        return true
    }
    if ch == "5" || ch == "6" || ch == "7" || ch == "8" || ch == "9" {
        return true
    }
    false
}
