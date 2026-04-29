package compile.internal.noder

use s.parse_source
use std.result.result
use std.vec.vec

func run_unified(string path, vec[string] quirks) result[noder_output, noder_error] {
    let unit = read_unit(path)?
    apply_quirks(quirks, unit)?

    let tokens = lex_source(unit)?
    let imports = parse_imports(unit)

    let ast_result = parse_source(unit.text)
    if ast_result.is_err() {
        let err = ast_result.unwrap_err()
        return result::err(make_error(code_parse_failed(), err.message, unit.path, err.line, err.column))
    }

    let ast = ast_result.unwrap()
    let ir = lower_to_ir(ast)
    let exports = collect_exports(ast)

    let notes = vec[string]()
    notes.push("imports=" + to_string(imports.len()))
    notes.push("tokens=" + to_string(tokens.len()))
    notes.push("exports=" + to_string(exports.len()))

    result::ok(noder_output {
        unit: unit,
        tokens: tokens,
        imports: imports,
        ast: ast,
        ir: ir,
        exports: exports,
        notes: notes,
    })
}
