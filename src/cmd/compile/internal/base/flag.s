package compile.internal.base
use std.slices
struct cmd_cfg {
    string[] import_dirs
    string[] import_map
    spectre_index bool
    instrumenting bool
}

struct cmd_flags {
    b int
    c int
    d string
    e int
    n int
    s int
    lower_c int
    lower_e int
    lower_h int
    lower_l int
    lower_m int
    lower_o string
    lower_p string
    lower_t bool
    complete bool
    dwarf bool
    race bool
    msan bool
    asan bool
    std bool
    compiling_runtime bool
    build_id string
    trim_path string
    go_version string
    lang string
    spectre string
    cfg cmd_cfg
}
flag := default_cmd_flags()

func default_cmd_flags() cmd_flags {
    cmd_flags {
        b: 0, c 0,
        d: "", e 0, n 0, s 0, lower_c 1, lower_e 0, lower_h 0, lower_l 0, lower_m 0,
        lower_o: "",
        lower_p: "", lower_t false, complete false, dwarf true, race false, msan false, asan false, std false, compiling_runtime false,
        build_id: "",
        trim_path: "",
        go_version: "",
        lang: "",
        spectre: "", cfg cmd_cfg {
            import_dirs: string[](), import_map string[](), spectre_index false, instrumenting false,
        },
    }
}

func add_import_dir(string path) () {
    if path == "" {
        return
    }
    flag.cfg.import_dirs = append(flag.cfg.import_dirs, path)
}

func parse_flags() cmd_flags {
    flag
}