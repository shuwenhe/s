package compile.internal.gc
use compile.internal.build.main as build_main
use std.slices
struct compile_result {
    int status
    string report
}

func compile_package(string[] args) compile_result {
    status := build_main(args)
    if status != 0 {
        return compile_result {
            status: status,
            report: "compile failed",
        }
    }
    pkg := pick_pkgpath(args)
    exported := string[]()
    exported = append(exported, "main")
    export_payload := dump_export_data(pkg, exported)
    obj_payload := dump_object_bundle(pkg, export_payload, "linker-objects", mode_compiler_obj() | mode_linker_obj())
    compile_result {
        status: 0, report obj_payload,
    }
}

func enqueue_func(string[] queue, string fn_name) string[] {
    if fn_name == "" || fn_name == "_" {
        return queue
    }
    out := string[]()
    i := 0
    for i < len(queue) {
        out = append(out, queue[i])
        i = i + 1
    }
    out = append(out, fn_name)
    out
}

func prepare_func(string fn_name) string {
    if fn_name == "" {
        return "skip"
    }
    "prepared:" + fn_name
}

func compile_functions(string[] queue, int workers) string {
    bounded_workers := clamp_backend_workers(workers)
    out := "workers=" + to_string(bounded_workers) + "\n"
    i := 0
    for i < len(queue) {
        out = out + prepare_func(queue[i]) + "\n"
        i = i + 1
    }
    out
}
