package compile.internal.noder

import (
    "compile.internal.base"
    "compile.internal.ir"
    "compile.internal.syntax"
    "compile.internal.types"
    "compile.internal.typecheck"
    "std.io"
    "std.result"
    "std.strings"
    "std.regexp"
    "std.os"
)

struct type_check_info {
    vec[string] definitions
    vec[string] uses
    vec[string] scopes
    vec[string] selections
    vec[string] instances
    vec[string] file_versions
    vec[string] errors
}

struct type_check_config {
    string lang_version
    bool ignore_branch_errors
    bool store_types_in_syntax
    bool error_url
}

struct cycle_finder {
    vec[string] cyclic_types
}

struct ir_gen_result {
    ir.package pkg
    type_check_info info
}

func check_files(vec[file_parse_result] parsed_files) result[ir_gen_result, string] {
    base.timer_start("fe", "typecheck")
    
    if count_syntax_errors() > 0 {
        return result.err("syntax errors found")
    }
    
    conf := type_check_config {
        lang_version: "1.0",
        ignore_branch_errors: true,
        store_types_in_syntax: true,
        error_url: false,
    }
    
    info := type_check_info {
        definitions: vec[string](),
        uses: vec[string](),
        scopes: vec[string](),
        selections: vec[string](),
        instances: vec[string](),
        file_versions: vec[string](),
        errors: vec[string](),
    }
    
    pkg := typecheck.new_package()
    
    for parsed in parsed_files {
        result := check_file(parsed.file, conf, &info, pkg)
        
        switch result {
            result.ok() : {}
            result.err(msg) : {
                info.errors.push(msg)
            }
        }
    }
    
    if info.errors.len() > 0 {
        error_msg := format_type_errors(info.errors)
        return result.err(error_msg)
    }
    
    base.timer_add_event(info.definitions.len() + info.uses.len(), "type-info-items")
    
    result.ok(ir_gen_result {
        pkg: pkg,
        info: info,
    })
}

func check_file(syntax.file f, type_check_config conf, &type_check_info info, ir.package pkg) result[void, string] {
    decls := syntax.file_decls(f)
    
    for decl in decls {
        result := check_decl(decl, conf, info, pkg)
        
        switch result {
            result.ok() : {}
            result.err(msg) : {
                return result.err(msg)
            }
        }
    }
    
    result.ok()
}

func check_decl(syntax.decl d, type_check_config conf, type_check_info info, ir.package pkg) result[void, string] {
    decl_type := syntax.decl_type(d)
    
    switch decl_type {
        "func" : {
            func_decl := syntax.as_func_decl(d)
            func_name := syntax.func_name(func_decl)
            func_type := syntax.func_type(func_decl)
            
            resolved_type := resolve_type(func_type, conf, info)?
            
            ir_func := ir.new_func(func_name, resolved_type)
            pkg.add_func(ir_func)
            
            info.definitions.push(func_name)
        }
        
        "type" : {
            type_decl := syntax.as_type_decl(d)
            type_name := syntax.type_name(type_decl)
            type_spec := syntax.type_spec(type_decl)
            
            resolved_type := resolve_type(type_spec, conf, info)?
            
            ir_type := ir.new_type(type_name, resolved_type)
            pkg.add_type(ir_type)
            
            info.definitions.push(type_name)
        }
        
        "var" : {
            var_decl := syntax.as_var_decl(d)
            var_names := syntax.var_names(var_decl)
            var_type := syntax.var_type(var_decl)
            
            resolved_type := resolve_type(var_type, conf, info)?
            
            for name in var_names {
                ir_var := ir.new_var(name, resolved_type)
                pkg.add_var(ir_var)
                info.definitions.push(name)
            }
        }
        
        "const" : {
            const_decl := syntax.as_const_decl(d)
            const_names := syntax.const_names(const_decl)
            const_type := syntax.const_type(const_decl)
            const_values := syntax.const_values(const_decl)
            
            resolved_type := resolve_type(const_type, conf, info)?
            
            for i in 0..const_names.len() {
                ir_const := ir.new_const(
                    const_names[i],
                    resolved_type,
                    const_values[i]
                )
                pkg.add_const(ir_const)
                info.definitions.push(const_names[i])
            }
        }
        
        default : {
            return result.err("unknown declaration type: " + decl_type)
        }
    }
    
    result.ok()
}

