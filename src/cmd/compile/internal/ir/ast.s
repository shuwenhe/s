package compile.internal.ir.ast

use std.vec.vec
use compile.internal.ir.types

struct program_ir {
    string package_name
    vec[package_ir] packages
}

struct package_ir {
    string name
    vec[decl_ir] decls
}

enum decl_ir {
    func(func_decl),
    r#type(type_decl),
    var(var_decl),
    const(const_decl),
    impl(impl_decl),
}

struct func_decl {
    string name
    func_sig sig
    option[block_ir] body
}

struct func_sig {
    vec[param] params
    option[string] return_type_name
    vec[string] generics
}

struct param { string name, string type_name }

struct type_decl { string name, string type_expr }

struct var_decl { string name, string type_name, option[string] init }

struct const_decl { string name, string value }

struct impl_decl { string type_name, vec[func_decl] methods }

struct block_ir { vec[stmt_ir] statements, option[expr_ir] final_expr }

enum stmt_ir {
    var(var_stmt),
    assign(assign_stmt),
    increment(increment_stmt),
    cfor(c_for_stmt),
    expr(expr_stmt),
    r#return(return_stmt),
}

struct var_stmt { string name, option[string] type_name, expr_ir value }
struct assign_stmt { string name, expr_ir value }
struct increment_stmt { string name }
struct c_for_stmt { stmt_ir init, expr_ir condition, stmt_ir step, block_ir body }
struct expr_stmt { expr_ir expr }
struct return_stmt { option[expr_ir] value }

enum expr_ir {
    int(int),
    string(string),
    bool(bool),
    name(string),
    binary(binary_expr),
    call(call_expr),
    borrow(borrow_expr),
    member(member_expr),
    index(index_expr),
    array(array_expr),
    map(map_expr),
    block(block_ir),
}

struct binary_expr { string op, expr_ir left, expr_ir right }
struct call_expr { string callee, vec[expr_ir] args }
struct borrow_expr { expr_ir target, bool mutable }
struct member_expr { expr_ir target, string member }
struct index_expr { expr_ir target, expr_ir index }
struct array_expr { option[string] type_name, vec[expr_ir] items }
struct map_entry_expr { expr_ir key, expr_ir value }
struct map_expr { option[string] type_name, vec[map_entry_expr] entries }

func make_empty_package(string name) package_ir {
    package_ir { name: name, decls: vec[decl_ir]() }
}
