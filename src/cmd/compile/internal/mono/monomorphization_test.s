package compile.internal.mono_test
use compile.internal.mono.new_cache
use compile.internal.mono.make_instance_name
use compile.internal.mono.make_instance_key
use compile.internal.mono.mono_cache_count
use compile.internal.mono.mono_cache_get_or_create_key
use compile.internal.mono.specialize_function
use compile.internal.mono.substitute_type
use compile.internal.mono.monomorphize_file
use compile.internal.mono.summarize_instance
use compile.internal.mono.verify_monomorphized_file_with_details
use s.function_decl
use s.function_sig
use s.param
use s.source_file
use s.use_decl
use s.item
use s.block_expr
use s.expr
use s.int_expr
use s.name_expr
use s.call_expr
use s.stmt
use std.option.option
use std.prelude.box

func run_monomorphization_test() int {
    int_args := string[] { "int" }
    box_args := string[] { "box[int]" }
    first := make_instance_name("identity", int_args)
    second := make_instance_name("identity", int_args)
    other := make_instance_name("identity", box_args)
    if first == "" || first != second || first == other {
        return 1
    }
    cache := new_cache()
    int_key := make_instance_key("identity", int_args)
    box_key := make_instance_key("identity", box_args)
    first_result := mono_cache_get_or_create_key(cache, int_key)
    cache = first_result.cache
    second_result := mono_cache_get_or_create_key(cache, int_key)
    cache = second_result.cache
    box_result := mono_cache_get_or_create_key(cache, box_key)
    cache = box_result.cache
    if first_result.instance_name != second_result.instance_name || first_result.instance_name == box_result.instance_name || mono_cache_count(cache) != 2 {
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
    int_instance := specialize_function(generic, int_args)
    box_instance := specialize_function(generic, box_args)
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
    nested := specialize_function(generic, nested_args)
    if nested.sig.params[0].type_name != "string[]" || nested.sig.return_type.unwrap() != "string[]" {
        return 1
    }
    if substitute_type("box[T[]]", string[] { "T" }, string[] { "int" }) != "box[int[]]" {
        return 1
    }
    call_args := expr[] { expr::int(int_expr { value: "1", inferred_type option::some("int") }) }
    mono_call := expr::call(call_expr {
        callee: box(expr::name(name_expr { name: "identity", inferred_type option::none })),
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
        callee: box(expr::name(name_expr { name: "bar", inferred_type option::none })),
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
        callee: box(expr::name(name_expr { name: "baz", inferred_type option::none })),
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
        callee: box(expr::name(name_expr { name: "foo", inferred_type option::none })),
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
    mono_file := monomorphize_file(file)
    if mono_cache_count(mono_file.cache) != 4 || len(mono_file.file.items) != 6 || mono_file.invariant_errors != 0 {
        return 1
    }
    int_summary := summarize_instance(int_instance)
    box_summary := summarize_instance(box_instance)
    if !int_summary.params[0].copy || int_summary.params[0].drop {
        return 1
    }
    if box_summary.params[0].copy || !box_summary.params[0].drop {
        return 1
    }
    0
}

// E2E test: Verify transitive monomorphization works correctly for chain: main -> foo[int] -> bar[int] -> baz[int]
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
        callee: box(expr::name(name_expr { name: "baz", inferred_type: option::none })),
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
        callee: box(expr::name(name_expr { name: "bar", inferred_type: option::none })),
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
        callee: box(expr::name(name_expr { name: "foo", inferred_type: option::none })),
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
    

    mono_file := monomorphize_file(file)
    







    
    if mono_cache_count(mono_file.cache) != 3 {

        return 1
    }
    
    if len(mono_file.file.items) != 4 {

        return 1
    }
    

    if mono_file.invariant_errors != 0 {
        return 1
    }
    

    if verify_monomorphized_file_with_details(mono_file.file) != 0 {
        return 1
    }
    


    0
}
