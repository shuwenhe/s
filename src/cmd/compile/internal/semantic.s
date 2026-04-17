package compile.internal.semantic

use compile.internal.prelude.LookupBuiltinFieldType
use compile.internal.prelude.LookupBuiltinMethodArity
use compile.internal.prelude.LookupBuiltinMethodType
use compile.internal.typesys.BaseTypeName
use compile.internal.typesys.ParseType
use compile.internal.typesys.SameType
use s.BlockExpr
use s.Expr
use s.FunctionDecl
use s.ImplDecl
use s.Item
use s.Pattern
use s.Stmt
use s.parseSource
use std.option.Option
use std.prelude.charAt
use std.prelude.len
use std.prelude.slice
use std.vec.Vec

struct TypeBinding {
    string name,
    string typeName,
}

struct FunctionBinding {
    string name,
    Vec[string] genericNames,
    Vec[string] paramTypes,
    string returnType,
}

struct SignatureMatch {
    bool ok,
    string returnType,
    int32 score,
}

struct CheckResult {
    string typeName,
    int32 errors,
}

struct PatternCheckResult {
    Vec[TypeBinding] bindings,
    int32 errors,
}

struct SourcePos {
    int32 line,
    int32 column,
}

struct SemanticError {
    string code,
    string message,
    int32 line,
    int32 column,
}

func CheckText(string source) int32 {
    var diagnostics = CheckDetailed(source)
    if diagnostics.len() > 0 {
        return 1
    }
    0
}

func CheckDetailed(string source) Vec[SemanticError] {
    var diagnostics = Vec[SemanticError]()

    var parsed = parseSource(source)
    if parsed.isErr() {
        addError(source, diagnostics, "E0001", "parse failed", "package");
        return diagnostics
    }

    var file = parsed.unwrap()
    var functions = collectFunctions(file.items)

    var i = 0
    while i < file.items.len() {
        var ignored = checkItem(file.items[i], functions, source, diagnostics)
        i = i + 1
    }

    diagnostics
}

func collectFunctions(Vec[Item] items) Vec[FunctionBinding] {
    var out = Vec[FunctionBinding]()
    var i = 0
    while i < items.len() {
        match items[i] {
            Item.Function(functionDecl) => out.push(makeFunctionBinding(functionDecl)),
            _ => {},
        }
        i = i + 1
    }
    out
}

func makeFunctionBinding(FunctionDecl functionDecl) FunctionBinding {
    var genericNames = Vec[string]()
    var i = 0
    while i < functionDecl.sig.generics.len() {
        genericNames.push(genericName(functionDecl.sig.generics[i]));
        i = i + 1
    }

    var params = Vec[string]()
    i = 0
    while i < functionDecl.sig.params.len() {
        params.push(ParseType(functionDecl.sig.params[i].typeName));
        i = i + 1
    }

    var returnType =
        match functionDecl.sig.returnType {
            Option.Some(typeName) => ParseType(typeName),
            Option.None => "()",
        }

    FunctionBinding {
        name: functionDecl.sig.name,
        genericNames: genericNames,
        paramTypes: params,
        returnType: returnType,
    }
}

func checkItem(Item item, Vec[FunctionBinding] functions, string source, Vec[SemanticError] mut diagnostics) int32 {
    match item {
        Item.Function(functionDecl) => checkFunction(functionDecl, functions, source, diagnostics),
        Item.Impl(implDecl) => checkImpl(implDecl, functions, source, diagnostics),
        _ => 0,
    }
}

func checkImpl(ImplDecl implDecl, Vec[FunctionBinding] functions, string source, Vec[SemanticError] mut diagnostics) int32 {
    var errors = 0
    var i = 0
    while i < implDecl.methods.len() {
        errors = errors + checkFunction(implDecl.methods[i], functions, source, diagnostics)
        i = i + 1
    }
    errors
}

func checkFunction(FunctionDecl functionDecl, Vec[FunctionBinding] functions, string source, Vec[SemanticError] mut diagnostics) int32 {
    if functionDecl.body.isNone() {
        return 0
    }

    var expectedReturn =
        match functionDecl.sig.returnType {
            Option.Some(typeName) => ParseType(typeName),
            Option.None => "()",
        }

    var env = Vec[TypeBinding]()
    var i = 0
    while i < functionDecl.sig.params.len() {
        var param = functionDecl.sig.params[i]
        env.push(TypeBinding {
            name: param.name,
            typeName: ParseType(param.typeName),
        })
        ;
        i = i + 1
    }

    var result = inferBlockExpr(functionDecl.body.unwrap(), env, expectedReturn, functions, source, diagnostics)
    if expectedReturn != "()" && !isUnknown(expectedReturn) && !isUnknown(result.typeName) {
        if !SameType(expectedReturn, result.typeName) {
            return result.errors + addError(source, diagnostics, "E3004", "function return type mismatch", functionDecl.sig.name)
        }
    }
    result.errors
}

