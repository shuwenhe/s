package compile.internal.mono_test
use compile.internal.mono.new_cache
use compile.internal.mono.make_instance_name
use compile.internal.mono.make_instance_key
use compile.internal.mono.mono_cache_count
use compile.internal.mono.mono_cache_get_or_create_key
use compile.internal.mono.specialize_function
use compile.internal.mono.summarize_instance
use s.function_decl
use s.function_sig
use s.param
use std.option.option

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
