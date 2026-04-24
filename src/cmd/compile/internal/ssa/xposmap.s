package compile.internal.ssa

use std.vec.vec

struct line_range {
    int first
    int last
}

struct xpos_map_entry {
    int file_index
    line_range lines
    sparse_map data
}

struct xpos_map {
    vec[xpos_map_entry] maps
    int last_index
    int last_slot
}

func new_xpos_map(vec[int_pair] file_ranges) xpos_map {
    var maps = vec[xpos_map_entry]()
    var i = 0
    while i < file_ranges.len() {
        var left = file_ranges[i].left
        var right = file_ranges[i].right
        var width = right - left + 1
        if width < 0 {
            width = 0
        }
        maps.push(xpos_map_entry {
            file_index: i,
            lines: line_range { first: left, last: right },
            data: new_sparse_map(width),
        })
        i = i + 1
    }
    xpos_map {
        maps: maps,
        last_index: -1,
        last_slot: -1,
    }
}

func xpos_map_slot(mut xpos_map m, int file_index) int_pair {
    if file_index == m.last_index && m.last_slot >= 0 {
        return make_int_pair(m.last_slot, 1)
    }
    var i = 0
    while i < m.maps.len() {
        if m.maps[i].file_index == file_index {
            m.last_index = file_index
            m.last_slot = i
            return make_int_pair(i, 1)
        }
        i = i + 1
    }
    make_int_pair(0, 0)
}

func xpos_map_clear(mut xpos_map m) xpos_map {
    var i = 0
    while i < m.maps.len() {
        m.maps[i].data = sparse_map_clear(m.maps[i].data)
        i = i + 1
    }
    m.last_index = -1
    m.last_slot = -1
    m
}

func xpos_map_set(mut xpos_map m, int file_index, int line, int value) xpos_map {
    var slot = xpos_map_slot(m, file_index)
    if slot.right == 0 {
        return m
    }
    var start = m.maps[slot.left].lines.first
    m.maps[slot.left].data = sparse_map_set(m.maps[slot.left].data, line - start, value)
    m
}

func xpos_map_get(mut xpos_map m, int file_index, int line) int_pair {
    var slot = xpos_map_slot(m, file_index)
    if slot.right == 0 {
        return make_int_pair(0, 0)
    }
    var start = m.maps[slot.left].lines.first
    sparse_map_get(m.maps[slot.left].data, line - start)
}

func xpos_map_contains(mut xpos_map m, int file_index, int line) bool {
    var slot = xpos_map_slot(m, file_index)
    if slot.right == 0 {
        return false
    }
    var start = m.maps[slot.left].lines.first
    sparse_map_contains(m.maps[slot.left].data, line - start)
}
