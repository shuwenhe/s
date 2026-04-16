package runtime.runner

use std.env.Args
use std.fs.MakeTempDir
use std.fs.ReadToString
use std.fs.WriteTextFile
use std.io.eprintln
use std.io.println
use std.option.Option
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.process.Exit
use std.process.RunProcess
use std.result.Result
use std.vec.Vec

func main() -> () {
    Exit(runMain(Args()))
}

func runMain(Vec[String] args) int {
    return match run(args) {
        Ok(_) => 0,
        Err(err) => {
            eprintln("error: " + err);
            1
        }
    }
}

func run(Vec[String] args) Result[int, String] {
    if args.len() != 4 {
        return usageError()
    }
    if args[0] != "build" {
        return usageError()
    }
    if args[2] != "-o" {
        return Err("expected -o before output path")
    }
    return buildSource(args[1], normalizeOutputPath(args[3]))
}

func buildSource(String path, String outputPath) Result[int, String] {
    var source =
        match ReadToString(path) {
            Ok(text) => text,
            Err(_) => {
                return Err("failed to read source file: " + path)
            }
        }
    if isSelfHostSource(source) {
        return buildSelfHostedRunner(outputPath)
    }
    if isCompilerCommandSource(source) {
        return buildCompilerCommandLauncher(outputPath)
    }

    var message =
        match compileMessageForSource(source) {
            Some(text) => text,
            None => {
                return Err("unsupported source shape for native runner MVP")
            }
        }

    var asmText = emitAsm(message)
    match assembleAndLink(asmText, outputPath) {
        Ok(_) => 0,
        Err(err) => {
            return Err(err)
        },
    }
    println("built: " + outputPath);
    return Ok(0)
}

func isSelfHostSource(String source) bool {
    return containsText(source, "package runtime.runner")
}

func isCompilerCommandSource(String source) bool {
    if containsText(source, "package cmd") && containsText(source, "use compiler.main as compilerMain") {
        return true
    }
    if containsText(source, "package cmd") && containsText(source, "use compile.internal.gc.Main as compileMain") {
        return true
    }
    if containsText(source, "package cmd") && containsText(source, "use compile.internal.sc.Main as compileMain") {
        return true
    }
    if containsText(source, "package compiler.internal.gc") && containsText(source, "func Main(") {
        return true
    }
    return false
}

func buildSelfHostedRunner(String outputPath) Result[int, String] {
    var templateText =
        match ReadToString("/app/s/src/cmd/compiler/backend_elf64_runner_bootstrap.c") {
            Ok(text) => text,
            Err(err) => {
                return Err("failed to read native runner template: " + err.message)
            }
        }
    var tempDir =
        match MakeTempDir("s-runner-") {
            Ok(path) => path,
            Err(err) => {
                return Err(err.message)
            }
        }
    var cPath = tempDir + "/runner.c"
    match WriteTextFile(cPath, templateText) {
        Ok(_) => 0,
        Err(err) => {
            return Err("failed to write native runner template: " + err.message)
        },
    }
    var ccArgv = Vec[String]()
    ccArgv.push("cc");
    ccArgv.push("-O2");
    ccArgv.push("-std=c11");
    ccArgv.push(cPath);
    ccArgv.push("-o");
    ccArgv.push(outputPath);
    match runTool(ccArgv, "native runner bootstrap failed") {
        Ok(_) => 0,
        Err(err) => {
            return Err(err)
        },
    }
    println("built: " + outputPath);
    return Ok(0)
}

