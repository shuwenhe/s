package compile.internal.base

use std.vec.vec

struct cmd_cfg {
    vec[string] import_dirs
    vec[string] import_map
    bool spectre_index
    bool instrumenting
}

struct cmd_flags {
    int b
    int c
    string d
    int e
    int n
    int s
    int lower_c
    int lower_e
    int lower_h
    int lower_l
    int lower_m
    string lower_o
    string lower_p
    bool lower_t
    bool complete
    bool dwarf
    bool race
    bool msan
    bool asan
    bool std
    bool compiling_runtime
    string build_id
    string trim_path
    string go_version
    string lang
    string spectre
    cmd_cfg cfg
}

var flag = default_cmd_flags()

func default_cmd_flags() cmd_flags {
    cmd_flags {
        b: 0,
        c: 0,
        d: "",
        e: 0,
        n: 0,
        s: 0,
        lower_c: 1,
        lower_e: 0,
        lower_h: 0,
        lower_l: 0,
        lower_m: 0,
        lower_o: "",
        lower_p: "",
        lower_t: false,
        complete: false,
        dwarf: true,
        race: false,
        msan: false,
        asan: false,
        std: false,
        compiling_runtime: false,
        build_id: "",
        trim_path: "",
        go_version: "",
        lang: "",
        spectre: "",
        cfg: cmd_cfg {
            import_dirs: vec[string](),
            import_map: vec[string](),
            spectre_index: false,
            instrumenting: false,
        },
    }
}

func add_import_dir(string path) () {
    if path == "" {
        return
    }
    flag.cfg.import_dirs.push(path)
}

func parse_flags() cmd_flags {
    flag
}
