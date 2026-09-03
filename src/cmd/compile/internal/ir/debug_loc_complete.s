package compile.internal.ir.debug_loc_complete

struct source_location {
    string filename
    i32 line
    i32 column
    i32 end_line
    i32 end_column
}

struct debug_loc_info {
    i32 instr_id
    source_location loc
    string var_name
    string scope
}

struct debug_loc_propagator {
    debug_loc_info[] loc_infos
    source_location[] file_locations
    string[] scope_stack
    i32 current_depth
}

func new_debug_loc_propagator() debug_loc_propagator* {
    dlp := new(debug_loc_propagator)
    dlp.loc_infos = debug_loc_info[]()
    dlp.file_locations = source_location[]()
    dlp.scope_stack = make(string[], 100)
    dlp.current_depth = 0
    dlp
}

func (dlp debug_loc_propagator*) enter_scope(scope_name string) {
    if dlp.current_depth < i32(len(dlp.scope_stack)) {
        dlp.scope_stack[dlp.current_depth] = scope_name
        dlp.current_depth += 1
    }
}

func (dlp debug_loc_propagator*) exit_scope() {
    if dlp.current_depth > 0 {
        dlp.current_depth -= 1
    }
}

func (dlp debug_loc_propagator*) get_current_scope() string {
    scope := ""
    for i := i32(0); i < dlp.current_depth; i += 1 {
        if i > 0 {
            scope += "::"
        }
        scope += dlp.scope_stack[i]
    }
    scope
}

func (debug_loc_propagator* dlp) set_location(i32 instr_id, string filename, i32 line, i32 column) {
    loc := source_location{
        filename: filename,
        line: line,
        column: column,
        end_line: line,
        end_column: column + 1
    }
    
    info := debug_loc_info{
        instr_id: instr_id,
        loc: loc,
        var_name: "",
        scope: dlp.get_current_scope()
    }
    
    dlp.loc_infos = append(dlp.loc_infos, info)
}

func (debug_loc_propagator* dlp) set_location_with_range(i32 instr_id, string filename, i32 line, i32 col, i32 end_line, i32 end_col) {
    loc := source_location{
        filename: filename,
        line: line,
        column: col,
        end_line: end_line,
        end_column: end_col
    }
    
    info := debug_loc_info{
        instr_id: instr_id,
        loc: loc,
        var_name: "",
        scope: dlp.get_current_scope()
    }
    
    dlp.loc_infos = append(dlp.loc_infos, info)
}

func (debug_loc_propagator* dlp) set_variable_location(i32 instr_id, string var_name, string filename, i32 line, i32 column) {
    loc := source_location{
        filename: filename,
        line: line,
        column: column,
        end_line: line,
        end_column: column + 1
    }
    
    info := debug_loc_info{
        instr_id: instr_id,
        loc: loc,
        var_name: var_name,
        scope: dlp.get_current_scope()
    }
    
    dlp.loc_infos = append(dlp.loc_infos, info)
}

func (dlp debug_loc_propagator*) propagate_locations(instr_ids i32[]) {
    for i := i32(0); i < i32(len(instr_ids)); i += 1 {
        if i == 0 {
            continue
        }
        
        instr_id := instr_ids[i]
        prev_instr_id := instr_ids[i - 1]
        
        prev_loc := source_location{}
        for info in dlp.loc_infos {
            if info.instr_id == prev_instr_id {
                prev_loc = info.loc
                break
            }
        }
        
        found := false
        for j in 0..i32(len(dlp.loc_infos)) {
            if dlp.loc_infos[j].instr_id == instr_id {
                found = true
                break
            }
        }
        
        if !found && (prev_loc.filename != "") {
            info := debug_loc_info{
                instr_id: instr_id,
                loc: prev_loc,
                var_name: "",
                scope: dlp.get_current_scope()
            }
            dlp.loc_infos = append(dlp.loc_infos, info)
        }
    }
}

func (dlp debug_loc_propagator*) get_location(instr_id i32) source_location {
    for info in dlp.loc_infos {
        if info.instr_id == instr_id {
            return info.loc
        }
    }
    source_location{}
}

func (debug_loc_propagator* dlp) get_locations_by_file(string filename) debug_loc_info[] {
    result := debug_loc_info[]()
    for info in dlp.loc_infos {
        if info.loc.filename == filename {
            result = append(result, info)
        }
    }
    result
}

func (dlp debug_loc_propagator*) get_locations_by_scope(scope string) debug_loc_info[] {
    result := debug_loc_info[]()
    for info in dlp.loc_infos {
        if info.scope == scope {
            result = append(result, info)
        }
    }
    result
}

func (dlp debug_loc_propagator*) get_location_info(instr_id i32) debug_loc_info {
    for info in dlp.loc_infos {
        if info.instr_id == instr_id {
            return info
        }
    }
    debug_loc_info{}
}

func (dlp debug_loc_propagator*) compute_line_maps() map[string]i32[] {
    line_map := make(map[string]i32[])
    
    for info in dlp.loc_infos {
        filename := info.loc.filename
        if line_map[filename] == nil {
            line_map[filename] = i32[]()
        }
    }
    
    line_map
}

func (dlp debug_loc_propagator*) emit_dwarf_debug_info() string {
    s := ".section .debug_info\n"
    
    for info in dlp.loc_infos {
        s += ".long " + string(info.instr_id) + "\n"
        s += ".string \"" + info.loc.filename + "\"\n"
        s += ".long " + string(info.loc.line) + "\n"
        s += ".long " + string(info.loc.column) + "\n"
    }
    
    s
}

func (dlp debug_loc_propagator*) to_string() string {
    s := "Debug Location Map:\n"
    for info in dlp.loc_infos {
        s += "  Instr[" + string(info.instr_id) + "]: "
        s += info.loc.filename + ":" + string(info.loc.line) + ":" + string(info.loc.column)
        if info.var_name != "" {
            s += " (var: " + info.var_name + ")"
        }
        s += " [scope: " + info.scope + "]\n"
    }
    s
}
