package compile.internal.noder
use s.parse_source
use std.result.result
use std.slices
func run_unified(string path, []string quirks) (noder_output, noder_error) {
    unit := read_unit(path)?
    apply_quirks(quirks, unit)?
    tokens := lex_source(unit)?
    imports := parse_imports(unit)
    ast_result := parse_source(unit.text)
    if ast_result.is_err() {
        err := ast_result.unwrap_err()
        return make_error(code_parse_failed(), err.message, unit.path, err.line, err.column)
    }
    ast := ast_result.unwrap()
    ir := lower_to_ir(ast)
    exports := collect_exports(ast)
    notes := []string()
    notes = append(notes, "imports=" + to_string(len(imports)))
    notes = append(notes, "tokens=" + to_string(len(tokens)))
    notes = append(notes, "exports=" + to_string(len(exports)))
    noder_output {
        unit: unit, tokens tokens, imports imports, ast ast, ir ir, exports exports, notes notes,
    }
}
