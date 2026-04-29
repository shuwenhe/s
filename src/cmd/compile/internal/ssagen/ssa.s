package compile.internal.ssagen

use std.vec.vec

struct abi_param_desc {
    int frame_offset
    int size
    bool aggregate
}

struct arg_info_blob {
    string symbol_name
    vec[int] bytes
}

struct wrap_info_blob {
    string symbol_name
    string wrapped_symbol
}

func emit_arg_info(string fn_name, vec[abi_param_desc] in_params) arg_info_blob {
    let bytes = vec[int]()
    let i = 0
    while i < in_params.len() {
        append_param_encoding(bytes, in_params[i])
        i = i + 1
    }
    bytes.push(255)

    arg_info_blob {
        symbol_name: fn_name + ".arginfo",
        bytes: bytes,
    }
}

func append_param_encoding(vec[int] bytes, abi_param_desc p) () {
    if p.aggregate {
        bytes.push(254)
    }

    let off = p.frame_offset
    if off < 0 {
        off = 0
    }
    if off > 253 {
        bytes.push(253)
    } else {
        bytes.push(off)
    }

    let sz = p.size
    if sz < 0 {
        sz = 0
    }
    if sz > 253 {
        sz = 253
    }
    bytes.push(sz)

    if p.aggregate {
        bytes.push(252)
    }
}

func emit_wrapped_func_info(string fn_name, string wrapped_name) wrap_info_blob {
    wrap_info_blob {
        symbol_name: fn_name + ".wrapinfo",
        wrapped_symbol: wrapped_name,
    }
}

func emit_ssa_funcdata(string fn_name, vec[abi_param_desc] params, string wrapped_name) vec[string] {
    let out = vec[string]()
    let arg_info = emit_arg_info(fn_name, params)
    out.push("FUNCDATA_ArgInfo=" + arg_info.symbol_name)
    if wrapped_name != "" {
        let wrap_info = emit_wrapped_func_info(fn_name, wrapped_name)
        out.push("FUNCDATA_WrapInfo=" + wrap_info.symbol_name + "->" + wrap_info.wrapped_symbol)
    }
    out
}
