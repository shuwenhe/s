package compile.internal.noder

func run_lex_tests() int {
    let unit = source_unit {
        path: "demo.s",
        text: "package demo\nuse \"std.io\"\nfunc main() int { 0 }\n",
    }
    let tokens_result = lex_source(unit)
    if tokens_result.is_err() {
        return 1
    }
    let tokens = tokens_result.unwrap()
    if tokens.len() == 0 {
        return 1
    }
    if tokens[0].text != "package" {
        return 1
    }
    if tokens[1].text != "demo" {
        return 1
    }
    0
}
