package compile.internal.semantic

use compile.internal.prelude.lookup_builtin_field_type
use compile.internal.prelude.lookup_builtin_method_arity
use compile.internal.prelude.lookup_builtin_method_type
use compile.internal.typesys.base_type_name
use compile.internal.typesys.parse_type
use compile.internal.typesys.same_type
use s.block_expr
use s.Expr
use s.function_decl
use s.impl_decl
use s.Item
use s.Pattern
use s.Stmt
use s.parse_source
use std.option.Option
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.vec.Vec

struct type_binding {
    string name,
    string type_name,
}

struct function_binding {
    string name,
    Vec[string] generic_names,
    Vec[string] param_types,
    string return_type,
}

struct signature_match {
    bool ok,
    string return_type,
    int32 score,
}

struct check_result {
    string type_name,
    int32 errors,
}

struct pattern_check_result {
    Vec[type_binding] bindings,
    int32 errors,
}

struct source_pos {
    int32 line,
    int32 column,
}

struct semantic_error {
    string code,
    string message,
    int32 line,
    int32 column,
}

func check_text(string source) int32 {
    var diagnostics = check_detailed(source);
    if diagnostics.len() > 0 {
        return 1;
    }
    0
}

func check_detailed(string source) Vec[semantic_error] {
    var diagnostics = Vec[semantic_error]()

    var parsed = parse_source(source)
    if parsed.is_err() {
        add_error(source, diagnostics, "E0001", "parse failed", "package");
        return diagnostics
    }

    var file = parsed.unwrap()
    var functions = collect_functions(file.items)

    var i = 0
    while i < file.items.len() {
        var ignored = check_item(file.items[i], functions, source, diagnostics)
        i = i + 1
    }

    diagnostics
}

func collect_functions(Vec[Item] items) Vec[function_binding] {
    var out = Vec[function_binding]()
    var i = 0
    while i < items.len() {
        switch items[i] {
            Item.Function(function_decl) : out.push(make_function_binding(function_decl)),
            _ : {},
        }
        i = i + 1
    }
    out
}

func make_function_binding(function_decl function_decl) function_binding {
    var generic_names = Vec[string]()
    var i = 0
    while i < function_decl.sig.generics.len() {
        generic_names.push(generic_name(function_decl.sig.generics[i]));
        i = i + 1
    }

    var params = Vec[string]()
    i = 0
    while i < function_decl.sig.params.len() {
        params.push(parse_type(function_decl.sig.params[i].type_name));
        i = i + 1
    }

    var return_type =
        switch function_decl.sig.return_type {
            Option.Some(type_name) : parse_type(type_name),
            Option.None : "()",
        }

    return function_binding {
        name: function_decl.sig.name,
        generic_names: generic_names,
        param_types: params,
        return_type: return_type,
    };
}

func check_item(Item item, Vec[function_binding] functions, string source, Vec[semantic_error] mut diagnostics) int32 {
    switch item {
        Item.Function(function_decl) : check_function(function_decl, functions, source, diagnostics),
        Item.Impl(impl_decl) : check_impl(impl_decl, functions, source, diagnostics),
        _ : 0,
    }
}

func check_impl(impl_decl impl_decl, Vec[function_binding] functions, string source, Vec[semantic_error] mut diagnostics) int32 {
    var errors = 0
    var i = 0
    while i < impl_decl.methods.len() {
        errors = errors + check_function(impl_decl.methods[i], functions, source, diagnostics)
        i = i + 1
    }
    errors
}

func check_function(function_decl function_decl, Vec[function_binding] functions, string source, Vec[semantic_error] mut diagnostics) int32 {
    if function_decl.body.is_none() {
        return 0
    }

    var expected_return =
        switch function_decl.sig.return_type {
            Option.Some(type_name) : parse_type(type_name),
            Option.None : "()",
        }

    var env = Vec[type_binding]()
    var i = 0
    while i < function_decl.sig.params.len() {
        var param = function_decl.sig.params[i]
        env.push(type_binding {
            name: param.name,
            type_name: parse_type(param.type_name),
        })
        ;
        i = i + 1
    }

    var result = infer_block_expr(function_decl.body.unwrap(), env, expected_return, functions, source, diagnostics)
    if expected_return != "()" && !is_unknown(expected_return) && !is_unknown(result.type_name) {
        if !same_type(expected_return, result.type_name) {
            return result.errors + add_error(source, diagnostics, "E3004", "function return type mismatch", function_decl.sig.name)
        }
    }
    result.errors
}

