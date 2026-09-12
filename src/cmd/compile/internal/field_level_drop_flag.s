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
    state drop_state
    string type_name
    int scope_depth
}

struct field_level_drop_flag {
    field_level_entry[] entries
    int scope_depth
    string[] errors
}

func fldf_new() field_level_drop_flag {
    field_level_entry[] entries
    string[] errors
    field_level_drop_flag { entries: entries, scope_depth: 0, errors: errors }
}

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

func fldf_move(field_level_drop_flag f, path from_path, path to_path, int line, int col) field_level_drop_flag {
    idx := fldf_find(f, from_path)
    if idx < 0 {
        f.errors = append(f.errors, "unknown variable in move")
        return f
    }

    from_entry := f.entries[idx]
    type_name := from_entry.type_name

    new_state, err := drop_state_after_move(from_entry.state, "move", line, col)
    if len(err) > 0 {
        f.errors = append(f.errors, err)
        return f
    }

    f.entries[idx].state = new_state

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

        f.entries[to_idx].state = drop_state_new_live()
    }

    f
}

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

func fldf_reassign(field_level_drop_flag f, path p, string type_name) field_level_drop_flag {
    idx := fldf_find(f, p)
    if idx < 0 {

        return fldf_declare(f, p, type_name)
    }

    f.entries[idx].state = drop_state_new_live()
    f.entries[idx].type_name = type_name
    f
}

func fldf_enter_scope(field_level_drop_flag f) field_level_drop_flag {
    f.scope_depth = f.scope_depth + 1
    f
}

func fldf_scope_exit(field_level_drop_flag f) (field_level_drop_flag, path[]) {
    path[] drops

    i := len(f.entries) - 1
    for i >= 0 {
        entry := f.entries[i]

        if entry.scope_depth != f.scope_depth {
            i = i - 1
            continue
        }

        if drop_state_needs_drop(entry.state) {
            drops = append(drops, entry.path)

            new_state, _ := drop_state_after_drop(entry.state)
            f.entries[i].state = new_state
        }

        i = i - 1
    }

    f.scope_depth = f.scope_depth - 1
    f, drops
}

struct branch_snapshot {
    field_level_entry[] entries
    int branch_id
}

func fldf_save_checkpoint(field_level_drop_flag f) branch_snapshot {

    branch_snapshot {
        entries: f.entries,
        branch_id: -1,
    }
}

func fldf_merge_branches(field_level_drop_flag f_if, field_level_drop_flag f_else) field_level_drop_flag {
    merged := fldf_new()
    merged.scope_depth = f_if.scope_depth

    i := 0
    for i < len(f_if.entries) {
        if_entry := f_if.entries[i]

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

            merged.entries = append(merged.entries, if_entry)
        }

        i = i + 1
    }

    i = 0
    for i < len(f_else.entries) {
        else_entry := f_else.entries[i]

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

func fldf_entry_count(field_level_drop_flag f) int {
    len(f.entries)
}

func fldf_get_entry(field_level_drop_flag f, int idx) field_level_entry {
    if idx < 0 || idx >= len(f.entries) {
        return field_level_entry {}
    }
    f.entries[idx]
}

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