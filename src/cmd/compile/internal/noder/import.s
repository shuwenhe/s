package compile.internal.noder

use std.option.option
use std.vec.vec

func parse_imports(source_unit unit) vec[import_record] {
    var out = vec[import_record]()
    var lines = split_lines(unit.text)
    var i = 0
    while i < lines.len() {
        var line = trim_spaces(lines[i])
        if !starts_with(line, "use ") {
            i = i + 1
            continue
        }

        var parts = split_words(line)
        if parts.len() >= 2 {
            var path = normalize_import_path(parts[1])
            var alias = option::none
            if parts.len() >= 4 && parts[2] == "as" {
                alias = option::some(parts[3])
            }
            out.push(import_record {
                path: path,
                alias: alias,
            })
        }
        i = i + 1
    }
    out
}

func import_map(vec[import_record] imports) vec[string] {
    var out = vec[string]()
    var i = 0
    while i < imports.len() {
        switch imports[i].alias {
            option::some(alias) : out.push(alias + "=" + imports[i].path),
            option::none : out.push(imports[i].path),
        }
        i = i + 1
    }
    out
}
