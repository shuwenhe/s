package compiler.internal.ir

use compiler.internal.typecheck.OwnershipEntry
use compiler.internal.typecheck.FindTypeBinding
use compiler.internal.typecheck.Type
use compiler.internal.typecheck.TypeBinding
use compiler.internal.typecheck.UnknownTypeOf
use std.option.Option
use std.prelude.Box
use std.prelude.box
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.vec.Vec
use s.AssignStmt
use s.BlockExpr
use s.CForStmt
use s.CallExpr
use s.Expr
use s.ExprStmt
use s.FunctionDecl
use s.IncrementStmt
use s.IndexExpr
use s.IntExpr
use s.Item
use s.MatchExpr
use s.MemberExpr
use s.NameExpr
use s.Pattern
use s.ReturnStmt
use s.SourceFile
use s.Stmt
use s.StringExpr
use s.VarStmt
use s.VariantPattern
use s.WhileExpr

struct LocalSlot {
    i32 id,
    String name,
    String kind,
    i32 version,
    Type ty,
}

struct Operand {
    String kind,
    i32 slot,
    String text,
}

struct AssignStmt {
    i32 target,
    String op,
    Vec[Operand] args,
}

struct EvalStmt {
    String op,
    Vec[Operand] args,
}

struct MoveStmt {
    i32 target,
    Operand source,
}

struct CopyStmt {
    i32 target,
    Operand source,
}

struct DropStmt {
    i32 slot,
}

struct ControlEdge {
    String id,
    i32 target,
    Vec[Operand] args,
}

struct Terminator {
    String kind,
    Vec[ControlEdge] edges,
}

struct BasicBlock {
    i32 id,
    Vec[i32] params,
    Vec[String] statements,
    Terminator terminator,
}

struct MIRGraph {
    Vec[BasicBlock] blocks,
    i32 entry,
    i32 exit,
    Vec[LocalSlot] locals,
}

struct MIRWriteOp {
    int fd,
    String text,
}

struct MIRProgram {
    Vec[MIRWriteOp] writes,
    int exit_code,
}

enum MIRValue {
    Int(int),
    String(String),
    Bool(bool),
    VecString(Vec[String]),
    Variant(MIRVariantValue),
    Unit(()),
}

struct MIRVariantValue {
    String tag,
    Option[Box[MIRValue]] payload,
}

struct MIRLocalBinding {
    String name,
    MIRValue value,
}

func LowerBlock(BlockExpr block, Vec[String] param_names, Vec[TypeBinding] type_env) -> MIRGraph {
    var locals = Vec[LocalSlot]()
    var statements = Vec[String]()
    var next_local = 0

    for name in param_names {
        var ty =
            match FindTypeBinding(type_env, name) {
                Option::Some(value) => value,
                Option::None => UnknownTypeOf("param"),
            }
        locals.push(LocalSlot {
            id: next_local,
            name: name,
            kind: "param",
            version: 0,
            ty: ty,
        })
        next_local = next_local + 1
    }

    for stmt in block.statements {
        statements.push("stmt")
    }
    match block.final_expr {
        Option::Some(_) => statements.push("yield"),
        Option::None => (),
    }

    var blocks = Vec[BasicBlock]()
    blocks.push(BasicBlock {
        id: 0,
        params: Vec[i32](),
        statements: statements,
        terminator: Terminator {
            kind: "goto",
            edges: Vec[ControlEdge] {
                ControlEdge {
                    id: "edge:0",
                    target: 1,
                    args: Vec[Operand](),
                },
            },
        },
    })
    blocks.push(BasicBlock {
        id: 1,
        params: Vec[i32](),
        statements: Vec[String](),
        terminator: Terminator {
            kind: "return",
            edges: Vec[ControlEdge](),
        },
    })

    MIRGraph {
        blocks: blocks,
        entry: 0,
        exit: 1,
        locals: locals,
    }
}

func LowerSource(SourceFile source, Vec[OwnershipEntry] ownership_plan) -> Result[MIRProgram, String] {
    ownership_plan
    var main_func =
        match findMain(source) {
            Option::Some(value) => value,
            Option::None => {
                return Result::Err("entry function main not found")
            }
        }
    var env = Vec[MIRLocalBinding]()
    var writes = Vec[MIRWriteOp]()
    var exit_code =
        match executeFunction(main_func, env, writes) {
            Result::Ok(value) => value,
            Result::Err(err) => {
                return Result::Err(err)
            }
        }
    Result::Ok(MIRProgram {
        writes: writes,
        exit_code: exit_code,
    })
}