func inferBlockExpr(BlockExpr block, Vec[TypeBinding] outerEnv, string expectedReturn, Vec[FunctionBinding] functions, string source, Vec[SemanticError] mut diagnostics) CheckResult {
    var localEnv = cloneEnv(outerEnv)
    var errors = 0

    var i = 0
    while i < block.statements.len() {
        errors = errors + checkStmt(block.statements[i], localEnv, expectedReturn, functions, source, diagnostics)
        i = i + 1
    }

    match block.finalExpr {
        Option.Some(finalExpr) => {
            var finalResult = inferExpr(finalExpr, localEnv, expectedReturn, functions, source, diagnostics)
            CheckResult {
                typeName: finalResult.typeName,
                errors: errors + finalResult.errors,
            }
        }
        Option.None => CheckResult {
            typeName: "()",
            errors: errors,
        },
    }
}

func checkStmt(Stmt stmt, Vec[TypeBinding] mut env, string expectedReturn, Vec[FunctionBinding] functions, string source, Vec[SemanticError] mut diagnostics) int32 {
    match stmt {
        Stmt.Var(value) => {
            var rhs = inferExpr(value.value, env, expectedReturn, functions, source, diagnostics)
            var errors = rhs.errors

            var bindingType = rhs.typeName
            if value.typeName.isSome() {
                var declared = ParseType(value.typeName.unwrap())
                if !typesCompatible(declared, rhs.typeName) {
                    errors = errors + addError(source, diagnostics, "E3001", "variable initializer type mismatch", value.name)
                }
                bindingType = declared
            }

            env.push(TypeBinding {
                name: value.name,
                typeName: bindingType,
            })
            ;
            errors
        }
        Stmt.Assign(value) => {
            var targetType = lookupNameType(env, value.name)
            var rhs = inferExpr(value.value, env, expectedReturn, functions, source, diagnostics)
            var errors = rhs.errors
            if isUnknown(targetType) {
                return errors + addError(source, diagnostics, "E3002", "assignment to undefined name", value.name)
            }
            if !typesCompatible(targetType, rhs.typeName) {
                return errors + addError(source, diagnostics, "E3003", "assignment type mismatch", value.name)
            }
            errors
        }
        Stmt.Increment(value) => {
            var ty = lookupNameType(env, value.name)
            if !typesCompatible("int32", ty) {
                return addError(source, diagnostics, "E3005", "increment requires int32", value.name)
            }
            0
        }
        Stmt.CFor(value) => {
            var errors = 0
            errors = errors + checkStmt(value.init.value, env, expectedReturn, functions, source, diagnostics)
            var cond = inferExpr(value.condition, env, expectedReturn, functions, source, diagnostics)
            errors = errors + cond.errors
            if !typesCompatible("bool", cond.typeName) {
                errors = errors + addError(source, diagnostics, "E3006", "for condition must be bool", "for")
            }
            errors = errors + checkStmt(value.step.value, env, expectedReturn, functions, source, diagnostics)
            var bodyResult = inferBlockExpr(value.body, env, expectedReturn, functions, source, diagnostics)
            errors = errors + bodyResult.errors
            errors
        }
        Stmt.Return(value) => {
            match value.value {
                Option.Some(expr) => {
                    var exprResult = inferExpr(expr, env, expectedReturn, functions, source, diagnostics)
                    if expectedReturn == "()" {
                        return exprResult.errors + addError(source, diagnostics, "E3007", "unexpected return value", "return")
                    }
                    if !typesCompatible(expectedReturn, exprResult.typeName) {
                        return exprResult.errors + addError(source, diagnostics, "E3008", "return type mismatch", "return")
                    }
                    exprResult.errors
                }
                Option.None => {
                    if expectedReturn == "()" {
                        return 0
                    }
                    addError(source, diagnostics, "E3009", "missing return value", "return")
                }
            }
        }
        Stmt.Expr(value) => {
            inferExpr(value.expr, env, expectedReturn, functions, source, diagnostics).errors
        }
        Stmt.Defer(value) => {
            inferExpr(value.expr, env, expectedReturn, functions, source, diagnostics).errors
        }
    }
}