func infer_block_expr(block_expr block, Vec[type_binding] outer_env, string expected_return, Vec[function_binding] functions, string source, Vec[semantic_error] mut diagnostics) check_result {
    var local_env = clone_env(outer_env)
    var errors = 0

    var i = 0
    while i < block.statements.len() {
        errors = errors + check_stmt(block.statements[i], local_env, expected_return, functions, source, diagnostics)
        i = i + 1
    }

    switch block.final_expr {
        Option.Some(final_expr) : {
            var final_result = infer_expr(final_expr, local_env, expected_return, functions, source, diagnostics)
            check_result {
                type_name: final_result.type_name,
                errors: errors + final_result.errors,
            }
        }
        Option.None : check_result {
            type_name: "()",
            errors: errors,
        },
    }
}

func check_stmt(Stmt stmt, Vec[type_binding] mut env, string expected_return, Vec[function_binding] functions, string source, Vec[semantic_error] mut diagnostics) int32 {
    switch stmt {
        Stmt.Var(value) : {
            var rhs = infer_expr(value.value, env, expected_return, functions, source, diagnostics)
            var errors = rhs.errors

            var binding_type = rhs.type_name
            if value.type_name.is_some() {
                var declared = parse_type(value.type_name.unwrap())
                if !types_compatible(declared, rhs.type_name) {
                    errors = errors + add_error(source, diagnostics, "E3001", "variable initializer type mismatch", value.name)
                }
                binding_type = declared
            }

            env.push(type_binding {
                name: value.name,
                type_name: binding_type,
            })
            ;
            errors
        }
        Stmt.Assign(value) : {
            var target_type = lookup_name_type(env, value.name)
            var rhs = infer_expr(value.value, env, expected_return, functions, source, diagnostics)
            var errors = rhs.errors
            if is_unknown(target_type) {
                return errors + add_error(source, diagnostics, "E3002", "assignment to undefined name", value.name)
            }
            if !types_compatible(target_type, rhs.type_name) {
                return errors + add_error(source, diagnostics, "E3003", "assignment type mismatch", value.name)
            }
            errors
        }
        Stmt.Increment(value) : {
            var ty = lookup_name_type(env, value.name)
            if !types_compatible("int32", ty) {
                return add_error(source, diagnostics, "E3005", "increment requires int32", value.name)
            }
            0
        }
        Stmt.c_for(value) : {
            var errors = 0
            errors = errors + check_stmt(value.init.value, env, expected_return, functions, source, diagnostics)
            var cond = infer_expr(value.condition, env, expected_return, functions, source, diagnostics)
            errors = errors + cond.errors
            if !types_compatible("bool", cond.type_name) {
                errors = errors + add_error(source, diagnostics, "E3006", "for condition must be bool", "for")
            }
            errors = errors + check_stmt(value.step.value, env, expected_return, functions, source, diagnostics)
            var body_result = infer_block_expr(value.body, env, expected_return, functions, source, diagnostics)
            errors = errors + body_result.errors
            errors
        }
        Stmt.Return(value) : {
            switch value.value {
                Option.Some(expr) : {
                    var expr_result = infer_expr(expr, env, expected_return, functions, source, diagnostics)
                    if expected_return == "()" {
                        return expr_result.errors + add_error(source, diagnostics, "E3007", "unexpected return value", "return")
                    }
                    if !types_compatible(expected_return, expr_result.type_name) {
                        return expr_result.errors + add_error(source, diagnostics, "E3008", "return type mismatch", "return")
                    }
                    expr_result.errors
                }
                Option.None : {
                    if expected_return == "()" {
                        return 0
                    }
                    add_error(source, diagnostics, "E3009", "missing return value", "return")
                }
            }
        }
        Stmt.Expr(value) : {
            infer_expr(value.expr, env, expected_return, functions, source, diagnostics).errors
        }
        Stmt.Defer(value) : {
            infer_expr(value.expr, env, expected_return, functions, source, diagnostics).errors
        }
    }
}

