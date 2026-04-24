package compile.internal.noder

use std.vec.vec

func build_pos_map(string source) vec[pos_entry] {
    var out = vec[pos_entry]()
    var lines = split_lines(source)
    var offset = 0
    var i = 0
    while i < lines.len() {
        out.push(pos_entry {
            offset: offset,
            line: i + 1,
            column: 1,
        })
        offset = offset + len(lines[i]) + 1
        i = i + 1
    }
    out
}

func offset_to_pos(vec[pos_entry] table, int offset) pos_entry {
    if table.len() == 0 {
        return pos_entry { offset: offset, line: 1, column: 1 }
    }

    var i = 0
    var last = table[0]
    while i < table.len() {
        if table[i].offset > offset {
            break
        }
        last = table[i]
        i = i + 1
    }
    pos_entry {
        offset: offset,
        line: last.line,
        column: offset - last.offset + 1,
    }
}
