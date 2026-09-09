package compile.internal.path

// Path: 字段级访问路径的结构表示
// 示例: x.f[0].g → Path { base: "x", segments: [FIELD("f"), INDEX(0), FIELD("g")] }

// PathSegment kinds
func path_segment_kind_field() int { 0 }
func path_segment_kind_index() int { 1 }
func path_segment_kind_index_var() int { 2 }
func path_segment_kind_deref() int { 3 }

struct path_segment {
    int kind                    // FIELD, INDEX, INDEX_VAR, DEREF
    string field_name          // for FIELD
    int index_value            // for INDEX
    string index_var           // for INDEX_VAR
}

struct path {
    string base_var
    path_segment[] segments
}

// ============================================================================
// Path Construction & Manipulation
// ============================================================================

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

// ============================================================================
// Path Comparison & Query
// ============================================================================

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

// 检查 p1 是否是 p2 的前缀
// 例: x.f 是 x.f[0].g 的前缀
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

// path 的长度（段数）
func path_len(path p) int {
    len(p.segments)
}

// 获取第 i 个段
func path_get_segment(path p, int i) path_segment {
    if i < 0 || i >= len(p.segments) {
        return path_segment { kind: -1 }  // error
    }
    p.segments[i]
}

// ============================================================================
// Path String Conversion (for debugging & serialization)
// ============================================================================

func path_to_string(path p) string {
    result := p.base_var
    
    i := 0
    for i < len(p.segments) {
        seg := p.segments[i]
        
        if seg.kind == path_segment_kind_field() {
            result = result + "." + seg.field_name
        } else if seg.kind == path_segment_kind_index() {
            // 转换 int 到 string
            idx_str := "0"
            if seg.index_value > 0 {
                idx_str = "N"  // 简化表示，实际应实现 int->string
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

// ============================================================================
// Path Parsing (from string to structured)
// ============================================================================

// 简化的解析器，支持基本的路径格式
// "x" → Path { base: "x" }
// "x.f" → Path { base: "x", segments: [FIELD("f")] }
// "x.f[0]" → Path { base: "x", segments: [FIELD("f"), INDEX(0)] }
// "x[i]" → Path { base: "x", segments: [INDEX_VAR("i")] }

func path_parse(string s) path {
    // TODO: Implement full parser
    // For now, simple implementation for base case
    path_new(s)
}

// ============================================================================
// Path Utilities
// ============================================================================

// 获取父路径（移除最后一个段）
func path_parent(path p) path {
    if len(p.segments) == 0 {
        return path_new("")  // error
    }
    new_segments := p.segments
    new_len := len(p.segments) - 1
    // 截断数组（S 语言中可能需要手动处理）
    path { base_var: p.base_var, segments: new_segments }
}

// 获取第一个不同的路径前缀（用于 CFG merge）
// 例: merge(x.f, x.g) → x
func path_common_prefix(path p1, path p2) path {
    if p1.base_var != p2.base_var {
        return path_new("")  // error
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
    
    // 构建公共前缀
    result := path_new(p1.base_var)
    i = 0
    for i < common_segs_count {
        seg := p1.segments[i]
        result.segments = append(result.segments, seg)
        i = i + 1
    }
    result
}

// 检查两个路径是否涉及同一个基变量
func path_same_base(path p1, path p2) bool {
    p1.base_var == p2.base_var
}

// ============================================================================
// Path Collections (for efficient lookup)
// ============================================================================

struct path_map {
    path[] keys
    int[] values  // 存储的关联值（例如 state ID）
}

func path_map_new() path_map {
    path[] keys
    int[] values
    path_map { keys: keys, values: values }
}

func path_map_insert(path_map m, path p, int value) path_map {
    // 检查是否已存在
    i := 0
    for i < len(m.keys) {
        if path_equal(m.keys[i], p) {
            m.values[i] = value
            return m
        }
        i = i + 1
    }
    
    // 不存在，添加新项
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
    -1  // not found
}

func path_map_remove(path_map m, path p) path_map {
    // 找到并移除
    found_idx := -1
    i := 0
    for i < len(m.keys) {
        if path_equal(m.keys[i], p) {
            found_idx = i
            break
        }
        i = i + 1
    }
    
    if found_idx < 0 { return m }  // not found
    
    // 移除（需要重建数组）
    new_keys := m.keys
    new_values := m.values
    // S 语言中可能需要手动处理数组移除
    
    path_map { keys: new_keys, values: new_values }
}

// ============================================================================
// Path Set (collection of paths without values)
// ============================================================================

struct path_set {
    path[] paths
}

func path_set_new() path_set {
    path[] paths
    path_set { paths: paths }
}

func path_set_add(path_set s, path p) path_set {
    // 检查是否已存在
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
