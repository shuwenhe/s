package compiler

use std.fs.read_to_string
use std.result.Result
use std.vec.Vec
use frontend.dump_source_file
use frontend.dump_tokens
use frontend.parse_source
use frontend.new_lexer

struct GoldenCase {
    String name,
    String source_path,
    String expected_path,
}

struct GoldenFailure {
    String name,
    String message,
}

func LexerCases(String root) -> Vec[GoldenCase] {
    Vec[GoldenCase] {
        GoldenCase {
            name: "sample.tokens",
            source_path: root + "/sample.s",
            expected_path: root + "/sample.tokens",
        },
    }
}

func ParserCases(String root) -> Vec[GoldenCase] {
    Vec[GoldenCase] {
        GoldenCase {
            name: "sample.ast",
            source_path: root + "/sample.s",
            expected_path: root + "/sample.ast",
        },
        GoldenCase {
            name: "match_sample.ast",
            source_path: root + "/match_sample.s",
            expected_path: root + "/match_sample.ast",
        },
        GoldenCase {
            name: "binary_sample.ast",
            source_path: root + "/binary_sample.s",
            expected_path: root + "/binary_sample.ast",
        },
        GoldenCase {
            name: "control_flow_sample.ast",
            source_path: root + "/control_flow_sample.s",
            expected_path: root + "/control_flow_sample.ast",
        },
        GoldenCase {
            name: "member_method_sample.ast",
            source_path: root + "/member_method_sample.s",
            expected_path: root + "/member_method_sample.ast",
        },
    }
}

func RunLexerCase(GoldenCase case) -> Result[(), GoldenFailure] {
    var source = readFixture(case.name, case.source_path)?
    var expected = readFixture(case.name, case.expected_path)?
    match new_lexer(source).tokenize() {
        Result::Ok(tokens) => compareOutput(case.name, expected, dump_tokens(tokens)),
        Result::Err(err) => Result::Err(GoldenFailure {
            name: case.name,
            message: "lex error: " + err.message,
        }),
    }
}

func RunParserCase(GoldenCase case) -> Result[(), GoldenFailure] {
    var source = readFixture(case.name, case.source_path)?
    var expected = readFixture(case.name, case.expected_path)?
    match parse_source(source) {
        Result::Ok(ast) => compareOutput(case.name, expected, dump_source_file(ast)),
        Result::Err(err) => Result::Err(GoldenFailure {
            name: case.name,
            message: "parse error: " + err.message,
        }),
    }
}

func readFixture(String name, String path) -> Result[String, GoldenFailure] {
    match read_to_string(path) {
        Result::Ok(text) => Result::Ok(text),
        Result::Err(_) => Result::Err(GoldenFailure {
            name: name,
            message: "failed to read fixture",
        }),
    }
}

func compareOutput(String name, String expected, String actual) -> Result[(), GoldenFailure] {
    if expected.trim() == actual.trim() {
        return Result::Ok(())
    }
    Result::Err(GoldenFailure {
        name: name,
        message: "golden output mismatch",
    })
}
