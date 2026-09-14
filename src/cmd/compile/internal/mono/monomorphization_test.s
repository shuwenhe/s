package compile.internal.mono_test
import (
    "compile.internal.mono"
    "s"
    "std.option"
    "std.prelude"
)
func run_monomorphization_test() int {
    int_args := string[] { "int" }
    box_args := string[] { "box[int]" }
    first := compile.internal.mono.make_instance_name("identity", int_args)
    second := compile.internal.mono.make_instance_name("identity", int_args)
    other := compile.internal.mono.make_instance_name("identity", box_args)
    if first == "" || first != second || first == other {
        return 1
    }
    cache := compile.internal.mono.new_cache()
    int_key := compile.internal.mono.make_instance_key("identity", int_args)
    box_key := compile.internal.mono.make_instance_key("identity", box_args)
    first_result := compile.internal.mono.mono_cache_get_or_create_key(cache, int_key)
    cache = first_result.cache
    second_result := compile.internal.mono.mono_cache_get_or_create_key(cache, int_key)
    cache = second_result.cache
    box_result := compile.internal.mono.mono_cache_get_or_create_key(cache, box_key)
    cache = box_result.cache
    if first_result.instance_name != second_result.instance_name || first_result.instance_name == box_result.instance_name || compile.internal.mono.mono_cache_count(cache) != 2 {
        return 1
    }
    generic := function_decl {
        sig: function_sig {
            name: "identity",
            generics: string[] { "T" },
            params: param[] { param { name: "value", type_name: "T" } },
            return_type: option.some("T"),
        },
        body: option.none,
        is_public: false,
    }
    int_instance := compile.internal.mono.specialize_function(generic, int_args)
    box_instance := compile.internal.mono.specialize_function(generic, box_args)
    if int_instance.sig.name == box_instance.sig.name {
        return 1
    }
    if int_instance.sig.params[0].type_name != "int" || int_instance.sig.return_type.unwrap() != "int" {
        return 1
    }
    if box_instance.sig.params[0].type_name != "box[int]" || box_instance.sig.return_type.unwrap() != "box[int]" {
        return 1
    }
    nested_args := string[] { "string[]" }
    nested := compile.internal.mono.specialize_function(generic, nested_args)
    if nested.sig.params[0].type_name != "string[]" || nested.sig.return_type.unwrap() != "string[]" {
        return 1
    }
    if compile.internal.mono.substitute_type("box[T[]]", string[] { "T" }, string[] { "int" }) != "box[int[]]" {
        return 1
    }
    call_args := expr[] { expr::int(int_expr { value: "1", inferred_type option::some("int") }) }
    mono_call := expr::call(call_expr {
        callee: std.prelude.box(expr::name(name_expr { name: "identity", inferred_type option::none })),
        args: call_args,
        inferred_type: option::some("int"),
        resolved_callee: option::some("identity__mono_int"),
        type_args: string[] { "int" },
    })
    caller := function_decl {
        sig: function_sig {
            name: "caller",
            generics: string[] {},
            params: param[] {},
            return_type: option::some("int"),
        },
        body: option::some(block_expr { statements: stmt[] {}, final_expr option::some(mono_call), inferred_type option::some("int") }),
        is_public: false,
    }
    bar_call := expr::call(call_expr {
        callee: std.prelude.box(expr::name(name_expr { name: "bar", inferred_type option::none })),
        args: expr[] { expr::name(name_expr { name: "value", inferred_type option::some("T") }) },
        inferred_type: option::some("T"),
        resolved_callee: option::some("bar__mono_T"),
        type_args: string[] { "T" },
    })
    foo := function_decl {
        sig: function_sig {
            name: "foo",
            generics: string[] { "T" },
            params: param[] { param { name: "value", type_name: "T" } },
            return_type: option::some("T"),
        },
        body: option::some(block_expr { statements: stmt[] {}, final_expr option::some(bar_call), inferred_type option::some("T") }),
        is_public: false,
    }
    baz_call := expr::call(call_expr {
        callee: std.prelude.box(expr::name(name_expr { name: "baz", inferred_type option::none })),
        args: expr[] { expr::name(name_expr { name: "value", inferred_type option::some("T") }) },
        inferred_type: option::some("T"),
        resolved_callee: option::some("baz__mono_T"),
        type_args: string[] { "T" },
    })
    bar := function_decl {
        sig: function_sig {
            name: "bar",
            generics: string[] { "T" },
            params: param[] { param { name: "value", type_name: "T" } },
            return_type: option::some("T"),
        },
        body: option::some(block_expr { statements: stmt[] {}, final_expr option::some(baz_call), inferred_type option::some("T") }),
        is_public: false,
    }
    baz := function_decl {
        sig: function_sig {
            name: "baz",
            generics: string[] { "T" },
            params: param[] { param { name: "value", type_name: "T" } },
            return_type: option::some("T"),
        },
        body: option::some(block_expr { statements: stmt[] {}, final_expr option::some(expr::name(name_expr { name: "value", inferred_type option::some("T") })), inferred_type option::some("T") }),
        is_public: false,
    }
    foo_seed := expr::call(call_expr {
        callee: std.prelude.box(expr::name(name_expr { name: "foo", inferred_type option::none })),
        args: call_args,
        inferred_type: option::some("int"),
        resolved_callee: option::some("foo__mono_int"),
        type_args: string[] { "int" },
    })
    chain_caller := function_decl {
        sig: function_sig {
            name: "chain_caller",
            generics: string[] {},
            params: param[] {},
            return_type: option::some("int"),
        },
        body: option::some(block_expr { statements: stmt[] {}, final_expr option::some(foo_seed), inferred_type option::some("int") }),
        is_public: false,
    }
    file := source_file { pkg: "mono.test", uses: use_decl[](), items item[] { item::function(generic), item::function(caller), item::function(foo), item::function(bar), item::function(baz), item::function(chain_caller) } }
    mono_file := compile.internal.mono.monomorphize_file(file)
    if compile.internal.mono.mono_cache_count(mono_file.cache) != 4 || len(mono_file.file.items) != 6 || mono_file.invariant_errors != 0 {
        return 1
    }
    int_summary := compile.internal.mono.summarize_instance(int_instance)
    box_summary := compile.internal.mono.summarize_instance(box_instance)
    if !int_summary.params[0].copy || int_summary.params[0].drop {
        return 1
    }
    if box_summary.params[0].copy || !box_summary.params[0].drop {
        return 1
    }
    0
}
func run_e2e_transitive_monomorphization_test() int {
    baz_return := expr::name(name_expr { name: "x", inferred_type option::some("T") })
    baz := function_decl {
        sig: function_sig {
            name: "baz",
            generics: string[] { "T" },
            params: param[] { param { name: "x", type_name: "T" } },
            return_type: option::some("T"),
        },
        body: option::some(block_expr {
            statements: stmt[] {},
            final_expr: option::some(baz_return),
            inferred_type: option::some("T"),
        }),
        is_public: false,
    }
    baz_call := expr::call(call_expr {
        callee: std.prelude.box(expr::name(name_expr { name: "baz", inferred_type: option::none })),
        args: expr[] { expr::name(name_expr { name: "x", inferred_type: option::some("T") }) },
        inferred_type: option::some("T"),
        resolved_callee: option::some("baz__mono_T"),
        type_args: string[] { "T" },
    })
    bar := function_decl {
        sig: function_sig {
            name: "bar",
            generics: string[] { "T" },
            params: param[] { param { name: "x", type_name: "T" } },
            return_type: option::some("T"),
        },
        body: option::some(block_expr {
            statements: stmt[] {},
            final_expr: option::some(baz_call),
            inferred_type: option::some("T"),
        }),
        is_public: false,
    }
    bar_call := expr::call(call_expr {
        callee: std.prelude.box(expr::name(name_expr { name: "bar", inferred_type: option::none })),
        args: expr[] { expr::name(name_expr { name: "x", inferred_type: option::some("T") }) },
        inferred_type: option::some("T"),
        resolved_callee: option::some("bar__mono_T"),
        type_args: string[] { "T" },
    })
    foo := function_decl {
        sig: function_sig {
            name: "foo",
            generics: string[] { "T" },
            params: param[] { param { name: "x", type_name: "T" } },
            return_type: option::some("T"),
        },
        body: option::some(block_expr {
            statements: stmt[] {},
            final_expr: option::some(bar_call),
            inferred_type: option::some("T"),
        }),
        is_public: false,
    }
    foo_call := expr::call(call_expr {
        callee: std.prelude.box(expr::name(name_expr { name: "foo", inferred_type: option::none })),
        args: expr[] { expr::int(int_expr { value: "42", inferred_type: option::some("int") }) },
        inferred_type: option::some("int"),
        resolved_callee: option::some("foo__mono_int"),
        type_args: string[] { "int" },
    })
    main := function_decl {
        sig: function_sig {
            name: "main",
            generics: string[] {},
            params: param[] {},
            return_type: option::some("int"),
        },
        body: option::some(block_expr {
            statements: stmt[] {},
            final_expr: option::some(foo_call),
            inferred_type: option::some("int"),
        }),
        is_public: true,
    }
    file := source_file {
        pkg: "e2e.mono.test",
        uses: use_decl[] {},
        items: item[] {
            item::function(foo),
            item::function(bar),
            item::function(baz),
            item::function(main),
        },
    }
    mono_file := compile.internal.mono.monomorphize_file(file)
    if compile.internal.mono.mono_cache_count(mono_file.cache) != 3 {
        return 1
    }
    if len(mono_file.file.items) != 4 {
        return 1
    }
    if mono_file.invariant_errors != 0 {
        return 1
    }
    if compile.internal.mono.verify_monomorphized_file_with_details(mono_file.file) != 0 {
        return 1
    }
    method_result := run_generic_receiver_method_monomorphization_test()
    if method_result != 0 {
        return method_result
    }
    0
}
func run_generic_receiver_method_monomorphization_test() int {
    get_call_int := expr::call(call_expr {
        callee: std.prelude.box(expr::member(member_expr {
            target: std.prelude.box(expr::name(name_expr { name: "int_box", inferred_type: option::some("Box[int]") })),
            member: "get",
            inferred_type: option::none,
        })),
        args: expr[] {},
        inferred_type: option::some("int"),
        resolved_callee: option::some("get__mono_int"),
        type_args: string[] { "int" },
    })
    get_call_int_again := expr::call(call_expr {
        callee: std.prelude.box(expr::member(member_expr {
            target: std.prelude.box(expr::name(name_expr { name: "other_int_box", inferred_type: option::some("Box[int]") })),
            member: "get",
            inferred_type: option::none,
        })),
        args: expr[] {},
        inferred_type: option::some("int"),
        resolved_callee: option::some("get__mono_int"),
        type_args: string[] { "int" },
    })
    get_call_string := expr::call(call_expr {
        callee: std.prelude.box(expr::member(member_expr {
            target: std.prelude.box(expr::name(name_expr { name: "string_box", inferred_type: option::some("Box[string]") })),
            member: "get",
            inferred_type: option::none,
        })),
        args: expr[] {},
        inferred_type: option::some("string"),
        resolved_callee: option::some("get__mono_string"),
        type_args: string[] { "string" },
    })
    get_method := receiver_method_decl {
        receiver_name: "b",
        receiver_type: "Box[T]",
        method: function_decl {
            sig: function_sig {
                name: "get",
                generics: string[] { "T" },
                params: param[] {},
                return_type: option::some("T"),
            },
            body: option::some(block_expr { statements: stmt[] {}, final_expr: option::some(expr::member(member_expr {
                target: std.prelude.box(expr::name(name_expr { name: "b", inferred_type: option::some("Box[T]") })),
                member: "value",
                inferred_type: option::some("T"),
            })), inferred_type: option::some("T") }),
            is_public: false,
        },
    }
    set_method := receiver_method_decl {
        receiver_name: "b",
        receiver_type: "Box[T]",
        method: function_decl {
            sig: function_sig {
                name: "set",
                generics: string[] { "T" },
                params: param[] { param { name: "v", type_name: "T" } },
                return_type: option::some("Box[T]"),
            },
            body: option::some(block_expr { statements: stmt[] {}, final_expr: option::some(expr::name(name_expr { name: "b", inferred_type: option::some("Box[T]") })), inferred_type: option::some("Box[T]") }),
            is_public: false,
        },
    }
    set_call := expr::call(call_expr {
        callee: std.prelude.box(expr::member(member_expr {
            target: std.prelude.box(expr::name(name_expr { name: "int_box", inferred_type: option::some("Box[int]") })),
            member: "set",
            inferred_type: option::none,
        })),
        args: expr[] { expr::int(int_expr { value: "42", inferred_type: option::some("int") }) },
        inferred_type: option::some("Box[int]"),
        resolved_callee: option::some("set__mono_int"),
        type_args: string[] { "int" },
    })
    use_methods := function_decl {
        sig: function_sig {
            name: "use_methods",
            generics: string[] {},
            params: param[] {
                param { name: "int_box", type_name: "Box[int]" },
                param { name: "other_int_box", type_name: "Box[int]" },
                param { name: "string_box", type_name: "Box[string]" },
            },
            return_type: option::some("int"),
        },
        body: option::some(block_expr {
            statements: stmt[] {
                stmt::s.expr(expr_stmt { expr: get_call_int }),
                stmt::s.expr(expr_stmt { expr: get_call_int_again }),
                stmt::s.expr(expr_stmt { expr: get_call_string }),
                stmt::s.expr(expr_stmt { expr: set_call }),
            },
            final_expr: option::some(expr::int(int_expr { value: "0", inferred_type: option::some("int") })),
            inferred_type: option::some("int"),
        }),
        is_public: false,
    }
    file := source_file {
        pkg: "mono.method.test",
        uses: use_decl[] {},
        items: item[] {
            item::method(get_method),
            item::method(set_method),
            item::function(use_methods),
        },
    }
    mono_file := compile.internal.mono.monomorphize_file(file)
    if compile.internal.mono.mono_cache_count(mono_file.cache) != 3 {
        return 1
    }
    if len(mono_file.file.items) != 4 {
        return 1
    }
    if count_method_named(mono_file.file, "get__mono_int") != 1 {
        return 1
    }
    if count_method_named(mono_file.file, "get__mono_string") != 1 {
        return 1
    }
    if count_method_named(mono_file.file, "set__mono_int") != 1 {
        return 1
    }
    if mono_file.invariant_errors != 0 {
        return 1
    }
    recursive_result := run_recursive_generic_method_monomorphization_test()
    if recursive_result != 0 {
        return recursive_result
    }
    0
}
func run_recursive_generic_method_monomorphization_test() int {
    wrap := function_decl {
        sig: function_sig {
            name: "wrap",
            generics: string[] { "T" },
            params: param[] { param { name: "x", type_name: "T" } },
            return_type: option::some("T"),
        },
        body: option::some(block_expr { statements: stmt[] {}, final_expr: option::some(expr::name(name_expr { name: "x", inferred_type: option::some("T") })), inferred_type: option::some("T") }),
        is_public: false,
    }
    wrap_call := expr::call(call_expr {
        callee: std.prelude.box(expr::name(name_expr { name: "wrap", inferred_type: option::none })),
        args: expr[] { expr::member(member_expr {
            target: std.prelude.box(expr::name(name_expr { name: "b", inferred_type: option::some("Box[T]") })),
            member: "value",
            inferred_type: option::some("T"),
        }) },
        inferred_type: option::some("T"),
        resolved_callee: option::some("wrap__mono_T"),
        type_args: string[] { "T" },
    })
    get_wrapped := receiver_method_decl {
        receiver_name: "b",
        receiver_type: "Box[T]",
        method: function_decl {
            sig: function_sig {
                name: "get_wrapped",
                generics: string[] { "T" },
                params: param[] {},
                return_type: option::some("T"),
            },
            body: option::some(block_expr { statements: stmt[] {}, final_expr: option::some(wrap_call), inferred_type: option::some("T") }),
            is_public: false,
        },
    }
    call := expr::call(call_expr {
        callee: std.prelude.box(expr::member(member_expr {
            target: std.prelude.box(expr::name(name_expr { name: "box", inferred_type: option::some("Box[int]") })),
            member: "get_wrapped",
            inferred_type: option::none,
        })),
        args: expr[] {},
        inferred_type: option::some("int"),
        resolved_callee: option::some("get_wrapped__mono_int"),
        type_args: string[] { "int" },
    })
    caller := function_decl {
        sig: function_sig {
            name: "call_wrapped",
            generics: string[] {},
            params: param[] { param { name: "box", type_name: "Box[int]" } },
            return_type: option::some("int"),
        },
        body: option::some(block_expr { statements: stmt[] {}, final_expr: option::some(call), inferred_type: option::some("int") }),
        is_public: false,
    }
    file := source_file {
        pkg: "mono.method.recursive.test",
        uses: use_decl[] {},
        items: item[] {
            item::function(wrap),
            item::method(get_wrapped),
            item::function(caller),
        },
    }
    mono_file := compile.internal.mono.monomorphize_file(file)
    if compile.internal.mono.mono_cache_count(mono_file.cache) != 2 {
        return 1
    }
    if count_method_named(mono_file.file, "get_wrapped__mono_int") != 1 {
        return 1
    }
    if count_function_named(mono_file.file, "wrap__mono_int") != 1 {
        return 1
    }
    if mono_file.invariant_errors != 0 {
        return 1
    }
    compile.internal.mono.verify_monomorphized_file_with_details(mono_file.file)
}
func count_method_named(source_file file, string name) int {
    count := 0
    i := 0
    for i < len(file.items) {
        switch file.items[i] {
            item.method(method) : {
                if method.method.sig.name == name {
                    count = count + 1
                }
            }
            _ : (),
        }
        i = i + 1
    }
    count
}
func count_function_named(source_file file, string name) int {
    count := 0
    i := 0
    for i < len(file.items) {
        switch file.items[i] {
            item.function(fn) : {
                if fn.sig.name == name {
                    count = count + 1
                }
            }
            _ : (),
        }
        i = i + 1
    }
    count