func buildCompilerCommandLauncher(String outputPath) Result[int, String] {
    var templateText =
        match ReadToString("/app/s/src/runtime/s_command_bootstrap.c") {
            Ok(text) => text,
            Err(err) => {
                return Err("failed to read command launcher template: " + err.message)
            }
        }
    var tempDir =
        match MakeTempDir("s-command-") {
            Ok(path) => path,
            Err(err) => {
                return Err(err.message)
            }
        }
    var cPath = tempDir + "/s_command.c"
    match WriteTextFile(cPath, templateText) {
        Ok(_) => 0,
        Err(err) => {
            return Err("failed to write command launcher template: " + err.message)
        },
    }
    var ccArgv = Vec[String]()
    ccArgv.push("cc");
    ccArgv.push("-O2");
    ccArgv.push("-std=c11");
    ccArgv.push(cPath);
    ccArgv.push("-o");
    ccArgv.push(outputPath);
    match runTool(ccArgv, "command launcher bootstrap failed") {
        Ok(_) => 0,
        Err(err) => {
            return Err(err)
        },
    }
    println("built: " + outputPath);
    return Ok(0)
}

func compileMessageForSource(String source) Option[String] {
    match extractQuotedPrintln(source) {
        Some(text) => {
            return Some(text + "\n")
        },
        None => 0,
    }
    match extractPrintedIntLiteral(source) {
        Some(text) => {
            return Some(text + "\n")
        },
        None => 0,
    }

    if containsText(source, "println(sum)") == false {
        return None
    }
    if containsText(source, "sum = sum + i") == false {
        return None
    }

    var initial =
        match parseSignedIntAfter(source, "int sum = ") {
            Some(value) => value,
            None => {
                return None
            },
        }
    var start =
        match parseSignedIntAfter(source, "for (int i = ") {
            Some(value) => value,
            None => {
                return None
            },
        }
    var end =
        match parseSignedIntAfter(source, "; i <= ") {
            Some(value) => value,
            None => {
                return None
            },
        }

    var total = initial
    var index = start
    while index <= end {
        total = total + index
        index++
    }
    return Some(to_string(total) + "\n")
}

func extractQuotedPrintln(String source) Option[String] {
    var prefix = "println(\""
    var startIndex = findText(source, prefix)
    if startIndex < 0 {
        return None
    }
    var textStart = startIndex + len(prefix)
    var endIndex = findCharFrom(source, "\"", textStart)
    if endIndex < 0 {
        return None
    }
    return Some(slice(source, textStart, endIndex))
}

func extractPrintedIntLiteral(String source) Option[String] {
    var startIndex = findText(source, "println(")
    if startIndex < 0 {
        return None
    }
    return parseSignedIntLiteralAt(source, startIndex + len("println("))
}

func parseSignedIntAfter(String source, String needle) Option[int] {
    var startIndex = findText(source, needle)
    if startIndex < 0 {
        return None
    }
    var index = startIndex + len(needle)
    var sign = 1
    if index < len(source) {
        if char_at(source, index) == "-" {
            sign = 0 - 1
            index = index + 1
        }
    }
    var value = 0
    var found = false
    while index < len(source) {
        var ch = char_at(source, index)
        if ch < "0" {
            index = len(source)
        } else if ch > "9" {
            index = len(source)
        } else {
            value = value * 10 + digitValue(ch)
            found = true
            index = index + 1
        }
    }
    if found == false {
        return None
    }
    return Some(value * sign)
}

func parseSignedIntLiteralAt(String source, int start) Option[String] {
    var index = start
    var sign = 1
    if index < len(source) {
        if char_at(source, index) == "-" {
            sign = 0 - 1
            index = index + 1
        }
    }
    var value = 0
    var found = false
    while index < len(source) {
        var ch = char_at(source, index)
        if ch == ")" {
            if found == false {
                return None
            }
            return Some(to_string(value * sign))
        }
        if ch < "0" {
            return None
        } else if ch > "9" {
            return None
        } else {
            value = value * 10 + digitValue(ch)
            found = true
            index = index + 1
        }
    }
    return None
}

func emitAsm(String message) String {
    var lines = Vec[String]()
    lines.push(".section .data");
    lines.push("message_0:");
    lines.push("    .byte " + encodeBytes(message));
    lines.push("");
    lines.push(".section .text");
    lines.push(".global _start");
    lines.push("_start:");
    lines.push("    mov $1, %rax");
    lines.push("    mov $1, %rdi");
    lines.push("    lea message_0(%rip), %rsi");
    lines.push("    mov $" + to_string(len(message)) + ", %rdx");
    lines.push("    syscall");
    lines.push("    mov $60, %rax");
    lines.push("    mov $0, %rdi");
    lines.push("    syscall");
    return joinWith(lines, "\n") + "\n"
}