func inferExpr(Expr expr, Vec[TypeBinding] env, string expectedReturn, Vec[FunctionBinding] functions, string source, Vec[SemanticError] mut diagnostics) CheckResult {
    match expr {
        Expr::Int(_) => okType("int32"),
        Expr::String(_) => okType("string"),
        Expr::Bool(_) => okType("bool"),
        Expr::Name(value) => {
            var ty = lookupNameType(env, value.name)
            if isUnknown(ty) {
                return CheckResult {
                    typeName: "unknown",
                    errors: addError(source, diagnostics, "E3010", "undefined identifier", value.name),
                }
            }
            okType(ty)
        }
        Expr::Borrow(value) => {
            var base = inferExpr(value.target.value, env, expectedReturn, functions, source, diagnostics)
            if isUnknown(base.typeName) {
                return base
            }
            var prefix = if value.mutable { "&mut " } else { "&" }
            CheckResult {
                typeName: prefix + base.typeName,
                errors: base.errors,
            }
        }
        Expr::Binary(value) => {
            var left = inferExpr(value.left.value, env, expectedReturn, functions, source, diagnostics)
            var right = inferExpr(value.right.value, env, expectedReturn, functions, source, diagnostics)
            inferBinary(value.op, left, right, source, diagnostics)
        }
        Expr::Member(value) => {
            var target = inferExpr(value.target.value, env, expectedReturn, functions, source, diagnostics)
            var fieldType = LookupBuiltinFieldType(target.typeName, value.member)
            if fieldType == "" {
                return CheckResult {
                    typeName: "unknown",
                    errors: target.errors + addError(source, diagnostics, "E3011", "unknown member", value.member),
                }
            }
            CheckResult {
                typeName: ParseType(fieldType),
                errors: target.errors,
            }
        }
        Expr::Index(value) => {
            var target = inferExpr(value.target.value, env, expectedReturn, functions, source, diagnostics)
            var index = inferExpr(value.index.value, env, expectedReturn, functions, source, diagnostics)
            var errors = target.errors + index.errors
            if !typesCompatible("int32", index.typeName) {
                errors = errors + addError(source, diagnostics, "E3012", "index must be int32", "[")
            }
            if startsWith(target.typeName, "[]") {
                return CheckResult {
                    typeName: ParseType(slice(target.typeName, 2, len(target.typeName))),
                    errors: errors,
                }
            }
            if startsWith(target.typeName, "string") {
                return CheckResult {
                    typeName: "u8",
                    errors: errors,
                }
            }
            CheckResult {
                typeName: "unknown",
                errors: errors + addError(source, diagnostics, "E3013", "index target is not indexable", "["),
            }
        }
        Expr::Call(value) => {
            var errors = 0
            var argTypes = Vec[string]()
            var i = 0
            while i < value.args.len() {
                var argResult = inferExpr(value.args[i], env, expectedReturn, functions, source, diagnostics)
                errors = errors + argResult.errors
                argTypes.push(argResult.typeName);
                i = i + 1
            }

            match value.callee.value {
                Expr::Member(member) => {
                    var target = inferExpr(member.target.value, env, expectedReturn, functions, source, diagnostics)
                    errors = errors + target.errors

                    var arity = LookupBuiltinMethodArity(target.typeName, member.member)
                    if arity >= 0 && arity != value.args.len() {
                        errors = errors + addError(source, diagnostics, "E1005", "builtin method arity mismatch", member.member)
                    }

                    var methodType = LookupBuiltinMethodType(target.typeName, member.member)
                    if methodType == "" {
                        return CheckResult {
                            typeName: "unknown",
                            errors: errors + addError(source, diagnostics, "E1006", "unknown builtin method", member.member),
                        }
                    }
                    CheckResult {
                        typeName: resolveMethodReturn(target.typeName, methodType),
                        errors: errors,
                    }
                }
                Expr::Name(calleeName) => {
                    var candidates = lookupFunctions(functions, calleeName.name)
                    if candidates.len() == 0 {
                        return CheckResult {
                            typeName: "unknown",
                            errors: errors + addError(source, diagnostics, "E1001", "undefined function", calleeName.name),
                        }
                    }

                    var matches = Vec[SignatureMatch]()
                    var j = 0
                    while j < candidates.len() {
                        var m = tryMatchSignature(candidates[j], argTypes)
                        if m.ok {
                            matches.push(m);
                        }
                        j = j + 1
                    }

                    if matches.len() == 0 {
                        return CheckResult {
                            typeName: "unknown",
                            errors: errors + addError(source, diagnostics, "E1002", "no matching overload", calleeName.name),
                        }
                    }

                    var best = matches[0]
                    var ambiguous = false
                    j = 1
                    while j < matches.len() {
                        if matches[j].score > best.score {
                            best = matches[j]
                            ambiguous = false
                        } else if matches[j].score == best.score {
                            ambiguous = true
                        }
                        j = j + 1
                    }

                    if ambiguous {
                        return CheckResult {
                            typeName: "unknown",
                            errors: errors + addError(source, diagnostics, "E1003", "ambiguous overload", calleeName.name),
                        }
                    }

                    CheckResult {
                        typeName: best.returnType,
                        errors: errors,
                    }
                }
                _ => {
                    var callee = inferExpr(value.callee.value, env, expectedReturn, functions, source, diagnostics)
                    CheckResult {
                        typeName: "unknown",
                        errors: errors + callee.errors,
                    }
                }
            }
        }
        Expr::Match(value) => {
            var subject = inferExpr(value.subject.value, env, expectedReturn, functions, source, diagnostics)
            var errors = subject.errors
            var armType = "unknown"
            var seenPatterns = Vec[Pattern]()

            var i = 0
            while i < value.arms.len() {
                var arm = value.arms[i]
                if patternUnreachable(seenPatterns, arm.pattern, subject.typeName) {
                    errors = errors + addError(source, diagnostics, "E2003", "unreachable match arm", patternAnchor(arm.pattern))
                }

                if patternDuplicate(seenPatterns, arm.pattern, subject.typeName) {
                    errors = errors + addError(source, diagnostics, "E2002", "duplicate match arm", patternAnchor(arm.pattern))
                }

                var patternResult = checkPattern(arm.pattern, subject.typeName, source, diagnostics)
                errors = errors + patternResult.errors

                var armEnv = cloneEnv(env)
                appendBindings(armEnv, patternResult.bindings)

                var armResult = inferExpr(arm.expr, armEnv, expectedReturn, functions, source, diagnostics)
                errors = errors + armResult.errors
                if isUnknown(armType) {
                    armType = armResult.typeName
                } else if !typesCompatible(armType, armResult.typeName) {
                    errors = errors + addError(source, diagnostics, "E2005", "match arm result type mismatch", "match")
                }

                seenPatterns.push(arm.pattern);
                i = i + 1
            }

            var base = BaseTypeName(subject.typeName)
            if (base == "Option" || base == "Result") && !patternsCoverType(seenPatterns, subject.typeName) {
                errors = errors + addError(source, diagnostics, "E2001", "non-exhaustive match", "match")
            }

            CheckResult {
                typeName: armType,
                errors: errors,
            }
        }
        Expr::If(value) => {
            var cond = inferExpr(value.condition.value, env, expectedReturn, functions, source, diagnostics)
            var thenResult = inferBlockExpr(value.thenBranch, env, expectedReturn, functions, source, diagnostics)
            var errors = cond.errors + thenResult.errors
            if !typesCompatible("bool", cond.typeName) {
                errors = errors + addError(source, diagnostics, "E3014", "if condition must be bool", "if")
            }
            match value.elseBranch {
                Option::Some(elseExpr) => {
                    var elseResult = inferExpr(elseExpr.value, env, expectedReturn, functions, source, diagnostics)
                    errors = errors + elseResult.errors
                    if !typesCompatible(thenResult.typeName, elseResult.typeName) {
                        errors = errors + addError(source, diagnostics, "E3015", "if/else type mismatch", "if")
                    }
                    CheckResult {
                        typeName: thenResult.typeName,
                        errors: errors,
                    }
                }
                Option::None => CheckResult {
                    typeName: "()",
                    errors: errors,
                },
            }
        }
        Expr::While(value) => {
            var cond = inferExpr(value.condition.value, env, expectedReturn, functions, source, diagnostics)
            var bodyResult = inferBlockExpr(value.body, env, expectedReturn, functions, source, diagnostics)
            var errors = cond.errors + bodyResult.errors
            if !typesCompatible("bool", cond.typeName) {
                errors = errors + addError(source, diagnostics, "E3016", "while condition must be bool", "while")
            }
            CheckResult {
                typeName: "()",
                errors: errors,
            }
        }
        Expr::For(value) => {
            var iter = inferExpr(value.iterable.value, env, expectedReturn, functions, source, diagnostics)
            var bodyResult = inferBlockExpr(value.body, env, expectedReturn, functions, source, diagnostics)
            CheckResult {
                typeName: "()",
                errors: iter.errors + bodyResult.errors,
            }
        }
        Expr::Block(value) => {
            inferBlockExpr(value, env, expectedReturn, functions, source, diagnostics)
        }
        Expr::Array(value) => {
            if value.items.len() == 0 {
                return okType("[]unknown")
            }

            var first = inferExpr(value.items[0], env, expectedReturn, functions, source, diagnostics)
            var errors = first.errors
            var i = 1
            while i < value.items.len() {
                var item = inferExpr(value.items[i], env, expectedReturn, functions, source, diagnostics)
                errors = errors + item.errors
                if !typesCompatible(first.typeName, item.typeName) {
                    errors = errors + addError(source, diagnostics, "E3017", "array item type mismatch", "[")
                }
                i = i + 1
            }
            CheckResult {
                typeName: "[]" + first.typeName,
                errors: errors,
            }
        }
        Expr::Map(value) => {
            var errors = 0
            var i = 0
            while i < value.entries.len() {
                errors = errors + inferExpr(value.entries[i].key, env, expectedReturn, functions, source, diagnostics).errors
                errors = errors + inferExpr(value.entries[i].value, env, expectedReturn, functions, source, diagnostics).errors
                i = i + 1
            }
            CheckResult {
                typeName: "map",
                errors: errors,
            }
        }
    }
}

