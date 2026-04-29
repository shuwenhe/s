package compile.internal.gc

use compile.internal.build.main as build_main
use std.vec.vec

struct compile_result {
    int status
    string report
}

func compile_package(vec[string] args) compile_result {
    let status = build_main(args)
    if status != 0 {
        return compile_result {
            status: status,
            report: "compile failed",
        }
    }

    let pkg = pick_pkgpath(args)
    let exported = vec[string]()
    exported.push("main")
    let export_payload = dump_export_data(pkg, exported)
    let obj_payload = dump_object_bundle(pkg, export_payload, "linker-objects", mode_compiler_obj() | mode_linker_obj())

    compile_result {
        status: 0,
        report: obj_payload,
    }
}

func enqueue_func(vec[string] queue, string fn_name) vec[string] {
    if fn_name == "" || fn_name == "_" {
        return queue
    }
    let out = vec[string]()
    let i = 0
    while i < queue.len() {
        out.push(queue[i])
        i = i + 1
    }
    out.push(fn_name)
    out
}

func prepare_func(string fn_name) string {
    if fn_name == "" {
        return "skip"
    }
    "prepared:" + fn_name
}

func compile_functions(vec[string] queue, int workers) string {
    let bounded_workers = clamp_backend_workers(workers)
    let out = "workers=" + to_string(bounded_workers) + "\n"
    let i = 0
    while i < queue.len() {
        out = out + prepare_func(queue[i]) + "\n"
        i = i + 1
    }
    out
}
