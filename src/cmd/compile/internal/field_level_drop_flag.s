package compile.internal.field_level_drop_flag

use compile.internal.path.path
use compile.internal.path.path_new
use compile.internal.path.path_equal
use compile.internal.path.path_is_prefix
use compile.internal.path.path_field
use compile.internal.drop_state_v2.drop_state
use compile.internal.drop_state_v2.drop_state_new_live
use compile.internal.drop_state_v2.drop_state_after_move
use compile.internal.drop_state_v2.drop_state_after_use
use compile.internal.drop_state_v2.drop_state_after_drop
use compile.internal.drop_state_v2.drop_state_after_reassign
use compile.internal.drop_state_v2.drop_state_merge
use compile.internal.drop_state_v2.drop_state_is_live
use compile.internal.drop_state_v2.drop_state_is_moved
use compile.internal.drop_state_v2.drop_state_needs_drop

struct field_level_entry {
    path path
    drop_state state
    string type_name
    int scope_depth
}

struct field_level_drop_flag {
    field_level_entry[] entries
    int scope_depth
    string[] errors
}

// ============================================================================
// Initialization
// ============================================================================

func fldf_new() field_level_drop_flag {
    field_level_entry[] entries
    string[] errors
    field_level_drop_flag { entries: entries, scope_depth: 0, errors: errors }
}

// ============================================================================
// Finding & Lookup
// ============================================================================

func fldf_find(field_level_drop_flag f, path p) int {
    i := len(f.entries) - 1
    for i >= 0 {
        if path_equal(f.entries[i].path, p) {
            return i
        }
        i = i - 1
    }
    -1
}

// 查找所有与给定路径相关的条目（前缀匹配）
// 例如: 查找 x 时，返回 x, x.f, x.f[0] 等
func fldf_find_related(field_level_drop_flag f, path p) int[] {
    int[] results
    i := 0
    for i < len(f.entries) {
        if path_is_prefix(p, f.entries[i].path) {
            results = append(results, i)
        }
        i = i + 1
    }
    results
}

// ============================================================================
// Core Operations
// ============================================================================

// Declaration: 声明一个新变量
func fldf_declare(field_level_drop_flag f, path p, string type_name) field_level_drop_flag {
    if fldf_find(f, p) >= 0 {
        f.errors = append(f.errors, "duplicate variable: variable already declared")
        return f
    }
    
    entry := field_level_entry {
        path: p,
        state: drop_state_new_live(),
        type_name: type_name,
        scope_depth: f.scope_depth,
    }
    f.entries = append(f.entries, entry)
    f
}

// Move: 移出所有权
func fldf_move(field_level_drop_flag f, path from_path, path to_path, int line, int col) field_level_drop_flag {
    idx := fldf_find(f, from_path)
    if idx < 0 {
        f.errors = append(f.errors, "unknown variable in move")
        return f
    }
    
    from_entry := f.entries[idx]
    type_name := from_entry.type_name
    
    // 检查从路径的状态
    new_state, err := drop_state_after_move(from_entry.state, "move", line, col)
    if len(err) > 0 {
        f.errors = append(f.errors, err)
        return f
    }
    
    // 更新源路径状态
    f.entries[idx].state = new_state
    
    // 声明目标路径为 live（如果不存在）
    to_idx := fldf_find(f, to_path)
    if to_idx < 0 {
        entry := field_level_entry {
            path: to_path,
            state: drop_state_new_live(),
            type_name: type_name,
            scope_depth: f.scope_depth,
        }
        f.entries = append(f.entries, entry)
    } else {
        // 目标已存在，用 live 状态覆盖
        f.entries[to_idx].state = drop_state_new_live()
    }
    
    f
}

// Use: 使用变量（检查状态）
func fldf_use(field_level_drop_flag f, path p) field_level_drop_flag {
    idx := fldf_find(f, p)
    if idx < 0 {
        f.errors = append(f.errors, "unknown variable in use")
        return f
    }
    
    entry := f.entries[idx]
    _, err := drop_state_after_use(entry.state)
    if len(err) > 0 {
        f.errors = append(f.errors, err)
        return f
    }
    
    f
}

// Reassign: 重新赋值（可能覆盖之前的值）
func fldf_reassign(field_level_drop_flag f, path p, string type_name) field_level_drop_flag {
    idx := fldf_find(f, p)
    if idx < 0 {
        // 不存在，声明新的
        return fldf_declare(f, p, type_name)
    }
    
    // 存在，更新为 live
    f.entries[idx].state = drop_state_new_live()
    f.entries[idx].type_name = type_name
    f
}

// ============================================================================
// Scope Management
// ============================================================================

func fldf_enter_scope(field_level_drop_flag f) field_level_drop_flag {
    f.scope_depth = f.scope_depth + 1
    f
}