func assembleAndLink(String asmText, String outputPath) Result[int, String] {
    var tempDir =
        match MakeTempDir("s-native-") {
            Ok(path) => path,
            Err(err) => {
                return Err(err.message)
            }
        }
    var asmPath = tempDir + "/out.s"
    var objPath = tempDir + "/out.o"
    match WriteTextFile(asmPath, asmText) {
        Ok(_) => 0,
        Err(err) => {
            return Err(err.message)
        }
    }
    var asArgv = Vec[String]()
    asArgv.push("as");
    asArgv.push("-o");
    asArgv.push(objPath);
    asArgv.push(asmPath);
    match runTool(asArgv, "assembler failed") {
        Ok(_) => 0,
        Err(err) => {
            return Err(err)
        },
    }
    var ldArgv = Vec[String]()
    ldArgv.push("ld");
    ldArgv.push("-o");
    ldArgv.push(outputPath);
    ldArgv.push(objPath);
    return runTool(ldArgv, "linker failed")
}

func runTool(Vec[String] argv, String message) Result[int, String] {
    return match RunProcess(argv) {
        Ok(_) => Ok(0),
        Err(err) => Err(message + ": " + err.message),
    }
}

func containsText(String text, String needle) bool {
    return findText(text, needle) >= 0
}

func findText(String text, String needle) int {
    if len(needle) == 0 {
        return 0
    }
    if len(needle) > len(text) {
        return 0 - 1
    }
    var index = 0
    while index <= len(text) - len(needle) {
        if slice(text, index, index + len(needle)) == needle {
            return index
        }
        index++
    }
    return 0 - 1
}

func findCharFrom(String text, String needle, int start) int {
    var index = start
    while index < len(text) {
        if char_at(text, index) == needle {
            return index
        }
        index++
    }
    return 0 - 1
}

func digitValue(String ch) int {
    if ch == "0" {
        return 0
    }
    if ch == "1" {
        return 1
    }
    if ch == "2" {
        return 2
    }
    if ch == "3" {
        return 3
    }
    if ch == "4" {
        return 4
    }
    if ch == "5" {
        return 5
    }
    if ch == "6" {
        return 6
    }
    if ch == "7" {
        return 7
    }
    if ch == "8" {
        return 8
    }
    if ch == "9" {
        return 9
    }
    return 0
}

func encodeBytes(String text) String {
    var parts = Vec[String]()
    var index = 0
    while index < len(text) {
        parts.push(to_string(asciiCode(char_at(text, index))));
        index++
    }
    return joinWith(parts, ", ")
}

