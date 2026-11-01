package compile.internal.source

struct file_load_task {
    string path
    string source
    source_file parsed
    parse_error parse_err
    int index
}

struct file_loader_config {
    int max_concurrent
    bool enable_parallel
}

func load_files(string[] paths) (file_load_task[], backend_error) {
    tasks := file_load_task[]()
    
    i := 0
    for i < std.prelude.len(paths) {
        path := paths[i]
        
        source_result := std.fs.read_file(path)
        
        if source_result.is_err() {
            return tasks, backend_error {
                message: "Failed to read file: " + path + " - " + source_result.unwrap_err().message
            }
        }
        
        source := source_result.unwrap()
        
        parsed_result := compile.internal.syntax.parse_source(source)
        
        parse_err := if parsed_result.is_err() {
            parsed_result.unwrap_err()
        } else {
            parse_error { message: "", line: 0, column: 0 }
        }
        
        parsed := if parsed_result.is_ok() {
            parsed_result.unwrap()
        } else {
            source_file {}
        }
        
        task := file_load_task {
            path: path,
            source: source,
            parsed: parsed,
            parse_err: parse_err,
            index: i
        }
        
        tasks.push(task)
        
        i = i + 1
    }
    
    tasks
}

func load_files_concurrent(string[] paths, file_loader_config config) (file_load_task[], backend_error) {
    if !config.enable_parallel {
        return load_files(paths)
    }
    
    max_concurrent := config.max_concurrent
    if max_concurrent <= 0 {
        max_concurrent = 4
    }
    
    sem := chan_make(max_concurrent)
    
    task_results := chan_make(std.prelude.len(paths))
    
    i := 0
    for i < std.prelude.len(paths) {
        path := paths[i]
        index := i
        
        chan_send(sem, true)
        
        sroutine {
            defer chan_recv(sem)
            
            source_result := std.fs.read_file(path)
            
            if source_result.is_err() {
                chan_send(task_results, file_load_task {
                    path: path,
                    index: index,
                    parse_err: parse_error {
                        message: "Failed: to read file: " + path,
                        line: 0,
                        column: 0
                    }
                })
                return
            }
            
            source := source_result.unwrap()
            
            parsed_result := compile.internal.syntax.parse_source(source)
            
            parse_err := if parsed_result.is_err() {
                parsed_result.unwrap_err()
            } else {
                parse_error { message: "", line: 0, column: 0 }
            }
            
            parsed := if parsed_result.is_ok() {
                parsed_result.unwrap()
            } else {
                source_file {}
            }
            
            chan_send(task_results, file_load_task {
                path: path,
                source: source,
                parsed: parsed,
                parse_err: parse_err,
                index: index
            })
        }
        
        i = i + 1
    }
    
    all_tasks := file_load_task[]()
    
    j := 0
    for j < std.prelude.len(paths) {
        task := chan_recv(task_results)
        all_tasks.push(task)
        j = j + 1
    }
    
    chan_close(sem)
    chan_close(task_results)
    
    seen := bool[std.prelude.len(paths)]()
    loop_var_2 := 0
    for loop_var_2 < std.prelude.len(seen) {
        seen[loop_var_2] = false
        loop_var_2 = loop_var_2 + 1
    }
    
    sorted_tasks := file_load_task[std.prelude.len(paths)]()
    
    loop_var_3 := 0
    for loop_var_3 < std.prelude.len(all_tasks) {
        task := all_tasks[loop_var_3]
        
        if task.index < 0 || task.index >= std.prelude.len(paths) {
            return file_load_task[](), backend_error {
                message: "task index out of range: " + task.index
            }
        }
        
        if seen[task.index] {
            return file_load_task[](), backend_error {
                message: "duplicate result for index: " + task.index
            }
        }
        
        seen[task.index] = true
        sorted_tasks[task.index] = task
        
        loop_var_3 = loop_var_3 + 1
    }
    
    loop_var_4 := 0
    for loop_var_4 < std.prelude.len(seen) {
        if !seen[loop_var_4] {
            return file_load_task[](), backend_error {
                message: "missing result for index: " + loop_var_4
            }
        }
        loop_var_4 = loop_var_4 + 1
    }
    
    result_tasks := file_load_task[]()
    loop_var_5 := 0
    for loop_var_5 < std.prelude.len(sorted_tasks) {
        result_tasks.push(sorted_tasks[loop_var_5])
        loop_var_5 = loop_var_5 + 1
    }
    
    result_tasks
}

func has_parse_error(file_load_task task) bool {
    task.parse_err.message != ""
}

func get_failed_files(file_load_task[] tasks) (string[], backend_error) {
    failed := string[]()
    
    i := 0
    for i < std.prelude.len(tasks) {
        if has_parse_error(tasks[i]) {
            failed.push(tasks[i].path)
        }
        i = i + 1
    }
    
    failed
}

func get_successful_files(file_load_task[] tasks) (file_load_task[], backend_error) {
    successful := file_load_task[]()
    
    i := 0
    for i < std.prelude.len(tasks) {
        if !has_parse_error(tasks[i]) {
            successful.push(tasks[i])
        }
        i = i + 1
    }
    
    successful
}

func collect_parse_errors(file_load_task[] tasks) (parse_error[], backend_error) {
    errors := parse_error[]()
    
    i := 0
    for i < std.prelude.len(tasks) {
        if has_parse_error(tasks[i]) {
            errors.push(tasks[i].parse_err)
        }
        i = i + 1
    }
    
    errors
}