// Scope Exit: 自动 drop 所有在当前作用域中 live 的值
// 返回: (更新后的 fldf, 需要生成的 drop 调用列表)
func fldf_scope_exit(field_level_drop_flag f) (field_level_drop_flag, path[]) {
    path[] drops
    
    // 反向遍历（LIFO），找到当前作用域的所有 live 变量
    i := len(f.entries) - 1
    for i >= 0 {
        entry := f.entries[i]
        
        // 是否在当前作用域
        if entry.scope_depth != f.scope_depth {
            i = i - 1
            continue
        }
        
        // 是否需要 drop
        if drop_state_needs_drop(entry.state) {
            drops = append(drops, entry.path)
            
            // 更新状态为 dropped
            new_state, _ := drop_state_after_drop(entry.state)
            f.entries[i].state = new_state
        }
        
        i = i - 1
    }
    
    f.scope_depth = f.scope_depth - 1
    f, drops
}

// ============================================================================
// Control Flow (Branching)
// ============================================================================

struct branch_snapshot {
    field_level_entry[] entries
    int branch_id
}

// 在进入条件分支前保存状态
func fldf_save_checkpoint(field_level_drop_flag f) branch_snapshot {
    // 简化版本，只保存 entries 副本
    branch_snapshot {
        entries: f.entries,
        branch_id: -1,
    }
}

// 合并两个条件分支（if-else）
func fldf_merge_branches(field_level_drop_flag f_if, field_level_drop_flag f_else) field_level_drop_flag {
    merged := fldf_new()
    merged.scope_depth = f_if.scope_depth
    
    // 合并所有路径
    // 策略: 对于两个分支都存在的路径，合并它们的状态
    //      对于只在一个分支存在的路径，也包括它（状态为 maybe）
    
    i := 0
    for i < len(f_if.entries) {
        if_entry := f_if.entries[i]
        
        // 在 else 分支中查找相同的路径
        else_idx := -1
        j := 0
        for j < len(f_else.entries) {
            if path_equal(f_else.entries[j].path, if_entry.path) {
                else_idx = j
                break
            }
            j = j + 1
        }
        
        if else_idx >= 0 {
            // 两个分支都有，合并状态
            else_entry := f_else.entries[else_idx]
            merged_state := drop_state_merge(if_entry.state, else_entry.state)
            
            entry := field_level_entry {
                path: if_entry.path,
                state: merged_state,
                type_name: if_entry.type_name,
                scope_depth: if_entry.scope_depth,
            }
            merged.entries = append(merged.entries, entry)
        } else {
            // 只在 if 分支，保持原状态
            merged.entries = append(merged.entries, if_entry)
        }
        
        i = i + 1
    }
    
    // 添加只在 else 分支存在的路径
    i = 0
    for i < len(f_else.entries) {
        else_entry := f_else.entries[i]
        
        // 检查是否已在 merged 中
        found := false
        j := 0
        for j < len(merged.entries) {
            if path_equal(merged.entries[j].path, else_entry.path) {
                found = true
                break
            }
            j = j + 1
        }
        
        if !found {
            merged.entries = append(merged.entries, else_entry)
        }
        
        i = i + 1
    }
    
    merged
}

// ============================================================================
// Error Handling
// ============================================================================

func fldf_add_error(field_level_drop_flag f, string message) field_level_drop_flag {
    f.errors = append(f.errors, message)
    f
}

func fldf_has_errors(field_level_drop_flag f) bool {
    len(f.errors) > 0
}

func fldf_get_errors(field_level_drop_flag f) string[] {
    f.errors
}

// ============================================================================
// Query & Debug
// ============================================================================

func fldf_entry_count(field_level_drop_flag f) int {
    len(f.entries)
}

func fldf_get_entry(field_level_drop_flag f, int idx) field_level_entry {
    if idx < 0 || idx >= len(f.entries) {
        return field_level_entry {}
    }
    f.entries[idx]
}

// 获取所有 live 或 partial 的路径（需要 drop）
func fldf_get_paths_needing_drop(field_level_drop_flag f) path[] {
    path[] results
    i := 0
    for i < len(f.entries) {
        if drop_state_needs_drop(f.entries[i].state) {
            results = append(results, f.entries[i].path)
        }
        i = i + 1
    }
    results
}

// 获取所有 moved 的路径（不能再使用）
func fldf_get_moved_paths(field_level_drop_flag f) path[] {
    path[] results
    i := 0
    for i < len(f.entries) {
        if drop_state_is_moved(f.entries[i].state) {
            results = append(results, f.entries[i].path)
        }
        i = i + 1
    }
    results
}

// ============================================================================
// Backward Compatibility Layer
// ============================================================================

// 为了与旧代码兼容，提供简单的变量级 API
// 这些函数内部使用 field_level_drop_flag，但接口简化

func fldf_declare_var(field_level_drop_flag f, string var_name, string type_name) field_level_drop_flag {
    fldf_declare(f, path_new(var_name), type_name)
}

func fldf_move_var(field_level_drop_flag f, string from_var, string to_var, int line, int col) field_level_drop_flag {
    fldf_move(f, path_new(from_var), path_new(to_var), line, col)
}

func fldf_use_var(field_level_drop_flag f, string var_name) field_level_drop_flag {
    fldf_use(f, path_new(var_name))
}

func fldf_reassign_var(field_level_drop_flag f, string var_name, string type_name) field_level_drop_flag {
    fldf_reassign(f, path_new(var_name), type_name)
}