func infer_expr(Expr expr, Vec[type_binding] env, string expected_return, Vec[function_binding] functions, string source, Vec[semantic_error] mut diagnostics) check_result {
    switch expr {
        Expr::Int(_) : ok_type("int32"),
        Expr::String(_) : ok_type("string"),
        Expr::Bool(_) : ok_type("bool"),
        Expr::Name(value) : {
            var ty = lookup_name_type(env, value.name)
            if is_unknown(ty) {
                return check_result {
                    type_name: "unknown",
                    errors: add_error(source, diagnostics, "E3010", "undefined identifier", value.name),
                }
            }
            ok_type(ty)
        }
        Expr::Borrow(value) : {
            var base = infer_expr(value.target.value, env, expected_return, functions, source, diagnostics)
            if is_unknown(base.type_name) {
                return base
            }
            var prefix = if value.mutable { "&mut " } else { "&" }
            check_result {
                type_name: prefix + base.type_name,
                errors: base.errors,
            }
        }
        Expr::Binary(value) : {
            var left = infer_expr(value.left.value, env, expected_return, functions, source, diagnostics)
            var right = infer_expr(value.right.value, env, expected_return, functions, source, diagnostics)
            infer_binary(value.op, left, right, source, diagnostics)
        }
        Expr::Member(value) : {
            var target = infer_expr(value.target.value, env, expected_return, functions, source, diagnostics)
            var field_type = lookup_builtin_field_type(target.type_name, value.member)
            if field_type == "" {
                return check_result {
                    type_name: "unknown",
                    errors: target.errors + add_error(source, diagnostics, "E3011", "unknown member", value.member),
                }
            }
            check_result {
                type_name: parse_type(field_type),
                errors: target.errors,
            }
        }
        Expr::Index(value) : {
            var target = infer_expr(value.target.value, env, expected_return, functions, source, diagnostics)
            var index = infer_expr(value.index.value, env, expected_return, functions, source, diagnostics)
            var errors = target.errors + index.errors
            if !types_compatible("int32", index.type_name) {
                errors = errors + add_error(source, diagnostics, "E3012", "index must be int32", "[")
            }
            if starts_with(target.type_name, "[]") {
                return check_result {
                    type_name: parse_type(slice(target.type_name, 2, len(target.type_name))),
                    errors: errors,
                }
            }
            if starts_with(target.type_name, "string") {
                return check_result {
                    type_name: "u8",
                    errors: errors,
                }
            }
            check_result {
                type_name: "unknown",
                errors: errors + add_error(source, diagnostics, "E3013", "index target is not indexable", "["),
            }
        }
        Expr::Call(value) : {
            var errors = 0
            var arg_types = Vec[string]()
            var i = 0
            while i < value.args.len() {
                var arg_result = infer_expr(value.args[i], env, expected_return, functions, source, diagnostics)
                errors = errors + arg_result.errors
                arg_types.push(arg_result.type_name);
                i = i + 1
            }

            switch value.callee.value {
                Expr::Member(member) : {
                    var target = infer_expr(member.target.value, env, expected_return, functions, source, diagnostics)
                    errors = errors + target.errors

                    var arity = lookup_builtin_method_arity(target.type_name, member.member)
                    if arity >= 0 && arity != value.args.len() {
                        errors = errors + add_error(source, diagnostics, "E1005", "builtin method arity mismatch", member.member)
                    }

                    var method_type = lookup_builtin_method_type(target.type_name, member.member)
                    if method_type == "" {
                        return check_result {
                            type_name: "unknown",
                            errors: errors + add_error(source, diagnostics, "E1006", "unknown builtin method", member.member),
                        }
                    }
                    check_result {
                        type_name: resolve_method_return(target.type_name, method_type),
                        errors: errors,
                    }
                }
                Expr::Name(callee_name) : {
                    var candidates = lookup_functions(functions, callee_name.name)
                    if candidates.len() == 0 {
                        return check_result {
                            type_name: "unknown",
                            errors: errors + add_error(source, diagnostics, "E1001", "undefined function", callee_name.name),
                        }
                    }

                    var matches = Vec[signature_match]()
                    var j = 0
                    while j < candidates.len() {
                        var m = try_match_signature(candidates[j], arg_types)
                        if m.ok {
                            matches.push(m);
                        }
                        j = j + 1
                    }

                    if matches.len() == 0 {
                        return check_result {
                            type_name: "unknown",
                            errors: errors + add_error(source, diagnostics, "E1002", "no matching overload", callee_name.name),
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
                        return check_result {
                            type_name: "unknown",
                            errors: errors + add_error(source, diagnostics, "E1003", "ambiguous overload", callee_name.name),
                        }
                    }

                    check_result {
                        type_name: best.return_type,
                        errors: errors,
                    }
                }
                _ : {
                    var callee = infer_expr(value.callee.value, env, expected_return, functions, source, diagnostics)
                    check_result {
                        type_name: "unknown",
                        errors: errors + callee.errors,
                    }
                }
            }
        }
        Expr::Switch(value) : {
            var subject = infer_expr(value.subject.value, env, expected_return, functions, source, diagnostics)
            var errors = subject.errors
            var arm_type = "unknown"
            var seen_patterns = Vec[Pattern]()

            var i = 0
            while i < value.arms.len() {
                var arm = value.arms[i]
                if pattern_unreachable(seen_patterns, arm.pattern, subject.type_name) {
                    errors = errors + add_error(source, diagnostics, "E2003", "unreachable switch arm", pattern_anchor(arm.pattern))
                }

                if pattern_duplicate(seen_patterns, arm.pattern, subject.type_name) {
                    errors = errors + add_error(source, diagnostics, "E2002", "duplicate switch arm", pattern_anchor(arm.pattern))
                }

                var pattern_result = check_pattern(arm.pattern, subject.type_name, source, diagnostics)
                errors = errors + pattern_result.errors

                var arm_env = clone_env(env)
                append_bindings(arm_env, pattern_result.bindings)

                var arm_result = infer_expr(arm.expr, arm_env, expected_return, functions, source, diagnostics)
                errors = errors + arm_result.errors
                if is_unknown(arm_type) {
                    arm_type = arm_result.type_name
                } else if !types_compatible(arm_type, arm_result.type_name) {
                    errors = errors + add_error(source, diagnostics, "E2005", "switch arm result type mismatch", "switch")
                }

                seen_patterns.push(arm.pattern);
                i = i + 1
            }

            var base = base_type_name(subject.type_name)
            if (base == "Option" || base == "Result") && !patterns_cover_type(seen_patterns, subject.type_name) {
                errors = errors + add_error(source, diagnostics, "E2001", "non-exhaustive switch", "switch")
            }

            check_result {
                type_name: arm_type,
                errors: errors,
            }
        }
        Expr::If(value) : {
            var cond = infer_expr(value.condition.value, env, expected_return, functions, source, diagnostics)
            var then_result = infer_block_expr(value.then_branch, env, expected_return, functions, source, diagnostics)
            var errors = cond.errors + then_result.errors
            if !types_compatible("bool", cond.type_name) {
                errors = errors + add_error(source, diagnostics, "E3014", "if condition must be bool", "if")
            }
            switch value.else_branch {
                Option::Some(else_expr) : {
                    var else_result = infer_expr(else_expr.value, env, expected_return, functions, source, diagnostics)
                    errors = errors + else_result.errors
                    if !types_compatible(then_result.type_name, else_result.type_name) {
                        errors = errors + add_error(source, diagnostics, "E3015", "if/else type mismatch", "if")
                    }
                    check_result {
                        type_name: then_result.type_name,
                        errors: errors,
                    }
                }
                Option::None : check_result {
                    type_name: "()",
                    errors: errors,
                },
            }
        }
        Expr::While(value) : {
            var cond = infer_expr(value.condition.value, env, expected_return, functions, source, diagnostics)
            var body_result = infer_block_expr(value.body, env, expected_return, functions, source, diagnostics)
            var errors = cond.errors + body_result.errors
            if !types_compatible("bool", cond.type_name) {
                errors = errors + add_error(source, diagnostics, "E3016", "while condition must be bool", "while")
            }
            check_result {
                type_name: "()",
                errors: errors,
            }
        }
        Expr::For(value) : {
            var iter = infer_expr(value.iterable.value, env, expected_return, functions, source, diagnostics)
            var body_result = infer_block_expr(value.body, env, expected_return, functions, source, diagnostics)
            check_result {
                type_name: "()",
                errors: iter.errors + body_result.errors,
            }
        }
        Expr::Block(value) : {
            infer_block_expr(value, env, expected_return, functions, source, diagnostics)
        }
        Expr::Array(value) : {
            if value.items.len() == 0 {
                return ok_type("[]unknown")
            }

            var first = infer_expr(value.items[0], env, expected_return, functions, source, diagnostics)
            var errors = first.errors
            var i = 1
            while i < value.items.len() {
                var item = infer_expr(value.items[i], env, expected_return, functions, source, diagnostics)
                errors = errors + item.errors
                if !types_compatible(first.type_name, item.type_name) {
                    errors = errors + add_error(source, diagnostics, "E3017", "array item type mismatch", "[")
                }
                i = i + 1
            }
            check_result {
                type_name: "[]" + first.type_name,
                errors: errors,
            }
        }
        Expr::Map(value) : {
            var errors = 0
            var i = 0
            while i < value.entries.len() {
                errors = errors + infer_expr(value.entries[i].key, env, expected_return, functions, source, diagnostics).errors
                errors = errors + infer_expr(value.entries[i].value, env, expected_return, functions, source, diagnostics).errors
                i = i + 1
            }
            check_result {
                type_name: "map",
                errors: errors,
            }
        }
    }
}

func check_pattern(Pattern pattern, string expected_type, string source, Vec[semantic_error] mut diagnostics) pattern_check_result {
    var bindings = Vec[type_binding]()
    var errors = bind_pattern(pattern, expected_type, bindings, source, diagnostics)
    pattern_check_result {
        bindings: bindings,
        errors: errors,
    }
}

func bind_pattern(Pattern pattern, string expected_type, Vec[type_binding] mut bindings, string source, Vec[semantic_error] mut diagnostics) int32 {
    if is_unknown(expected_type) {
        return add_error(source, diagnostics, "E2007", "pattern expected type is unknown", pattern_anchor(pattern))
    }

    switch pattern {
        Pattern::Name(value) : {
            add_binding(bindings, value.name, expected_type, source, diagnostics)
        }
        Pattern::Wildcard(_) : 0,
        Pattern::Literal(value) : {
            var literal_type = literal_pattern_type(value)
            if !types_compatible(expected_type, literal_type) {
                return add_error(source, diagnostics, "E2006", "literal pattern type mismatch", literal_pattern_text(value))
            }
            0
        }
        Pattern::Variant(value) : {
            var variant = last_path_segment(value.path)
            var base = base_type_name(expected_type)
            if base == "Option" {
                if variant == "Some" {
                    if value.args.len() != 1 {
                        return add_error(source, diagnostics, "E2004", "Some payload arity mismatch", value.path)
                    }
                    return bind_pattern(value.args[0], first_type_arg(expected_type), bindings, source, diagnostics)
                }
                if variant == "None" {
                    if value.args.len() == 0 {
                        return 0
                    }
                    return add_error(source, diagnostics, "E2004", "None must not have payload", value.path)
                }
                return add_error(source, diagnostics, "E2006", "invalid Option constructor", value.path)
            }
            if base == "Result" {
                if variant == "Ok" {
                    if value.args.len() != 1 {
                        return add_error(source, diagnostics, "E2004", "Ok payload arity mismatch", value.path)
                    }
                    return bind_pattern(value.args[0], first_type_arg(expected_type), bindings, source, diagnostics)
                }
                if variant == "Err" {
                    if value.args.len() != 1 {
                        return add_error(source, diagnostics, "E2004", "Err payload arity mismatch", value.path)
                    }
                    return bind_pattern(value.args[0], second_type_arg(expected_type), bindings, source, diagnostics)
                }
                return add_error(source, diagnostics, "E2006", "invalid Result constructor", value.path)
            }
            add_error(source, diagnostics, "E2006", "variant pattern not allowed for this type", value.path)
        }
    }
}

func add_binding(Vec[type_binding] mut bindings, string name, string type_name, string source, Vec[semantic_error] mut diagnostics) int32 {
    if name == "_" {
        return 0
    }

    var i = 0
    while i < bindings.len() {
        if bindings[i].name == name {
            if !types_compatible(bindings[i].type_name, type_name) {
                return add_error(source, diagnostics, "E2008", "conflicting binding type in pattern", name)
            }
            return 0
        }
        i = i + 1
    }

    bindings.push(type_binding {
        name: name,
        type_name: parse_type(type_name),
    })
    ;
    0
}

func append_bindings(Vec[type_binding] mut target, Vec[type_binding] source) () {
    var i = 0
    while i < source.len() {
        target.push(source[i]);
        i = i + 1
    }
}

func pattern_duplicate(Vec[Pattern] seen, Pattern current, string expected_type) bool {
    var i = 0
    while i < seen.len() {
        if pattern_equivalent(seen[i], current, expected_type) {
            return true
        }
        i = i + 1
    }
    false
}

func pattern_unreachable(Vec[Pattern] seen, Pattern current, string expected_type) bool {
    var i = 0
    while i < seen.len() {
        if pattern_subsumes(seen[i], current, expected_type) {
            return true
        }
        i = i + 1
    }
    false
}

func pattern_equivalent(Pattern left, Pattern right, string expected_type) bool {
    pattern_subsumes(left, right, expected_type) && pattern_subsumes(right, left, expected_type)
}

func pattern_subsumes(Pattern left, Pattern right, string expected_type) bool {
    if pattern_is_wild(left) {
        return true
    }
    if pattern_is_wild(right) {
        return false
    }

    switch left {
        Pattern::Literal(lv) : {
            switch right {
                Pattern::Literal(rv) : literal_pattern_equals(lv, rv),
                _ : false,
            }
        }
        Pattern::Variant(lv) : {
            switch right {
                Pattern::Variant(rv) : {
                    var lctor = last_path_segment(lv.path)
                    var rctor = last_path_segment(rv.path)
                    if lctor != rctor {
                        return false
                    }
                    if lv.args.len() == 0 && rv.args.len() == 0 {
                        return true
                    }
                    if lv.args.len() != 1 || rv.args.len() != 1 {
                        return false
                    }

                    var payload_type = variant_payload_type(expected_type, lctor)
                    if is_unknown(payload_type) {
                        return false
                    }
                    return pattern_subsumes(lv.args[0], rv.args[0], payload_type)
                }
                _ : false,
            }
        }
        _ : false,
    }
}

func patterns_cover_type(Vec[Pattern] patterns, string expected_type) bool {
    var i = 0
    while i < patterns.len() {
        if pattern_is_wild(patterns[i]) {
            return true
        }
        i = i + 1
    }

    var base = base_type_name(expected_type)
    if base == "Option" {
        return option_patterns_cover(patterns, expected_type)
    }
    if base == "Result" {
        return result_patterns_cover(patterns, expected_type)
    }

    false
}

func option_patterns_cover(Vec[Pattern] patterns, string expected_type) bool {
    var seen_none = false
    var some_patterns = Vec[Pattern]()

    var i = 0
    while i < patterns.len() {
        switch patterns[i] {
            Pattern::Variant(value) : {
                var ctor = last_path_segment(value.path)
                if ctor == "None" {
                    seen_none = true
                } else if ctor == "Some" && value.args.len() == 1 {
                    some_patterns.push(value.args[0]);
                }
            }
            _ : (),
        }
        i = i + 1
    }

    if !seen_none {
        return false
    }
    patterns_cover_type(some_patterns, first_type_arg(expected_type))
}

func result_patterns_cover(Vec[Pattern] patterns, string expected_type) bool {
    var ok_patterns = Vec[Pattern]()
    var err_patterns = Vec[Pattern]()

    var i = 0
    while i < patterns.len() {
        switch patterns[i] {
            Pattern::Variant(value) : {
                var ctor = last_path_segment(value.path)
                if ctor == "Ok" && value.args.len() == 1 {
                    ok_patterns.push(value.args[0]);
                } else if ctor == "Err" && value.args.len() == 1 {
                    err_patterns.push(value.args[0]);
                }
            }
            _ : (),
        }
        i = i + 1
    }

    if !patterns_cover_type(ok_patterns, first_type_arg(expected_type)) {
        return false
    }
    patterns_cover_type(err_patterns, second_type_arg(expected_type))
}

func pattern_is_wild(Pattern pattern) bool {
    switch pattern {
        Pattern::Wildcard(_) : true,
        Pattern::Name(_) : true,
        _ : false,
    }
}

func pattern_anchor(Pattern pattern) string {
    switch pattern {
        Pattern::Name(value) : value.name,
        Pattern::Wildcard(_) : "_",
        Pattern::Literal(value) : literal_pattern_text(value),
        Pattern::Variant(value) : value.path,
    }
}

func literal_pattern_type(literal_pattern value) string {
    switch value.value {
        Expr::Int(_) : "int32",
        Expr::string(_) : "string",
        Expr::Bool(_) : "bool",
        _ : "unknown",
    }
}

func literal_pattern_text(literal_pattern value) string {
    switch value.value {
        Expr::Int(v) : v.value,
        Expr::string(v) : v.value,
        Expr::Bool(v) : if v.value { "true" } else { "false" },
        _ : "<literal>",
    }
}

func literal_pattern_equals(literal_pattern left, literal_pattern right) bool {
    literal_pattern_type(left) == literal_pattern_type(right) && literal_pattern_text(left) == literal_pattern_text(right)
}

func variant_payload_type(string expected_type, string ctor) string {
    var base = base_type_name(expected_type)
    if base == "Option" {
        if ctor == "Some" {
            return first_type_arg(expected_type)
        }
        if ctor == "None" {
            return "()"
        }
    }
    if base == "Result" {
        if ctor == "Ok" {
            return first_type_arg(expected_type)
        }
        if ctor == "Err" {
            return second_type_arg(expected_type)
        }
    }
    "unknown"
}

func infer_binary(string op, check_result left, check_result right, string source, Vec[semantic_error] mut diagnostics) check_result {
    var errors = left.errors + right.errors

    if op == "+" || op == "-" || op == "*" || op == "/" || op == "%" {
        if !types_compatible("int32", left.type_name) || !types_compatible("int32", right.type_name) {
            errors = errors + add_error(source, diagnostics, "E3018", "arithmetic requires int32", op)
        }
        return check_result {
            type_name: "int32",
            errors: errors,
        }
    }

    if op == "<" || op == "<=" || op == ">" || op == ">=" {
        if !types_compatible("int32", left.type_name) || !types_compatible("int32", right.type_name) {
            errors = errors + add_error(source, diagnostics, "E3019", "ordering compare requires int32", op)
        }
        return check_result {
            type_name: "bool",
            errors: errors,
        }
    }

    if op == "==" || op == "!=" {
        if !types_compatible(left.type_name, right.type_name) {
            errors = errors + add_error(source, diagnostics, "E3020", "equality compare requires same type", op)
        }
        return check_result {
            type_name: "bool",
            errors: errors,
        }
    }

    if op == "&&" || op == "||" {
        if !types_compatible("bool", left.type_name) || !types_compatible("bool", right.type_name) {
            errors = errors + add_error(source, diagnostics, "E3021", "logical op requires bool", op)
        }
        return check_result {
            type_name: "bool",
            errors: errors,
        }
    }

    check_result {
        type_name: "unknown",
        errors: errors,
    }
}

func lookup_functions(Vec[function_binding] functions, string name) Vec[function_binding] {
    var out = Vec[function_binding]()
    var i = 0
    while i < functions.len() {
        if functions[i].name == name {
            out.push(functions[i]);
        }
        i = i + 1
    }
    out
}

func try_match_signature(function_binding binding, Vec[string] arg_types) signature_match {
    if binding.param_types.len() != arg_types.len() {
        return signature_match {
            ok: false,
            return_type: "unknown",
            score: 0,
        }
    }

    var generic_bindings = Vec[type_binding]()
    var score = 0

    var i = 0
    while i < arg_types.len() {
        var matched = match_type_pattern(binding.param_types[i], arg_types[i], binding.generic_names, generic_bindings)
        if !matched {
            return signature_match {
                ok: false,
                return_type: "unknown",
                score: 0,
            }
        }
        if !type_contains_generic(binding.param_types[i], binding.generic_names) {
            score = score + 1
        }
        i = i + 1
    }

    signature_match {
        ok: true,
        return_type: instantiate_type(binding.return_type, binding.generic_names, generic_bindings),
        score: score,
    }
}

func match_type_pattern(string param_type, string arg_type, Vec[string] generic_names, Vec[type_binding] mut generic_bindings) bool {
    var p = parse_type(param_type)
    var a = parse_type(arg_type)

    if is_generic_name(generic_names, p) {
        var bound = lookup_name_type(generic_bindings, p)
        if is_unknown(bound) {
            generic_bindings.push(type_binding {
                name: p,
                type_name: a,
            })
            ;
            return true
        }
        return same_type(bound, a)
    }

    if starts_with(p, "&mut ") {
        if !starts_with(a, "&mut ") {
            return false
        }
        return match_type_pattern(slice(p, 5, len(p)), slice(a, 5, len(a)), generic_names, generic_bindings)
    }
    if starts_with(p, "&") {
        if !starts_with(a, "&") {
            return false
        }
        return match_type_pattern(slice(p, 1, len(p)), slice(a, 1, len(a)), generic_names, generic_bindings)
    }
    if starts_with(p, "[]") {
        if !starts_with(a, "[]") {
            return false
        }
        return match_type_pattern(slice(p, 2, len(p)), slice(a, 2, len(a)), generic_names, generic_bindings)
    }

    var p_base = base_type_name(p)
    var a_base = base_type_name(a)
    if p_base != a_base {
        return false
    }

    var p_args = extract_type_args(p)
    var a_args = extract_type_args(a)
    if p_args.len() != a_args.len() {
        return same_type(p, a)
    }

    var i = 0
    while i < p_args.len() {
        if !match_type_pattern(p_args[i], a_args[i], generic_names, generic_bindings) {
            return false
        }
        i = i + 1
    }
    true
}

func instantiate_type(string ty, Vec[string] generic_names, Vec[type_binding] generic_bindings) string {
    var clean = parse_type(ty)
    if is_generic_name(generic_names, clean) {
        var bound = lookup_name_type(generic_bindings, clean)
        if !is_unknown(bound) {
            return bound
        }
    }

    if starts_with(clean, "&mut ") {
        return "&mut " + instantiate_type(slice(clean, 5, len(clean)), generic_names, generic_bindings)
    }
    if starts_with(clean, "&") {
        return "&" + instantiate_type(slice(clean, 1, len(clean)), generic_names, generic_bindings)
    }
    if starts_with(clean, "[]") {
        return "[]" + instantiate_type(slice(clean, 2, len(clean)), generic_names, generic_bindings)
    }

    var args = extract_type_args(clean)
    if args.len() == 0 {
        return clean
    }

    var base = base_type_name(clean)
    var built = base + "["
    var i = 0
    while i < args.len() {
        if i > 0 {
            built = built + ", "
        }
        built = built + instantiate_type(args[i], generic_names, generic_bindings)
        i = i + 1
    }
    built + "]"
}

func type_contains_generic(string ty, Vec[string] generic_names) bool {
    var clean = parse_type(ty)
    if is_generic_name(generic_names, clean) {
        return true
    }

    if starts_with(clean, "&mut ") {
        return type_contains_generic(slice(clean, 5, len(clean)), generic_names)
    }
    if starts_with(clean, "&") {
        return type_contains_generic(slice(clean, 1, len(clean)), generic_names)
    }
    if starts_with(clean, "[]") {
        return type_contains_generic(slice(clean, 2, len(clean)), generic_names)
    }

    var args = extract_type_args(clean)
    var i = 0
    while i < args.len() {
        if type_contains_generic(args[i], generic_names) {
            return true
        }
        i = i + 1
    }
    false
}

func is_generic_name(Vec[string] generic_names, string name) bool {
    var i = 0
    while i < generic_names.len() {
        if generic_names[i] == name {
            return true
        }
        i = i + 1
    }
    false
}

func generic_name(string raw) string {
    var i = 0
    while i < len(raw) {
        if char_at(raw, i) == ":" {
            return trim_text(slice(raw, 0, i))
        }
        i = i + 1
    }
    trim_text(raw)
}

func clone_env(Vec[type_binding] env) Vec[type_binding] {
    var out = Vec[type_binding]()
    var i = 0
    while i < env.len() {
        out.push(env[i]);
        i = i + 1
    }
    out
}

func lookup_name_type(Vec[type_binding] env, string name) string {
    var i = env.len()
    while i > 0 {
        i = i - 1
        if env[i].name == name {
            return env[i].type_name
        }
    }
    "unknown"
}

func ok_type(string type_name) check_result {
    check_result {
        type_name: parse_type(type_name),
        errors: 0,
    }
}

func types_compatible(string left, string right) bool {
    if is_unknown(left) || is_unknown(right) {
        return true
    }
    same_type(left, right)
}

func is_unknown(string type_name) bool {
    var clean = parse_type(type_name)
    clean == "" || clean == "unknown"
}

func resolve_method_return(string target_type, string method_type) string {
    if method_type == "T" {
        return first_type_arg(target_type)
    }
    if method_type == "E" {
        return second_type_arg(target_type)
    }
    if method_type == "Option[T]" {
        var arg = first_type_arg(target_type)
        if is_unknown(arg) {
            return "Option[unknown]"
        }
        return "Option[" + arg + "]"
    }
    parse_type(method_type)
}

func first_type_arg(string type_name) string {
    var args = extract_type_args(type_name)
    if args.len() > 0 {
        return parse_type(args[0])
    }
    "unknown"
}

func second_type_arg(string type_name) string {
    var args = extract_type_args(type_name)
    if args.len() > 1 {
        return parse_type(args[1])
    }
    "unknown"
}

func extract_type_args(string type_name) Vec[string] {
    var out = Vec[string]()
    var open = find_char(type_name, "[")
    var close = find_last_char(type_name, "]")
    if open < 0 || close <= open + 1 {
        return out
    }

    var inner = slice(type_name, open + 1, close)
    var depth = 0
    var start = 0
    var i = 0
    while i < len(inner) {
        var ch = char_at(inner, i)
        if ch == "[" {
            depth = depth + 1
        } else if ch == "]" {
            depth = depth - 1
        } else if ch == "," && depth == 0 {
            out.push(trim_text(slice(inner, start, i)));
            start = i + 1
        }
        i = i + 1
    }

    if start < len(inner) {
        out.push(trim_text(slice(inner, start, len(inner))));
    }

    out
}

func add_error(string source, Vec[semantic_error] mut diagnostics, string code, string message, string anchor) int32 {
    var pos = locate_anchor(source, anchor)
    diagnostics.push(semantic_error {
        code: code,
        message: message,
        line: pos.line,
        column: pos.column,
    })
    ;
    1
}

func locate_anchor(string source, string anchor) source_pos {
    if anchor == "" {
        return source_pos {
            line: 0,
            column: 0,
        }
    }
    var idx = find_substring(source, anchor)
    if idx < 0 {
        return source_pos {
            line: 0,
            column: 0,
        }
    }
    index_to_pos(source, idx)
}

func find_substring(string haystack, string needle) int32 {
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

func index_to_pos(string source, int32 index) source_pos {
    var line = 1
    var column = 1
    var i = 0
    while i < index {
        if char_at(source, i) == "\n" {
            line = line + 1
            column = 1
        } else {
            column = column + 1
        }
        i = i + 1
    }
    source_pos {
        line: line,
        column: column,
    }
}

func starts_with(string text, string prefix) bool {
    if len(prefix) > len(text) {
        return false
    }
    slice(text, 0, len(prefix)) == prefix
}

func find_char(string text, string needle) int32 {
    var i = 0
    while i < len(text) {
        if char_at(text, i) == needle {
            return i
        }
        i = i + 1
    }
    0 - 1
}

func find_last_char(string text, string needle) int32 {
    var i = len(text)
    while i > 0 {
        i = i - 1
        if char_at(text, i) == needle {
            return i
        }
    }
    0 - 1
}

func last_path_segment(string path) string {
    var i = len(path)
    while i > 0 {
        i = i - 1
        if char_at(path, i) == "." {
            return slice(path, i + 1, len(path))
        }
    }
    path
}

func trim_text(string text) string {
    var start = 0
    var end = len(text)
    while start < end && is_space(char_at(text, start)) {
        start = start + 1
    }
    while end > start && is_space(char_at(text, end - 1)) {
        end = end - 1
    }
    slice(text, start, end)
}

func is_space(string ch) bool {
    ch == " " || ch == "\n" || ch == "\t" || ch == "\r"
}
