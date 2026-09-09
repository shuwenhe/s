package compile.internal.drop_state_v2

// DropState v2: 包含元数据的状态表示
// 支持: live, moved, maybe, partial, dropped 五种状态

// State kinds
func drop_state_kind_live() int { 0 }
func drop_state_kind_moved() int { 1 }
func drop_state_kind_maybe() int { 2 }
func drop_state_kind_partial() int { 3 }
func drop_state_kind_dropped() int { 4 }

struct drop_state {
    int kind                    // live/moved/maybe/partial/dropped
    string reason              // "move at line X", "conditional merge", etc.
    int line_number
    int column_number
    
    // For partial state: 哪些字段的状态
    struct {
        string field_name
        int field_state        // kind 值
    }[] field_states
    
    // For maybe state: 来自哪些分支
    int[] source_branch_ids    // 哪些条件分支的合并
}

// ============================================================================
// State Construction
// ============================================================================

func drop_state_new_live() drop_state {
    drop_state {
        kind: drop_state_kind_live(),
        reason: "declared",
        line_number: -1,
        column_number: -1,
        field_states: nil,
        source_branch_ids: nil,
    }
}

func drop_state_new_moved(string reason, int line, int col) drop_state {
    drop_state {
        kind: drop_state_kind_moved(),
        reason: reason,
        line_number: line,
        column_number: col,
        field_states: nil,
        source_branch_ids: nil,
    }
}

func drop_state_new_maybe() drop_state {
    drop_state {
        kind: drop_state_kind_maybe(),
        reason: "conditional merge",
        line_number: -1,
        column_number: -1,
        field_states: nil,
        source_branch_ids: nil,
    }
}

func drop_state_new_partial() drop_state {
    struct {
        string field_name
        int field_state
    }[] fields
    
    drop_state {
        kind: drop_state_kind_partial(),
        reason: "partial move",
        line_number: -1,
        column_number: -1,
        field_states: fields,
        source_branch_ids: nil,
    }
}

func drop_state_new_dropped() drop_state {
    drop_state {
        kind: drop_state_kind_dropped(),
        reason: "dropped",
        line_number: -1,
        column_number: -1,
        field_states: nil,
        source_branch_ids: nil,
    }
}

// ============================================================================
// State Query
// ============================================================================

func drop_state_is_live(drop_state s) bool {
    s.kind == drop_state_kind_live()
}

func drop_state_is_moved(drop_state s) bool {
    s.kind == drop_state_kind_moved()
}

func drop_state_is_maybe(drop_state s) bool {
    s.kind == drop_state_kind_maybe()
}

func drop_state_is_partial(drop_state s) bool {
    s.kind == drop_state_kind_partial()
}

func drop_state_is_dropped(drop_state s) bool {
    s.kind == drop_state_kind_dropped()
}

func drop_state_needs_drop(drop_state s) bool {
    s.kind == drop_state_kind_live() || s.kind == drop_state_kind_partial()
}

// ============================================================================
// State Transitions
// ============================================================================

// 转移：After Move
// live → moved
// live (struct) → partial (当移出一个字段时)
// moved → error
// dropped → error

func drop_state_after_move(drop_state s, string reason, int line, int col) (drop_state, string) {
    if drop_state_is_live(s) {
        return drop_state_new_moved(reason, line, col), ""
    }
    
    if drop_state_is_moved(s) {
        return s, "error: move of moved value"
    }
    
    if drop_state_is_dropped(s) {
        return s, "error: move of dropped value"
    }
    
    return s, ""
}

// 转移：After Use
// live → live (no change, but verify)
// moved → error
// maybe → warning (might be moved)
// dropped → error

func drop_state_after_use(drop_state s) (drop_state, string) {
    if drop_state_is_live(s) {
        return s, ""
    }
    
    if drop_state_is_moved(s) {
        return s, "error: use of moved value"
    }
    
    if drop_state_is_maybe(s) {
        return s, "warning: use of value that might be moved"
    }
    
    if drop_state_is_dropped(s) {
        return s, "error: use of dropped value"
    }
    
    return s, ""
}

// 转移：After Drop
// live → dropped
// moved → error (double-drop prevention)
// partial → dropped
// dropped → error
// maybe → dropped (conservative)

func drop_state_after_drop(drop_state s) (drop_state, string) {
    if drop_state_is_live(s) || drop_state_is_partial(s) || drop_state_is_maybe(s) {
        return drop_state_new_dropped(), ""
    }
    
    if drop_state_is_moved(s) {
        return s, "error: double drop (value already moved)"
    }
    
    if drop_state_is_dropped(s) {
        return s, "error: double drop (value already dropped)"
    }
    
    return s, ""
}

// 转移：After Reassignment
// moved → live (重新赋值)
// live → live (overwrite)
// partial → live (overwrite entire value)

func drop_state_after_reassign(drop_state s_old) drop_state {
    // 无论之前的状态是什么，重新赋值后都是 live
    drop_state_new_live()
}