func findMain(SourceFile source) -> Option[FunctionDecl] {
    for item in source.items {
        match item {
            Item::Function(func) => {
                if func.sig.name == "main" {
                    return Option::Some(func)
                }
            }
            _ => (),
        }
    }
    Option::None
}

func executeFunction(
    FunctionDecl func,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[int, String] {
    match func.body {
        Option::Some(body) => executeBlock(body, env, writes),
        Option::None => Result::Ok(0),
    }
}

func executeBlock(
    BlockExpr body,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[int, String] {
    for stmt in body.statements {
        match stmt {
            Stmt::Return(value) => return executeReturnStmt(value, env),
            _ => {
                match executeStmt(stmt, env, writes) {
                    Result::Ok(()) => (),
                    Result::Err(err) => {
                        return Result::Err(err)
                    }
                }
            }
        }
    }
    match body.final_expr {
        Option::Some(expr) => {
            var value = evalExpr(expr, env, writes)?
            asExitCode(value)
        }
        Option::None => Result::Ok(0),
    }
}

func executeStmt(
    Stmt stmt,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[(), String] {
    match stmt {
        Stmt::Var(value) => executeVarStmt(value, env, writes),
        Stmt::Assign(value) => executeAssignStmt(value, env, writes),
        Stmt::Increment(value) => executeIncrementStmt(value, env),
        Stmt::CFor(value) => executeCForStmt(value, env, writes),
        Stmt::Expr(value) => executeExprStmt(value, env, writes),
        Stmt::Return(_) => Result::Ok(()),
    }
}

func executeVarStmt(
    VarStmt stmt,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[(), String] {
    var value = evalExpr(stmt.value, env, writes)?
    setLocal(env, stmt.name, value)
    Result::Ok(())
}

func executeAssignStmt(
    AssignStmt stmt,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[(), String] {
    if !hasLocal(env, stmt.name) {
        return Result::Err("undefined name " + stmt.name)
    }
    var value = evalExpr(stmt.value, env, writes)?
    setLocal(env, stmt.name, value)
    Result::Ok(())
}

func executeIncrementStmt(
    IncrementStmt stmt,
    Vec[MIRLocalBinding] env
) -> Result[(), String] {
    var current = lookupBinding(env, stmt.name)?
    match current {
        MIRValue::Int(number) => {
            setLocal(env, stmt.name, MIRValue::Int(number + 1))
            Result::Ok(())
        }
        _ => Result::Err("unsupported increment target"),
    }
}

func executeCForStmt(
    CForStmt stmt,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[(), String] {
    executeStmt(stmt.init.value, env, writes)?
    var keep_going = true
    while keep_going {
        var cond = evalExpr(stmt.condition, env, writes)?
        if isTrue(cond) == false {
            keep_going = false
        } else {
            executeBlock(stmt.body, env, writes)?
            executeStmt(stmt.step.value, env, writes)?
        }
    }
    Result::Ok(())
}

func executeExprStmt(
    ExprStmt stmt,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[(), String] {
    match stmt.expr {
        Expr::Call(value) => executeCallStmt(value, env, writes),
        Expr::While(value) => executeWhileExpr(value, env, writes),
        _ => {
            evalExpr(stmt.expr, env, writes)?
            Result::Ok(())
        }
    }
}

func executeCallStmt(
    CallExpr call,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[(), String] {
    match call.callee.value {
        Expr::Member(member) => return executeMemberCallStmt(member, call.args, env),
        _ => (),
    }
    var callee_name = extractCalleeName(call)?
    if len(call.args) != 1 {
        return Result::Err("unsupported call arity")
    }
    var value = evalExpr(call.args[0], env, writes)?
    var text = valueToString(value)?
    if callee_name == "println" {
        writes.push(MIRWriteOp {
            fd: 1,
            text: text + "\n",
        })
        return Result::Ok(())
    }
    if callee_name == "eprintln" {
        writes.push(MIRWriteOp {
            fd: 2,
            text: text + "\n",
        })
        return Result::Ok(())
    }
    Result::Err("unsupported call " + callee_name)
}

func executeMemberCallStmt(
    MemberExpr member,
    Vec[Expr] args,
    Vec[MIRLocalBinding] env
) -> Result[(), String] {
    match member.target.value {
        Expr::Name(name_expr) => {
            if member.member == "push" {
                if len(args) != 1 {
                    return Result::Err("unsupported call arity")
                }
                var current = lookupBinding(env, name_expr.name)?
                var next_value = evalExpr(args[0], env, Vec[MIRWriteOp]())?
                match current {
                    MIRValue::VecString(items) => {
                        match next_value {
                            MIRValue::String(text) => {
                                items.push(text)
                                setLocal(env, name_expr.name, MIRValue::VecString(items))
                                return Result::Ok(())
                            }
                            _ => return Result::Err("unsupported vec push payload"),
                        }
                    }
                    _ => return Result::Err("unsupported method " + member.member),
                }
            }
            Result::Err("unsupported method " + member.member)
        }
        _ => Result::Err("unsupported method receiver"),
    }
}

func executeWhileExpr(
    WhileExpr expr,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[(), String] {
    var keep_going = true
    while keep_going {
        var cond = evalExpr(expr.condition.value, env, writes)?
        if isTrue(cond) == false {
            keep_going = false
        } else {
            executeBlock(expr.body, env, writes)?
        }
    }
    Result::Ok(())
}

func executeReturnStmt(ReturnStmt stmt, Vec[MIRLocalBinding] env) -> Result[int, String] {
    match stmt.value {
        Option::Some(expr) => {
            var value = evalExpr(expr, env, Vec[MIRWriteOp]())?
            asExitCode(value)
        }
        Option::None => Result::Ok(0),
    }
}

func evalExpr(
    Expr expr,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[MIRValue, String] {
    writes
    match expr {
        Expr::Int(value) => Result::Ok(MIRValue::Int(parseIntLiteral(value))),
        Expr::String(value) => Result::Ok(MIRValue::String(unquoteString(value))),
        Expr::Bool(value) => Result::Ok(MIRValue::Bool(value.value)),
        Expr::Index(value) => evalIndexExpr(value, env, writes),
        Expr::Name(value) => lookupBinding(env, value.name),
        Expr::Call(value) => evalCallExpr(value, env, writes),
        Expr::Binary(value) => evalBinaryExpr(value, env, writes),
        Expr::Match(value) => evalMatchExpr(value, env, writes),
        _ => Result::Err("unsupported backend expr"),
    }
}

func evalCallExpr(
    CallExpr call,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[MIRValue, String] {
    writes
    match call.callee.value {
        Expr::Name(name_expr) => {
            if name_expr.name == "Vec" {
                if len(call.args) == 0 {
                    return Result::Ok(MIRValue::VecString(Vec[String]()))
                }
                return Result::Err("unsupported vec constructor arity")
            }
            if name_expr.name == "Some" || name_expr.name == "Ok" || name_expr.name == "Err" {
                if len(call.args) != 1 {
                    return Result::Err("unsupported variant constructor arity")
                }
                var payload = evalExpr(call.args[0], env, writes)?
                return Result::Ok(MIRValue::Variant(MIRVariantValue {
                    tag: name_expr.name,
                    payload: Option::Some(box(payload)),
                }))
            }
            Result::Err("unsupported call " + name_expr.name)
        }
        Expr::Index(index_expr) => {
            match index_expr.target.value {
                Expr::Name(name_expr) => {
                    if name_expr.name == "Vec" && len(call.args) == 0 {
                        return Result::Ok(MIRValue::VecString(Vec[String]()))
                    }
                    Result::Err("unsupported callee")
                }
                _ => Result::Err("unsupported callee"),
            }
        }
        Expr::Member(member_expr) => evalMemberCallExpr(member_expr, call.args, env, writes),
        _ => Result::Err("unsupported callee"),
    }
}

func evalMemberCallExpr(
    MemberExpr member,
    Vec[Expr] args,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[MIRValue, String] {
    var receiver = evalExpr(member.target.value, env, writes)?
    if member.member == "len" {
        if len(args) != 0 {
            return Result::Err("unsupported call arity")
        }
        match receiver {
            MIRValue::VecString(items) => return Result::Ok(MIRValue::Int(items.len())),
            MIRValue::String(text) => return Result::Ok(MIRValue::Int(text.len())),
            _ => return Result::Err("unsupported method len"),
        }
    }
    if member.member == "push" {
        executeMemberCallStmt(member, args, env)?
        return Result::Ok(MIRValue::Unit(()))
    }
    Result::Err("unsupported method " + member.member)
}

struct MIRPatternMatch {
    bool matched,
    Vec[MIRLocalBinding] bindings,
}

func evalMatchExpr(
    MatchExpr expr,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[MIRValue, String] {
    var subject = evalExpr(expr.subject.value, env, writes)?
    for arm in expr.arms {
        var matched = matchPattern(arm.pattern, subject)?
        if matched.matched {
            var arm_env = cloneEnv(env)
            applyBindings(arm_env, matched.bindings)
            return evalExpr(arm.expr, arm_env, writes)
        }
    }
    Result::Err("unsupported match fallthrough")
}

func matchPattern(Pattern pattern, MIRValue value) -> Result[MIRPatternMatch, String] {
    match pattern {
        Pattern::Wildcard(_) => Result::Ok(MIRPatternMatch {
            matched: true,
            bindings: Vec[MIRLocalBinding](),
        }),
        Pattern::Name(name) => Result::Ok(MIRPatternMatch {
            matched: true,
            bindings: Vec[MIRLocalBinding] {
                MIRLocalBinding {
                    name: name.name,
                    value: value,
                },
            },
        }),
        Pattern::Variant(variant) => matchVariantPattern(variant, value),
    }
}

func matchVariantPattern(
    VariantPattern pattern,
    MIRValue value
) -> Result[MIRPatternMatch, String] {
    match value {
        MIRValue::Variant(variant) => {
            if lastPathSegment(pattern.path) != variant.tag {
                return Result::Ok(MIRPatternMatch {
                    matched: false,
                    bindings: Vec[MIRLocalBinding](),
                })
            }
            if len(pattern.args) == 0 {
                return Result::Ok(MIRPatternMatch {
                    matched: true,
                    bindings: Vec[MIRLocalBinding](),
                })
            }
            match variant.payload {
                Option::Some(payload) => {
                    if len(pattern.args) != 1 {
                        return Result::Err("unsupported variant pattern arity")
                    }
                    return matchPattern(pattern.args[0], payload.value)
                }
                Option::None => Result::Ok(MIRPatternMatch {
                    matched: false,
                    bindings: Vec[MIRLocalBinding](),
                }),
            }
        }
        _ => Result::Ok(MIRPatternMatch {
            matched: false,
            bindings: Vec[MIRLocalBinding](),
        }),
    }
}

func evalIndexExpr(
    IndexExpr expr,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[MIRValue, String] {
    var target = evalExpr(expr.target.value, env, writes)?
    var index = evalExpr(expr.index.value, env, writes)?
    match index {
        MIRValue::Int(pos) => {
            match target {
                MIRValue::VecString(items) => Result::Ok(MIRValue::String(items[pos])),
                _ => Result::Err("unsupported index target"),
            }
        }
        _ => Result::Err("unsupported index value"),
    }
}

func evalBinaryExpr(
    s.BinaryExpr expr,
    Vec[MIRLocalBinding] env,
    Vec[MIRWriteOp] writes
) -> Result[MIRValue, String] {
    var left = evalExpr(expr.left.value, env, writes)?
    var right = evalExpr(expr.right.value, env, writes)?
    if expr.op == "+" {
        match left {
            MIRValue::Int(left_value) => {
                match right {
                    MIRValue::Int(right_value) => return Result::Ok(MIRValue::Int(left_value + right_value)),
                    _ => return Result::Err("unsupported mixed + operands"),
                }
            }
            MIRValue::String(left_value) => {
                match right {
                    MIRValue::String(right_value) => return Result::Ok(MIRValue::String(left_value + right_value)),
                    _ => return Result::Err("unsupported mixed + operands"),
                }
            }
            _ => return Result::Err("unsupported operator +"),
        }
    }
    if expr.op == "<=" {
        match left {
            MIRValue::Int(left_value) => {
                match right {
                    MIRValue::Int(right_value) => return Result::Ok(MIRValue::Bool(left_value <= right_value)),
                    _ => return Result::Err("unsupported operator <="),
                }
            }
            _ => return Result::Err("unsupported operator <="),
        }
    }
    Result::Err("unsupported binary operator " + expr.op)
}

func lookupBinding(Vec[MIRLocalBinding] env, String name) -> Result[MIRValue, String] {
    if name == "None" {
        return Result::Ok(MIRValue::Variant(MIRVariantValue {
            tag: "None",
            payload: Option::None,
        }))
    }
    for binding in env {
        if binding.name == name {
            return Result::Ok(binding.value)
        }
    }
    Result::Err("undefined name " + name)
}

func cloneEnv(Vec[MIRLocalBinding] env) -> Vec[MIRLocalBinding] {
    var copied = Vec[MIRLocalBinding]()
    for binding in env {
        copied.push(MIRLocalBinding {
            name: binding.name,
            value: binding.value,
        })
    }
    copied
}

func applyBindings(Vec[MIRLocalBinding] env, Vec[MIRLocalBinding] bindings) -> () {
    for binding in bindings {
        setLocal(env, binding.name, binding.value)
    }
}

func setLocal(Vec[MIRLocalBinding] env, String name, MIRValue value) -> () {
    var index = 0
    while index < env.len() {
        if env[index].name == name {
            env[index] = MIRLocalBinding {
                name: name,
                value: value,
            }
            return
        }
        index = index + 1
    }
    env.push(MIRLocalBinding {
        name: name,
        value: value,
    })
}

func hasLocal(Vec[MIRLocalBinding] env, String name) -> bool {
    var index = 0
    while index < env.len() {
        if env[index].name == name {
            return true
        }
        index = index + 1
    }
    false
}

func extractCalleeName(CallExpr call) -> Result[String, String] {
    match call.callee.value {
        Expr::Name(value) => Result::Ok(value.name),
        _ => Result::Err("unsupported callee"),
    }
}

func valueToString(MIRValue value) -> Result[String, String] {
    match value {
        MIRValue::Int(number) => Result::Ok(to_string(number)),
        MIRValue::String(text) => Result::Ok(text),
        MIRValue::Bool(flag) => Result::Ok(if flag { "true" } else { "false" }),
        MIRValue::VecString(_) => Result::Err("unsupported stringify vec"),
        MIRValue::Variant(variant) => {
            match variant.payload {
                Option::Some(payload) => {
                    var text = valueToString(payload.value)?
                    Result::Ok(variant.tag + "(" + text + ")")
                }
                Option::None => Result::Ok(variant.tag),
            }
        }
        MIRValue::Unit(()) => Result::Ok("()"),
    }
}

func asExitCode(MIRValue value) -> Result[int, String] {
    match value {
        MIRValue::Int(number) => Result::Ok(number),
        MIRValue::Bool(flag) => Result::Ok(if flag { 1 } else { 0 }),
        MIRValue::Unit(()) => Result::Ok(0),
        _ => Result::Err("unsupported main return type"),
    }
}

func isTrue(MIRValue value) -> bool {
    match value {
        MIRValue::Bool(flag) => flag,
        MIRValue::Int(number) => number != 0,
        _ => false,
    }
}

func parseIntLiteral(IntExpr expr) -> int {
    parseDecimal(expr.value)
}

func unquoteString(StringExpr expr) -> String {
    var text = expr.value
    if len(text) < 2 {
        return text
    }
    slice(text, 1, len(text) - 1)
}

func parseDecimal(String text) -> int {
    var value = 0
    var index = 0
    while index < len(text) {
        var ch = char_at(text, index)
        if ch == "_" {
            index = index + 1
            continue
        }
        value = value * 10 + digitValue(ch)
        index = index + 1
    }
    value
}

func digitValue(String ch) -> int {
    if ch == "0" { return 0 }
    if ch == "1" { return 1 }
    if ch == "2" { return 2 }
    if ch == "3" { return 3 }
    if ch == "4" { return 4 }
    if ch == "5" { return 5 }
    if ch == "6" { return 6 }
    if ch == "7" { return 7 }
    if ch == "8" { return 8 }
    if ch == "9" { return 9 }
    0
}

func lastPathSegment(String path) -> String {
    var index = path.len() - 1
    while index >= 0 {
        if char_at(path, index) == ":" {
            return slice(path, index + 1, path.len())
        }
        if char_at(path, index) == "/" {
            return slice(path, index + 1, path.len())
        }
        index = index - 1
    }
    path
}
