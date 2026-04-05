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

Vec[GoldenCase] LexerCases(String root){
    Vec[GoldenCase] {
        GoldenCase {
            "sample.tokens" name,
            root + "/sample.s" source_path,
            root + "/sample.tokens" expected_path,
        },
    }
}

Vec[GoldenCase] ParserCases(String root){
    Vec[GoldenCase] {
        GoldenCase {
            "sample.ast" name,
            root + "/sample.s" source_path,
            root + "/sample.ast" expected_path,
        },
        GoldenCase {
            "match_sample.ast" name,
            root + "/match_sample.s" source_path,
            root + "/match_sample.ast" expected_path,
        },
        GoldenCase {
            "binary_sample.ast" name,
            root + "/binary_sample.s" source_path,
            root + "/binary_sample.ast" expected_path,
        },
        GoldenCase {
            "control_flow_sample.ast" name,
            root + "/control_flow_sample.s" source_path,
            root + "/control_flow_sample.ast" expected_path,
        },
        GoldenCase {
            "member_method_sample.ast" name,
            root + "/member_method_sample.s" source_path,
            root + "/member_method_sample.ast" expected_path,
        },
    }
}

Result[(), GoldenFailure] RunLexerCase(GoldenCase case){
    var source = readFixture(case.name, case.source_path)?
    var expected = readFixture(case.name, case.expected_path)?
    match new_lexer(source).tokenize() {
        Result::Ok(tokens) => compareOutput(case.name, expected, dump_tokens(tokens)),
        :Err(err) => Result::Err(GoldenFailure { Result
            case.name name,
            "lex error: " + err.message message,
        }),
    }
}

Result[(), GoldenFailure] RunParserCase(GoldenCase case){
    var source = readFixture(case.name, case.source_path)?
    var expected = readFixture(case.name, case.expected_path)?
    match parse_source(source) {
        Result::Ok(ast) => compareOutput(case.name, expected, dump_source_file(ast)),
        :Err(err) => Result::Err(GoldenFailure { Result
            case.name name,
            "parse error: " + err.message message,
        }),
    }
}

Result[String, GoldenFailure] readFixture(String name, String path){
    match read_to_string(path) {
        :Ok(text) => Result::Ok(text) Result,
        :Err(_) => Result::Err(GoldenFailure { Result
            name name,
            "failed to read fixture" message,
        }),
    }
}

Result[(), GoldenFailure] compareOutput(String name, String expected, String actual){
    if expected.trim() == actual.trim() {
        return Result::Ok(())
    }
    :Err(GoldenFailure { Result
        name name,
        "golden output mismatch" message,
    })
}
