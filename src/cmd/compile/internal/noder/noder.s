package compile.internal.noder

import (
    "compile.internal.base"
    "compile.internal.ir"
    "compile.internal.syntax"
    "compile.internal.typecheck"
    "compile.internal.types"
    "std.io"
    "std.result"
    "std.os"
    "std.strings"
    "std.sync"
)

struct file_parse_result {
    syntax.file file
    vec[string] errors
}

struct noder {
    vec[file_parse_result] files
    vec[syntax.linkname] linknames
    sync.mutex parse_mu
}

struct noder_output {
    ir.package pkg
    vec[string] exports
}

struct parse_error {
    int line
    int column
    string message
    string filename
}

func load_package(vec[string] filenames) result[noder_output, string] {
    base.timer_start("fe", "parse")
    
    noder_inst := noder {
        files: vec[file_parse_result](),
        linknames: vec[syntax.linkname](),
    }
    
    total_lines := 0
    errors_found := vec[parse_error]()
    
    for filename in filenames {
        result := parse_file(filename)
        
        switch result {
            result::ok(parsed) : {
                noder_inst.files.push(parsed)
                total_lines = total_lines + count_lines(parsed.file)
            }
            result::err(err_msg) : {
                errors_found.push(parse_error {
                    line: 0,
                    column: 0,
                    message: err_msg,
                    filename: filename,
                })
            }
        }
    }
    
    if errors_found.len() > 0 {
        return result::err(format_errors(errors_found))
    }
    
    base.timer_add_event(total_lines, "lines")
    
    unified_result := run_unified(noder_inst)
    
    switch unified_result {
        result::ok(output) : {
            return result::ok(output)
        }
        result::err(err) : {
            return result::err(err)
        }
    }
}

func parse_file(string filename) result[file_parse_result, string] {
    file_content := os.read_file(filename)?
    
    fbase := syntax.new_file_base(filename)
    parse_result := syntax.parse(fbase, file_content)?
    
    result::ok(file_parse_result {
        file: parse_result,
        errors: vec[string](),
    })
}

func count_lines(syntax.file f) int {
    line_count := 0
    i := 0
    content := syntax.file_content(f)
    
    for i < content.len() {
        if content[i] == '\n' {
            line_count = line_count + 1
        }
        i = i + 1
    }
    
    line_count
}

func run_unified(noder inst) result[noder_output, string] {
    pkg := typecheck.new_package()
    
    for parsed in inst.files {
        process_file(pkg, parsed.file)?
    }
    
    exports := collect_exports(pkg)
    
    result::ok(noder_output {
        pkg: pkg,
        exports: exports,
    })
}

func process_file(ir.package pkg, syntax.file f) result[void, string] {
    for decl in syntax.file_decls(f) {
        convert_decl(pkg, decl)?
    }
    
    result::ok()
}

func convert_decl(ir.package pkg, syntax.decl decl) result[void, string] {
    switch syntax.decl_type(decl) {
        "funcDecl" : {
            func_decl := syntax.as_func_decl(decl)
            ir_func := ir.new_func(
                syntax.func_name(func_decl),
                syntax.func_recv(func_decl),
                syntax.func_type(func_decl),
            )
            pkg.add_func(ir_func)
        }
        "typeDecl" : {
            type_decl := syntax.as_type_decl(decl)
            ir_type := ir.new_type(
                syntax.type_name(type_decl),
                syntax.type_spec(type_decl),
            )
            pkg.add_type(ir_type)
        }
        "varDecl" : {
            var_decl := syntax.as_var_decl(decl)
            ir_var := ir.new_var(
                syntax.var_names(var_decl),
                syntax.var_type(var_decl),
            )
            pkg.add_var(ir_var)
        }
        "constDecl" : {
            const_decl := syntax.as_const_decl(decl)
            ir_const := ir.new_const(
                syntax.const_names(const_decl),
                syntax.const_type(const_decl),
                syntax.const_values(const_decl),
            )
            pkg.add_const(ir_const)
        }
        default : {
            result::err("unknown declaration type")
            return
        }
    }
    
    result::ok()
}

func collect_exports(ir.package pkg) vec[string] {
    exports := vec[string]()
    
    for func in pkg.funcs() {
        if ir.is_exported(func) {
            exports.push(ir.func_name(func))
        }
    }
    
    for typ in pkg.types() {
        if ir.is_exported(typ) {
            exports.push(ir.type_name(typ))
        }
    }
    
    for var in pkg.vars() {
        if ir.is_exported(var) {
            exports.push(ir.var_name(var))
        }
    }
    
    exports
}

func trim_filename(syntax.pos_base base) string {
    filename := syntax.pos_base_filename(base)
    
    if !syntax.pos_base_trimmed(base) {
        filename = normalize_path(filename)
    }
    
    filename
}

func normalize_path(string path) string {
    path
}

func format_errors(vec[parse_error] errors) string {
    msg := strings.new_builder()
    
    for err in errors {
        msg.write_string(err.filename)
        msg.write_string(":")
        msg.write_int(err.line)
        msg.write_string(":")
        msg.write_int(err.column)
        msg.write_string(": ")
        msg.write_string(err.message)
        msg.write_string("\n")
    }
    
    msg.to_string()
}

func compile_unit(string source_path, string export_out, string ir_out, string link_out) result[noder_output, string] {
    quirks := vec[string]()
    quirks.push("normalize-import-quotes")
    
    filenames := vec[string]()
    filenames.push(source_path)
    
    output := load_package(filenames)?
    
    write_export_file(export_out, output.exports)?
    write_ir_file(ir_out, output.pkg)?
    
    links := build_link_symbols(output.pkg, output.exports)
    write_link_file(link_out, links)?
    
    result::ok(output)
}

func compile_unit_default_paths(string source_path) result[noder_output, string] {
    compile_unit(
        source_path,
        source_path + ".export",
        source_path + ".ir",
        source_path + ".link"
    )
}

func write_export_file(string path, vec[string] exports) result[void, string] {
    content := strings.new_builder()
    
    for export in exports {
        content.write_string(export)
        content.write_string("\n")
    }
    
    os.write_file(path, content.to_string())?
    result::ok()
}

func write_ir_file(string path, ir.package pkg) result[void, string] {
    content := ir.emit_ir(pkg)
    os.write_file(path, content)?
    result::ok()
}

func build_link_symbols(ir.package pkg, vec[string] exports) vec[string] {
    links := vec[string]()
    
    for export in exports {
        symbol := strings.new_builder()
        symbol.write_string("_")
        symbol.write_string(export)
        links.push(symbol.to_string())
    }
    
    links
}

func write_link_file(string path, vec[string] links) result[void, string] {
    content := strings.new_builder()
    
    for link in links {
        content.write_string(link)
        content.write_string("\n")
    }
    
    os.write_file(path, content.to_string())?
    result::ok()
}
