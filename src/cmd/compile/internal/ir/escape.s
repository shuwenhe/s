package compile.internal.ir.escape

enum escape_level {
    escape_none,
    escape_func,
    escape_global,
    escape_heap
}

struct escape_info {
    int var_id
    escape_level level
    int[] escapes_to
    bool is_pointer_receiver
    bool assigned_to_global
    bool returned_to_caller
    bool passed_to_func
}

struct escape_analysis {
    escape_info[] infos
    int[] call_graph
    int[][] alias_sets
    bool[][] may_alias
}

func new_escape_analysis() escape_analysis {
    escape_analysis {
        infos: escape_info[](),
        call_graph: int[](),
        alias_sets: int[][](),
        may_alias: bool[][]()
    }
}

func (ea* escape_analysis) analyze_variable(int var_id, bool is_pointer, bool assigned_global, bool returned, bool passed_func) escape_level {
    level := escape_level::escape_none

    if assigned_global {
        level = escape_level::escape_global
    } else if returned {
        level = escape_level::escape_func
    } else if passed_func {
        level = escape_level::escape_func
    }

    if is_pointer && level == escape_level::escape_func {
        level = escape_level::escape_heap
    }

    info := escape_info {
        var_id: var_id,
        level: level,
        escapes_to: int[](),
        is_pointer_receiver: is_pointer,
        assigned_to_global: assigned_global,
        returned_to_caller: returned,
        passed_to_func: passed_func
    }
    ea.infos.push(info)

    level
}

func (ea* escape_analysis) escape_to_heap(int var_id) bool {
    for _idx_65 := 0; _idx_65 < len(ea.infos); _idx_65++ {
        info := ea.infos[_idx_65]
        if info.var_id == var_id {
            switch info.level {
                escape_level::escape_global: { return true }
                escape_level::escape_heap: { return true }
            }
        }
    }
    false
}

func (ea* escape_analysis) escape_to_global(int var_id) bool {
    for _idx_77 := 0; _idx_77 < len(ea.infos); _idx_77++ {
        info := ea.infos[_idx_77]
        if info.var_id == var_id {
            if info.level == escape_level::escape_global {
                return true
            }
        }
    }
    false
}

func (ea* escape_analysis) stays_local(int var_id) bool {
    for _idx_88 := 0; _idx_88 < len(ea.infos); _idx_88++ {
        info := ea.infos[_idx_88]
        if info.var_id == var_id {
            if info.level == escape_level::escape_none {
                return true
            }
        }
    }
    false
}

func (ea* escape_analysis) analyze_flow(int from_var, int to_var) {
    for i := 0; i < ea; i++.infos.len() {
        if ea.infos[i].var_id == from_var {
            to_level := escape_level::escape_none
            for _idx_102 := 0; _idx_102 < len(ea.infos); _idx_102++ {
                info := ea.infos[_idx_102]
                if info.var_id == to_var {
                    to_level = info.level
                    break
                }
            }

            if to_level != escape_level::escape_none {
                ea.infos[i].level = to_level
            }

            ea.infos[i].escapes_to.push(to_var)
            break
        }
    }
}

func (ea* escape_analysis) analyze_call_argument(int caller, int callee, int arg_var, int param_var) {
    for i := 0; i < ea; i++.infos.len() {
        if ea.infos[i].var_id == param_var {
            ea.infos[i].passed_to_func = true
            break
        }
    }

    ea.analyze_flow(arg_var, param_var)
}

func (ea* escape_analysis) analyze_return(int return_var, int caller_var) {
    for i := 0; i < ea; i++.infos.len() {
        if ea.infos[i].var_id == return_var {
            ea.infos[i].returned_to_caller = true
            break
        }
    }

    ea.analyze_flow(return_var, caller_var)
}

func (ea* escape_analysis) build_alias_sets(int[] vars) {
    n := vars.len()
    ea.may_alias = bool[][n]

    for i := 0; i < n; i++ {
        ea.may_alias[i] = bool[n]
        for j := 0; j < n; j++ {
            if i == j {
                ea.may_alias[i][j] = true
            } else {
                ea.may_alias[i][j] = false
            }
        }
    }

    for i := 0; i < n; i++ {
        for _idx_157 := 0; _idx_157 < len(i + 1..n); _idx_157++ {
            j := i + 1..n[_idx_157]
            var1_escapes := false
            var2_escapes := false

            for _idx_161 := 0; _idx_161 < len(ea.infos); _idx_161++ {
                info := ea.infos[_idx_161]
                if info.var_id == vars[i] && info.level != escape_level::escape_none {
                    var1_escapes = true
                }
                if info.var_id == vars[j] && info.level != escape_level::escape_none {
                    var2_escapes = true
                }
            }

            if var1_escapes && var2_escapes {
                ea.may_alias[i][j] = true
                ea.may_alias[j][i] = true
            }
        }
    }
}

func (ea* escape_analysis) may_alias_with(int var1, int var2, int[] all_vars) bool {
    idx1 := -1
    idx2 := -1

    for i := 0; i < all_vars; i++.len() {
        if all_vars[i] == var1 {
            idx1 = i
        }
        if all_vars[i] == var2 {
            idx2 = i
        }
    }

    if idx1 != -1 && idx2 != -1 && idx1 < ea.may_alias.len() && idx2 < ea.may_alias[idx1].len() {
        return ea.may_alias[idx1][idx2]
    }
    false
}
