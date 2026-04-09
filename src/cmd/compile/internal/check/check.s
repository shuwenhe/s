package compile.internal.check

use compile.internal.syntax.ParseTokens
use compile.internal.syntax.ReadSource
use compile.internal.syntax.SyntaxError
use compile.internal.syntax.Tokenize
use s.AssignStmt
use s.BlockExpr
use s.BinaryExpr
use s.CallExpr
use s.CForStmt
use s.DeferStmt
use s.Expr
use s.FunctionDecl
use s.FunctionSig
use s.ImplDecl
use s.Item
use s.Param
use s.ReturnStmt
use s.SourceFile
use s.StructDecl
use s.TraitDecl
use s.Token
use s.VarStmt
use std.option.Option
use std.prelude.to_string
use std.result.Result
use std.vec.Vec

struct CliError {
    String message,
}

struct FrontendResult {
    String source,
    Vec[Token] tokens,
    SourceFile ast,
}

struct LocalVar {
    String name,
    String type_name,
}

struct FunctionInfo {
    String name,
    FunctionSig sig,
}

struct FieldInfo {
    String name,
    String type_name,
}

struct StructInfo {
    String name,
    Vec[FieldInfo] fields,
}

struct TypeEnv {
    Vec[FunctionInfo] functions,
    Vec[StructInfo] structs,
}

struct FunctionContext {
    Vec[LocalVar] locals,
    Option[String] return_type,
}

func LoadFrontend(String path) Result[FrontendResult, CliError] {
    var source = read_source(path)?
    var tokens = tokenize_source(source)?
    var ast = parse_tokens_text(tokens)?
    Result::Ok(FrontendResult {
        source: source,
        tokens: tokens,
        ast: ast,
    })
}

func CheckFrontend(FrontendResult frontend) Result[(), CliError] {
    if frontend.ast.package == "" {
        return Result::Err(CliError {
            message: "missing package declaration",
        })
    }

    var env = build_type_env(frontend.ast.items)?

    for item in frontend.ast.items {
        match item {
            Item::Function(func) => check_function(func, env)?,
            Item::Struct(strct) => check_struct(strct)?,
            Item::Trait(trait_decl) => check_trait(trait_decl)?,
            Item::Impl(impl_decl) => check_impl(impl_decl, env)?,
        }
    }

    Result::Ok(())
}

func build_type_env(Vec[Item] items) Result[TypeEnv, CliError] {
    var env = TypeEnv {
        functions: Vec[FunctionInfo](),
        structs: Vec[StructInfo](),
    }

    for item in items {
        match item {
            Item::Function(func) => env = register_function(env, func)?,
            Item::Struct(strct) => env = register_struct(env, strct)?,
            _ => (),
        }
    }

    Result::Ok(env)
}

func register_function(TypeEnv env, FunctionDecl func) Result[TypeEnv, CliError] {
    if find_function(env, func.sig.name).is_some() {
        return Result::Err(cli_error("duplicate function: " + func.sig.name))
    }

    ensure_params_have_types(func.sig.params)?

    env.functions.push(FunctionInfo {
        name: func.sig.name,
        sig: func.sig,
    })
    Result::Ok(env)
}

func register_struct(TypeEnv env, StructDecl decl) Result[TypeEnv, CliError] {
    if find_struct(env, decl.name).is_some() {
        return Result::Err(cli_error("duplicate struct: " + decl.name))
    }

    var fields = Vec[FieldInfo]()
    for field in decl.fields {
        if field.type_name == "" {
            return Result::Err(cli_error("field " + field.name + " missing type"))
        }
        if field_name_exists(fields, field.name) {
            return Result::Err(cli_error("duplicate field " + field.name + " in " + decl.name))
        }
        fields.push(FieldInfo {
            name: field.name,
            type_name: normalize_type(field.type_name),
        })
    }

    env.structs.push(StructInfo {
        name: decl.name,
        fields: fields,
    })
    Result::Ok(env)
}

func ensure_params_have_types(Vec[Param] params) Result[(), CliError] {
    for param in params {
        if param.type_name == "" {
            return Result::Err(cli_error("missing type for parameter " + param.name))
        }
    }
    Result::Ok(())
}

func check_struct(StructDecl decl) Result[(), CliError] {
    var seen = Vec[String]()
    for field in decl.fields {
        if field.type_name == "" {
            return Result::Err(cli_error("field " + field.name + " missing type"))
        }
        if contains_string(seen, field.name) {
            return Result::Err(cli_error("duplicate field " + field.name + " in " + decl.name))
        }
        seen.push(field.name)
    }
    Result::Ok(())
}

func check_trait(TraitDecl decl) Result[(), CliError] {
    var seen = Vec[String]()
    for method in decl.methods {
        ensure_params_have_types(method.params)?
        if contains_string(seen, method.name) {
            return Result::Err(cli_error("duplicate trait method: " + method.name))
        }
        seen.push(method.name)
    }
    Result::Ok(())
}

