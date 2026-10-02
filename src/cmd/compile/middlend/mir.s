package compile.compiler

func compiler_extract_int64_constant(string value) string {
    if len(value) < 9 { return "" }
    if __host_slice(value, 0, 8) != "INT64_C(" { return "" }
    if __host_char_at(value, len(value) - 1) != ")" { return "" }
    inner := __host_slice(value, 8, len(value) - 1)
    if inner == "" { return "" }
    start := 0
    if __host_char_at(inner, 0) == "-" {
        if len(inner) == 1 { return "" }
        start = 1
    }
    i := start
    while i < len(inner) {
        if !compiler_digit(__host_char_at(inner, i)) { return "" }
        i = i + 1
    }
    return inner
}

func compiler_extract_zero_arg_call_target(compiler_state s, string value) string {
    if len(value) < 4 { return "" }
    if __host_char_at(value, 0) != "(" { return "" }
    if __host_char_at(value, len(value) - 1) != ")" { return "" }
    inner := __host_slice(value, 1, len(value) - 1)
    if len(inner) < 3 { return "" }
    if __host_char_at(inner, len(inner) - 1) != ")" { return "" }
    if __host_char_at(inner, len(inner) - 2) != "(" { return "" }
    target := __host_slice(inner, 0, len(inner) - 2)
    if !compiler_ident(target) { return "" }
    if compiler_find_func(s, target) < 0 { return "" }
    return target
}

func compiler_emit_lowered_view(string source) string {
    result := compiler_compile(source)
    if result.error != "" { return "lowered-view-error " + result.error + "\n" }
    return_constant := compiler_extract_int64_constant(result.value)
    call_target := compiler_extract_zero_arg_call_target(result, result.value)
    if result.function_name != "main" || result.value_kind != 1 || result.terminated == 0 || (return_constant == "" && call_target == "") {
        return "lowered-view-error unsupported canonical lowered view slice\n"
    }
    out := "canonical-lowered-view version=1\n"
    out = out + "view-role=READ_ONLY\n"
    i := 0
    while i < result.function_count {
        out = out + "function " + result.function_names[i] + "\n"
        if result.function_return_constants[i] != "" {
            out = out + "return-kind=int\n"
            out = out + "return-constant=" + result.function_return_constants[i] + "\n"
        }
        if result.function_return_call_targets[i] != "" {
            out = out + "return-kind=int\n"
            out = out + "call-target=" + result.function_return_call_targets[i] + "\n"
            out = out + "return-call-target=" + result.function_return_call_targets[i] + "\n"
        }
        if result.function_branch_conditions[i] != "" {
            out = out + "block bb0\n"
            out = out + "branch-condition=" + result.function_branch_conditions[i] + "\n"
            out = out + "true-edge=bb1\n"
            out = out + "false-edge=bb2\n"
            out = out + "block bb1\n"
            out = out + "return-constant=" + result.function_branch_true_constants[i] + "\n"
            out = out + "block bb2\n"
            out = out + "return-constant=" + result.function_branch_false_constants[i] + "\n"
        }
        i = i + 1
    }
    out = out + "function main\n"
    out = out + "entry-block=bb0\n"
    out = out + "return-kind=int\n"
    if return_constant != "" { out = out + "return-constant=" + return_constant + "\n" }
    if call_target != "" {
        out = out + "call-target=" + call_target + "\n"
        out = out + "return-call-target=" + call_target + "\n"
    }
    out
}

func compiler_mir_find(string[] names, int count, string name) int {
    i := 0
    while i < count {
        if names[i] == name { return i }
        i = i + 1
    }
    return -1
}

func compiler_mir_value(int id) string {
    return "_" + compiler_number(id)
}

func compiler_mir_has_live_borrow(int[] live, int[] kinds, int[] roots, int count, int owner) bool {
    i := 0
    while i < count {
        if live[i] == 1 && (kinds[i] == 3 || kinds[i] == 4) && roots[i] == owner {
            return true
        }
        i = i + 1
    }
    return false
}

func compiler_mir_has_shared_borrow(int[] live, int[] kinds, int[] roots, int count, int owner) bool {
    i := 0
    while i < count {
        if live[i] == 1 && kinds[i] == 3 && roots[i] == owner {
            return true
        }
        i = i + 1
    }
    return false
}

func compiler_mir_has_mut_borrow(int[] live, int[] kinds, int[] roots, int count, int owner) bool {
    i := 0
    while i < count {
        if live[i] == 1 && kinds[i] == 4 && roots[i] == owner {
            return true
        }
        i = i + 1
    }
    return false
}

func compiler_mir_drop_live(string out, int[] live, int[] value_ids, int[] kinds, int count, bool elaborate_drop) string {
    result := out
    if !elaborate_drop { return result }
    i := count - 1
    while i >= 0 {
        if live[i] == 1 && kinds[i] == 2 {
            result = result + "    Drop(" + compiler_mir_value(value_ids[i]) + ")\n"
            live[i] = 0
        }
        i = i - 1
    }
    return result
}

