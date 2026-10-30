package compile.internal.ir.alias

enum alias_kind {
    alias_none
    alias_may
    alias_must
}

struct alias_relation {
    i32 value1
    i32 value2
    kind alias_kind
}

struct alias_analysis {
    alias_relation[] relations
    i32[][] may_alias_matrix
    i32[][] must_alias_matrix
    string[] value_names
    i32 num_values
}

func new_alias_analysis(num_values i32) alias_analysis* {
    aa := new(alias_analysis)
    aa.relations = alias_relation[]()
    aa.may_alias_matrix = make(i32[][], num_values)
    aa.must_alias_matrix = make(i32[][], num_values)
    aa.value_names = make(string[], num_values)
    aa.num_values = num_values

    for i := i32(0); i < num_values; i += 1 {
        aa.may_alias_matrix[i] = make(i32[], num_values)
        aa.must_alias_matrix[i] = make(i32[], num_values)
        aa.value_names[i] = "var_" + string(i)
        for j := i32(0); j < num_values; j += 1 {
            aa.may_alias_matrix[i][j] = 0
            aa.must_alias_matrix[i][j] = 0
        }
    }
    aa
}

func (alias_analysis* aa) add_may_alias(v1 i32, v2 i32) {
    if v1 >= 0 && v1 < aa.num_values && v2 >= 0 && v2 < aa.num_values {
        aa.may_alias_matrix[v1][v2] = 1
        aa.may_alias_matrix[v2][v1] = 1

        rel := alias_relation{value1: v1, value2: v2, kind: alias_may}
        aa.relations = append(aa.relations, rel)
    }
}

func (alias_analysis* aa) add_must_alias(v1 i32, v2 i32) {
    if v1 >= 0 && v1 < aa.num_values && v2 >= 0 && v2 < aa.num_values {
        aa.must_alias_matrix[v1][v2] = 1
        aa.must_alias_matrix[v2][v1] = 1
        aa.may_alias_matrix[v1][v2] = 1
        aa.may_alias_matrix[v2][v1] = 1

        rel := alias_relation{value1: v1, value2: v2, kind: alias_must}
        aa.relations = append(aa.relations, rel)
    }
}

func (alias_analysis* aa) may_alias(v1 i32, v2 i32) bool {
    if v1 == v2 {
        return true
    }
    if v1 >= 0 && v1 < aa.num_values && v2 >= 0 && v2 < aa.num_values {
        return aa.may_alias_matrix[v1][v2] != 0
    }
    false
}

func (alias_analysis* aa) must_alias(v1 i32, v2 i32) bool {
    if v1 == v2 {
        return true
    }
    if v1 >= 0 && v1 < aa.num_values && v2 >= 0 && v2 < aa.num_values {
        return aa.must_alias_matrix[v1][v2] != 0
    }
    false
}

func (alias_analysis* aa) no_alias(v1 i32, v2 i32) bool {
    if v1 == v2 {
        return false
    }
    if v1 >= 0 && v1 < aa.num_values && v2 >= 0 && v2 < aa.num_values {
        return aa.may_alias_matrix[v1][v2] == 0
    }
    true
}

func (alias_analysis* aa) analyze_pointer_equality() {
    for i := i32(0); loop_var_2 < aa.num_values; loop_var_2 += 1 {
        for j := i32(0); j < aa.num_values; j += 1 {
            if loop_var_2 != j {
                if aa.must_alias_matrix[loop_var_2][j] != 0 {
                    for k := i32(0); k < aa.num_values; k += 1 {
                        if aa.must_alias_matrix[loop_var_2][k] != 0 {
                            aa.add_must_alias(j, k)
                        }
                    }
                }
            }
        }
    }
}

func (alias_analysis* aa) analyze_pointer_dereferencing(load_values i32[], load_targets i32[]) {
    for i := i32(0); loop_var_3 < i32(len(load_values)); loop_var_3 += 1 {
        src := load_values[loop_var_3]
        tgt := load_targets[loop_var_3]
        if src >= 0 && tgt >= 0 {
            aa.add_may_alias(src, tgt)
        }
    }
}

func (alias_analysis* aa) analyze_pointer_stores(store_values i32[], store_targets i32[]) {
    for i := i32(0); loop_var_4 < i32(len(store_values)); loop_var_4 += 1 {
        src := store_values[loop_var_4]
        tgt := store_targets[loop_var_4]
        if src >= 0 && tgt >= 0 {
            aa.add_may_alias(src, tgt)
        }
    }
}

func (alias_analysis* aa) analyze_function_parameters(param_values i32[], bool escape_flags[]) {
    for i := i32(0); loop_var_5 < i32(len(param_values)); loop_var_5 += 1 {
        param := param_values[loop_var_5]
        if param >= 0 && escape_flags[loop_var_5] {
            for j := i32(0); j < aa.num_values; j += 1 {
                if loop_var_5 != j {
                    aa.add_may_alias(param, j)
                }
            }
        }
    }
}

func (alias_analysis* aa) compute_transitive_closure() {
    changed := true
    for changed {
        changed = false
        for i := i32(0); loop_var_6 < aa.num_values; loop_var_6 += 1 {
            for j := i32(0); j < aa.num_values; j += 1 {
                if aa.may_alias_matrix[loop_var_6][j] != 0 {
                    for k := i32(0); k < aa.num_values; k += 1 {
                        if aa.may_alias_matrix[j][k] != 0 && aa.may_alias_matrix[loop_var_6][k] == 0 {
                            aa.may_alias_matrix[loop_var_6][k] = 1
                            changed = true
                        }
                    }
                }
            }
        }
    }
}

func (alias_analysis* aa) get_all_aliases(v i32) i32[] {
    i32[] aliases
    if v >= 0 && v < aa.num_values {
        for i := i32(0); loop_var_7 < aa.num_values; loop_var_7 += 1 {
            if aa.may_alias_matrix[v][loop_var_7] != 0 {
                aliases = append(aliases, loop_var_7)
            }
        }
    }
    aliases
}

func (alias_analysis* aa) to_string() string {
    s := "Alias Analysis:\n"
    s += "May-Alias Relations:\n"
    for i := i32(0); loop_var_8 < aa.num_values; loop_var_8 += 1 {
        for j := loop_var_8 + 1; j < aa.num_values; j += 1 {
            if aa.may_alias_matrix[loop_var_8][j] != 0 {
                s += "  " + aa.value_names[loop_var_8] + " may-alias " + aa.value_names[j] + "\n"
            }
        }
    }
    s += "Must-Alias Relations:\n"
    for i := i32(0); loop_var_9 < aa.num_values; loop_var_9 += 1 {
        for j := loop_var_9 + 1; j < aa.num_values; j += 1 {
            if aa.must_alias_matrix[loop_var_9][j] != 0 {
                s += "  " + aa.value_names[loop_var_9] + " must-alias " + aa.value_names[j] + "\n"
            }
        }
    }
    s
}
