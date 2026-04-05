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
    String message,
}

struct CheckResult {
    Vec[Diagnostic] diagnostics,
}

struct FunctionInfo {
    String name,
    Vec[Type] params,
    Type return_type,
}

struct StructInfo {
    String name,
    Vec[FieldType] fields,
}

struct FieldType {
    String name,
    Type ty,
}

struct VarState {
    String name,
    Type ty,
}

CheckResult CheckSource(SourceFile source){
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
        diagnostics diagnostics,
    }
}

bool IsOK(CheckResult result){
    result.diagnostics.len() == 0
}

Vec[FunctionInfo] collectFunctions(SourceFile source){
    var functions = Vec[FunctionInfo]()
    for item in source.items {
        match item {
            frontend.Item::Function(func) => {
                var params = Vec[Type]()
                for param in func.sig.params {
                    params.push(ParseType(param.type_name))
                }
                functions.push(FunctionInfo {
                    func.sig.name name,
                    params params,
                    match func.sig.return_type { return_type
                            :Some(value) => ParseType(value) Option,
                            :None => NewUnitType() Option,
                        },
                })
            }
            _ => (),
        }
    }
    functions
}

Vec[StructInfo] collectStructs(SourceFile source){
    var structs = Vec[StructInfo]()
    for item in source.items {
        match item {
            frontend.Item::Struct(decl) => {
                var fields = Vec[FieldType]()
                for field in decl.fields {
                    fields.push(FieldType {
                        field.name name,
                        ParseType(field.type_name) ty,
                    })
                }
                structs.push(StructInfo {
                    decl.name name,
                    fields fields,
                })
            }
            _ => (),
        }
    }
    structs
}

