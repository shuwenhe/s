package compile.internal.source

use std.fs.fs
use std.prelude.prelude

struct test_result {
    string test_name
    bool passed
    string message
}

func run_tests() (test_result[], string) {
    results := test_result[]()
    
    t1 := test_three_normal_files()
    results.push(t1)
    
    t2 := test_second_file_missing()
    results.push(t2)
    
    t3 := test_first_file_parse_error()
    results.push(t3)
    
    t4 := test_duplicate_path()
    results.push(t4)
    
    t5 := test_multiple_runs()
    results.push(t5)
    
    results, ""
}

func test_three_normal_files() test_result {
    paths := string[]()
    paths.push("test_a.s")
    paths.push("test_b.s")
    paths.push("test_c.s")
    
    config := file_loader_config {
        max_concurrent: 2,
        enable_parallel: true
    }
    
    tasks, err := load_files_concurrent(paths, config)
    
    if err.message != "" {
        return test_result {
            test_name: "T1: Three normal files",
            passed: false,
            message: "load_files_concurrent failed: " + err.message
        }
    }
    
    if std.prelude.len(tasks) != 3 {
        return test_result {
            test_name: "T1: Three normal files",
            passed: false,
            message: "expected 3 tasks, got " + std.prelude.len(tasks)
        }
    }
    
    if tasks[0].path != "test_a.s" {
        return test_result {
            test_name: "T1: Three normal files",
            passed: false,
            message: "tasks[0].path != test_a.s, got " + tasks[0].path
        }
    }
    
    if tasks[1].path != "test_b.s" {
        return test_result {
            test_name: "T1: Three normal files",
            passed: false,
            message: "tasks[1].path != test_b.s, got " + tasks[1].path
        }
    }
    
    if tasks[2].path != "test_c.s" {
        return test_result {
            test_name: "T1: Three normal files",
            passed: false,
            message: "tasks[2].path != test_c.s, got " + tasks[2].path
        }
    }
    
    test_result {
        test_name: "T1: Three normal files",
        passed: true,
        message: "PASS: result order matches input order"
    }
}

func test_second_file_missing() test_result {
    paths := string[]()
    paths.push("test_a.s")
    paths.push("missing_file.s")
    paths.push("test_c.s")
    
    config := file_loader_config {
        max_concurrent: 2,
        enable_parallel: true
    }
    
    tasks, err := load_files_concurrent(paths, config)
    
    if err.message != "" {
        return test_result {
            test_name: "T2: Second file missing",
            passed: false,
            message: "load_files_concurrent failed: " + err.message
        }
    }
    
    if std.prelude.len(tasks) != 3 {
        return test_result {
            test_name: "T2: Second file missing",
            passed: false,
            message: "expected 3 tasks, got " + std.prelude.len(tasks)
        }
    }
    
    if tasks[0].path != "test_a.s" {
        return test_result {
            test_name: "T2: Second file missing",
            passed: false,
            message: "tasks[0].path != test_a.s"
        }
    }
    
    if tasks[1].path != "missing_file.s" {
        return test_result {
            test_name: "T2: Second file missing",
            passed: false,
            message: "tasks[1].path != missing_file.s"
        }
    }
    
    if tasks[2].path != "test_c.s" {
        return test_result {
            test_name: "T2: Second file missing",
            passed: false,
            message: "tasks[2].path != test_c.s"
        }
    }
    
    test_result {
        test_name: "T2: Second file missing",
        passed: true,
        message: "PASS: error indices correct, order maintained"
    }
}

func test_first_file_parse_error() test_result {
    paths := string[]()
    paths.push("error_file.s")
    paths.push("test_b.s")
    paths.push("test_c.s")
    
    config := file_loader_config {
        max_concurrent: 2,
        enable_parallel: true
    }
    
    tasks, err := load_files_concurrent(paths, config)
    
    if err.message != "" {
        return test_result {
            test_name: "T3: First file parse error",
            passed: false,
            message: "load_files_concurrent failed: " + err.message
        }
    }
    
    if std.prelude.len(tasks) != 3 {
        return test_result {
            test_name: "T3: First file parse error",
            passed: false,
            message: "expected 3 tasks"
        }
    }
    
    if tasks[0].path != "error_file.s" {
        return test_result {
            test_name: "T3: First file parse error",
            passed: false,
            message: "tasks[0].path != error_file.s"
        }
    }
    
    test_result {
        test_name: "T3: First file parse error",
        passed: true,
        message: "PASS: error position correct (index 0)"
    }
}

func test_duplicate_path() test_result {
    paths := string[]()
    paths.push("test_a.s")
    paths.push("test_a.s")
    paths.push("test_b.s")
    
    config := file_loader_config {
        max_concurrent: 2,
        enable_parallel: true
    }
    
    tasks, err := load_files_concurrent(paths, config)
    
    if err.message != "" {
        return test_result {
            test_name: "T4: Duplicate path",
            passed: false,
            message: "load_files_concurrent failed: " + err.message
        }
    }
    
    if std.prelude.len(tasks) != 3 {
        return test_result {
            test_name: "T4: Duplicate path",
            passed: false,
            message: "expected 3 tasks despite duplicate path"
        }
    }
    
    if tasks[0].path != "test_a.s" {
        return test_result {
            test_name: "T4: Duplicate path",
            passed: false,
            message: "tasks[0] incorrect"
        }
    }
    
    if tasks[1].path != "test_a.s" {
        return test_result {
            test_name: "T4: Duplicate path",
            passed: false,
            message: "tasks[1] incorrect"
        }
    }
    
    if tasks[2].path != "test_b.s" {
        return test_result {
            test_name: "T4: Duplicate path",
            passed: false,
            message: "tasks[2] incorrect"
        }
    }
    
    test_result {
        test_name: "T4: Duplicate path",
        passed: true,
        message: "PASS: no false positive duplicate detection"
    }
}

func test_multiple_runs() test_result {
    paths := string[]()
    paths.push("test_1.s")
    paths.push("test_2.s")
    paths.push("test_3.s")
    
    config := file_loader_config {
        max_concurrent: 2,
        enable_parallel: true
    }
    
    tasks_run1, err1 := load_files_concurrent(paths, config)
    
    if err1.message != "" {
        return test_result {
            test_name: "T5: Multiple runs",
            passed: false,
            message: "run 1 failed: " + err1.message
        }
    }
    
    tasks_run2, err2 := load_files_concurrent(paths, config)
    
    if err2.message != "" {
        return test_result {
            test_name: "T5: Multiple runs",
            passed: false,
            message: "run 2 failed: " + err2.message
        }
    }
    
    if std.prelude.len(tasks_run1) != std.prelude.len(tasks_run2) {
        return test_result {
            test_name: "T5: Multiple runs",
            passed: false,
            message: "run1 and run2 have different lengths"
        }
    }
    
    i := 0
    for i < std.prelude.len(tasks_run1) {
        if tasks_run1[i].path != tasks_run2[i].path {
            return test_result {
                test_name: "T5: Multiple runs",
                passed: false,
                message: "run1[" + i + "] != run2[" + i + "]"
            }
        }
        i = i + 1
    }
    
    test_result {
        test_name: "T5: Multiple runs",
        passed: true,
        message: "PASS: consistent ordering across runs"
    }
}
