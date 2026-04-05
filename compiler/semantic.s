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
use frontend.MatchExpr
use frontend.MemberExpr
use frontend.NameExpr
use frontend.ReturnStmt
use frontend.SourceFile
use frontend.StringExpr
use frontend.WhileExpr

struct Diagnostic {
    message: String,
}

struct CheckResult {
    diagnostics: Vec[Diagnostic],
}

struct FunctionInfo {
    name: String,
    params: Vec[Type],
    return_type: Type,
}

struct StructInfo {
    name: String,
    fields: Vec[FieldType],
}

struct FieldType {
    name: String,
    ty: Type,
}

struct VarState {
    name: String,
    ty: Type,
}

func CheckSource(source: SourceFile) -> CheckResult {
    var diagnostics = Vec[Diagnostic]()
    var functions = collectFunctions(source)
    var structs = collectStructs(source)

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

func IsOK(result: CheckResult) -> bool {
    result.diagnostics.len() == 0
}

func collectFunctions(source: SourceFile) -> Vec[FunctionInfo] {
    var functions = Vec[FunctionInfo]()
    for item in source.items {
        match item {
            frontend.Item::Function(func) => {
                var params = Vec[Type]()
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

func collectStructs(source: SourceFile) -> Vec[StructInfo] {
    var structs = Vec[StructInfo]()
    for item in source.items {
        match item {
            frontend.Item::Struct(decl) => {
                var fields = Vec[FieldType]()
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

func checkFunction(
    item: FunctionDecl,
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> () {
    match item.body {
        Option::Some(body) => {
            var scope = Vec[VarState]()
            for param in item.sig.params {
                scope.push(VarState {
                    name: param.name,
                    ty: ParseType(param.type_name),
                })
            }
            var expected =
                match item.sig.return_type {
                    Option::Some(value) => ParseType(value),
                    Option::None => NewUnitType(),
                }
            var actual = inferBlock(body, scope, functions, structs, diagnostics)
            if !typeEq(expected, actual) && !typeEq(expected, NewUnitType()) {
                pushError(
                    diagnostics,
                    "function " + item.sig.name + " expected " + DumpType(expected) + ", got " + DumpType(actual),
                )
            }

            var borrow_diags = AnalyzeBlock(body, scope)
            for diag in borrow_diags {
                pushError(diagnostics, diag.message)
            }
        }
        Option::None => (),
    }
}

func inferBlock(
    block: BlockExpr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    var local_scope = cloneScope(scope)
    for stmt in block.statements {
        checkStmt(stmt, local_scope, functions, structs, diagnostics)
    }
    match block.final_expr {
        Option::Some(expr) => inferExpr(expr, local_scope, functions, structs, diagnostics),
        Option::None => NewUnitType(),
    }
}

func checkStmt(
    stmt: frontend.Stmt,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> () {
    match stmt {
        frontend.Stmt::Var(value) => {
            var actual = inferExpr(value.value, scope, functions, structs, diagnostics)
            var resolved =
                match value.type_name {
                    Option::Some(type_name) => {
                        var declared = ParseType(type_name)
                        if !typeEq(declared, actual) {
                            pushError(
                                diagnostics,
                                "var " + value.name + " expected " + DumpType(declared) + ", got " + DumpType(actual),
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

func inferExpr(
    expr: Expr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    match expr {
        Expr::Int(_) => NewI32Type(),
        Expr::String(_) => NewStringType(),
        Expr::Bool(_) => NewBoolType(),
        Expr::Name(value) => lookupName(scope, value.name, diagnostics),
        Expr::Borrow(value) => Type::Reference(ReferenceType {
            inner: Box(inferExpr(value.target.value, scope, functions, structs, diagnostics)),
            mutable: value.mutable,
        }),
        Expr::Binary(value) => inferBinary(value, scope, functions, structs, diagnostics),
        Expr::Member(value) => inferMember(value, scope, functions, structs, diagnostics),
        Expr::Index(value) => inferIndex(value, scope, functions, structs, diagnostics),
        Expr::Call(value) => inferCall(value, scope, functions, structs, diagnostics),
        Expr::Block(value) => inferBlock(value, scope, functions, structs, diagnostics),
        Expr::If(value) => {
            inferExpr(value.condition.value, scope, functions, structs, diagnostics)
            var then_type = inferBlock(value.then_branch, scope, functions, structs, diagnostics)
            match value.else_branch {
                Option::Some(other) => {
                    var else_type = inferExpr(other.value, scope, functions, structs, diagnostics)
                    if !typeEq(then_type, else_type) {
                        pushError(diagnostics, "if branch type mismatch")
                        return UnknownTypeOf("if")
                    }
                    then_type
                }
                Option::None => NewUnitType(),
            }
        }
        Expr::While(value) => {
            inferExpr(value.condition.value, scope, functions, structs, diagnostics)
            inferBlock(value.body, scope, functions, structs, diagnostics)
            NewUnitType()
        }
        Expr::For(value) => {
            inferExpr(value.iterable.value, scope, functions, structs, diagnostics)
            inferBlock(value.body, scope, functions, structs, diagnostics)
            NewUnitType()
        }
        Expr::Match(value) => {
            inferExpr(value.subject.value, scope, functions, structs, diagnostics)
            var arm_type = UnknownTypeOf("match")
            for arm in value.arms {
                var current = inferExpr(arm.expr, scope, functions, structs, diagnostics)
                if isUnknownType(arm_type) {
                    arm_type = current
                } else if !typeEq(arm_type, current) {
                    pushError(diagnostics, "match arm type mismatch")
                }
            }
            arm_type
        }
    }
}

func inferBinary(
    expr: BinaryExpr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    var left = inferExpr(expr.left.value, scope, functions, structs, diagnostics)
    var right = inferExpr(expr.right.value, scope, functions, structs, diagnostics)
    if expr.op == "+" || expr.op == "-" || expr.op == "*" || expr.op == "/" || expr.op == "%" {
        if typeEq(left, NewI32Type()) && typeEq(right, NewI32Type()) {
            return NewI32Type()
        }
        pushError(diagnostics, "binary operator expects i32 operands")
        return UnknownTypeOf("binary")
    }
    if expr.op == "==" || expr.op == "!=" || expr.op == "<" || expr.op == "<=" || expr.op == ">" || expr.op == ">=" {
        return NewBoolType()
    }
    if expr.op == "&&" || expr.op == "||" {
        return NewBoolType()
    }
    UnknownTypeOf("binary")
}

func inferMember(
    expr: MemberExpr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    var target = inferExpr(expr.target.value, scope, functions, structs, diagnostics)
    var field_type = lookupStructFieldType(structs, target, expr.member)
    match field_type {
        Option::Some(value) => value,
        Option::None => {
            var builtin_method = LookupBuiltinMethod(target, expr.member)
            match builtin_method {
                Option::Some(method) => Type::Function(method.signature),
                Option::None => {
                    pushError(diagnostics, "unknown member " + expr.member)
                    UnknownTypeOf("member")
                }
            }
        }
    }
}

func inferIndex(
    expr: IndexExpr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    var target = inferExpr(expr.target.value, scope, functions, structs, diagnostics)
    inferExpr(expr.index.value, scope, functions, structs, diagnostics)
    match LookupIndexType(target) {
        Option::Some(value) => value,
        Option::None => UnknownTypeOf("index"),
    }
}

func inferCall(
    expr: CallExpr,
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> Type {
    match expr.callee.value {
        Expr::Name(name_expr) => {
            var info = lookupFunction(functions, name_expr.name)
            match info {
                Option::Some(func) => {
                    checkCallArgs(func.params, expr.args, scope, functions, structs, diagnostics)
                    return func.return_type
                }
                Option::None => (),
            }
        }
        Expr::Member(member_expr) => {
            var target = inferExpr(member_expr.target.value, scope, functions, structs, diagnostics)
            var methods = LookupBuiltinMethods(target, member_expr.member)
            if methods.len() == 1 {
                checkCallArgs(methods[0].signature.params, expr.args, scope, functions, structs, diagnostics)
                match methods[0].signature.return_type {
                    Option::Some(value) => return value,
                    Option::None => return NewUnitType(),
                }
            }
        }
        _ => (),
    }
    inferExpr(expr.callee.value, scope, functions, structs, diagnostics)
    for arg in expr.args {
        inferExpr(arg, scope, functions, structs, diagnostics)
    }
    UnknownTypeOf("call")
}

func checkCallArgs(
    params: Vec[Type],
    args: Vec[Expr],
    scope: Vec[VarState],
    functions: Vec[FunctionInfo],
    structs: Vec[StructInfo],
    diagnostics: Vec[Diagnostic],
) -> () {
    if params.len() != args.len() {
        pushError(diagnostics, "call argument count mismatch")
        return
    }
    var index = 0
    for arg in args {
        var actual = inferExpr(arg, scope, functions, structs, diagnostics)
        var expected = params[index]
        if !typeEq(expected, actual) && !IsNamedTypeVar(expected, "T") {
            pushError(diagnostics, "call argument type mismatch")
        }
        index = index + 1
    }
}

func lookupName(scope: Vec[VarState], name: String, diagnostics: Vec[Diagnostic]) -> Type {
    for entry in scope {
        if entry.name == name {
            return entry.ty
        }
    }
    pushError(diagnostics, "unresolved name " + name)
    UnknownTypeOf("name")
}

func lookupFunction(functions: Vec[FunctionInfo], name: String) -> Option[FunctionInfo] {
    for function in functions {
        if function.name == name {
            return Option::Some(function)
        }
    }
    Option::None
}

func lookupStructFieldType(structs: Vec[StructInfo], target: Type, member: String) -> Option[Type] {
    match UnwrapRefs(target) {
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

func bindVar(scope: Vec[VarState], name: String, ty: Type) -> () {
    scope.push(VarState {
        name: name,
        ty: ty,
    })
}

func cloneScope(scope: Vec[VarState]) -> Vec[VarState] {
    var out = Vec[VarState]()
    for value in scope {
        out.push(value)
    }
    out
}

func pushError(diagnostics: Vec[Diagnostic], message: String) -> () {
    diagnostics.push(Diagnostic {
        message: message,
    })
}

func UnknownTypeOf(label: String) -> Type {
    Type::Unknown(UnknownType {
        label: label,
    })
}

func isUnknownType(ty: Type) -> bool {
    match ty {
        Type::Unknown(_) => true,
        _ => false,
    }
}

func typeEq(left: Type, right: Type) -> bool {
    DumpType(left) == DumpType(right)
}
