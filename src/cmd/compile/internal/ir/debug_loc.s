package compile.internal.ir.debug_loc

struct source_location {
    string file
    int line
    int column
    int end_line
    int end_column
}

struct debug_scope {
    int id
    int parent_scope
    string scope_name
    int start_instr
    int end_instr
    []int local_vars
    int line_start
    int line_end
}

struct debug_variable {
    int id
    string name
    string type_name
    int scope_id
    []int ssa_values
    source_location def_location
    []int use_locations
}

struct debug_info {
    debug_scope[] scopes
    debug_variable[] variables
    source_location[] instr_locations
    []int line_numbers
    []string file_names
    int num_instructions
}

func new_debug_info(int num_instructions) debug_info {
    debug_info {
        scopes: debug_scope[](),
        variables: debug_variable[](),
        instr_locations: new source_location[num_instructions],
        line_numbers: new int[num_instructions],
        file_names: []string(),
        num_instructions: num_instructions
    }
}

func (di* debug_info) add_scope(int id, int parent, string name, int start, int end) debug_scope {
    scope := debug_scope {
        id: id,
        parent_scope: parent,
        scope_name: name,
        start_instr: start,
        end_instr: end,
        local_vars: []int(),
        line_start: -1,
        line_end: -1
    }
    di.scopes.push(scope)
    scope
}

func (di* debug_info) add_variable(int id, string name, string type_name, int scope_id, source_location def_loc) debug_variable {
    var := debug_variable {
        id: id,
        name: name,
        type_name: type_name,
        scope_id: scope_id,
        ssa_values: []int(),
        def_location: def_loc,
        use_locations: []int()
    }
    di.variables.push(var)

    for i in 0..di.scopes.len() {
        if di.scopes[i].id == scope_id {
            di.scopes[i].local_vars.push(id)
            break
        }
    }

    var
}

func (di* debug_info) set_instr_location(int instr_id, source_location loc) {
    if instr_id < di.num_instructions {
        di.instr_locations[instr_id] = loc
        di.line_numbers[instr_id] = loc.line
    }
}

func (di* debug_info) add_file(string file_name) int {
    for i in 0..di.file_names.len() {
        if di.file_names[i] == file_name {
            return i
        }
    }
    di.file_names.push(file_name)
    di.file_names.len() - 1
}

func (di* debug_info) record_variable_use(int var_id, int instr_id) {
    for i in 0..di.variables.len() {
        if di.variables[i].id == var_id {
            di.variables[i].use_locations.push(instr_id)
            break
        }
    }
}

func (di* debug_info) add_ssa_value_to_var(int var_id, int ssa_value_id) {
    for i in 0..di.variables.len() {
        if di.variables[i].id == var_id {
            di.variables[i].ssa_values.push(ssa_value_id)
            break
        }
    }
}

func (di* debug_info) get_variable_at_location(int instr_id) debug_variable[] {
    result := debug_variable[]()
    for var in di.variables {
        for use_loc in var.use_locations {
            if use_loc == instr_id {
                result.push(var)
                break
            }
        }
    }
    result
}

func (di* debug_info) get_scope_variables(int scope_id) debug_variable[] {
    result := debug_variable[]()
    for var in di.variables {
        if var.scope_id == scope_id {
            result.push(var)
        }
    }
    result
}

func (di* debug_info) generate_line_number_table() []int {
    table := new int[di.num_instructions]
    for i in 0..di.num_instructions {
        table[i] = di.line_numbers[i]
    }
    table
}

func (di* debug_info) generate_location_info() []string {
    info := []string()
    for i in 0..di.num_instructions {
        if i < di.instr_locations.len() {
            loc := di.instr_locations[i]
            if loc.file != "" {
                entry := loc.file
                info.push(entry)
            }
        }
    }
    info
}

func (di* debug_info) get_instr_location(int instr_id) source_location {
    if instr_id < di.instr_locations.len() {
        return di.instr_locations[instr_id]
    }
    source_location { file: "", line: -1, column: -1, end_line: -1, end_column: -1 }
}

func (di* debug_info) compute_scope_lines() {
    for i in 0..di.scopes.len() {
        scope := &di.scopes[i]
        first_line := -1
        last_line := -1

        for instr_id in scope.start_instr..scope.end_instr {
            if instr_id < di.instr_locations.len() {
                line := di.instr_locations[instr_id].line
                if line != -1 {
                    if first_line == -1 {
                        first_line = line
                    }
                    last_line = line
                }
            }
        }

        scope.line_start = first_line
        scope.line_end = last_line
    }
}

func (di* debug_info) find_scope_for_instr(int instr_id) int {
    for scope in di.scopes {
        if instr_id >= scope.start_instr && instr_id <= scope.end_instr {
            return scope.id
        }
    }
    -1
}
