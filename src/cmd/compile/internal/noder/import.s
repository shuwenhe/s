package compile.internal.noder
use std.option.option
use std.slices
func parse_imports(source_unit unit) import_record[] {
    out := import_record[]()
    lines := split_lines(unit.text)
    i := 0
    for i < len(lines) {
        line := trim_spaces(lines[i])
        if !starts_with(line, "use ") {
            i = i + 1
            continue
        }
        parts := split_words(line)
        if len(parts) >= 2 {
            path := normalize_import_path(parts[1])
            alias := option::none
            if len(parts) >= 4 && parts[2] == "as" {
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

func import_map(import_record[] imports) string[] {
    out := string[]()
    i := 0
    for i < len(imports) {
        switch imports[i].alias {
            option::some(alias) : out = append(out, alias + "=" + imports[i].path),
            option::none : out = append(out, imports[i].path),
        }
        i = i + 1
    }
    out
}