func checkPattern(Pattern pattern, string expectedType, string source, Vec[SemanticError] mut diagnostics) PatternCheckResult {
    var bindings = Vec[TypeBinding]()
    var errors = bindPattern(pattern, expectedType, bindings, source, diagnostics)
    PatternCheckResult {
        bindings: bindings,
        errors: errors,
    }
}

func bindPattern(Pattern pattern, string expectedType, Vec[TypeBinding] mut bindings, string source, Vec[SemanticError] mut diagnostics) int32 {
    if isUnknown(expectedType) {
        return addError(source, diagnostics, "E2007", "pattern expected type is unknown", patternAnchor(pattern))
    }

    match pattern {
        Pattern::Name(value) => {
            addBinding(bindings, value.name, expectedType, source, diagnostics)
        }
        Pattern::Wildcard(_) => 0,
        Pattern::Variant(value) => {
            var variant = lastPathSegment(value.path)
            var base = BaseTypeName(expectedType)
            if base == "Option" {
                if variant == "Some" {
                    if value.args.len() != 1 {
                        return addError(source, diagnostics, "E2004", "Some payload arity mismatch", value.path)
                    }
                    return bindPattern(value.args[0], firstTypeArg(expectedType), bindings, source, diagnostics)
                }
                if variant == "None" {
                    if value.args.len() == 0 {
                        return 0
                    }
                    return addError(source, diagnostics, "E2004", "None must not have payload", value.path)
                }
                return addError(source, diagnostics, "E2006", "invalid Option constructor", value.path)
            }
            if base == "Result" {
                if variant == "Ok" {
                    if value.args.len() != 1 {
                        return addError(source, diagnostics, "E2004", "Ok payload arity mismatch", value.path)
                    }
                    return bindPattern(value.args[0], firstTypeArg(expectedType), bindings, source, diagnostics)
                }
                if variant == "Err" {
                    if value.args.len() != 1 {
                        return addError(source, diagnostics, "E2004", "Err payload arity mismatch", value.path)
                    }
                    return bindPattern(value.args[0], secondTypeArg(expectedType), bindings, source, diagnostics)
                }
                return addError(source, diagnostics, "E2006", "invalid Result constructor", value.path)
            }
            addError(source, diagnostics, "E2006", "variant pattern not allowed for this type", value.path)
        }
    }
}