() checkFunction(FunctionDecl item, Vec[FunctionInfo] functions, Vec[StructInfo] structs, Vec[Diagnostic] diagnostics){
    match item.body {
        :Some(body) => { Option
            var scope = Vec[VarState]()
            for param in item.sig.params {
                scope.push(VarState {
                    param.name name,
                    ParseType(param.type_name) ty,
                })
            }
            var expected =
                match item.sig.return_type {
                    :Some(value) => ParseType(value) Option,
                    :None => NewUnitType() Option,
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
        :None => () Option,
    }
}

Type inferBlock(BlockExpr block, Vec[VarState] scope, Vec[FunctionInfo] functions, Vec[StructInfo] structs, Vec[Diagnostic] diagnostics){
    var local_scope = cloneScope(scope)
    for stmt in block.statements {
        checkStmt(stmt, local_scope, functions, structs, diagnostics)
    }
    match block.final_expr {
        Option::Some(expr) => inferExpr(expr, local_scope, functions, structs, diagnostics),
        :None => NewUnitType() Option,
    }
}

() checkStmt(frontend.Stmt stmt, Vec[VarState] scope, Vec[FunctionInfo] functions, Vec[StructInfo] structs, Vec[Diagnostic] diagnostics){
    match stmt {
        frontend.Stmt::Var(value) => {
            var actual = inferExpr(value.value, scope, functions, structs, diagnostics)
            var resolved =
                match value.type_name {
                    :Some(type_name) => { Option
                        var declared = ParseType(type_name)
                        if !typeEq(declared, actual) {
                            pushError(
                                diagnostics,
                                "var " + value.name + " expected " + DumpType(declared) + ", got " + DumpType(actual),
                            )
                        }
                        declared
                    }
                    :None => actual Option,
                }
            bindVar(scope, value.name, resolved)
        }
        frontend.Stmt::Return(value) => {
            match value.value {
                :Some(expr) => { Option
                    inferExpr(expr, scope, functions, structs, diagnostics)
                }
                :None => () Option,
            }
        }
        frontend.Stmt::Expr(value) => {
            inferExpr(value.expr, scope, functions, structs, diagnostics)
        }
    }
}

Type inferExpr(Expr expr, Vec[VarState] scope, Vec[FunctionInfo] functions, Vec[StructInfo] structs, Vec[Diagnostic] diagnostics){
    match expr {
        :Int(_) => NewI32Type() Expr,
        :String(_) => NewStringType() Expr,
        :Bool(_) => NewBoolType() Expr,
        Expr::Name(value) => lookupName(scope, value.name, diagnostics),
        :Borrow(value) => Type::Reference(ReferenceType { Expr
            inner: Box(inferExpr(value.target.value, scope, functions, structs, diagnostics)),
            value.mutable mutable,
        }),
        Expr::Binary(value) => inferBinary(value, scope, functions, structs, diagnostics),
        Expr::Member(value) => inferMember(value, scope, functions, structs, diagnostics),
        Expr::Index(value) => inferIndex(value, scope, functions, structs, diagnostics),
        Expr::Call(value) => inferCall(value, scope, functions, structs, diagnostics),
        Expr::Block(value) => inferBlock(value, scope, functions, structs, diagnostics),
        :If(value) => { Expr
            inferExpr(value.condition.value, scope, functions, structs, diagnostics)
            var then_type = inferBlock(value.then_branch, scope, functions, structs, diagnostics)
            match value.else_branch {
                :Some(other) => { Option
                    var else_type = inferExpr(other.value, scope, functions, structs, diagnostics)
                    if !typeEq(then_type, else_type) {
                        pushError(diagnostics, "if branch type mismatch")
                        return UnknownTypeOf("if")
                    }
                    then_type
                }
                :None => NewUnitType() Option,
            }
        }
        :While(value) => { Expr
            inferExpr(value.condition.value, scope, functions, structs, diagnostics)
            inferBlock(value.body, scope, functions, structs, diagnostics)
            NewUnitType()
        }
        :For(value) => { Expr
            inferExpr(value.iterable.value, scope, functions, structs, diagnostics)
            inferBlock(value.body, scope, functions, structs, diagnostics)
            NewUnitType()
        }
        :Match(value) => { Expr
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

Type inferBinary(BinaryExpr expr, Vec[VarState] scope, Vec[FunctionInfo] functions, Vec[StructInfo] structs, Vec[Diagnostic] diagnostics){
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

Type inferMember(MemberExpr expr, Vec[VarState] scope, Vec[FunctionInfo] functions, Vec[StructInfo] structs, Vec[Diagnostic] diagnostics){
    var target = inferExpr(expr.target.value, scope, functions, structs, diagnostics)
    var field_type = lookupStructFieldType(structs, target, expr.member)
    match field_type {
        :Some(value) => value Option,
        :None => { Option
            var builtin_method = LookupBuiltinMethod(target, expr.member)
            match builtin_method {
                :Some(method) => Type::Function(method.signature) Option,
                :None => { Option
                    pushError(diagnostics, "unknown member " + expr.member)
                    UnknownTypeOf("member")
                }
            }
        }
    }
}

Type inferIndex(IndexExpr expr, Vec[VarState] scope, Vec[FunctionInfo] functions, Vec[StructInfo] structs, Vec[Diagnostic] diagnostics){
    var target = inferExpr(expr.target.value, scope, functions, structs, diagnostics)
    inferExpr(expr.index.value, scope, functions, structs, diagnostics)
    match LookupIndexType(target) {
        :Some(value) => value Option,
        :None => UnknownTypeOf("index") Option,
    }
}

Type inferCall(CallExpr expr, Vec[VarState] scope, Vec[FunctionInfo] functions, Vec[StructInfo] structs, Vec[Diagnostic] diagnostics){
    match expr.callee.value {
        :Name(name_expr) => { Expr
            var info = lookupFunction(functions, name_expr.name)
            match info {
                :Some(func) => { Option
                    checkCallArgs(func.params, expr.args, scope, functions, structs, diagnostics)
                    return func.return_type
                }
                :None => () Option,
            }
        }
        :Member(member_expr) => { Expr
            var target = inferExpr(member_expr.target.value, scope, functions, structs, diagnostics)
            var methods = LookupBuiltinMethods(target, member_expr.member)
            if methods.len() == 1 {
                checkCallArgs(methods[0].signature.params, expr.args, scope, functions, structs, diagnostics)
                match methods[0].signature.return_type {
                    :Some(value) => return value Option,
                    :None => return NewUnitType() Option,
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

() checkCallArgs(Vec[Type] params, Vec[Expr] args, Vec[VarState] scope, Vec[FunctionInfo] functions, Vec[StructInfo] structs, Vec[Diagnostic] diagnostics){
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

Type lookupName(Vec[VarState] scope, String name, Vec[Diagnostic] diagnostics){
    for entry in scope {
        if entry.name == name {
            return entry.ty
        }
    }
    pushError(diagnostics, "unresolved name " + name)
    UnknownTypeOf("name")
}

Option[FunctionInfo] lookupFunction(Vec[FunctionInfo] functions, String name){
    for function in functions {
        if function.name == name {
            return Option::Some(function)
        }
    }
    :None Option
}

Option[Type] lookupStructFieldType(Vec[StructInfo] structs, Type target, String member){
    match UnwrapRefs(target) {
        :Named(named) => { Type
            for item in structs {
                if item.name == named.name {
                    for field in item.fields {
                        if field.name == member {
                            return Option::Some(field.ty)
                        }
                    }
                }
            }
            :None Option
        }
        _ => Option::None,
    }
}

() bindVar(Vec[VarState] scope, String name, Type ty){
    scope.push(VarState {
        name name,
        ty ty,
    })
}

Vec[VarState] cloneScope(Vec[VarState] scope){
    var out = Vec[VarState]()
    for value in scope {
        out.push(value)
    }
    out
}

() pushError(Vec[Diagnostic] diagnostics, String message){
    diagnostics.push(Diagnostic {
        message message,
    })
}

Type UnknownTypeOf(String label){
    :Unknown(UnknownType { Type
        label label,
    })
}

bool isUnknownType(Type ty){
    match ty {
        :Unknown(_) => true Type,
        _ => false,
    }
}

bool typeEq(Type left, Type right){
    DumpType(left) == DumpType(right)
}