func check_impl(ImplDecl decl, TypeEnv env) Result[(), CliError] {
    if find_struct(env, decl.target).is_none() {
        return Result::Err(cli_error("impl target not found: " + decl.target))
    }

    var seen = Vec[String]()
    for method in decl.methods {
        if contains_string(seen, method.sig.name) {
            return Result::Err(cli_error("duplicate method in impl: " + method.sig.name))
        }
        seen.push(method.sig.name)
        check_function(method, env)?
    }
    Result::Ok(())
}

func check_function(FunctionDecl decl, TypeEnv env) Result[(), CliError] {
    var ctx = FunctionContext {
        locals: Vec[LocalVar](),
        return_type: decl.sig.return_type,
    }

    for param in decl.sig.params {
        var ty = normalize_type(param.type_name)
        add_local(mut ctx, LocalVar {
            name: param.name,
            type_name: ty,
        })?
    }

    match decl.body {
        Option::Some(body) => check_block(body, mut ctx, env)?,
        Option::None => (),
    }

    Result::Ok(())
}

func check_block(BlockExpr block, mut FunctionContext ctx, TypeEnv env) Result[(), CliError] {
    for stmt in block.statements {
        check_stmt(stmt, mut ctx, env)?
    }
    match block.final_expr {
        Option::Some(expr) => {
            infer_expr_type(expr, ctx, env)?
        }
        Option::None => (),
    }
    Result::Ok(())
}

func check_stmt(Stmt stmt, mut FunctionContext ctx, TypeEnv env) Result[(), CliError] {
    match stmt {
        Stmt::Var(value) => check_var_stmt(value, mut ctx, env)?,
        Stmt::Assign(value) => check_assign_stmt(value, ctx, env)?,
        Stmt::Increment(value) => check_increment_stmt(value, ctx)?,
        Stmt::CFor(value) => {
            check_stmt(*value.init, mut ctx, env)?
            var cond_type = infer_expr_type(value.condition, ctx, env)?
            if cond_type != "bool" {
                return Result::Err(cli_error("for condition must be bool"))
            }
            check_stmt(*value.step, mut ctx, env)?
            check_block(value.body, mut ctx, env)?
        }
        Stmt::Return(value) => check_return_stmt(value, ctx, env)?,
        Stmt::Expr(value) => {
            infer_expr_type(value.expr, ctx, env)?
        }
        Stmt::Defer(value) => {
            infer_expr_type(value.expr, ctx, env)?
        }
    }
    Result::Ok(())
}

func check_var_stmt(VarStmt stmt, mut FunctionContext ctx, TypeEnv env) Result[(), CliError] {
    var inferred = infer_expr_type(stmt.value, ctx, env)?
    var ty =
        match stmt.type_name {
            Option::Some(name) => normalize_type(name),
            Option::None => inferred,
        }
    if ty == "" {
        return Result::Err(cli_error("unable to infer type for " + stmt.name))
    }
    if ty != inferred {
        return Result::Err(cli_error("type mismatch in var " + stmt.name))
    }
        add_local(mut ctx, LocalVar {
            name: stmt.name,
            type_name: ty,
        })?
    Result::Ok(())
}

func check_assign_stmt(AssignStmt stmt, FunctionContext ctx, TypeEnv env) Result[(), CliError] {
    var var_type =
        match find_local(ctx, stmt.name) {
            Option::Some(value) => value,
            Option::None => return Result::Err(cli_error("assignment to unknown variable: " + stmt.name)),
        }
    var expr_type = infer_expr_type(stmt.value, ctx, env)?
    if var_type != expr_type {
        return Result::Err(cli_error("type mismatch in assignment to " + stmt.name))
    }
    Result::Ok(())
}

func check_increment_stmt(IncrementStmt stmt, FunctionContext ctx) Result[(), CliError] {
    var var_type =
        match find_local(ctx, stmt.name) {
            Option::Some(value) => value,
            Option::None => return Result::Err(cli_error("increment of unknown variable: " + stmt.name)),
        }
    if var_type != "int" {
        return Result::Err(cli_error("increment requires int variable: " + stmt.name))
    }
    Result::Ok(())
}

func check_return_stmt(ReturnStmt stmt, FunctionContext ctx, TypeEnv env) Result[(), CliError] {
    match stmt.value {
        Option::Some(expr) => {
            var expr_type = infer_expr_type(expr, ctx, env)?
            match ctx.return_type {
                Option::Some(ret) => {
                    if normalize_type(ret) != expr_type {
                        return Result::Err(cli_error("return type mismatch"))
                    }
                }
                Option::None => return Result::Err(cli_error("unexpected return value")),
            }
        }
        Option::None => {
            if ctx.return_type.is_some() {
                return Result::Err(cli_error("missing return value"))
            }
        }
    }
    Result::Ok(())
}

