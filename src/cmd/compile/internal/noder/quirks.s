package compile.internal.noder
use std.result.result
use std.vec.vec

func apply_quirk(string name, source_unit unit) ((), noder_error) {
    if name == "trim-trailing-space" {
        unit.text = trim_spaces(unit.text)
        return ())
    }
    if name == "normalize-import-quotes" {
        lines := split_lines(unit.text)
        out := ""
        i := 0
        for i < lines.len() {
            line := trim_spaces(lines[i])
            if starts_with(line, "use ") {
                words := split_words(line)
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
        return ())
    }
    make_error(code_unknown_quirk(), "unknown quirk: " + name, unit.path, 0, 0)
}

func apply_quirks(vec[string] quirks, source_unit unit) ((), noder_error) {
    i := 0
    for i < quirks.len() {
        r := apply_quirk(quirks[i], unit)
        if r.is_err() {
            return r
        }
        i = i + 1
    }
    ()
}
