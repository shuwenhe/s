package compile.internal.mono_test
use compile.internal.mono.make_instance_name

func run_monomorphization_test() int {
    int_args := string[] { "int" }
    float_args := string[] { "float" }
    first := make_instance_name("identity", int_args)
    second := make_instance_name("identity", int_args)
    other := make_instance_name("identity", float_args)
    if first == "" || first != second || first == other {
        return 1
    }
    0
}