func infer_expr_type(Expr expr, FunctionContext ctx, TypeEnv env) Result[String, CliError] {
    match expr {
        Expr::Int(_) => Result::Ok("int"),
        Expr::String(_) => Result::Ok("str"),
        Expr::Bool(_) => Result::Ok("bool"),
        Expr::Name(value) =>
            match find_local(ctx, value.name) {
                Option::Some(ty) => Result::Ok(ty),
                Option::None => Result::Err(cli_error("unknown identifier: " + value.name)),
            },
        Expr::Binary(value) => infer_binary_type(value, ctx, env),
        Expr::Call(value) => infer_call_type(value, ctx, env),
        _ => Result::Err(cli_error("unsupported expression in this pass")),
    }
}

func infer_binary_type(BinaryExpr expr, FunctionContext ctx, TypeEnv env) Result[String, CliError] {
    var left = infer_expr_type(*expr.left, ctx, env)?
    var right = infer_expr_type(*expr.right, ctx, env)?
    match expr.op {
        "+" | "-" | "*" | "/" | "%" => {
            if left != "int" || right != "int" {
                return Result::Err(cli_error("arithmetic requires ints"))
            }
            Result::Ok("int")
        }
        "==" | "!=" => {
            if left != right {
                return Result::Err(cli_error("comparison requires same types"))
            }
            Result::Ok("bool")
        }
        "<" | "<=" | ">" | ">=" => {
            if left != "int" || right != "int" {
                return Result::Err(cli_error("comparison requires ints"))
            }
            Result::Ok("bool")
        }
        "&&" | "||" => {
            if left != "bool" || right != "bool" {
                return Result::Err(cli_error("boolean operations require bools"))
            }
            Result::Ok("bool")
        }
        _ => Result::Err(cli_error("operator not supported")),
    }
}

func infer_call_type(CallExpr expr, FunctionContext ctx, TypeEnv env) Result[String, CliError] {
    var callee =
        match *expr.callee {
            Expr::Name(value) => value.name,
            _ => return Result::Err(cli_error("call target must be identifier")),
        }
    if callee == "println" {
        for arg in expr.args {
            infer_expr_type(arg, ctx, env)?
        }
        return Result::Ok("")
    }
    var target =
        match find_function(env, callee) {
            Option::Some(info) => info,
            Option::None => return Result::Err(cli_error("call to undefined function: " + callee)),
        }
    if expr.args.len() != target.sig.params.len() {
        return Result::Err(cli_error("wrong argument count for " + callee))
    }
    var i = 0
    while i < expr.args.len() {
        var arg_type = infer_expr_type(expr.args[i], ctx, env)?
        var param_type = normalize_type(target.sig.params[i].type_name)
        if arg_type != param_type {
            return Result::Err(cli_error("mismatched argument type for " + callee))
        }
        i = i + 1
    }
    match target.sig.return_type {
        Option::Some(ret) => Result::Ok(normalize_type(ret)),
        Option::None => Result::Ok(""),
    }
}

func normalize_type(String ty) String {
    match ty {
        "i32" | "int" => "int",
        "string" => "str",
        _ => ty,
    }
}

func find_function(TypeEnv env, String name) Option[FunctionInfo] {
    var i = 0
    while i < env.functions.len() {
        var info = env.functions[i]
        if info.name == name {
            return Option::Some(info)
        }
        i = i + 1
    }
    Option::None
}

func find_struct(TypeEnv env, String name) Option[StructInfo] {
    var i = 0
    while i < env.structs.len() {
        var info = env.structs[i]
        if info.name == name {
            return Option::Some(info)
        }
        i = i + 1
    }
    Option::None
}

func find_local(FunctionContext ctx, String name) Option[String] {
    for local in ctx.locals {
        if local.name == name {
            return Option::Some(local.type_name)
        }
    }
    Option::None
}

func add_local(mut FunctionContext ctx, LocalVar local) Result[(), CliError] {
    if find_local(ctx, local.name).is_some() {
        return Result::Err(cli_error("duplicate local: " + local.name))
    }
    ctx.locals.push(local)
    Result::Ok(())
}

func field_name_exists(Vec[FieldInfo] fields, String name) bool {
    for field in fields {
        if field.name == name {
            return true
        }
    }
    false
}

func contains_string(Vec[String] values, String target) bool {
    for value in values {
        if value == target {
            return true
        }
    }
    false
}

func cli_error(String message) CliError {
    CliError { message: message }
}

func read_source(String path) Result[String, CliError] {
    match ReadSource(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(err) => Result::Err(convert_syntax_error(err)),
    }
}

func tokenize_source(String source) Result[Vec[Token], CliError] {
    match Tokenize(source) {
        Result::Ok(tokens) => Result::Ok(tokens),
        Result::Err(err) => Result::Err(convert_syntax_error(err)),
    }
}

func parse_tokens_text(Vec[Token] tokens) Result[SourceFile, CliError] {
    match ParseTokens(tokens) {
        Result::Ok(ast) => Result::Ok(ast),
        Result::Err(err) => Result::Err(convert_syntax_error(err)),
    }
}

func convert_syntax_error(SyntaxError err) CliError {
    if err.line == 0 {
        return CliError {
            message: err.message,
        }
    }
    CliError {
        message: err.message + " at " + to_string(err.line) + ":" + to_string(err.column),
    }
}
