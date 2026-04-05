package compiler

use std.option.Option
use std.prelude.Box
use std.vec.Vec
use frontend.BinaryExpr
use frontend.BlockExpr
use frontend.BoolExpr
use frontend.BorrowExpr
use frontend.CallExpr
use frontend.EnumDecl
use frontend.Expr
use frontend.ExprStmt
use frontend.ForExpr
use frontend.FunctionDecl
use frontend.IfExpr
use frontend.IndexExpr
use frontend.IntExpr
use frontend.LetStmt
use frontend.MatchExpr
use frontend.MemberExpr
use frontend.NameExpr
use frontend.ReturnStmt
use frontend.SourceFile
use frontend.StringExpr
use frontend.WhileExpr

pub struct Diagnostic {
    message: String,
}

pub struct CheckResult {
    diagnostics: Vec[Diagnostic],
}

pub struct FunctionInfo {
    name: String,
    params: Vec[Type],
    return_type: Type,
}

pub struct StructInfo {
    name: String,
    fields: Vec[FieldType],
}

pub struct FieldType {
    name: String,
    ty: Type,
}

pub struct VarState {
    name: String,
    ty: Type,
}

pub fn CheckSource(source: SourceFile) -> CheckResult {
    let diagnostics = Vec[Diagnostic]()
    let functions = collectFunctions(source)
    let structs = collectStructs(source)

    for item in source.items {
        match item {
            frontend.Item::Function(func) => checkFunction(func, functions, structs, diagnostics),
            _ => (),
        }
    }

    CheckResult {
        diagnostics: diagnostics,
    }
}

pub fn IsOK(result: CheckResult) -> bool {
    result.diagnostics.len() == 0
}

fn collectFunctions(source: SourceFile) -> Vec[FunctionInfo] {
    let functions = Vec[FunctionInfo]()
    for item in source.items {
        match item {
            frontend.Item::Function(func) => {
                let params = Vec[Type]()
                for param in func.sig.params {
                    params.push(ParseType(param.type_name))
                }
                functions.push(FunctionInfo {
                    name: func.sig.name,
                    params: params,
                    return_type:
                        match func.sig.return_type {
                            Option::Some(value) => ParseType(value),
                            Option::None => NewUnitType(),
                        },
                })
            }
            _ => (),
        }
    }
    functions
}

fn collectStructs(source: SourceFile) -> Vec[StructInfo] {
    let structs = Vec[StructInfo]()
    for item in source.items {
        match item {
            frontend.Item::Struct(decl) => {
                let fields = Vec[FieldType]()
                for field in decl.fields {
                    fields.push(FieldType {
                        name: field.name,
                        ty: ParseType(field.type_name),
                    })
                }
                structs.push(StructInfo {
                    name: decl.name,
                    fields: fields,
                })
            }
            _ => (),
        }
    }
    structs
}