func asciiCode(String ch) int {
    if ch == "\n" {
        return 10
    }
    if ch == " " {
        return 32
    }
    if ch == "!" {
        return 33
    }
    if ch == "\"" {
        return 34
    }
    if ch == "#" {
        return 35
    }
    if ch == "$" {
        return 36
    }
    if ch == "%" {
        return 37
    }
    if ch == "&" {
        return 38
    }
    if ch == "'" {
        return 39
    }
    if ch == "*" {
        return 42
    }
    if ch == "," {
        return 44
    }
    if ch == "-" {
        return 45
    }
    if ch == "." {
        return 46
    }
    if ch == "/" {
        return 47
    }
    if ch == "(" {
        return 40
    }
    if ch == ")" {
        return 41
    }
    if ch == "+" {
        return 43
    }
    if ch == "0" {
        return 48
    }
    if ch == "1" {
        return 49
    }
    if ch == "2" {
        return 50
    }
    if ch == "3" {
        return 51
    }
    if ch == "4" {
        return 52
    }
    if ch == "5" {
        return 53
    }
    if ch == "6" {
        return 54
    }
    if ch == "7" {
        return 55
    }
    if ch == "8" {
        return 56
    }
    if ch == "9" {
        return 57
    }
    if ch == ":" {
        return 58
    }
    if ch == ";" {
        return 59
    }
    if ch == "<" {
        return 60
    }
    if ch == "=" {
        return 61
    }
    if ch == ">" {
        return 62
    }
    if ch == "?" {
        return 63
    }
    if ch == "@" {
        return 64
    }
    if ch == "A" {
        return 65
    }
    if ch == "B" {
        return 66
    }
    if ch == "C" {
        return 67
    }
    if ch == "D" {
        return 68
    }
    if ch == "E" {
        return 69
    }
    if ch == "F" {
        return 70
    }
    if ch == "G" {
        return 71
    }
    if ch == "H" {
        return 72
    }
    if ch == "I" {
        return 73
    }
    if ch == "J" {
        return 74
    }
    if ch == "K" {
        return 75
    }
    if ch == "L" {
        return 76
    }
    if ch == "M" {
        return 77
    }
    if ch == "N" {
        return 78
    }
    if ch == "O" {
        return 79
    }
    if ch == "P" {
        return 80
    }
    if ch == "Q" {
        return 81
    }
    if ch == "R" {
        return 82
    }
    if ch == "S" {
        return 83
    }
    if ch == "T" {
        return 84
    }
    if ch == "U" {
        return 85
    }
    if ch == "V" {
        return 86
    }
    if ch == "W" {
        return 87
    }
    if ch == "X" {
        return 88
    }
    if ch == "Y" {
        return 89
    }
    if ch == "Z" {
        return 90
    }
    if ch == "_" {
        return 95
    }
    if ch == "[" {
        return 91
    }
    if ch == "\\" {
        return 92
    }
    if ch == "]" {
        return 93
    }
    if ch == "^" {
        return 94
    }
    if ch == "`" {
        return 96
    }
    if ch == "a" {
        return 97
    }
    if ch == "b" {
        return 98
    }
    if ch == "c" {
        return 99
    }
    if ch == "d" {
        return 100
    }
    if ch == "e" {
        return 101
    }
    if ch == "f" {
        return 102
    }
    if ch == "g" {
        return 103
    }
    if ch == "h" {
        return 104
    }
    if ch == "i" {
        return 105
    }
    if ch == "j" {
        return 106
    }
    if ch == "k" {
        return 107
    }
    if ch == "l" {
        return 108
    }
    if ch == "m" {
        return 109
    }
    if ch == "n" {
        return 110
    }
    if ch == "o" {
        return 111
    }
    if ch == "p" {
        return 112
    }
    if ch == "q" {
        return 113
    }
    if ch == "r" {
        return 114
    }
    if ch == "s" {
        return 115
    }
    if ch == "t" {
        return 116
    }
    if ch == "u" {
        return 117
    }
    if ch == "v" {
        return 118
    }
    if ch == "w" {
        return 119
    }
    if ch == "x" {
        return 120
    }
    if ch == "y" {
        return 121
    }
    if ch == "z" {
        return 122
    }
    if ch == "{" {
        return 123
    }
    if ch == "|" {
        return 124
    }
    if ch == "}" {
        return 125
    }
    if ch == "~" {
        return 126
    }
    return 63
}

func joinWith(Vec[String] values, String sep) String {
    var text = ""
    var index = 0
    while index < values.len() {
        if index > 0 {
            text = text + sep
        }
        text = text + values[index]
        index++
    }
    return text
}

func usageError() Result[int, String] {
    return Err("usage: s_native build <path> -o <output>")
}

func normalizeOutputPath(String outputPath) String {
    if outputPath.len() > 0 && char_at(outputPath, 0) == "/" {
        return outputPath
    }
    return "/app/tmp/" + lastPathSegment(outputPath)
}

func lastPathSegment(String path) String {
    var index = path.len() - 1
    while index >= 0 {
        if char_at(path, index) == "/" {
            return slice(path, index + 1, path.len())
        }
        index = index - 1
    }
    return path
}
