package compile.internal.ssagen
import (
    "std"
)
struct abi_param_desc {
    int frame_offset
    int size
    bool aggregate
}

struct arg_info_blob {
    string symbol_name
    int[] bytes
}

struct wrap_info_blob {
    string symbol_name
    string wrapped_symbol
}

func emit_arg_info(string fn_name, abi_param_desc[] in_params) arg_info_blob {
    bytes := []int{}
    i := 0
    for i < len(in_params) {
        bytes = append_param_encoding(bytes, in_params[i])
        i = i + 1
    }
    bytes = append(bytes, 255)
    arg_info_blob {
        symbol_name: fn_name + ".arginfo", bytes bytes,
    }
}

func append_param_encoding(int[] bytes, abi_param_desc p) int[] {
    out := bytes
    if p.aggregate {
        out = append(out, 254)
    }
    off := p.frame_offset
    if off < 0 {
        off = 0
    }
    if off > 253 {
        out = append(out, 253)
    } else {
        out = append(out, off)
    }
    sz := p.size
    if sz < 0 {
        sz = 0
    }
    if sz > 253 {
        sz = 253
    }
    out = append(out, sz)
    if p.aggregate {
        out = append(out, 252)
    }
    out
}

func emit_wrapped_func_info(string fn_name, string wrapped_name) wrap_info_blob {
    wrap_info_blob {
        symbol_name: fn_name + ".wrapinfo", wrapped_symbol wrapped_name,
    }
}

func emit_ssa_funcdata(string fn_name, abi_param_desc[] params, string wrapped_name) string[] {
    out := []string{}
    arg_info := emit_arg_info(fn_name, params)
    out = append(out, "FUNCDATA_ArgInfo=" + arg_info.symbol_name)
    if wrapped_name != "" {
        wrap_info := emit_wrapped_func_info(fn_name, wrapped_name)
        out = append(out, "FUNCDATA_WrapInfo=" + wrap_info.symbol_name + "->" + wrap_info.wrapped_symbol)
    }
    out
}

func estimate_ssagen_plan_graph(string graph_text) int {
    blocks := count_ssagen_token(graph_text, "bb")
    terms := count_ssagen_token(graph_text, "term=")
    stmts := count_ssagen_token(graph_text, "stmts=")
    blocks + terms + stmts
}

func count_ssagen_token(string text, string token) int {
    if token == "" {
        return 0
    }
    count := 0
    i := 0
    limit := len(text) - len(token)
    for i <= limit {
        if slice(text, i, i + len(token)) == token {
            count = count + 1
            i = i + len(token)
        } else {
            i = i + 1
        }
    }
    count
}