fn checkFunction(
    item: FunctionDecl,
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> () {
    match item.body {
        Option::Some(body) => {
            let scope = Vec[VarState]()
            for param in item.sig.params {
                scope.push(VarState {
                    name: param.name,
                    ty: ParseType(param.type_name),
                })
            }
            let expected =
                match item.sig.return_type {
                    Option::Some(value) => ParseType(value),
                    Option::None => NewUnitType(),
                }
            let actual = inferBlock(body, scope, functions, structs, diagnostics)
            if !typeEq(expected, actual) && !typeEq(expected, NewUnitType()) {
                pushError(
                    diagnostics,
                    "function " + item.sig.name + " expected " + DumpType(expected) + ", got " + DumpType(actual),
                )
            }

            let borrow_diags = AnalyzeBlock(body, scope)
            for diag in borrow_diags {
                pushError(diagnostics, diag.message)
            }
        }
        Option::None => (),
    }
}

fn inferBlock(
    block: BlockExpr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    let local_scope = cloneScope(scope)
    for stmt in block.statements {
        checkStmt(stmt, local_scope, functions, structs, diagnostics)
    }
    match block.final_expr {
        Option::Some(expr) => inferExpr(expr, local_scope, functions, structs, diagnostics),
        Option::None => NewUnitType(),
    }
}

fn checkStmt(
    stmt: frontend.Stmt,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> () {
    match stmt {
        frontend.Stmt::Let(value) => {
            let actual = inferExpr(value.value, scope, functions, structs, diagnostics)
            let resolved =
                match value.type_name {
                    Option::Some(type_name) => {
                        let declared = ParseType(type_name)
                        if !typeEq(declared, actual) {
                            pushError(
                                diagnostics,
                                "let " + value.name + " expected " + DumpType(declared) + ", got " + DumpType(actual),
                            )
                        }
                        declared
                    }
                    Option::None => actual,
                }
            bindVar(scope, value.name, resolved)
        }
        frontend.Stmt::Return(value) => {
            match value.value {
                Option::Some(expr) => {
                    inferExpr(expr, scope, functions, structs, diagnostics)
                }
                Option::None => (),
            }
        }
        frontend.Stmt::Expr(value) => {
            inferExpr(value.expr, scope, functions, structs, diagnostics)
        }
    }
}

pub fn infer_expr(
    expr: Expr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    match expr {
        Expr::Int(_) => i32_type(),
        Expr::String(_) => string_type(),
        Expr::Bool(_) => bool_type(),
        Expr::Name(value) => lookup_name(scope, value.name, diagnostics),
        Expr::Borrow(value) => Type::Reference(ReferenceType {
            inner: Box(infer_expr(value.target.value, scope, functions, structs, diagnostics)),
            mutable: value.mutable,
        }),
        Expr::Binary(value) => infer_binary(value, scope, functions, structs, diagnostics),
        Expr::Member(value) => infer_member(value, scope, functions, structs, diagnostics),
        Expr::Index(value) => infer_index(value, scope, functions, structs, diagnostics),
        Expr::Call(value) => infer_call(value, scope, functions, structs, diagnostics),
        Expr::Block(value) => infer_block(value, scope, functions, structs, diagnostics),
        Expr::If(value) => {
            infer_expr(value.condition.value, scope, functions, structs, diagnostics)
            let then_type = infer_block(value.then_branch, scope, functions, structs, diagnostics)
            match value.else_branch {
                Option::Some(other) => {
                    let else_type = infer_expr(other.value, scope, functions, structs, diagnostics)
                    if !type_eq(then_type, else_type) {
                        push_error(diagnostics, "if branch type mismatch")
                        return unknown_type("if")
                    }
                    then_type
                }
                Option::None => unit_type(),
            }
        }
        Expr::While(value) => {
            infer_expr(value.condition.value, scope, functions, structs, diagnostics)
            infer_block(value.body, scope, functions, structs, diagnostics)
            unit_type()
        }
        Expr::For(value) => {
            infer_expr(value.iterable.value, scope, functions, structs, diagnostics)
            infer_block(value.body, scope, functions, structs, diagnostics)
            unit_type()
        }
        Expr::Match(value) => {
            infer_expr(value.subject.value, scope, functions, structs, diagnostics)
            let arm_type = unknown_type("match")
            for arm in value.arms {
                let current = infer_expr(arm.expr, scope, functions, structs, diagnostics)
                if is_unknown_type(arm_type) {
                    arm_type = current
                } else if !type_eq(arm_type, current) {
                    push_error(diagnostics, "match arm type mismatch")
                }
            }
            arm_type
        }
    }
}

pub fn infer_binary(
    expr: BinaryExpr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    let left = infer_expr(expr.left.value, scope, functions, structs, diagnostics)
    let right = infer_expr(expr.right.value, scope, functions, structs, diagnostics)
    if expr.op == "+" || expr.op == "-" || expr.op == "*" || expr.op == "/" || expr.op == "%" {
        if type_eq(left, i32_type()) && type_eq(right, i32_type()) {
            return i32_type()
        }
        push_error(diagnostics, "binary operator expects i32 operands")
        return unknown_type("binary")
    }
    if expr.op == "==" || expr.op == "!=" || expr.op == "<" || expr.op == "<=" || expr.op == ">" || expr.op == ">=" {
        return bool_type()
    }
    if expr.op == "&&" || expr.op == "||" {
        return bool_type()
    }
    unknown_type("binary")
}

pub fn infer_member(
    expr: MemberExpr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    let target = infer_expr(expr.target.value, scope, functions, structs, diagnostics)
    let field_type = lookup_struct_field_type(structs, target, expr.member)
    match field_type {
        Option::Some(value) => value,
        Option::None => {
            let builtin_method = lookup_builtin_method(target, expr.member)
            match builtin_method {
                Option::Some(method) => Type::Function(method.signature),
                Option::None => {
                    push_error(diagnostics, "unknown member " + expr.member)
                    unknown_type("member")
                }
            }
        }
    }
}

pub fn infer_index(
    expr: IndexExpr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    let target = infer_expr(expr.target.value, scope, functions, structs, diagnostics)
    infer_expr(expr.index.value, scope, functions, structs, diagnostics)
    match lookup_index_type(target) {
        Option::Some(value) => value,
        Option::None => unknown_type("index"),
    }
}

pub fn infer_call(
    expr: CallExpr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    match expr.callee.value {
        Expr::Name(name_expr) => {
            let info = lookup_function(functions, name_expr.name)
            match info {
                Option::Some(func) => {
                    check_call_args(func.params, expr.args, scope, functions, structs, diagnostics)
                    return func.return_type
                }
                Option::None => (),
            }
        }
        Expr::Member(member_expr) => {
            let target = infer_expr(member_expr.target.value, scope, functions, structs, diagnostics)
            let methods = lookup_builtin_methods(target, member_expr.member)
            if methods.len() == 1 {
                check_call_args(methods[0].signature.params, expr.args, scope, functions, structs, diagnostics)
                match methods[0].signature.return_type {
                    Option::Some(value) => return value,
                    Option::None => return unit_type(),
                }
            }
        }
        _ => (),
    }
    infer_expr(expr.callee.value, scope, functions, structs, diagnostics)
    for arg in expr.args {
        infer_expr(arg, scope, functions, structs, diagnostics)
    }
    unknown_type("call")
}

pub fn check_call_args(
    params: Vec[Type],
    args: Vec[Expr],
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> () {
    if params.len() != args.len() {
        push_error(diagnostics, "call argument count mismatch")
        return
    }
    let index = 0
    for arg in args {
        let actual = infer_expr(arg, scope, functions, structs, diagnostics)
        let expected = params[index]
        if !type_eq(expected, actual) && !is_named_type_var(expected, "T") {
            push_error(diagnostics, "call argument type mismatch")
        }
        index = index + 1
    }
}

pub fn lookup_name(scope: Vec[VarState], name: String, diagnostics: Vec[Diagnostic]) -> Type {
    for entry in scope {
        if entry.name == name {
            return entry.ty
        }
    }
    push_error(diagnostics, "unresolved name " + name)
    unknown_type("name")
}

pub fn lookup_function(functions: Vec[FunctionInfo], name: String) -> Option[FunctionInfo] {
    for function in functions {
        if function.name == name {
            return Option::Some(function)
        }
    }
    Option::None
}

pub fn lookup_struct_field_type(structs: Vec[StructInfo], target: Type, member: String) -> Option[Type] {
    match unwrap_refs(target) {
        Type::Named(named) => {
            for item in structs {
                if item.name == named.name {
                    for field in item.fields {
                        if field.name == member {
                            return Option::Some(field.ty)
                        }
                    }
                }
            }
            Option::None
        }
        _ => Option::None,
    }
}

pub fn bind_var(scope: Vec[VarState], name: String, ty: Type) -> () {
    scope.push(VarState {
        name: name,
        ty: ty,
    })
}

pub fn clone_scope(scope: Vec[VarState]) -> Vec[VarState] {
    let out = Vec[VarState]()
    for value in scope {
        out.push(value)
    }
    out
}

pub fn push_error(diagnostics: Vec[Diagnostic], message: String) -> () {
    diagnostics.push(Diagnostic {
        message: message,
    })
}

pub fn unknown_type(label: String) -> Type {
    Type::Unknown(UnknownType {
        label: label,
    })
}

pub fn is_unknown_type(ty: Type) -> bool {
    match ty {
        Type::Unknown(_) => true,
        _ => false,
    }
}

pub fn type_eq(left: Type, right: Type) -> bool {
    dump_type(left) == dump_type(right)
}
