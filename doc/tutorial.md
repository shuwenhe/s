# Native S tutorial

Build on Linux/amd64 using the [compiler guide](compiler.md), then compile the
checked-in example from the repository root:

```sh
./bin/s build test/native-bootstrap-diagnostic/native_tour.s -o /tmp/s-native-tour
/tmp/s-native-tour
echo $?
# 42
```

The integer returned by main becomes the process exit status. A shell treats 42
as nonzero; here it is the example's expected result. See
[`test/native-bootstrap-diagnostic/native_tour.s`](../test/native-bootstrap-diagnostic/native_tour.s) for the complete source.

## Values and arrays

```s
values := [4, 5, 6]
saved := values
values[0] = 40
values.push(7)
```

`:=` declares a binding with inferred type; `=` updates an existing place.
Arrays have value semantics: changing values preserves the saved array's
contents and length. `len(values)` is four, while `len(saved)` remains three.
An empty typed array uses `int[]()`. Array bounds are checked at runtime.

## Records and receiver methods

```s
struct Counter { int value }
func (Counter* self) add(int amount) { self.value = self.value + amount }
```

Create a value with `Counter { value: 40 }`, then call `counter.add(2)`.
The pointer receiver permits the method to mutate the caller's counter. A
record passed by value preserves value semantics. The compiler checks borrow
and alias restrictions; arbitrary C pointer operations are a separate question
from these typed references.

## Generics and multiple results

```s
struct Box[T] { T value }
func identity[T](T value) T { return value }
func split(int value) (int, int) { return value / 10, value % 10 }
```

Use `Box[int] { value: identity(42) }`. The call infers identity's type argument;
the compiler specializes generic declarations for concrete types. Destructure
the two results with `tens, units := split(42)`. These are source-level multiple
results, lowered to an aggregate by the native compiler.

## Enums and matching

```s
enum Choice { some(int), none }
selected := Choice.some(42)
return switch selected {
    Choice.some(value): value,
    Choice.none: 3,
}
```

Each arm produces a value. The payload binding is available in its matching
arm. Construction must supply the variant's declared payload type; payloads
cannot be read by bypassing a variant check.

## Control flow and next steps

Canonical loops use `for condition { ... }` or
`for i := 0; i < limit; i++ { ... }`. Ordinary `if`, `else`, `break`, `continue`
and explicit `return` are supported. A final expression can supply a function's
result. See the example for early failure returns and expression-valued switch.

The historical syntax guide `doc/s` describes additional language intentions;
it is not an end-to-end native support guarantee. Check the
[native backend guide](native-codegen.md), [runtime guide](runtime-gc.md) and
[current limitations](production-readiness/known-limitations.md) before relying
on floating point, concurrency, embedding lifetimes or other unverified paths.
