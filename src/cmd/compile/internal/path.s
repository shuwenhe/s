package compile.internal.path

func path_segment_kind_field() int { 0 }
func path_segment_kind_index() int { 1 }
func path_segment_kind_index_var() int { 2 }
func path_segment_kind_deref() int { 3 }

struct path_segment {
    kind int
    field_name string
    index_value int
    index_var string
}

struct path {
    base_var string
    path_segment[] segments
}

func path_new(string base_var) path {
    path_segment[] segs
    path { base_var: base_var, segments: segs }
}

func path_field(path p, string field_name) path {
    new_seg := path_segment {
        kind: path_segment_kind_field(),
        field_name: field_name
    }
    p.segments = append(p.segments, new_seg)
    p
}

func path_index(path p, int index_value) path {
    new_seg := path_segment {
        kind: path_segment_kind_index(),
        index_value: index_value
    }
    p.segments = append(p.segments, new_seg)
    p
}

func path_index_var(path p, string var_name) path {
    new_seg := path_segment {
        kind: path_segment_kind_index_var(),
        index_var: var_name
    }
    p.segments = append(p.segments, new_seg)
    p
}

func path_deref(path p) path {
    new_seg := path_segment {
        kind: path_segment_kind_deref()
    }
    p.segments = append(p.segments, new_seg)
    p
}

func path_equal(path p1, path p2) bool {
    if p1.base_var != p2.base_var { return false }
    if len(p1.segments) != len(p2.segments) { return false }

    i := 0
    for i < len(p1.segments) {
        seg1 := p1.segments[i]
        seg2 := p2.segments[i]

        if seg1.kind != seg2.kind { return false }

        if seg1.kind == path_segment_kind_field() {
            if seg1.field_name != seg2.field_name { return false }
        } else if seg1.kind == path_segment_kind_index() {
            if seg1.index_value != seg2.index_value { return false }
        } else if seg1.kind == path_segment_kind_index_var() {
            if seg1.index_var != seg2.index_var { return false }
        }

        i = i + 1
    }
    true
}

func path_is_prefix(path p1, path p2) bool {
    if p1.base_var != p2.base_var { return false }
    if len(p1.segments) > len(p2.segments) { return false }

    i := 0
    for i < len(p1.segments) {
        seg1 := p1.segments[i]
        seg2 := p2.segments[i]

        if seg1.kind != seg2.kind { return false }

        if seg1.kind == path_segment_kind_field() {
            if seg1.field_name != seg2.field_name { return false }
        } else if seg1.kind == path_segment_kind_index() {
            if seg1.index_value != seg2.index_value { return false }
        } else if seg1.kind == path_segment_kind_index_var() {
            if seg1.index_var != seg2.index_var { return false }
        }

        i = i + 1
    }
    true
}

func path_len(path p) int {
    len(p.segments)
}

func path_get_segment(path p, int i) path_segment {
    if i < 0 || i >= len(p.segments) {
        return path_segment { kind: -1 }
    }
    p.segments[i]
}

func path_to_string(path p) string {
    result := p.base_var

    i := 0
    for i < len(p.segments) {
        seg := p.segments[i]

        if seg.kind == path_segment_kind_field() {
            result = result + "." + seg.field_name
        } else if seg.kind == path_segment_kind_index() {

            idx_str := "0"
            if seg.index_value > 0 {
                idx_str = "N"
            }
            result = result + "[" + idx_str + "]"
        } else if seg.kind == path_segment_kind_index_var() {
            result = result + "[" + seg.index_var + "]"
        } else if seg.kind == path_segment_kind_deref() {
            result = result + "(*)"
        }

        i = i + 1
    }
    result
}

func path_parse(string s) path {

    path_new(s)
}

func path_parent(path p) path {
    if len(p.segments) == 0 {
        return path_new("")
    }
    new_segments := p.segments
    new_len := len(p.segments) - 1

    path { base_var: p.base_var, segments: new_segments }
}

func path_common_prefix(path p1, path p2) path {
    if p1.base_var != p2.base_var {
        return path_new("")
    }

    min_len := len(p1.segments)
    if len(p2.segments) < min_len {
        min_len = len(p2.segments)
    }

    i := 0
    common_segs_count := 0

    for i < min_len {
        seg1 := p1.segments[i]
        seg2 := p2.segments[i]

        if seg1.kind != seg2.kind {
            break
        }

        if seg1.kind == path_segment_kind_field() {
            if seg1.field_name != seg2.field_name { break }
        } else if seg1.kind == path_segment_kind_index() {
            if seg1.index_value != seg2.index_value { break }
        }

        common_segs_count = common_segs_count + 1
        i = i + 1
    }

    result := path_new(p1.base_var)
    i = 0
    for i < common_segs_count {
        seg := p1.segments[i]
        result.segments = append(result.segments, seg)
        i = i + 1
    }
    result
}

func path_same_base(path p1, path p2) bool {
    p1.base_var == p2.base_var
}

struct path_map {
    path[] keys
    int[] values
}

func path_map_new() path_map {
    path[] keys
    int[] values
    path_map { keys: keys, values: values }
}

func path_map_insert(path_map m, path p, int value) path_map {

    i := 0
    for i < len(m.keys) {
        if path_equal(m.keys[i], p) {
            m.values[i] = value
            return m
        }
        i = i + 1
    }

    m.keys = append(m.keys, p)
    m.values = append(m.values, value)
    m
}

func path_map_get(path_map m, path p) int {
    i := 0
    for i < len(m.keys) {
        if path_equal(m.keys[i], p) {
            return m.values[i]
        }
        i = i + 1
    }
    -1
}

func path_map_remove(path_map m, path p) path_map {

    found_idx := -1
    i := 0
    for i < len(m.keys) {
        if path_equal(m.keys[i], p) {
            found_idx = i
            break
        }
        i = i + 1
    }

    if found_idx < 0 { return m }

    new_keys := m.keys
    new_values := m.values

    path_map { keys: new_keys, values: new_values }
}

struct path_set {
    path[] paths
}

func path_set_new() path_set {
    path[] paths
    path_set { paths: paths }
}

func path_set_add(path_set s, path p) path_set {

    i := 0
    for i < len(s.paths) {
        if path_equal(s.paths[i], p) {
            return s
        }
        i = i + 1
    }

    s.paths = append(s.paths, p)
    s
}

func path_set_contains(path_set s, path p) bool {
    i := 0
    for i < len(s.paths) {
        if path_equal(s.paths[i], p) {
            return true
        }
        i = i + 1
    }
    false
}

func path_set_size(path_set s) int {
    len(s.paths)
}