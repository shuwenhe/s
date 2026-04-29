package compile.internal.noder

use std.result.result
use std.vec.vec

func apply_quirk(string name, source_unit mut unit) result[(), noder_error] {
    if name == "trim-trailing-space" {
        unit.text = trim_spaces(unit.text)
        return result::ok(())
    }
    if name == "normalize-import-quotes" {
        let lines = split_lines(unit.text)
        let out = ""
        let i = 0
        while i < lines.len() {
            let line = trim_spaces(lines[i])
            if starts_with(line, "use ") {
                let words = split_words(line)
                if words.len() >= 2 {
                    line = "use \"" + normalize_import_path(words[1]) + "\""
                    if words.len() >= 4 && words[2] == "as" {
                        line = line + " as " + words[3]
                    }
                }
            }
            if i > 0 {
                out = out + "\n"
            }
            out = out + line
            i = i + 1
        }
        unit.text = out
        return result::ok(())
    }

    result::err(make_error(code_unknown_quirk(), "unknown quirk: " + name, unit.path, 0, 0))
}

func apply_quirks(vec[string] quirks, source_unit mut unit) result[(), noder_error] {
    let i = 0
    while i < quirks.len() {
        let r = apply_quirk(quirks[i], unit)
        if r.is_err() {
            return r
        }
        i = i + 1
    }
    result::ok(())
}
