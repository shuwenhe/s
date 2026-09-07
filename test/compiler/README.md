# Ownership Call Regressions

Build with `make compiler`, then run `python3 test/compiler/call_regression.py`.
The tests compile generated C with strict warnings and allocation counting.
Rejected programs must leave existing output files untouched.

Helper functions can return `int` or `box` (an owning integer box):

```s
package example
func identity(box value) box {
    return value;
}
func main() int {
    original := box(42);
    returned := identity(original);
    return *returned;
}
```

Returning an owner moves it before local cleanup. Other owned resources are
released, and the caller owns the returned box. Borrowed owners cannot be
returned. Box functions must explicitly return on every accepted control-flow
path; reference returns remain unsupported. Helpers precede main.