func addBinding(Vec[TypeBinding] mut bindings, string name, string typeName, string source, Vec[SemanticError] mut diagnostics) int32 {
    if name == "_" {
        return 0
    }

    var i = 0
    while i < bindings.len() {
        if bindings[i].name == name {
            if !typesCompatible(bindings[i].typeName, typeName) {
                return addError(source, diagnostics, "E2008", "conflicting binding type in pattern", name)
            }
            return 0
        }
        i = i + 1
    }

    bindings.push(TypeBinding {
        name: name,
        typeName: ParseType(typeName),
    })
    ;
    0
}

func appendBindings(Vec[TypeBinding] mut target, Vec[TypeBinding] source) () {
    var i = 0
    while i < source.len() {
        target.push(source[i]);
        i = i + 1
    }
}

func patternDuplicate(Vec[Pattern] seen, Pattern current, string expectedType) bool {
    var i = 0
    while i < seen.len() {
        if patternEquivalent(seen[i], current, expectedType) {
            return true
        }
        i = i + 1
    }
    false
}

func patternUnreachable(Vec[Pattern] seen, Pattern current, string expectedType) bool {
    var i = 0
    while i < seen.len() {
        if patternSubsumes(seen[i], current, expectedType) {
            return true
        }
        i = i + 1
    }
    false
}

func patternEquivalent(Pattern left, Pattern right, string expectedType) bool {
    patternSubsumes(left, right, expectedType) && patternSubsumes(right, left, expectedType)
}

func patternSubsumes(Pattern left, Pattern right, string expectedType) bool {
    if patternIsWild(left) {
        return true
    }
    if patternIsWild(right) {
        return false
    }

    match left {
        Pattern::Variant(lv) => {
            match right {
                Pattern::Variant(rv) => {
                    var lctor = lastPathSegment(lv.path)
                    var rctor = lastPathSegment(rv.path)
                    if lctor != rctor {
                        return false
                    }
                    if lv.args.len() == 0 && rv.args.len() == 0 {
                        return true
                    }
                    if lv.args.len() != 1 || rv.args.len() != 1 {
                        return false
                    }

                    var payloadType = variantPayloadType(expectedType, lctor)
                    if isUnknown(payloadType) {
                        return false
                    }
                    return patternSubsumes(lv.args[0], rv.args[0], payloadType)
                }
                _ => false,
            }
        }
        _ => false,
    }
}