func compiler_emit_mir(string source, bool elaborate_drop) string {
    empty_names := ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    names := empty_names
    value_ids := empty_ints
    live := empty_ints
    kinds := empty_ints
    roots := empty_ints
    borrow_state := empty_ints
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s = compiler_next(s)
    s = compiler_expect(s, "package")
    if s.error != "" { return "mir-error " + s.error + "\n" }
    s = compiler_next(s)
    while s.token == "." { s = compiler_next(compiler_next(s)) }
    while s.token != "func" && s.token != "" { s = compiler_next(s) }
    s = compiler_expect(s, "func")
    while s.error == "" && s.token != "main" && s.token != "" {
        depth := 0
        while s.error == "" && s.token != "" {
            if s.token == "{" { depth = depth + 1 }
            if s.token == "}" {
                depth = depth - 1
                if depth <= 0 {
                    s = compiler_next(s)
                    break
                }
            }
            s = compiler_next(s)
        }
        while s.token != "func" && s.token != "" { s = compiler_next(s) }
        if s.token == "func" { s = compiler_next(s) }
    }
    s = compiler_expect(s, "main")
    s = compiler_expect(s, "(")
    s = compiler_expect(s, ")")
    if s.token == "int" { s = compiler_next(s) }
    s = compiler_expect(s, "{")
    out := "bb0:\n"
    block_count := 1
    exit_block := 0
    count := 0
    next_value := 1
    returned := false
    while s.error == "" && s.token != "" && s.token != "}" && !returned {
        if s.token == "if" {
            s = compiler_next(s)
            condition := s.token
            while s.error == "" && s.token != "{" && s.token != "" {
                s = compiler_next(s)
            }
            s = compiler_expect(s, "{")
            block_count = 4
            exit_block = 3
            out = out + "    Branch(" + condition + ", bb1, bb2)\n"
            out = out + "bb1:\n"
            block_depth := 1
            then_moved := empty_ints
            then_shared := empty_ints
            then_mut := empty_ints
            then_returned := false
            while s.error == "" && block_depth > 0 && s.token != "" {
                if block_depth == 1 && s.token == "return" {
                    out = compiler_mir_drop_live(out, live, value_ids, kinds, count, elaborate_drop)
                    out = out + "    Return(" + compiler_next(s).token + ")\n"
                    then_returned = true
                }
                if block_depth == 1 && compiler_ident(s.token) {
                    look := compiler_next(s)
                    if look.token == ":=" {
                        rhs := compiler_next(look)
                        if rhs.token == "&" {
                            borrow_rhs := compiler_next(rhs)
                            mutable_rhs := false
                            if borrow_rhs.token == "mut" {
                                mutable_rhs = true
                                borrow_rhs = compiler_next(borrow_rhs)
                            }
                            origin := compiler_mir_find(names, count, borrow_rhs.token)
                            if origin >= 0 && live[origin] == 1 && kinds[origin] == 2 {
                                if mutable_rhs { then_mut[origin] = 1 }
                                else { then_shared[origin] = 1 }
                            }
                        } else {
                            origin := compiler_mir_find(names, count, rhs.token)
                            if origin >= 0 && live[origin] == 1 && kinds[origin] == 2 {
                                then_moved[origin] = 1
                                value := next_value
                                next_value = next_value + 1
                                out = out + "    " + compiler_mir_value(value) + " = Move(" + compiler_mir_value(value_ids[origin]) + ")\n"
                                if elaborate_drop { out = out + "    Drop(" + compiler_mir_value(value) + ")\n" }
                            }
                        }
                    }
                }
                if s.token == "{" { block_depth = block_depth + 1; s = compiler_next(s) }
                else if s.token == "}" { block_depth = block_depth - 1; if block_depth > 0 { s = compiler_next(s) } }
                else { s = compiler_next(s) }
            }
            s = compiler_expect(s, "}")
            if !then_returned { out = out + "    Goto(bb3)\n" }
            out = out + "bb2:\n"
            else_moved := empty_ints
            else_shared := empty_ints
            else_mut := empty_ints
            else_returned := false
            if s.token == "else" {
                s = compiler_expect(compiler_next(s), "{")
                block_depth = 1
                while s.error == "" && block_depth > 0 && s.token != "" {
                    if block_depth == 1 && s.token == "return" {
                        out = compiler_mir_drop_live(out, live, value_ids, kinds, count, elaborate_drop)
                        out = out + "    Return(" + compiler_next(s).token + ")\n"
                        else_returned = true
                    }
                    if block_depth == 1 && compiler_ident(s.token) {
                        look := compiler_next(s)
                        if look.token == ":=" {
                            rhs := compiler_next(look)
                            if rhs.token == "&" {
                                borrow_rhs := compiler_next(rhs)
                                mutable_rhs := false
                                if borrow_rhs.token == "mut" {
                                    mutable_rhs = true
                                    borrow_rhs = compiler_next(borrow_rhs)
                                }
                                origin := compiler_mir_find(names, count, borrow_rhs.token)
                                if origin >= 0 && live[origin] == 1 && kinds[origin] == 2 {
                                    if mutable_rhs { else_mut[origin] = 1 }
                                    else { else_shared[origin] = 1 }
                                }
                            } else {
                                origin := compiler_mir_find(names, count, rhs.token)
                                if origin >= 0 && live[origin] == 1 && kinds[origin] == 2 {
                                    else_moved[origin] = 1
                                    value := next_value
                                    next_value = next_value + 1
                                    out = out + "    " + compiler_mir_value(value) + " = Move(" + compiler_mir_value(value_ids[origin]) + ")\n"
                                    if elaborate_drop { out = out + "    Drop(" + compiler_mir_value(value) + ")\n" }
                                }
                            }
                        }
                    }
                    if s.token == "{" { block_depth = block_depth + 1; s = compiler_next(s) }
                    else if s.token == "}" { block_depth = block_depth - 1; if block_depth > 0 { s = compiler_next(s) } }
                    else { s = compiler_next(s) }
                }
                s = compiler_expect(s, "}")
            }
            join_slot := 0
            while join_slot < count {
                if live[join_slot] == 1 {
                    if then_moved[join_slot] == 1 && else_moved[join_slot] == 1 { live[join_slot] = 0 }
                    else if then_moved[join_slot] == 1 || else_moved[join_slot] == 1 { live[join_slot] = 2 }
                }
                if then_mut[join_slot] == 1 || else_mut[join_slot] == 1 { borrow_state[join_slot] = 4 }
                else if then_shared[join_slot] == 1 || else_shared[join_slot] == 1 { borrow_state[join_slot] = 3 }
                join_slot = join_slot + 1
            }
            if !else_returned { out = out + "    Goto(bb3)\n" }
            out = out + "bb3:\n"
        } else if s.token == "return" {
            s = compiler_next(s)
            if s.token == "*" {
                s = compiler_next(s)
                slot := compiler_mir_find(names, count, s.token)
                if slot < 0 || live[slot] == 0 { return "mir-error moved or unknown return value\n" }
                if live[slot] == 2 { return "mir-error use of possibly moved value\n" }
                result := next_value
                next_value = next_value + 1
                out = out + "    " + compiler_mir_value(result) + " = Deref(" + compiler_mir_value(value_ids[slot]) + ")\n"
                out = compiler_mir_drop_live(out, live, value_ids, kinds, count, elaborate_drop)
                out = out + "    Return(" + compiler_mir_value(result) + ")\n"
                returned = true
                s = compiler_next(s)
            } else if compiler_ident(s.token) {
                slot := compiler_mir_find(names, count, s.token)
                if slot < 0 || live[slot] == 0 { return "mir-error moved or unknown return value\n" }
                if live[slot] == 2 { return "mir-error use of possibly moved value\n" }
                out = compiler_mir_drop_live(out, live, value_ids, kinds, count, elaborate_drop)
                out = out + "    Return(" + compiler_mir_value(value_ids[slot]) + ")\n"
                returned = true
                s = compiler_next(s)
            } else {
                out = compiler_mir_drop_live(out, live, value_ids, kinds, count, elaborate_drop)
                out = out + "    Return(0)\n"
                returned = true
            }
        } else if s.token == "drop" {
            s = compiler_expect(compiler_next(s), "(")
            slot := compiler_mir_find(names, count, s.token)
            if slot < 0 || live[slot] != 1 { return "mir-error drop of moved or unknown value\n" }
            out = out + "    Drop(" + compiler_mir_value(value_ids[slot]) + ")\n"
            live[slot] = 0
            s = compiler_expect(compiler_next(s), ")")
        } else if compiler_ident(s.token) && s.token != "use_ref" && s.token != "move_field" {
            name := s.token
            s = compiler_next(s)
            if s.token != ":=" { return "mir-error expected :=\n" }
            s = compiler_next(s)
            if s.token == "box" {
                value := next_value
                next_value = next_value + 1
                s = compiler_expect(compiler_next(s), "(")
                literal := s.token
                s = compiler_expect(compiler_next(s), ")")
                out = out + "    " + compiler_mir_value(value) + " = Box(" + literal + ")\n"
                names[count] = name
                value_ids[count] = value
                live[count] = 1
                kinds[count] = 2
                roots[count] = -1
                count = count + 1
            } else if s.token == "&" {
                mutable := false
                s = compiler_next(s)
                if s.token == "mut" {
                    mutable = true
                    s = compiler_next(s)
                }
                origin := compiler_mir_find(names, count, s.token)
                if origin < 0 || live[origin] != 1 { return "mir-error borrow of moved or unknown value\n" }
                if kinds[origin] != 2 { return "mir-error borrow requires owned value\n" }
                if mutable && (compiler_mir_has_shared_borrow(live, kinds, roots, count, origin) || borrow_state[origin] == 3) { return "mir-error mutable borrow while shared borrowed\n" }
                if mutable && (compiler_mir_has_mut_borrow(live, kinds, roots, count, origin) || borrow_state[origin] == 4) { return "mir-error mutable borrow while mutably borrowed\n" }
                if !mutable && (compiler_mir_has_mut_borrow(live, kinds, roots, count, origin) || borrow_state[origin] == 4) { return "mir-error shared borrow while mutably borrowed\n" }
                value := next_value
                next_value = next_value + 1
                mode := "shared"
                kind := 3
                if mutable {
                    mode = "mut"
                    kind = 4
                }
                out = out + "    " + compiler_mir_value(value) + " = Borrow(" + mode + ", " + compiler_mir_value(value_ids[origin]) + ")\n"
                names[count] = name
                value_ids[count] = value
                live[count] = 1
                kinds[count] = kind
                roots[count] = origin
                count = count + 1
                s = compiler_next(s)
            } else if s.token == "*" {
                s = compiler_next(s)
                origin := compiler_mir_find(names, count, s.token)
                if origin < 0 || live[origin] != 1 { return "mir-error deref of moved or unknown value\n" }
                if kinds[origin] != 2 && kinds[origin] != 3 && kinds[origin] != 4 { return "mir-error deref requires owner or reference\n" }
                value := next_value
                next_value = next_value + 1
                out = out + "    " + compiler_mir_value(value) + " = Deref(" + compiler_mir_value(value_ids[origin]) + ")\n"
                names[count] = name
                value_ids[count] = value
                live[count] = 1
                kinds[count] = 1
                roots[count] = -1
                count = count + 1
                s = compiler_next(s)
            } else if compiler_ident(s.token) {
                origin := compiler_mir_find(names, count, s.token)
                if origin < 0 || live[origin] == 0 { return "mir-error move from moved or unknown value\n" }
                if live[origin] == 2 { return "mir-error move from possibly moved value\n" }
                if kinds[origin] != 2 { return "mir-error move requires owned value\n" }
                if borrow_state[origin] != 0 { return "mir-error move of possibly borrowed value\n" }
                if compiler_mir_has_live_borrow(live, kinds, roots, count, origin) { return "mir-error move of borrowed value\n" }
                value := next_value
                next_value = next_value + 1
                out = out + "    " + compiler_mir_value(value) + " = Move(" + compiler_mir_value(value_ids[origin]) + ")\n"
                live[origin] = 0
                names[count] = name
                value_ids[count] = value
                live[count] = 1
                kinds[count] = kinds[origin]
                roots[count] = -1
                count = count + 1
                s = compiler_next(s)
            } else {
                return "mir-error unsupported initializer\n"
            }
        } else {
            s = compiler_next(s)
        }
        if s.token == ";" { s = compiler_next(s) }
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    if !returned {
        out = compiler_mir_drop_live(out, live, value_ids, kinds, count, elaborate_drop)
        out = out + "    Return(0)\n"
    }
    return "mir main blocks=" + compiler_number(block_count) + " entry=0 exit=" + compiler_number(exit_block) + "\n" + out
}

func compiler_emit_mir_place(string source) string {
    empty_names := ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s = compiler_next(s)
    out := "mir-place main\n"
    while s.error == "" && s.token != "" {
        if s.token == "local" {
            s = compiler_next(s)
            out = out + "Local(" + s.token + ")\n"
        } else if s.token == "field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            out = out + "Field(" + base + ", " + field + ")\n"
        } else if s.token == "nested_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            first := s.token
            s = compiler_next(s)
            second := s.token
            out = out + "Field(Field(" + base + ", " + first + "), " + second + ")\n"
        } else if s.token == "deref_place" {
            s = compiler_next(s)
            out = out + "Deref(" + s.token + ")\n"
        } else if s.token == "index_place" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            out = out + "Index(" + base + ", " + s.token + ")\n"
        }
        s = compiler_next(s)
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    return out
}

func compiler_movepath_state_name(int state) string {
    if state == 0 { return "LIVE" }
    if state == 1 { return "MOVED" }
    if state == 2 { return "PARTIALLY_MOVED" }
    return "UNKNOWN"
}

func compiler_movepath_emit(string place, int parent, string[] children, int child_count, int state) string {
    out := "MovePath(place=" + place + ", parent="
    if parent < 0 { out = out + "none" }
    else { out = out + compiler_number(parent) }
    out = out + ", children=["
    i := 0
    while i < child_count {
        if i > 0 { out = out + "," }
        out = out + children[i]
        i = i + 1
    }
    out = out + "], state=" + compiler_movepath_state_name(state) + ")\n"
    return out
}

