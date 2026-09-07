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
returned. A `ref` or `mutref` return may return any reference parameter;
returning a local borrow is rejected, and all return paths must use the same
parameter. Box functions must explicitly return on
every accepted control-flow path. Helpers precede main.

Arguments and binary operands evaluate from left to right. Calls accept fresh
boxes and box-returning calls as owning arguments. Logical operators preserve
short circuiting; a move on their right side makes the owner possibly moved
after the expression. Loop conditions cannot consume outer owners. Writes
through an owner are rejected if evaluating the right side consumes it.