func patternsCoverType(Vec[Pattern] patterns, string expectedType) bool {
    var i = 0
    while i < patterns.len() {
        if patternIsWild(patterns[i]) {
            return true
        }
        i = i + 1
    }

    var base = BaseTypeName(expectedType)
    if base == "Option" {
        return optionPatternsCover(patterns, expectedType)
    }
    if base == "Result" {
        return resultPatternsCover(patterns, expectedType)
    }

    false
}

func optionPatternsCover(Vec[Pattern] patterns, string expectedType) bool {
    var seenNone = false
    var somePatterns = Vec[Pattern]()

    var i = 0
    while i < patterns.len() {
        match patterns[i] {
            Pattern::Variant(value) => {
                var ctor = lastPathSegment(value.path)
                if ctor == "None" {
                    seenNone = true
                } else if ctor == "Some" && value.args.len() == 1 {
                    somePatterns.push(value.args[0]);
                }
            }
            _ => (),
        }
        i = i + 1
    }

    if !seenNone {
        return false
    }
    patternsCoverType(somePatterns, firstTypeArg(expectedType))
}

func resultPatternsCover(Vec[Pattern] patterns, string expectedType) bool {
    var okPatterns = Vec[Pattern]()
    var errPatterns = Vec[Pattern]()

    var i = 0
    while i < patterns.len() {
        match patterns[i] {
            Pattern::Variant(value) => {
                var ctor = lastPathSegment(value.path)
                if ctor == "Ok" && value.args.len() == 1 {
                    okPatterns.push(value.args[0]);
                } else if ctor == "Err" && value.args.len() == 1 {
                    errPatterns.push(value.args[0]);
                }
            }
            _ => (),
        }
        i = i + 1
    }

    if !patternsCoverType(okPatterns, firstTypeArg(expectedType)) {
        return false
    }
    patternsCoverType(errPatterns, secondTypeArg(expectedType))
}

func patternIsWild(Pattern pattern) bool {
    match pattern {
        Pattern::Wildcard(_) => true,
        Pattern::Name(_) => true,
        _ => false,
    }
}

func patternAnchor(Pattern pattern) string {
    match pattern {
        Pattern::Name(value) => value.name,
        Pattern::Wildcard(_) => "_",
        Pattern::Variant(value) => value.path,
    }
}

func variantPayloadType(string expectedType, string ctor) string {
    var base = BaseTypeName(expectedType)
    if base == "Option" {
        if ctor == "Some" {
            return firstTypeArg(expectedType)
        }
        if ctor == "None" {
            return "()"
        }
    }
    if base == "Result" {
        if ctor == "Ok" {
            return firstTypeArg(expectedType)
        }
        if ctor == "Err" {
            return secondTypeArg(expectedType)
        }
    }
    "unknown"
}

func inferBinary(string op, CheckResult left, CheckResult right, string source, Vec[SemanticError] mut diagnostics) CheckResult {
    var errors = left.errors + right.errors

    if op == "+" || op == "-" || op == "*" || op == "/" || op == "%" {
        if !typesCompatible("int32", left.typeName) || !typesCompatible("int32", right.typeName) {
            errors = errors + addError(source, diagnostics, "E3018", "arithmetic requires int32", op)
        }
        return CheckResult {
            typeName: "int32",
            errors: errors,
        }
    }

    if op == "<" || op == "<=" || op == ">" || op == ">=" {
        if !typesCompatible("int32", left.typeName) || !typesCompatible("int32", right.typeName) {
            errors = errors + addError(source, diagnostics, "E3019", "ordering compare requires int32", op)
        }
        return CheckResult {
            typeName: "bool",
            errors: errors,
        }
    }

    if op == "==" || op == "!=" {
        if !typesCompatible(left.typeName, right.typeName) {
            errors = errors + addError(source, diagnostics, "E3020", "equality compare requires same type", op)
        }
        return CheckResult {
            typeName: "bool",
            errors: errors,
        }
    }

    if op == "&&" || op == "||" {
        if !typesCompatible("bool", left.typeName) || !typesCompatible("bool", right.typeName) {
            errors = errors + addError(source, diagnostics, "E3021", "logical op requires bool", op)
        }
        return CheckResult {
            typeName: "bool",
            errors: errors,
        }
    }

    CheckResult {
        typeName: "unknown",
        errors: errors,
    }
}

func lookupFunctions(Vec[FunctionBinding] functions, string name) Vec[FunctionBinding] {
    var out = Vec[FunctionBinding]()
    var i = 0
    while i < functions.len() {
        if functions[i].name == name {
            out.push(functions[i]);
        }
        i = i + 1
    }
    out
}