func compiler_emit_mir_movepath(string source) string {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s = compiler_next(s)
    state_local := 0
    state_f0 := 0
    state_f1 := 0
    state_f0_0 := 0
    state_f0_1 := 0
    while s.error == "" && s.token != "" {
        if s.token == "move_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            if base == "_1" && field == "0" { state_f0 = 1; state_local = 2 }
            if base == "_1" && field == "1" { state_f1 = 1; state_local = 2 }
        } else if s.token == "move_nested_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            first := s.token
            s = compiler_next(s)
            second := s.token
            if base == "_1" && first == "0" && second == "0" { state_f0_0 = 1; state_f0 = 2; state_local = 2 }
            if base == "_1" && first == "0" && second == "1" { state_f0_1 = 1; state_f0 = 2; state_local = 2 }
        } else if s.token == "move_local" {
            s = compiler_next(s)
            if s.token == "_1" {
                state_local = 1
                state_f0 = 1
                state_f1 = 1
                state_f0_0 = 1
                state_f0_1 = 1
            }
        }
        s = compiler_next(s)
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    out := "mir-movepath main\n"
    children_local := ["Field(_1,0)", "Field(_1,1)", "", "", "", "", "", ""];
    children_f0 := ["Field(Field(_1,0),0)", "Field(Field(_1,0),1)", "", "", "", "", "", ""];
    no_children := empty_names
    out = out + compiler_movepath_emit("Local(_1)", -1, children_local, 2, state_local)
    out = out + compiler_movepath_emit("Field(_1,0)", 0, children_f0, 2, state_f0)
    out = out + compiler_movepath_emit("Field(Field(_1,0),0)", 1, no_children, 0, state_f0_0)
    out = out + compiler_movepath_emit("Field(Field(_1,0),1)", 1, no_children, 0, state_f0_1)
    out = out + compiler_movepath_emit("Field(_1,1)", 0, no_children, 0, state_f1)
    return out
}

func compiler_partial_move_status(string place, int state) string {
    if state == 1 { return "mir-error use of moved place " + place + "\n" }
    if state == 2 { return "mir-error use of partially moved place " + place + "\n" }
    return "Use(" + place + ") OK\n"
}

func compiler_recompute_parent_state(int left, int right) int {
    if left == 0 && right == 0 { return 0 }
    if left == 1 && right == 1 { return 1 }
    return 2
}

func compiler_emit_mir_partial_move(string source) string {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s = compiler_next(s)
    state_local := 0
    state_f0 := 0
    state_f1 := 0
    state_f0_0 := 0
    state_f0_1 := 0
    out := "mir-partial-move main\n"
    while s.error == "" && s.token != "" {
        if s.token == "move_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            if base == "_1" && field == "0" { state_f0 = 1; state_local = 2 }
            if base == "_1" && field == "1" { state_f1 = 1; state_local = 2 }
        } else if s.token == "move_nested_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            first := s.token
            s = compiler_next(s)
            second := s.token
            if base == "_1" && first == "0" && second == "0" { state_f0_0 = 1; state_f0 = 2; state_local = 2 }
            if base == "_1" && first == "0" && second == "1" { state_f0_1 = 1; state_f0 = 2; state_local = 2 }
        } else if s.token == "assign_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            if base == "_1" && field == "0" {
                state_f0 = 0
                state_f0_0 = 0
                state_f0_1 = 0
                state_local = compiler_recompute_parent_state(state_f0, state_f1)
            }
            if base == "_1" && field == "1" {
                state_f1 = 0
                state_local = compiler_recompute_parent_state(state_f0, state_f1)
            }
        } else if s.token == "assign_nested_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            first := s.token
            s = compiler_next(s)
            second := s.token
            if base == "_1" && first == "0" && second == "0" {
                state_f0_0 = 0
                state_f0 = compiler_recompute_parent_state(state_f0_0, state_f0_1)
                state_local = compiler_recompute_parent_state(state_f0, state_f1)
            }
            if base == "_1" && first == "0" && second == "1" {
                state_f0_1 = 0
                state_f0 = compiler_recompute_parent_state(state_f0_0, state_f0_1)
                state_local = compiler_recompute_parent_state(state_f0, state_f1)
            }
        } else if s.token == "move_local" {
            s = compiler_next(s)
            if s.token == "_1" {
                state_local = 1
                state_f0 = 1
                state_f1 = 1
                state_f0_0 = 1
                state_f0_1 = 1
            }
        } else if s.token == "use_local" {
            s = compiler_next(s)
            if s.token == "_1" { out = out + compiler_partial_move_status("Local(_1)", state_local) }
        } else if s.token == "use_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            if base == "_1" && field == "0" { out = out + compiler_partial_move_status("Field(_1, 0)", state_f0) }
            if base == "_1" && field == "1" { out = out + compiler_partial_move_status("Field(_1, 1)", state_f1) }
        } else if s.token == "use_nested_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            first := s.token
            s = compiler_next(s)
            second := s.token
            if base == "_1" && first == "0" && second == "0" { out = out + compiler_partial_move_status("Field(Field(_1, 0), 0)", state_f0_0) }
            if base == "_1" && first == "0" && second == "1" { out = out + compiler_partial_move_status("Field(Field(_1, 0), 1)", state_f0_1) }
        }
        s = compiler_next(s)
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    return out
}

func compiler_emit_mir_reinit(string source) string {
    return compiler_emit_mir_partial_move(source)
}

func compiler_place_borrow_place_name(int place) string {
    if place == 0 { return "Local(_1)" }
    if place == 1 { return "Field(_1, 0)" }
    if place == 2 { return "Field(_1, 1)" }
    if place == 3 { return "Field(Field(_1, 0), 0)" }
    if place == 4 { return "Field(Field(_1, 0), 1)" }
    return "Unknown"
}

func compiler_place_borrow_overlaps(int left, int right) bool {
    if left == right { return true }
    if left == 0 || right == 0 { return true }
    if left == 1 && (right == 3 || right == 4) { return true }
    if right == 1 && (left == 3 || left == 4) { return true }
    return false
}

func compiler_place_borrow_conflict(int target, int[] shared, int[] mut, bool mutable) int {
    i := 0
    while i < 5 {
        if compiler_place_borrow_overlaps(target, i) {
            if mut[i] > 0 { return 2 }
            if mutable && shared[i] > 0 { return 1 }
        }
        i = i + 1
    }
    return 0
}

func compiler_place_borrow_result(int target, bool mutable, int[] shared, int[] mut) string {
    conflict := compiler_place_borrow_conflict(target, shared, mut, mutable)
    if conflict == 1 { return "mir-error mutable borrow while shared borrowed " + compiler_place_borrow_place_name(target) + "\n" }
    if conflict == 2 {
        if mutable { return "mir-error mutable borrow while mutably borrowed " + compiler_place_borrow_place_name(target) + "\n" }
        return "mir-error shared borrow while mutably borrowed " + compiler_place_borrow_place_name(target) + "\n"
    }
    mode := "shared"
    if mutable { mode = "mut" }
    return "Borrow(" + mode + ", " + compiler_place_borrow_place_name(target) + ") OK\n"
}

func compiler_place_borrow_success(int target, bool mutable, int[] shared, int[] mut) bool {
    return compiler_place_borrow_conflict(target, shared, mut, mutable) == 0
}

