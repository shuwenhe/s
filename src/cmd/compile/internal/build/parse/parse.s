package compile.internal.build.parse

use std.prelude.char_at
use std.prelude.slice
use std.vec.vec

func parse_options(vec[string] args)  vec[string] {
    if args.len() < 2 {
        return make_options("help", "", "", "", false)
    }

    let command = args[1]
    if command == "help" || command == "--help" || command == "-h" {
        return make_options("help", "", "", "", false)
    }

    if command == "check" || command == "tokens" || command == "ast" {
        if args.len() < 3 {
            return make_options("help", "", "", "", false)
        }
        return make_options(command, args[2], "", "", false)
    }

    if command == "build" {
        if args.len() < 5 {
            return make_options("help", "", "", "", false)
        }
        if args[3] != "-o" {
            return make_options("help", "", "", "", false)
        }
        let nostdlib = has_flag(args, 5, "-nostdlib")
        let margin = parse_optional_margin(args, 5)
        if margin == "__invalid_margin__" {
            return make_options("help", "", "", "", false)
        }
        return make_options(command, args[2], args[4], margin, nostdlib)
    }

    if command == "run" {
        if args.len() < 3 {
            return make_options("help", "", "", "", false)
        }
        let nostdlib = has_flag(args, 3, "-nostdlib")
        let margin = parse_optional_margin(args, 3)
        if margin == "__invalid_margin__" {
            return make_options("help", "", "", "", false)
        }
        return make_options(command, args[2], "", margin, nostdlib)
    }

    if command == "test" {
        if args.len() >= 3 {
            return make_options(command, args[2], "", "", false)
        }
        return make_options(command, "", "", "", false)
    }

    if command == "mod" {
        if args.len() < 3 {
            return make_options("help", "", "", "", false)
        }
        let mod_command = args[2]
        if mod_command == "init" {
            if args.len() != 4 {
                return make_options("help", "", "", "", false)
            }
            return make_options(command, "init", args[3], "", false)
        }
        if mod_command == "tidy" {
            if args.len() != 3 {
                return make_options("help", "", "", "", false)
            }
            return make_options(command, "tidy", "", "", false)
        }
        if mod_command == "index" {
            if args.len() != 4 {
                return make_options("help", "", "", "", false)
            }
            return make_options(command, "index", args[3], "", false)
        }
        return make_options("help", "", "", "", false)
    }

    make_options("help", "", "", "", false)
}

func usage()  string {
    "usage:\n"
    + "  s check <path|module>\n"
    + "  s tokens <path|module>\n"
    + "  s ast <path|module>\n"
    + "  s build <path|module> -o <output> [--ssa-dominant-margin <n>|--ssa-dominant-margin=<n>] [-nostdlib]\n"
    + "  s run <path|module> [--ssa-dominant-margin <n>|--ssa-dominant-margin=<n>] [-nostdlib]\n"
    + "  s test [fixtures_root]\n"
    + "  s mod init <module>\n"
    + "  s mod tidy\n"
    + "  s mod index <dir>\n"
    + "\n"
    + "  <module> is a dot-separated package path, e.g. neurx.agent.code_agent\n"
    + "  -nostdlib  Generate standalone binary without C library dependencies\n"
    + "  Set S_PROJECT_ROOT=<dir> for neurx.* modules (strip neurx. prefix for paths).\n"
    + "  Run 's mod index' in the project to generate build/s-package-index.tsv for mismatched packages.\n"
}

func make_options(string command, string path, string output, string ssa_margin, bool nostdlib)  vec[string] {
    let options = vec[string]()
    options.push(command)
    options.push(path)
    options.push(output)
    options.push(ssa_margin)
    if nostdlib {
        options.push("nostdlib")
    }
    options
}

func has_flag(vec[string] args, int start_index, string flag) bool {
    let i = start_index
    while i < args.len() {
        if args[i] == flag {
            return true
        }
        i = i + 1
    }
    false
}

func parse_optional_margin(vec[string] args, int start_index) string {
    if args.len() <= start_index {
        return ""
    }

    if args[start_index] == "--ssa-dominant-margin" {
        if args.len() <= start_index + 1 {
            return "__invalid_margin__"
        }
        let value = args[start_index + 1]
        if !is_non_negative_integer(value) {
            return "__invalid_margin__"
        }
        if args.len() > start_index + 2 {
            return "__invalid_margin__"
        }
        return value
    }

    if starts_with(args[start_index], "--ssa-dominant-margin=") {
        let value = slice_after(args[start_index], "--ssa-dominant-margin=")
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

    let i = 0
    while i < text.len() {
        let ch = char_at(text, i)
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