func tryMatchSignature(FunctionBinding binding, Vec[string] argTypes) SignatureMatch {
    if binding.paramTypes.len() != argTypes.len() {
        return SignatureMatch {
            ok: false,
            returnType: "unknown",
            score: 0,
        }
    }

    var genericBindings = Vec[TypeBinding]()
    var score = 0

    var i = 0
    while i < argTypes.len() {
        var matched = matchTypePattern(binding.paramTypes[i], argTypes[i], binding.genericNames, genericBindings)
        if !matched {
            return SignatureMatch {
                ok: false,
                returnType: "unknown",
                score: 0,
            }
        }
        if !typeContainsGeneric(binding.paramTypes[i], binding.genericNames) {
            score = score + 1
        }
        i = i + 1
    }

    SignatureMatch {
        ok: true,
        returnType: instantiateType(binding.returnType, binding.genericNames, genericBindings),
        score: score,
    }
}

func matchTypePattern(string paramType, string argType, Vec[string] genericNames, Vec[TypeBinding] mut genericBindings) bool {
    var p = ParseType(paramType)
    var a = ParseType(argType)

    if isGenericName(genericNames, p) {
        var bound = lookupNameType(genericBindings, p)
        if isUnknown(bound) {
            genericBindings.push(TypeBinding {
                name: p,
                typeName: a,
            })
            ;
            return true
        }
        return SameType(bound, a)
    }

    if startsWith(p, "&mut ") {
        if !startsWith(a, "&mut ") {
            return false
        }
        return matchTypePattern(slice(p, 5, len(p)), slice(a, 5, len(a)), genericNames, genericBindings)
    }
    if startsWith(p, "&") {
        if !startsWith(a, "&") {
            return false
        }
        return matchTypePattern(slice(p, 1, len(p)), slice(a, 1, len(a)), genericNames, genericBindings)
    }
    if startsWith(p, "[]") {
        if !startsWith(a, "[]") {
            return false
        }
        return matchTypePattern(slice(p, 2, len(p)), slice(a, 2, len(a)), genericNames, genericBindings)
    }

    var pBase = BaseTypeName(p)
    var aBase = BaseTypeName(a)
    if pBase != aBase {
        return false
    }

    var pArgs = extractTypeArgs(p)
    var aArgs = extractTypeArgs(a)
    if pArgs.len() != aArgs.len() {
        return SameType(p, a)
    }

    var i = 0
    while i < pArgs.len() {
        if !matchTypePattern(pArgs[i], aArgs[i], genericNames, genericBindings) {
            return false
        }
        i = i + 1
    }
    true
}

func instantiateType(string ty, Vec[string] genericNames, Vec[TypeBinding] genericBindings) string {
    var clean = ParseType(ty)
    if isGenericName(genericNames, clean) {
        var bound = lookupNameType(genericBindings, clean)
        if !isUnknown(bound) {
            return bound
        }
    }

    if startsWith(clean, "&mut ") {
        return "&mut " + instantiateType(slice(clean, 5, len(clean)), genericNames, genericBindings)
    }
    if startsWith(clean, "&") {
        return "&" + instantiateType(slice(clean, 1, len(clean)), genericNames, genericBindings)
    }
    if startsWith(clean, "[]") {
        return "[]" + instantiateType(slice(clean, 2, len(clean)), genericNames, genericBindings)
    }

    var args = extractTypeArgs(clean)
    if args.len() == 0 {
        return clean
    }

    var base = BaseTypeName(clean)
    var built = base + "["
    var i = 0
    while i < args.len() {
        if i > 0 {
            built = built + ", "
        }
        built = built + instantiateType(args[i], genericNames, genericBindings)
        i = i + 1
    }
    built + "]"
}

func typeContainsGeneric(string ty, Vec[string] genericNames) bool {
    var clean = ParseType(ty)
    if isGenericName(genericNames, clean) {
        return true
    }

    if startsWith(clean, "&mut ") {
        return typeContainsGeneric(slice(clean, 5, len(clean)), genericNames)
    }
    if startsWith(clean, "&") {
        return typeContainsGeneric(slice(clean, 1, len(clean)), genericNames)
    }
    if startsWith(clean, "[]") {
        return typeContainsGeneric(slice(clean, 2, len(clean)), genericNames)
    }

    var args = extractTypeArgs(clean)
    var i = 0
    while i < args.len() {
        if typeContainsGeneric(args[i], genericNames) {
            return true
        }
        i = i + 1
    }
    false
}

func isGenericName(Vec[string] genericNames, string name) bool {
    var i = 0
    while i < genericNames.len() {
        if genericNames[i] == name {
            return true
        }
        i = i + 1
    }
    false
}

func genericName(string raw) string {
    var i = 0
    while i < len(raw) {
        if charAt(raw, i) == ":" {
            return trimText(slice(raw, 0, i))
        }
        i = i + 1
    }
    trimText(raw)
}