// ============================================================================
// State Merge (for CFG)
// ============================================================================

// 合并两个状态（来自不同的条件分支）
// 规则:
//   live + live = live
//   moved + moved = moved
//   live + moved = maybe
//   partial + partial = maybe (conservative)
//   maybe + X = maybe

func drop_state_merge(drop_state s1, drop_state s2) drop_state {
    // 如果两者相同
    if s1.kind == s2.kind {
        return s1  // 或 s2，都一样
    }
    
    // live + moved = maybe
    if (drop_state_is_live(s1) && drop_state_is_moved(s2)) ||
       (drop_state_is_moved(s1) && drop_state_is_live(s2)) {
        return drop_state_new_maybe()
    }
    
    // live + partial = maybe
    if (drop_state_is_live(s1) && drop_state_is_partial(s2)) ||
       (drop_state_is_partial(s1) && drop_state_is_live(s2)) {
        return drop_state_new_maybe()
    }
    
    // partial + moved = maybe
    if (drop_state_is_partial(s1) && drop_state_is_moved(s2)) ||
       (drop_state_is_moved(s1) && drop_state_is_partial(s2)) {
        return drop_state_new_maybe()
    }
    
    // maybe + X = maybe
    if drop_state_is_maybe(s1) || drop_state_is_maybe(s2) {
        return drop_state_new_maybe()
    }
    
    // 其他情况：maybe (保守)
    drop_state_new_maybe()
}

// 合并多个状态列表（用于 switch 等）
func drop_state_merge_list(drop_state[] states) drop_state {
    if len(states) == 0 {
        return drop_state_new_live()  // 默认 live
    }
    
    result := states[0]
    i := 1
    for i < len(states) {
        result = drop_state_merge(result, states[i])
        i = i + 1
    }
    result
}

// ============================================================================
// Partial State Management
// ============================================================================

// 当 struct 的一个字段被 move 时，整体状态变为 partial
// 记录哪些字段是 moved，哪些是 live

func drop_state_mark_field_moved(drop_state s, string field_name) drop_state {
    if !drop_state_is_partial(s) {
        // 第一次发生 partial move，创建新的 partial 状态
        struct {
            string field_name
            int field_state
        }[] fields
        
        fields = append(fields, struct {
            field_name: field_name,
            field_state: drop_state_kind_moved(),
        })
        
        return drop_state {
            kind: drop_state_kind_partial(),
            reason: "partial move: " + field_name,
            line_number: -1,
            field_states: fields,
            source_branch_ids: nil,
        }
    }
    
    // 已经是 partial，添加更多字段信息
    found := false
    i := 0
    for i < len(s.field_states) {
        if s.field_states[i].field_name == field_name {
            s.field_states[i].field_state = drop_state_kind_moved()
            found = true
            break
        }
        i = i + 1
    }
    
    if !found {
        s.field_states = append(s.field_states, struct {
            field_name: field_name,
            field_state: drop_state_kind_moved(),
        })
    }
    
    s
}

func drop_state_get_field_state(drop_state s, string field_name) int {
    if !drop_state_is_partial(s) {
        return drop_state_kind_live()  // 默认 live
    }
    
    i := 0
    for i < len(s.field_states) {
        if s.field_states[i].field_name == field_name {
            return s.field_states[i].field_state
        }
        i = i + 1
    }
    
    // 没有记录的字段，默认 live
    drop_state_kind_live()
}

// ============================================================================
// String Representation (for debugging)
// ============================================================================

func drop_state_to_string(drop_state s) string {
    if drop_state_is_live(s) {
        return "live"
    }
    if drop_state_is_moved(s) {
        return "moved (reason: " + s.reason + ")"
    }
    if drop_state_is_maybe(s) {
        return "maybe"
    }
    if drop_state_is_partial(s) {
        return "partial"
    }
    if drop_state_is_dropped(s) {
        return "dropped"
    }
    "unknown"
}

// ============================================================================
// Batch State Operations
// ============================================================================

struct drop_state_table {
    string[] var_names
    drop_state[] states
}

func drop_state_table_new() drop_state_table {
    string[] names
    drop_state[] states
    drop_state_table { var_names: names, states: states }
}

func drop_state_table_set(drop_state_table t, string var_name, drop_state s) drop_state_table {
    i := 0
    for i < len(t.var_names) {
        if t.var_names[i] == var_name {
            t.states[i] = s
            return t
        }
        i = i + 1
    }
    
    // 不存在，添加新项
    t.var_names = append(t.var_names, var_name)
    t.states = append(t.states, s)
    t
}

func drop_state_table_get(drop_state_table t, string var_name) drop_state {
    i := 0
    for i < len(t.var_names) {
        if t.var_names[i] == var_name {
            return t.states[i]
        }
        i = i + 1
    }
    
    // 不存在，返回 live（默认）
    drop_state_new_live()
}