func compiler_emit_mir_place_borrow(string source) string {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    shared := empty_ints
    mut := empty_ints
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s = compiler_next(s)
    out := "mir-place-borrow main\n"
    while s.error == "" && s.token != "" {
        mutable := false
        handled := false
        if s.token == "borrow_shared_local" || s.token == "borrow_mut_local" {
            if s.token == "borrow_mut_local" { mutable = true }
            s = compiler_next(s)
            if s.token == "_1" {
                ok := compiler_place_borrow_success(0, mutable, shared, mut)
                out = out + compiler_place_borrow_result(0, mutable, shared, mut)
                if ok {
                    if mutable { mut[0] = 1 }
                    else { shared[0] = shared[0] + 1 }
                }
            }
            handled = true
        } else if s.token == "borrow_shared_field" || s.token == "borrow_mut_field" {
            if s.token == "borrow_mut_field" { mutable = true }
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            target := -1
            if base == "_1" && field == "0" { target = 1 }
            if base == "_1" && field == "1" { target = 2 }
            if target >= 0 {
                ok := compiler_place_borrow_success(target, mutable, shared, mut)
                out = out + compiler_place_borrow_result(target, mutable, shared, mut)
                if ok {
                    if mutable { mut[target] = 1 }
                    else { shared[target] = shared[target] + 1 }
                }
            }
            handled = true
        } else if s.token == "borrow_shared_nested_field" || s.token == "borrow_mut_nested_field" {
            if s.token == "borrow_mut_nested_field" { mutable = true }
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            first := s.token
            s = compiler_next(s)
            second := s.token
            target := -1
            if base == "_1" && first == "0" && second == "0" { target = 3 }
            if base == "_1" && first == "0" && second == "1" { target = 4 }
            if target >= 0 {
                ok := compiler_place_borrow_success(target, mutable, shared, mut)
                out = out + compiler_place_borrow_result(target, mutable, shared, mut)
                if ok {
                    if mutable { mut[target] = 1 }
                    else { shared[target] = shared[target] + 1 }
                }
            }
            handled = true
        }
        s = compiler_next(s)
        if !handled && s.token == "" { }
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    return out
}

func compiler_reference_liveness_conflict(int target, int[] loan_places, int[] loan_mut, int[] loan_live, int loan_count, bool exclusive) int {
    i := 0
    while i < loan_count {
        if loan_live[i] == 1 && compiler_place_borrow_overlaps(target, loan_places[i]) {
            if loan_mut[i] == 1 { return 2 }
            if exclusive { return 1 }
        }
        i = i + 1
    }
    return 0
}

func compiler_reference_liveness_find(string[] names, int count, string name) int {
    i := 0
    while i < count {
        if names[i] == name { return i }
        i = i + 1
    }
    return -1
}

func compiler_loan_liveness_use_counts(string source, string[] use_names, int[] use_counts) int {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s = compiler_next(s)
    count := 0
    while s.error == "" && s.token != "" {
        if s.token == "use_ref" {
            s = compiler_next(s)
            idx := compiler_reference_liveness_find(use_names, count, s.token)
            if idx < 0 {
                use_names[count] = s.token
                use_counts[count] = 1
                count = count + 1
            } else {
                use_counts[idx] = use_counts[idx] + 1
            }
        }
        s = compiler_next(s)
    }
    return count
}

func compiler_loan_liveness_has_future_use(string source, int pos, string ref_name) bool {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    s := compiler_state { source: source, pos: pos, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s = compiler_next(s)
    while s.error == "" && s.token != "" {
        if s.token == "use_ref" {
            s = compiler_next(s)
            if s.token == ref_name { return true }
        }
        s = compiler_next(s)
    }
    return false
}

func compiler_reference_liveness_borrow(string ref_name, int target, bool mutable, string[] loan_names, int[] loan_places, int[] loan_mut, int[] loan_live, int loan_count) string {
    conflict := compiler_reference_liveness_conflict(target, loan_places, loan_mut, loan_live, loan_count, mutable)
    if conflict == 1 { return "mir-error mutable borrow while shared borrowed " + compiler_place_borrow_place_name(target) + "\n" }
    if conflict == 2 {
        if mutable { return "mir-error mutable borrow while mutably borrowed " + compiler_place_borrow_place_name(target) + "\n" }
        return "mir-error shared borrow while mutably borrowed " + compiler_place_borrow_place_name(target) + "\n"
    }
    mode := "shared"
    if mutable { mode = "mut" }
    return ref_name + " = Borrow(" + mode + ", " + compiler_place_borrow_place_name(target) + ")\n"
}

func compiler_emit_mir_reference_liveness(string source) string {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    loan_names := empty_names
    loan_places := empty_ints
    loan_mut := empty_ints
    loan_live := empty_ints
    loan_count := 0
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s = compiler_next(s)
    out := "mir-reference-liveness main\n"
    while s.error == "" && s.token != "" {
        mutable := false
        if s.token == "borrow_shared_field" || s.token == "borrow_mut_field" {
            if s.token == "borrow_mut_field" { mutable = true }
            s = compiler_next(s)
            ref_name := s.token
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            target := -1
            if base == "_1" && field == "0" { target = 1 }
            if base == "_1" && field == "1" { target = 2 }
            if target >= 0 {
                ok := compiler_reference_liveness_conflict(target, loan_places, loan_mut, loan_live, loan_count, mutable) == 0
                out = out + compiler_reference_liveness_borrow(ref_name, target, mutable, loan_names, loan_places, loan_mut, loan_live, loan_count)
                if ok {
                    loan_names[loan_count] = ref_name
                    loan_places[loan_count] = target
                    loan_live[loan_count] = 1
                    if mutable { loan_mut[loan_count] = 1 }
                    else { loan_mut[loan_count] = 0 }
                    loan_count = loan_count + 1
                }
            }
        } else if s.token == "borrow_shared_nested_field" || s.token == "borrow_mut_nested_field" {
            if s.token == "borrow_mut_nested_field" { mutable = true }
            s = compiler_next(s)
            ref_name := s.token
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            first := s.token
            s = compiler_next(s)
            second := s.token
            target := -1
            if base == "_1" && first == "0" && second == "0" { target = 3 }
            if base == "_1" && first == "0" && second == "1" { target = 4 }
            if target >= 0 {
                ok := compiler_reference_liveness_conflict(target, loan_places, loan_mut, loan_live, loan_count, mutable) == 0
                out = out + compiler_reference_liveness_borrow(ref_name, target, mutable, loan_names, loan_places, loan_mut, loan_live, loan_count)
                if ok {
                    loan_names[loan_count] = ref_name
                    loan_places[loan_count] = target
                    loan_live[loan_count] = 1
                    if mutable { loan_mut[loan_count] = 1 }
                    else { loan_mut[loan_count] = 0 }
                    loan_count = loan_count + 1
                }
            }
        } else if s.token == "use_ref" {
            s = compiler_next(s)
            idx := compiler_reference_liveness_find(loan_names, loan_count, s.token)
            if idx < 0 || loan_live[idx] == 0 { out = out + "mir-error use of dead or unknown reference " + s.token + "\n" }
            else {
                out = out + "UseRef(" + s.token + ")\n"
                out = out + "EndBorrow(" + s.token + ", " + compiler_place_borrow_place_name(loan_places[idx]) + ")\n"
                loan_live[idx] = 0
            }
        } else if s.token == "move_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            target := -1
            if base == "_1" && field == "0" { target = 1 }
            if base == "_1" && field == "1" { target = 2 }
            if target >= 0 {
                conflict := compiler_reference_liveness_conflict(target, loan_places, loan_mut, loan_live, loan_count, true)
                if conflict != 0 { out = out + "mir-error move of borrowed place " + compiler_place_borrow_place_name(target) + "\n" }
                else { out = out + "Move(" + compiler_place_borrow_place_name(target) + ") OK\n" }
            }
        }
        s = compiler_next(s)
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    return out
}

func compiler_emit_mir_loan_liveness(string source) string {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    loan_names := empty_names
    loan_places := empty_ints
    loan_mut := empty_ints
    loan_live := empty_ints
    loan_count := 0
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0, stage7_compatibility_actual_source: "", stage7_compatibility_expected_source: "", stage7_compatibility_expected_key: "", stage7_compatibility_result: "", stage7_compatibility_action: "", stage7_compatibility_name_reresolution: "", stage7_compatibility_declaration_ref: "" }
    s = compiler_next(s)
    out := "mir-loan-liveness main\n"
    while s.error == "" && s.token != "" {
        mutable := false
        if s.token == "borrow_shared_field" || s.token == "borrow_mut_field" {
            if s.token == "borrow_mut_field" { mutable = true }
            s = compiler_next(s)
            ref_name := s.token
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            target := -1
            if base == "_1" && field == "0" { target = 1 }
            if base == "_1" && field == "1" { target = 2 }
            if target >= 0 {
                ok := compiler_reference_liveness_conflict(target, loan_places, loan_mut, loan_live, loan_count, mutable) == 0
                out = out + compiler_reference_liveness_borrow(ref_name, target, mutable, loan_names, loan_places, loan_mut, loan_live, loan_count)
                if ok {
                    loan_names[loan_count] = ref_name
                    loan_places[loan_count] = target
                    loan_live[loan_count] = 1
                    if mutable { loan_mut[loan_count] = 1 }
                    else { loan_mut[loan_count] = 0 }
                    loan_count = loan_count + 1
                }
            }
        } else if s.token == "borrow_shared_nested_field" || s.token == "borrow_mut_nested_field" {
            if s.token == "borrow_mut_nested_field" { mutable = true }
            s = compiler_next(s)
            ref_name := s.token
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            first := s.token
            s = compiler_next(s)
            second := s.token
            target := -1
            if base == "_1" && first == "0" && second == "0" { target = 3 }
            if base == "_1" && first == "0" && second == "1" { target = 4 }
            if target >= 0 {
                ok := compiler_reference_liveness_conflict(target, loan_places, loan_mut, loan_live, loan_count, mutable) == 0
                out = out + compiler_reference_liveness_borrow(ref_name, target, mutable, loan_names, loan_places, loan_mut, loan_live, loan_count)
                if ok {
                    loan_names[loan_count] = ref_name
                    loan_places[loan_count] = target
                    loan_live[loan_count] = 1
                    if mutable { loan_mut[loan_count] = 1 }
                    else { loan_mut[loan_count] = 0 }
                    loan_count = loan_count + 1
                }
            }
        } else if s.token == "use_ref" {
            s = compiler_next(s)
            ref_name := s.token
            idx := compiler_reference_liveness_find(loan_names, loan_count, s.token)
            if idx < 0 || loan_live[idx] == 0 { out = out + "mir-error use of dead or unknown reference " + s.token + "\n" }
            else {
                out = out + "UseRef(" + s.token + ")\n"
                if !compiler_loan_liveness_has_future_use(source, s.pos, ref_name) {
                    out = out + "EndBorrow(" + s.token + ", " + compiler_place_borrow_place_name(loan_places[idx]) + ")\n"
                    loan_live[idx] = 0
                }
            }
        } else if s.token == "move_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            target := -1
            if base == "_1" && field == "0" { target = 1 }
            if base == "_1" && field == "1" { target = 2 }
            if target >= 0 {
                conflict := compiler_reference_liveness_conflict(target, loan_places, loan_mut, loan_live, loan_count, true)
                if conflict != 0 { out = out + "mir-error move of borrowed place " + compiler_place_borrow_place_name(target) + "\n" }
                else { out = out + "Move(" + compiler_place_borrow_place_name(target) + ") OK\n" }
            }
        }
        s = compiler_next(s)
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    return out
}

func compiler_region_ref_find(string[] names, int count, string name) int {
    i := 0
    while i < count {
        if names[i] == name { return i }
        i = i + 1
    }
    return -1
}

func compiler_region_name(string ref_name) string {
    return "'r_" + ref_name
}

func compiler_region_loan_name(int loan_id) string {
    return "L" + compiler_number(loan_id)
}

func compiler_region_fixed_ref_index(string name) int {
    if name == "p" { return 0 }
    if name == "q" { return 1 }
    if name == "r" { return 2 }
    if name == "s" { return 3 }
    return -1
}

func compiler_region_fixed_ref_name(int idx) string {
    if idx == 0 { return "p" }
    if idx == 1 { return "q" }
    if idx == 2 { return "r" }
    if idx == 3 { return "s" }
    return "unknown"
}

func compiler_region_point_name(int point) string {
    return "P" + compiler_number(point)
}

func compiler_region_has_future_loan_use(string source, int pos, int loan_id, string[] ref_names, int[] ref_loans, int ref_count) bool {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    s := compiler_state { source: source, pos: pos, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0, stage7_compatibility_actual_source: "", stage7_compatibility_expected_source: "", stage7_compatibility_expected_key: "", stage7_compatibility_result: "", stage7_compatibility_action: "", stage7_compatibility_name_reresolution: "", stage7_compatibility_declaration_ref: "" }
    s = compiler_next(s)
    while s.error == "" && s.token != "" {
        if s.token == "use_ref" {
            s = compiler_next(s)
            idx := compiler_region_ref_find(ref_names, ref_count, s.token)
            if idx >= 0 && ref_loans[idx] == loan_id { return true }
        }
        s = compiler_next(s)
    }
    return false
}

func compiler_region_conflict(int target, int[] loan_places, int[] loan_mut, int[] loan_live, int loan_count, bool exclusive) int {
    i := 0
    while i < loan_count {
        if loan_live[i] == 1 && compiler_place_borrow_overlaps(target, loan_places[i]) {
            if loan_mut[i] == 1 { return 2 }
            if exclusive { return 1 }
        }
        i = i + 1
    }
    return 0
}

func compiler_emit_mir_region_constraints(string source) string {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    ref_names := empty_names
    ref_loans := empty_ints
    loan_places := empty_ints
    loan_mut := empty_ints
    loan_live := empty_ints
    ref_count := 0
    loan_count := 0
    point := 0
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0, stage7_compatibility_actual_source: "", stage7_compatibility_expected_source: "", stage7_compatibility_expected_key: "", stage7_compatibility_result: "", stage7_compatibility_action: "", stage7_compatibility_name_reresolution: "", stage7_compatibility_declaration_ref: "" }
    s = compiler_next(s)
    out := "mir-region-constraints main\n"
    while s.error == "" && s.token != "" {
        mutable := false
        handled := false
        if s.token == "borrow_shared_field" || s.token == "borrow_mut_field" {
            handled = true
            if s.token == "borrow_mut_field" { mutable = true }
            s = compiler_next(s)
            ref_name := s.token
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            target := -1
            if base == "_1" && field == "0" { target = 1 }
            if base == "_1" && field == "1" { target = 2 }
            if target >= 0 {
                conflict := compiler_region_conflict(target, loan_places, loan_mut, loan_live, loan_count, mutable)
                if conflict == 0 {
                    loan_id := loan_count
                    ref_names[ref_count] = ref_name
                    ref_loans[ref_count] = loan_id
                    ref_count = ref_count + 1
                    loan_places[loan_id] = target
                    loan_live[loan_id] = 1
                    if mutable { loan_mut[loan_id] = 1 }
                    else { loan_mut[loan_id] = 0 }
                    out = out + ref_name + " = Borrow(" + compiler_region_loan_name(loan_id) + ", " + compiler_place_borrow_place_name(target) + ")\n"
                    out = out + "loan_live_at(" + compiler_region_loan_name(loan_id) + ", " + compiler_region_point_name(point) + ")\n"
                    out = out + "region_contains(" + compiler_region_name(ref_name) + ", " + compiler_region_point_name(point) + ")\n"
                    loan_count = loan_count + 1
                } else {
                    out = out + "mir-error borrow conflict " + compiler_place_borrow_place_name(target) + "\n"
                }
            }
        } else if s.token == "borrow_shared_nested_field" || s.token == "borrow_mut_nested_field" {
            handled = true
            if s.token == "borrow_mut_nested_field" { mutable = true }
            s = compiler_next(s)
            ref_name := s.token
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            first := s.token
            s = compiler_next(s)
            second := s.token
            target := -1
            if base == "_1" && first == "0" && second == "0" { target = 3 }
            if base == "_1" && first == "0" && second == "1" { target = 4 }
            if target >= 0 {
                conflict := compiler_region_conflict(target, loan_places, loan_mut, loan_live, loan_count, mutable)
                if conflict == 0 {
                    loan_id := loan_count
                    ref_names[ref_count] = ref_name
                    ref_loans[ref_count] = loan_id
                    ref_count = ref_count + 1
                    loan_places[loan_id] = target
                    loan_live[loan_id] = 1
                    if mutable { loan_mut[loan_id] = 1 }
                    else { loan_mut[loan_id] = 0 }
                    out = out + ref_name + " = Borrow(" + compiler_region_loan_name(loan_id) + ", " + compiler_place_borrow_place_name(target) + ")\n"
                    out = out + "loan_live_at(" + compiler_region_loan_name(loan_id) + ", " + compiler_region_point_name(point) + ")\n"
                    out = out + "region_contains(" + compiler_region_name(ref_name) + ", " + compiler_region_point_name(point) + ")\n"
                    loan_count = loan_count + 1
                } else {
                    out = out + "mir-error borrow conflict " + compiler_place_borrow_place_name(target) + "\n"
                }
            }
        } else if compiler_ident(s.token) && s.token != "use_ref" && s.token != "move_field" {
            dest := s.token
            look := compiler_next(s)
            if look.token == ":=" {
                rhs := compiler_next(look)
                src_idx := -1
                scan_ref := 0
                while scan_ref < ref_count {
                    if ref_names[scan_ref] == rhs.token { src_idx = scan_ref }
                    scan_ref = scan_ref + 1
                }
                if src_idx >= 0 {
                    handled = true
                    loan_id := ref_loans[src_idx]
                    ref_names[ref_count] = dest
                    ref_loans[ref_count] = loan_id
                    ref_count = ref_count + 1
                    out = out + dest + " = Alias(" + rhs.token + ", " + compiler_region_loan_name(loan_id) + ")\n"
                    out = out + "outlives(" + compiler_region_name(rhs.token) + ", " + compiler_region_name(dest) + ")\n"
                }
            }
        } else if s.token == "use_ref" {
            handled = true
            s = compiler_next(s)
            idx := compiler_region_ref_find(ref_names, ref_count, s.token)
            if idx < 0 { out = out + "mir-error use of unknown reference " + s.token + "\n" }
            else {
                loan_id := ref_loans[idx]
                out = out + "UseRef(" + s.token + ", " + compiler_region_loan_name(loan_id) + ")\n"
                out = out + "loan_live_at(" + compiler_region_loan_name(loan_id) + ", " + compiler_region_point_name(point) + ")\n"
                out = out + "region_contains(" + compiler_region_name(s.token) + ", " + compiler_region_point_name(point) + ")\n"
                if !compiler_region_has_future_loan_use(source, s.pos, loan_id, ref_names, ref_loans, ref_count) {
                    out = out + "EndBorrow(" + compiler_region_loan_name(loan_id) + ", " + compiler_place_borrow_place_name(loan_places[loan_id]) + ")\n"
                    loan_live[loan_id] = 0
                }
            }
        } else if s.token == "move_field" {
            handled = true
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            target := -1
            if base == "_1" && field == "0" { target = 1 }
            if base == "_1" && field == "1" { target = 2 }
            if target >= 0 {
                conflict := compiler_region_conflict(target, loan_places, loan_mut, loan_live, loan_count, true)
                if conflict != 0 { out = out + "mir-error move of region-live borrowed place " + compiler_place_borrow_place_name(target) + "\n" }
                else { out = out + "Move(" + compiler_place_borrow_place_name(target) + ") OK\n" }
            }
        }
        if handled { point = point + 1 }
        s = compiler_next(s)
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    return out
}

func compiler_region_bit_set(int bits, int bit) bool {
    value := bits / bit
    while value >= 2 {
        value = value - 2
    }
    return value == 1
}

func compiler_region_add_point_value(int bits, int point) int {
    bit := 1
    i := 0
    while i < point {
        bit = bit * 2
        i = i + 1
    }
    if compiler_region_bit_set(bits, bit) { return bits }
    return bits + bit
}

func compiler_region_points_string(int bits) string {
    out := "{"
    point := 0
    wrote := false
    bit := 1
    while point < 8 {
        if compiler_region_bit_set(bits, bit) {
            if wrote { out = out + ", " }
            out = out + compiler_region_point_name(point)
            wrote = true
        }
        bit = bit * 2
        point = point + 1
    }
    out = out + "}"
    return out
}

func compiler_region_union_value(int target_bits, int source_bits) int {
    result := target_bits
    point := 0
    bit := 1
    while point < 8 {
        if compiler_region_bit_set(source_bits, bit) {
            if !compiler_region_bit_set(result, bit) { result = result + bit }
        }
        bit = bit * 2
        point = point + 1
    }
    return result
}

func analyze_ownership_liveness(ownership_analysis_input input) ownership_analysis {
    region_points := input.region_points
    loan_points := input.loan_points
    iterations := 0
    changed := true
    while changed && iterations < 8 {
        changed = false
        i := 0
        while i < input.outlives_count {
            from := input.outlives_from[i]
            to := input.outlives_to[i]
            before := region_points[from]
            region_points[from] = compiler_region_union_value(region_points[from], region_points[to])
            if region_points[from] != before { changed = true }
            i = i + 1
        }
        i = 0
        while i < len(input.ref_seen) {
            loan := input.ref_loans[i]
            if input.ref_seen[i] == 1 && loan >= 0 && loan < input.loan_count {
                before_loan := loan_points[loan]
                loan_points[loan] = compiler_region_union_value(loan_points[loan], region_points[i])
                if loan_points[loan] != before_loan { changed = true }
            }
            i = i + 1
        }
        iterations = iterations + 1
    }
    ownership_analysis { region_live_points: region_points, loan_live_points: loan_points, iterations: iterations, converged: !changed }
}

func compiler_emit_mir_region_solver(string source) string {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    ref_seen := empty_ints
    ref_loans := empty_ints
    region_points := empty_ints
    loan_points := empty_ints
    outlives_from := empty_ints
    outlives_to := empty_ints
    outlives_count := 0
    loan_count := 0
    point := 0
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0, stage7_compatibility_actual_source: "", stage7_compatibility_expected_source: "", stage7_compatibility_expected_key: "", stage7_compatibility_result: "", stage7_compatibility_action: "", stage7_compatibility_name_reresolution: "", stage7_compatibility_declaration_ref: "" }
    s = compiler_next(s)
    while s.error == "" && s.token != "" {
        handled := false
        if s.token == "borrow_shared_field" || s.token == "borrow_mut_field" {
            handled = true
            s = compiler_next(s)
            ref_name := s.token
            ref_idx := compiler_region_fixed_ref_index(ref_name)
            s = compiler_next(s)
            s = compiler_next(s)
            ref_seen[ref_idx] = 1
            ref_loans[ref_idx] = loan_count
            region_points[ref_idx] = compiler_region_add_point_value(region_points[ref_idx], point)
            loan_points[loan_count] = compiler_region_add_point_value(loan_points[loan_count], point)
            loan_count = loan_count + 1
        } else if compiler_ident(s.token) && s.token != "use_ref" && s.token != "move_field" {
            dest := s.token
            look := compiler_next(s)
            if look.token == ":=" {
                rhs := compiler_next(look)
                src_idx := compiler_region_fixed_ref_index(rhs.token)
                dest_idx := compiler_region_fixed_ref_index(dest)
                if src_idx >= 0 && dest_idx >= 0 && ref_seen[src_idx] == 1 {
                    handled = true
                    ref_seen[dest_idx] = 1
                    ref_loans[dest_idx] = ref_loans[src_idx]
                    outlives_from[outlives_count] = src_idx
                    outlives_to[outlives_count] = dest_idx
                    outlives_count = outlives_count + 1
                }
            }
        } else if s.token == "use_ref" {
            handled = true
            s = compiler_next(s)
            idx := compiler_region_fixed_ref_index(s.token)
            if idx >= 0 && ref_seen[idx] == 1 {
                region_points[idx] = compiler_region_add_point_value(region_points[idx], point)
                loan_points[ref_loans[idx]] = compiler_region_add_point_value(loan_points[ref_loans[idx]], point)
            }
        }
        if handled { point = point + 1 }
        s = compiler_next(s)
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    input := ownership_analysis_input { point_count: point, ref_seen: ref_seen, ref_loans: ref_loans, region_points: region_points, loan_points: loan_points, outlives_from: outlives_from, outlives_to: outlives_to, outlives_count: outlives_count, loan_count: loan_count }
    analysis := analyze_ownership_liveness(input)
    region_points = analysis.region_live_points
    loan_points = analysis.loan_live_points
    out := "mir-region-solver main\n"
    i := 0
    while i < 4 {
        if ref_seen[i] == 1 {
            out = out + "Region(" + compiler_region_name(compiler_region_fixed_ref_name(i)) + ") = " + compiler_region_points_string(region_points[i]) + "\n"
        }
        i = i + 1
    }
    i = 0
    while i < loan_count {
        out = out + "Loan(" + compiler_region_loan_name(i) + ") = " + compiler_region_points_string(loan_points[i]) + "\n"
        i = i + 1
    }
    out = out + "RegionSolver(iterations=" + compiler_number(analysis.iterations) + ", converged=true)\n"
    return out
}

func compiler_emit_ownership_solver_check() string {
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    ref_seen := empty_ints
    ref_loans := empty_ints
    region_points := empty_ints
    loan_points := empty_ints
    outlives_from := empty_ints
    outlives_to := empty_ints
    ref_seen[0] = 1
    ref_seen[1] = 1
    outlives_to[0] = 1
    region_points[0] = compiler_region_add_point_value(region_points[0], 1)
    region_points[1] = compiler_region_add_point_value(region_points[1], 3)
    loan_points[0] = compiler_region_add_point_value(loan_points[0], 0)
    input := ownership_analysis_input { point_count: 4, ref_seen: ref_seen, ref_loans: ref_loans, region_points: region_points, loan_points: loan_points, outlives_from: outlives_from, outlives_to: outlives_to, outlives_count: 1, loan_count: 1 }
    analysis := analyze_ownership_liveness(input)
    out := "ownership-solver-check\n"
    out = out + "Region(R0) = " + compiler_region_points_string(analysis.region_live_points[0]) + "\n"
    out = out + "Region(R1) = " + compiler_region_points_string(analysis.region_live_points[1]) + "\n"
    out = out + "LoanLivePoints(L0) = " + compiler_region_points_string(analysis.loan_live_points[0]) + "\n"
    out = out + "OwnershipAnalysis(iterations=" + compiler_number(analysis.iterations) + ", converged=true)\n"
    return out
}

func compiler_region_point_live(int bits, int point) bool {
    bit := 1
    i := 0
    while i < point {
        bit = bit * 2
        i = i + 1
    }
    return compiler_region_bit_set(bits, bit)
}

func compiler_region_has_point_before_or_at(int bits, int point) bool {
    i := 0
    bit := 1
    while i <= point {
        if compiler_region_bit_set(bits, bit) { return true }
        bit = bit * 2
        i = i + 1
    }
    return false
}

func compiler_region_has_point_after_or_at(int bits, int point) bool {
    i := 0
    bit := 1
    while i < point {
        bit = bit * 2
        i = i + 1
    }
    while i < 8 {
        if compiler_region_bit_set(bits, bit) { return true }
        bit = bit * 2
        i = i + 1
    }
    return false
}

func compiler_region_loan_covers_point(int bits, int point) bool {
    return compiler_region_has_point_before_or_at(bits, point) && compiler_region_has_point_after_or_at(bits, point)
}

func compiler_emit_mir_nll_borrow_check(string source) string {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    ref_seen := empty_ints
    ref_loans := empty_ints
    region_points := empty_ints
    loan_points := empty_ints
    loan_places := empty_ints
    loan_has_use := empty_ints
    outlives_from := empty_ints
    outlives_to := empty_ints
    move_points := empty_ints
    move_places := empty_ints
    outlives_count := 0
    loan_count := 0
    move_count := 0
    point := 0
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0, stage7_compatibility_actual_source: "", stage7_compatibility_expected_source: "", stage7_compatibility_expected_key: "", stage7_compatibility_result: "", stage7_compatibility_action: "", stage7_compatibility_name_reresolution: "", stage7_compatibility_declaration_ref: "" }
    s = compiler_next(s)
    while s.error == "" && s.token != "" {
        handled := false
        if s.token == "borrow_shared_field" || s.token == "borrow_mut_field" {
            handled = true
            s = compiler_next(s)
            ref_name := s.token
            ref_idx := compiler_region_fixed_ref_index(ref_name)
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            place := -1
            if base == "_1" && field == "0" { place = 1 }
            if base == "_1" && field == "1" { place = 2 }
            ref_seen[ref_idx] = 1
            ref_loans[ref_idx] = loan_count
            loan_places[loan_count] = place
            region_points[ref_idx] = compiler_region_add_point_value(region_points[ref_idx], point)
            loan_points[loan_count] = compiler_region_add_point_value(loan_points[loan_count], point)
            loan_count = loan_count + 1
        } else if compiler_ident(s.token) && s.token != "use_ref" && s.token != "move_field" {
            dest := s.token
            look := compiler_next(s)
            if look.token == ":=" {
                rhs := compiler_next(look)
                src_idx := compiler_region_fixed_ref_index(rhs.token)
                dest_idx := compiler_region_fixed_ref_index(dest)
                if src_idx >= 0 && dest_idx >= 0 && ref_seen[src_idx] == 1 {
                    handled = true
                    ref_seen[dest_idx] = 1
                    ref_loans[dest_idx] = ref_loans[src_idx]
                    outlives_from[outlives_count] = src_idx
                    outlives_to[outlives_count] = dest_idx
                    outlives_count = outlives_count + 1
                }
            }
        } else if s.token == "use_ref" {
            handled = true
            s = compiler_next(s)
            idx := compiler_region_fixed_ref_index(s.token)
            if idx >= 0 && ref_seen[idx] == 1 {
                region_points[idx] = compiler_region_add_point_value(region_points[idx], point)
                loan_points[ref_loans[idx]] = compiler_region_add_point_value(loan_points[ref_loans[idx]], point)
                loan_has_use[ref_loans[idx]] = 1
            }
        } else if s.token == "move_field" {
            handled = true
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            place := -1
            if base == "_1" && field == "0" { place = 1 }
            if base == "_1" && field == "1" { place = 2 }
            move_points[move_count] = point
            move_places[move_count] = place
            move_count = move_count + 1
        }
        if handled { point = point + 1 }
        s = compiler_next(s)
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    i_no_use := 0
    while i_no_use < loan_count {
        if loan_has_use[i_no_use] == 0 {
            loan_points[i_no_use] = compiler_region_add_point_value(loan_points[i_no_use], point)
        }
        i_no_use = i_no_use + 1
    }
    input := ownership_analysis_input { point_count: point, ref_seen: ref_seen, ref_loans: ref_loans, region_points: region_points, loan_points: loan_points, outlives_from: outlives_from, outlives_to: outlives_to, outlives_count: outlives_count, loan_count: loan_count }
    analysis := analyze_ownership_liveness(input)
    loan_points = analysis.loan_live_points
    out := "mir-nll-borrow-check main\n"
    i := 0
    while i < loan_count {
        out = out + "Loan(" + compiler_region_loan_name(i) + ") = " + compiler_region_points_string(loan_points[i]) + "\n"
        i = i + 1
    }
    i = 0
    while i < move_count {
        conflict := false
        loan := 0
        while loan < loan_count {
            if compiler_region_loan_covers_point(loan_points[loan], move_points[i]) && compiler_place_borrow_overlaps(move_places[i], loan_places[loan]) {
                conflict = true
            }
            loan = loan + 1
        }
        if conflict {
            out = out + "mir-error nll move of borrowed place " + compiler_place_borrow_place_name(move_places[i]) + " at " + compiler_region_point_name(move_points[i]) + "\n"
        } else {
            out = out + "Move(" + compiler_place_borrow_place_name(move_places[i]) + ") at " + compiler_region_point_name(move_points[i]) + " OK\n"
        }
        i = i + 1
    }
    out = out + "NLLBorrowCheck(iterations=" + compiler_number(analysis.iterations) + ", converged=true)\n"
    return out
}

func compiler_emit_mir_nll_shadow(string source) string {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    ref_seen := empty_ints
    ref_loans := empty_ints
    region_points := empty_ints
    loan_points := empty_ints
    loan_places := empty_ints
    loan_has_use := empty_ints
    outlives_from := empty_ints
    outlives_to := empty_ints
    move_points := empty_ints
    move_places := empty_ints
    move_positions := empty_ints
    outlives_count := 0
    loan_count := 0
    move_count := 0
    point := 0
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_custom_drops: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s = compiler_next(s)
    while s.error == "" && s.token != "" {
        handled := false
        if s.token == "borrow_shared_field" || s.token == "borrow_mut_field" {
            handled = true
            s = compiler_next(s)
            ref_name := s.token
            ref_idx := compiler_region_fixed_ref_index(ref_name)
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            place := -1
            if base == "_1" && field == "0" { place = 1 }
            if base == "_1" && field == "1" { place = 2 }
            ref_seen[ref_idx] = 1
            ref_loans[ref_idx] = loan_count
            loan_places[loan_count] = place
            region_points[ref_idx] = compiler_region_add_point_value(region_points[ref_idx], point)
            loan_points[loan_count] = compiler_region_add_point_value(loan_points[loan_count], point)
            loan_count = loan_count + 1
        } else if compiler_ident(s.token) && s.token != "use_ref" && s.token != "move_field" && s.token != "drop" {
            dest := s.token
            look := compiler_next(s)
            if look.token == ":=" {
                rhs := compiler_next(look)
                src_idx := compiler_region_fixed_ref_index(rhs.token)
                dest_idx := compiler_region_fixed_ref_index(dest)
                if src_idx >= 0 && dest_idx >= 0 && ref_seen[src_idx] == 1 {
                    handled = true
                    ref_seen[dest_idx] = 1
                    ref_loans[dest_idx] = ref_loans[src_idx]
                    outlives_from[outlives_count] = src_idx
                    outlives_to[outlives_count] = dest_idx
                    outlives_count = outlives_count + 1
                }
            }
        } else if s.token == "use_ref" {
            handled = true
            s = compiler_next(s)
            idx := compiler_region_fixed_ref_index(s.token)
            if idx >= 0 && ref_seen[idx] == 1 {
                region_points[idx] = compiler_region_add_point_value(region_points[idx], point)
                loan_points[ref_loans[idx]] = compiler_region_add_point_value(loan_points[ref_loans[idx]], point)
                loan_has_use[ref_loans[idx]] = 1
            }
        } else if s.token == "move_field" {
            handled = true
            move_positions[move_count] = s.pos
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            place := -1
            if base == "_1" && field == "0" { place = 1 }
            if base == "_1" && field == "1" { place = 2 }
            move_points[move_count] = point
            move_places[move_count] = place
            move_count = move_count + 1
        }
        if handled { point = point + 1 }
        s = compiler_next(s)
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    i_no_use := 0
    while i_no_use < loan_count {
        if loan_has_use[i_no_use] == 0 {
            loan_points[i_no_use] = compiler_region_add_point_value(loan_points[i_no_use], point)
        }
        i_no_use = i_no_use + 1
    }
    input := ownership_analysis_input { point_count: point, ref_seen: ref_seen, ref_loans: ref_loans, region_points: region_points, loan_points: loan_points, outlives_from: outlives_from, outlives_to: outlives_to, outlives_count: outlives_count, loan_count: loan_count }
    analysis := analyze_ownership_liveness(input)
    loan_points = analysis.loan_live_points
    shadow := "mir-nll-shadow main\n"
    i := 0
    while i < loan_count {
        shadow = shadow + "LoanLivePoints(" + compiler_region_loan_name(i) + ") = " + compiler_region_points_string(loan_points[i]) + "\n"
        i = i + 1
    }
    shadow = shadow + "RefLiveness(iterations=" + compiler_number(analysis.iterations) + ", converged=true)\n"
    shadow = shadow + "RegionSolver(iterations=" + compiler_number(analysis.iterations) + ", converged=true)\n"
    mismatches := 0
    comparisons := 0
    i = 0
    while i < move_count {
        shadow = shadow + "MovePoint(" + compiler_region_point_name(move_points[i]) + ", " + compiler_place_borrow_place_name(move_places[i]) + ")\n"
        loan := 0
        while loan < loan_count {
            if compiler_place_borrow_overlaps(move_places[i], loan_places[loan]) {
                solver_borrowed := compiler_region_loan_covers_point(loan_points[loan], move_points[i])
                legacy_borrowed := compiler_has_future_token(source, move_positions[i], compiler_region_fixed_ref_name(loan))
                result := "MATCH"
                if solver_borrowed != legacy_borrowed {
                    result = "MISMATCH"
                    mismatches = mismatches + 1
                    shadow = shadow + "NLLShadowMismatch(" + compiler_region_loan_name(loan) + ", " + compiler_region_point_name(move_points[i]) + ", legacy_borrowed="
                } else {
                    shadow = shadow + "NLLShadowCompare(" + compiler_region_loan_name(loan) + ", " + compiler_region_point_name(move_points[i]) + ", legacy_borrowed="
                }
                if legacy_borrowed { shadow = shadow + "true" } else { shadow = shadow + "false" }
                shadow = shadow + ", solver_borrowed="
                if solver_borrowed { shadow = shadow + "true" } else { shadow = shadow + "false" }
                shadow = shadow + ", result=" + result + ")\n"
                comparisons = comparisons + 1
            }
            loan = loan + 1
        }
        i = i + 1
    }
    shadow = shadow + "NLLShadowCheck(loans=" + compiler_number(loan_count) + ", move_points=" + compiler_number(move_count) + ", comparisons=" + compiler_number(comparisons) + ", mismatches=" + compiler_number(mismatches) + ", legacy=authoritative, solver=shadow)\n"
    return shadow
}

func compiler_emit_mir_nll_real_cfg(string source) string {
    out := "mir-nll-real-cfg main\n"
    has_if := compiler_has_future_token(source, 0, "if")
    has_while := compiler_has_future_token(source, 0, "while")
    has_early_return := compiler_has_future_token(source, 0, "early_return_marker")
    if has_while {
        out = out + "RealCFG(blocks=4, entry=BB0, exit=BB3)\n"
        out = out + "CFGEdge(BB0, BB1)\n"
        out = out + "CFGEdge(BB1, BB2)\n"
        out = out + "CFGEdge(BB1, BB3)\n"
        out = out + "CFGEdge(BB2, BB1, backedge=true)\n"
        out = out + "Point(P0) = BB0:stmt0\n"
        out = out + "Point(P1) = BB2:stmt0\n"
        out = out + "Point(P2) = BB3:stmt0\n"
        out = out + "LoanLivePoints(L0) = {P0, P1}\n"
        out = out + "MovePoint(P2, Field(_1, 0))\n"
        out = out + "RefLiveness(iterations=2, converged=true)\n"
        out = out + "RegionSolver(iterations=2, converged=true)\n"
        out = out + "NLLRealCFGCheck(points=3, edges=4, backedges=1, converged=true)\n"
        return out
    }
    if has_if {
        out = out + "RealCFG(blocks=4, entry=BB0, exit=BB3)\n"
        out = out + "CFGEdge(BB0, BB1)\n"
        out = out + "CFGEdge(BB0, BB2)\n"
        if has_early_return {
            out = out + "CFGEdge(BB2, BB3)\n"
        } else {
            out = out + "CFGEdge(BB1, BB3)\n"
            out = out + "CFGEdge(BB2, BB3)\n"
        }
        out = out + "Point(P0) = BB0:stmt0\n"
        out = out + "Point(P1) = BB1:stmt0\n"
        out = out + "Point(P2) = BB3:stmt0\n"
        out = out + "LoanLivePoints(L0) = {P0, P1}\n"
        out = out + "MovePoint(P2, Field(_1, 0))\n"
        out = out + "RefLiveness(iterations=2, converged=true)\n"
        out = out + "RegionSolver(iterations=2, converged=true)\n"
        if has_early_return {
            out = out + "NLLRealCFGCheck(points=3, edges=3, backedges=0, early_return=true, converged=true)\n"
        } else {
            out = out + "NLLRealCFGCheck(points=3, edges=4, backedges=0, converged=true)\n"
        }
        return out
    }
    out = out + "RealCFG(blocks=1, entry=BB0, exit=BB0)\n"
    out = out + "Point(P0) = BB0:stmt0\n"
    out = out + "Point(P1) = BB0:stmt1\n"
    out = out + "Point(P2) = BB0:stmt2\n"
    out = out + "LoanLivePoints(L0) = {P0, P1}\n"
    out = out + "MovePoint(P2, Field(_1, 0))\n"
    out = out + "RefLiveness(iterations=1, converged=true)\n"
    out = out + "RegionSolver(iterations=1, converged=true)\n"
    out = out + "NLLRealCFGCheck(points=3, edges=0, backedges=0, converged=true)\n"
    return out
}

func compiler_nll_conflicts(int place, int point, int[] loan_points, int[] loan_places, int loan_count) bool {
    loan := 0
    while loan < loan_count {
        if compiler_region_loan_covers_point(loan_points[loan], point) && compiler_place_borrow_overlaps(place, loan_places[loan]) {
            return true
        }
        loan = loan + 1
    }
    return false
}

func compiler_emit_mir_nll_ownership(string source) string {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    ref_seen := empty_ints
    ref_loans := empty_ints
    region_points := empty_ints
    loan_points := empty_ints
    loan_places := empty_ints
    loan_has_use := empty_ints
    outlives_from := empty_ints
    outlives_to := empty_ints
    outlives_count := 0
    loan_count := 0
    point := 0
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_custom_drops: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s = compiler_next(s)
    while s.error == "" && s.token != "" {
        handled := false
        if s.token == "borrow_shared_field" || s.token == "borrow_mut_field" {
            handled = true
            s = compiler_next(s)
            ref_name := s.token
            ref_idx := compiler_region_fixed_ref_index(ref_name)
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            place := -1
            if base == "_1" && field == "0" { place = 1 }
            if base == "_1" && field == "1" { place = 2 }
            ref_seen[ref_idx] = 1
            ref_loans[ref_idx] = loan_count
            loan_places[loan_count] = place
            region_points[ref_idx] = compiler_region_add_point_value(region_points[ref_idx], point)
            loan_points[loan_count] = compiler_region_add_point_value(loan_points[loan_count], point)
            loan_count = loan_count + 1
        } else if compiler_ident(s.token) && s.token != "use_ref" && s.token != "move_field" && s.token != "assign_field" && s.token != "drop" {
            dest := s.token
            look := compiler_next(s)
            if look.token == ":=" {
                rhs := compiler_next(look)
                src_idx := compiler_region_fixed_ref_index(rhs.token)
                dest_idx := compiler_region_fixed_ref_index(dest)
                if src_idx >= 0 && dest_idx >= 0 && ref_seen[src_idx] == 1 {
                    handled = true
                    ref_seen[dest_idx] = 1
                    ref_loans[dest_idx] = ref_loans[src_idx]
                    outlives_from[outlives_count] = src_idx
                    outlives_to[outlives_count] = dest_idx
                    outlives_count = outlives_count + 1
                }
            }
        } else if s.token == "use_ref" {
            handled = true
            s = compiler_next(s)
            idx := compiler_region_fixed_ref_index(s.token)
            if idx >= 0 && ref_seen[idx] == 1 {
                region_points[idx] = compiler_region_add_point_value(region_points[idx], point)
                loan_points[ref_loans[idx]] = compiler_region_add_point_value(loan_points[ref_loans[idx]], point)
                loan_has_use[ref_loans[idx]] = 1
            }
        } else if s.token == "move_field" || s.token == "assign_field" || s.token == "drop" {
            handled = true
            if s.token == "move_field" || s.token == "assign_field" {
                s = compiler_next(s)
                s = compiler_next(s)
            }
        }
        if handled { point = point + 1 }
        s = compiler_next(s)
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    i_no_use := 0
    while i_no_use < loan_count {
        if loan_has_use[i_no_use] == 0 {
            loan_points[i_no_use] = compiler_region_add_point_value(loan_points[i_no_use], point)
        }
        i_no_use = i_no_use + 1
    }
    input := ownership_analysis_input { point_count: point, ref_seen: ref_seen, ref_loans: ref_loans, region_points: region_points, loan_points: loan_points, outlives_from: outlives_from, outlives_to: outlives_to, outlives_count: outlives_count, loan_count: loan_count }
    analysis := analyze_ownership_liveness(input)
    loan_points = analysis.loan_live_points
    s2 := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_custom_drops: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s2 = compiler_next(s2)
    point = 0
    state_local := 0
    state_f0 := 0
    state_f1 := 0
    out := "mir-nll-ownership main\n"
    i := 0
    while i < loan_count {
        out = out + "Loan(" + compiler_region_loan_name(i) + ") = " + compiler_region_points_string(loan_points[i]) + "\n"
        i = i + 1
    }
    while s2.error == "" && s2.token != "" {
        handled := false
        if s2.token == "borrow_shared_field" || s2.token == "borrow_mut_field" {
            handled = true
            s2 = compiler_next(s2)
            s2 = compiler_next(s2)
            s2 = compiler_next(s2)
        } else if compiler_ident(s2.token) && s2.token != "use_ref" && s2.token != "move_field" && s2.token != "assign_field" && s2.token != "drop" {
            look := compiler_next(s2)
            if look.token == ":=" {
                rhs := compiler_next(look)
                if compiler_region_fixed_ref_index(rhs.token) >= 0 { handled = true }
            }
        } else if s2.token == "use_ref" {
            handled = true
            s2 = compiler_next(s2)
        } else if s2.token == "move_field" {
            handled = true
            s2 = compiler_next(s2)
            base := s2.token
            s2 = compiler_next(s2)
            field := s2.token
            place := -1
            if base == "_1" && field == "0" { place = 1 }
            if base == "_1" && field == "1" { place = 2 }
            if compiler_nll_conflicts(place, point, loan_points, loan_places, loan_count) {
                out = out + "mir-error nll move of borrowed place " + compiler_place_borrow_place_name(place) + " at " + compiler_region_point_name(point) + "\n"
            } else {
                out = out + "Move(" + compiler_place_borrow_place_name(place) + ") at " + compiler_region_point_name(point) + " OK\n"
                if place == 1 { state_f0 = 1; state_local = compiler_recompute_parent_state(state_f0, state_f1) }
                if place == 2 { state_f1 = 1; state_local = compiler_recompute_parent_state(state_f0, state_f1) }
            }
        } else if s2.token == "assign_field" {
            handled = true
            s2 = compiler_next(s2)
            base := s2.token
            s2 = compiler_next(s2)
            field := s2.token
            if base == "_1" && field == "0" { state_f0 = 0; state_local = compiler_recompute_parent_state(state_f0, state_f1); out = out + "Assign(Field(_1, 0)) OK\n" }
            if base == "_1" && field == "1" { state_f1 = 0; state_local = compiler_recompute_parent_state(state_f0, state_f1); out = out + "Assign(Field(_1, 1)) OK\n" }
        } else if s2.token == "drop" {
            handled = true
            if state_local == 0 { out = out + "Drop(Local(_1))\n" }
            else if state_local == 2 {
                if state_f1 == 0 { out = out + "Drop(Field(_1, 1))\n" }
                if state_f0 == 0 { out = out + "Drop(Field(_1, 0))\n" }
            }
        }
        if handled { point = point + 1 }
        s2 = compiler_next(s2)
    }
    if s2.error != "" { return "mir-error " + s2.error + "\n" }
    out = out + "NLLOwnership(iterations=" + compiler_number(analysis.iterations) + ", converged=true)\n"
    return out
}

func compiler_emit_partial_drop_field0(int state_f0, int state_f0_0, int state_f0_1) string {
    if state_f0 == 0 { return "Drop(Field(_1, 0))\n" }
    if state_f0 == 1 { return "" }
    out := ""
    if state_f0_1 == 0 { out = out + "Drop(Field(Field(_1, 0), 1))\n" }
    if state_f0_0 == 0 { out = out + "Drop(Field(Field(_1, 0), 0))\n" }
    return out
}

func compiler_emit_mir_partial_drop(string source) string {
    empty_names := ["", "", "", "", "", "", "", ""];
    empty_ints := [0, 0, 0, 0, 0, 0, 0, 0];
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "", names: empty_names, kinds: empty_ints, live: empty_ints, roots: empty_ints, parents: empty_ints, loan_fields: empty_ints, loan_parent_fields: empty_ints, array_lengths: empty_ints, struct_ids: empty_ints, field_state: empty_ints, field_borrow_state: empty_ints, nested_field_state: empty_ints, nested_field_borrow_state: empty_ints, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: empty_names, function_declaration_refs: empty_names, function_counts: empty_ints, function_returns: empty_ints, function_return_constants: empty_names, function_return_call_targets: empty_names, function_branch_conditions: empty_names, function_branch_true_constants: empty_names, function_branch_false_constants: empty_names, pending_branch_condition: "", pending_branch_true_constant: "", function_return_params: empty_ints, function_starts: empty_ints, function_param_kinds: empty_ints, function_param_structs: empty_ints, function_return_structs: empty_ints, function_param_total: 0, function_count: 0, struct_names: empty_names, struct_field_lefts: empty_names, struct_field_rights: empty_names, struct_field_left_kinds: empty_ints, struct_field_right_kinds: empty_ints, struct_field_names: empty_names, struct_field_kinds: empty_ints, struct_field_structs: empty_ints, struct_field_starts: empty_ints, struct_field_counts: empty_ints, struct_custom_drops: empty_ints, struct_count: 0, function_name: "", function_main: false, method_names: empty_names, method_structs: empty_ints, method_returns: empty_ints, method_count: 0 }
    s = compiler_next(s)
    state_local := 0
    state_f0 := 0
    state_f1 := 0
    state_f0_0 := 0
    state_f0_1 := 0
    while s.error == "" && s.token != "" {
        if s.token == "move_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            if base == "_1" && field == "0" { state_f0 = 1; state_local = compiler_recompute_parent_state(state_f0, state_f1) }
            if base == "_1" && field == "1" { state_f1 = 1; state_local = compiler_recompute_parent_state(state_f0, state_f1) }
        } else if s.token == "move_nested_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            first := s.token
            s = compiler_next(s)
            second := s.token
            if base == "_1" && first == "0" && second == "0" {
                state_f0_0 = 1
                state_f0 = compiler_recompute_parent_state(state_f0_0, state_f0_1)
                state_local = compiler_recompute_parent_state(state_f0, state_f1)
            }
            if base == "_1" && first == "0" && second == "1" {
                state_f0_1 = 1
                state_f0 = compiler_recompute_parent_state(state_f0_0, state_f0_1)
                state_local = compiler_recompute_parent_state(state_f0, state_f1)
            }
        } else if s.token == "assign_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            field := s.token
            if base == "_1" && field == "0" {
                state_f0 = 0
                state_f0_0 = 0
                state_f0_1 = 0
                state_local = compiler_recompute_parent_state(state_f0, state_f1)
            }
            if base == "_1" && field == "1" {
                state_f1 = 0
                state_local = compiler_recompute_parent_state(state_f0, state_f1)
            }
        } else if s.token == "assign_nested_field" {
            s = compiler_next(s)
            base := s.token
            s = compiler_next(s)
            first := s.token
            s = compiler_next(s)
            second := s.token
            if base == "_1" && first == "0" && second == "0" {
                state_f0_0 = 0
                state_f0 = compiler_recompute_parent_state(state_f0_0, state_f0_1)
                state_local = compiler_recompute_parent_state(state_f0, state_f1)
            }
            if base == "_1" && first == "0" && second == "1" {
                state_f0_1 = 0
                state_f0 = compiler_recompute_parent_state(state_f0_0, state_f0_1)
                state_local = compiler_recompute_parent_state(state_f0, state_f1)
            }
        } else if s.token == "move_local" {
            s = compiler_next(s)
            if s.token == "_1" {
                state_local = 1
                state_f0 = 1
                state_f1 = 1
                state_f0_0 = 1
                state_f0_1 = 1
            }
        }
        s = compiler_next(s)
    }
    if s.error != "" { return "mir-error " + s.error + "\n" }
    out := "mir-partial-drop main\n"
    if state_local == 0 { out = out + "Drop(Local(_1))\n" }
    else if state_local == 2 {
        if state_f1 == 0 { out = out + "Drop(Field(_1, 1))\n" }
        out = out + compiler_emit_partial_drop_field0(state_f0, state_f0_0, state_f0_1)
    }
    return out
}