func cloneEnv(Vec[TypeBinding] env) Vec[TypeBinding] {
    var out = Vec[TypeBinding]()
    var i = 0
    while i < env.len() {
        out.push(env[i]);
        i = i + 1
    }
    out
}

func lookupNameType(Vec[TypeBinding] env, string name) string {
    var i = env.len()
    while i > 0 {
        i = i - 1
        if env[i].name == name {
            return env[i].typeName
        }
    }
    "unknown"
}

func okType(string typeName) CheckResult {
    CheckResult {
        typeName: ParseType(typeName),
        errors: 0,
    }
}

func typesCompatible(string left, string right) bool {
    if isUnknown(left) || isUnknown(right) {
        return true
    }
    SameType(left, right)
}

func isUnknown(string typeName) bool {
    var clean = ParseType(typeName)
    clean == "" || clean == "unknown"
}

func resolveMethodReturn(string targetType, string methodType) string {
    if methodType == "T" {
        return firstTypeArg(targetType)
    }
    if methodType == "E" {
        return secondTypeArg(targetType)
    }
    if methodType == "Option[T]" {
        var arg = firstTypeArg(targetType)
        if isUnknown(arg) {
            return "Option[unknown]"
        }
        return "Option[" + arg + "]"
    }
    ParseType(methodType)
}

func firstTypeArg(string typeName) string {
    var args = extractTypeArgs(typeName)
    if args.len() > 0 {
        return ParseType(args[0])
    }
    "unknown"
}

func secondTypeArg(string typeName) string {
    var args = extractTypeArgs(typeName)
    if args.len() > 1 {
        return ParseType(args[1])
    }
    "unknown"
}

func extractTypeArgs(string typeName) Vec[string] {
    var out = Vec[string]()
    var open = findChar(typeName, "[")
    var close = findLastChar(typeName, "]")
    if open < 0 || close <= open + 1 {
        return out
    }

    var inner = slice(typeName, open + 1, close)
    var depth = 0
    var start = 0
    var i = 0
    while i < len(inner) {
        var ch = charAt(inner, i)
        if ch == "[" {
            depth = depth + 1
        } else if ch == "]" {
            depth = depth - 1
        } else if ch == "," && depth == 0 {
            out.push(trimText(slice(inner, start, i)));
            start = i + 1
        }
        i = i + 1
    }

    if start < len(inner) {
        out.push(trimText(slice(inner, start, len(inner))));
    }

    out
}

func addError(string source, Vec[SemanticError] mut diagnostics, string code, string message, string anchor) int32 {
    var pos = locateAnchor(source, anchor)
    diagnostics.push(SemanticError {
        code: code,
        message: message,
        line: pos.line,
        column: pos.column,
    })
    ;
    1
}

func locateAnchor(string source, string anchor) SourcePos {
    if anchor == "" {
        return SourcePos {
            line: 0,
            column: 0,
        }
    }
    var idx = findSubstring(source, anchor)
    if idx < 0 {
        return SourcePos {
            line: 0,
            column: 0,
        }
    }
    indexToPos(source, idx)
}

func findSubstring(string haystack, string needle) int32 {
    if needle == "" {
        return 0
    }
    if len(needle) > len(haystack) {
        return 0 - 1
    }
    var i = 0
    while i + len(needle) <= len(haystack) {
        if slice(haystack, i, i + len(needle)) == needle {
            return i
        }
        i = i + 1
    }
    0 - 1
}

func indexToPos(string source, int32 index) SourcePos {
    var line = 1
    var column = 1
    var i = 0
    while i < index {
        if charAt(source, i) == "\n" {
            line = line + 1
            column = 1
        } else {
            column = column + 1
        }
        i = i + 1
    }
    SourcePos {
        line: line,
        column: column,
    }
}

func startsWith(string text, string prefix) bool {
    if len(prefix) > len(text) {
        return false
    }
    slice(text, 0, len(prefix)) == prefix
}

func findChar(string text, string needle) int32 {
    var i = 0
    while i < len(text) {
        if charAt(text, i) == needle {
            return i
        }
        i = i + 1
    }
    0 - 1
}

func findLastChar(string text, string needle) int32 {
    var i = len(text)
    while i > 0 {
        i = i - 1
        if charAt(text, i) == needle {
            return i
        }
    }
    0 - 1
}

func lastPathSegment(string path) string {
    var i = len(path)
    while i > 0 {
        i = i - 1
        if charAt(path, i) == "." {
            return slice(path, i + 1, len(path))
        }
    }
    path
}

func trimText(string text) string {
    var start = 0
    var end = len(text)
    while start < end && isSpace(charAt(text, start)) {
        start = start + 1
    }
    while end > start && isSpace(charAt(text, end - 1)) {
        end = end - 1
    }
    slice(text, start, end)
}

func isSpace(string ch) bool {
    ch == " " || ch == "\n" || ch == "\t" || ch == "\r"
}