func resolve_type(syntax.type_expr t, type_check_config conf, type_check_info info) result[types.type_obj, string] {
    type_kind := syntax.type_kind(t)
    
    switch type_kind {
        "basic" : {
            basic_name := syntax.basic_type_name(t)
            return result.ok(types.new_basic_type(basic_name))
        }
        
        "pointer" : {
            elem_type := syntax.ptr_elem_type(t)
            resolved := resolve_type(elem_type, conf, info)?
            return result.ok(types.new_pointer_type(resolved))
        }
        
        "array" : {
            len_expr := syntax.array_len(t)
            elem_type := syntax.array_elem_type(t)
            
            len_val := eval_const_expr(len_expr)?
            resolved_elem := resolve_type(elem_type, conf, info)?
            
            return result.ok(types.new_array_type(len_val, resolved_elem))
        }
        
        "slice" : {
            elem_type := syntax.slice_elem_type(t)
            resolved_elem := resolve_type(elem_type, conf, info)?
            return result.ok(types.new_slice_type(resolved_elem))
        }
        
        "map" : {
            key_type := syntax.map_key_type(t)
            val_type := syntax.map_val_type(t)
            
            resolved_key := resolve_type(key_type, conf, info)?
            resolved_val := resolve_type(val_type, conf, info)?
            
            return result.ok(types.new_map_type(resolved_key, resolved_val))
        }
        
        "named" : {
            named_type_name := syntax.named_type_name(t)
            return result.ok(types.lookup_type(named_type_name))
        }
        
        "struct" : {
            fields := vec[types.struct_field]()
            
            decls := syntax.struct_decls(t)
            for decl in decls {
                field_name := syntax.field_name(decl)
                field_type := syntax.field_type(decl)
                
                resolved_field_type := resolve_type(field_type, conf, info)?
                
                fields.push(types.struct_field {
                    name: field_name,
                    typ: resolved_field_type,
                })
            }
            
            return result.ok(types.new_struct_type(fields))
        }
        
        "interface" : {
            methods := vec[types.interface_method]()
            
            decls := syntax.interface_decls(t)
            for decl in decls {
                method_name := syntax.method_name(decl)
                method_sig := syntax.method_sig(decl)
                
                resolved_sig := resolve_type(method_sig, conf, info)?
                
                methods.push(types.interface_method {
                    name: method_name,
                    sig: resolved_sig,
                })
            }
            
            return result.ok(types.new_interface_type(methods))
        }
        
        default : {
            return result.err("unknown type kind: " + type_kind)
        }
    }
}

func eval_const_expr(syntax.expr e) result[int, string] {
    expr_type := syntax.expr_type(e)
    
    switch expr_type {
        "int_lit" : {
            val := syntax.int_value(e)
            return result.ok(val)
        }
        
        "ident" : {
            name := syntax.ident_name(e)
            val := types.lookup_const_value(name)?
            return result.ok(val)
        }
        
        default : {
            return result.err("cannot evaluate non-constant expression")
        }
    }
}

func check_interface_cycles(type_check_info info) result[void, string] {
    finder := cycle_finder {
        cyclic_types: vec[string](),
    }
    
    for interface_type in info.definitions {
        if is_interface_type(interface_type) {
            if find_cycle_in_interface(&finder, interface_type) {
                return result.err("invalid recursive type: interface cycle detected")
            }
        }
    }
    
    result.ok()
}

func find_cycle_in_interface(finder: &cycle_finder, typ: string) bool {
    if contains_string(finder.cyclic_types, typ) {
        return true
    }
    
    finder.cyclic_types.push(typ)
    
    false
}

func is_interface_type(string typ) bool {
    strings.contains(typ, "interface")
}

func contains_string(vec[string] list, string item) bool {
    for s in list {
        if s == item {
            return true
        }
    }
    false
}

func count_syntax_errors() int {
    0
}

func format_type_errors(vec[string] errors) string {
    msg := strings.new_builder()
    
    for err in errors {
        msg.write_string("type error: ")
        msg.write_string(err)
        msg.write_string("\n")
    }
    
    msg.to_string()
}

func dump_syntax_debug(ir.package pkg, type_check_info info, string phase) result[void, string] {
    base.timer_start("fe", "dump")
    
    funcs := pkg.funcs()
    for func in funcs {
        func_name := ir.func_name(func)
        if base.debug_enabled("ast-dump") {
            base.log_debug("AST dump [" + phase + "]: " + func_name)
        }
    }
    
    result.ok()
}

func lower_to_ir(syntax.file ast) result[vec[ir.node], string] {
    out := vec[ir.node]()
    
    decls := syntax.file_decls(ast)
    for decl in decls {
        decl_type := syntax.decl_type(decl)
        
        switch decl_type {
            "func" : {
                func_decl := syntax.as_func_decl(decl)
                func_name := syntax.func_name(func_decl)
                
                node := ir.new_node("fn", func_name)
                out.push(node)
            }
            
            "type" : {
                type_decl := syntax.as_type_decl(decl)
                type_name := syntax.type_name(type_decl)
                
                node := ir.new_node("type", type_name)
                out.push(node)
            }
            
            "var" : {
                var_decl := syntax.as_var_decl(decl)
                var_names := syntax.var_names(var_decl)
                
                for name in var_names {
                    node := ir.new_node("var", name)
                    out.push(node)
                }
            }
            
            "const" : {
                const_decl := syntax.as_const_decl(decl)
                const_names := syntax.const_names(const_decl)
                
                for name in const_names {
                    node := ir.new_node("const", name)
                    out.push(node)
                }
            }
            
            default : {}
        }
    }
    
    result.ok(out)
}
