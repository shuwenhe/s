# No-GC MVP

S should first prove one narrow production slice before competing with the
full breadth of Rust, C, C++, or Go.

The valuable position is:

- safer than C by default
- simpler than Rust in the common case
- lower-runtime than Go by default
- less complex than C++ in the core language

That means the current priority is not broad language growth. The priority is
a stable, no-GC ownership compiler path that can build real programs with
deterministic cleanup and repeatable performance.

`make no-gc-mvp-check` passing means the No-GC MVP infrastructure gate is
working. It does not mean ownership, borrow checking, or drop semantics are
complete.

## Current baseline

The existing no-GC compiler path lowers the supported S subset to C and links
against `src/runtime/compiler_runtime.h`. The generated binaries are checked
to avoid the S GC and seed interpreter runtime symbols.

`make compiler-check` is the current acceptance gate for this path. It covers
owned boxes, moves, shared and mutable borrows, branch behavior, loop control,
scope cleanup, early returns, custom `drop` methods, owned struct fields,
nested owned structs, partial moves, overwrite cleanup, and key rejection
diagnostics.

This is a real no-GC compiler path, but it is still a subset compiler. It
should not be described as a complete Rust/C replacement yet.

S No-GC MVP establishes deterministic ownership compilation and its regression
gate. Field-sensitive partial move, CFG-sensitive ownership, borrow
integration, and NLL remain separate closure gates.

## Near-term product slice

The first useful external story should be:

```sh
s build program.s -o program
./program
```

For programs inside the MVP subset, this must mean:

- no S GC linked into the binary
- no seed interpreter runtime linked into the binary
- deterministic cleanup on scope exit, return, break, and continue
- move-after-use, borrow-after-move, and invalid mutable aliasing rejected
- custom `drop` methods called exactly once for live owners
- owned fields recursively cleaned in a documented order
- clear diagnostics when syntax is outside the no-GC subset

## What to build next

1. Keep `make compiler-check` green and expand it only with behavior that
   belongs to the MVP subset.
2. Close field-sensitive partial move for named structs, including double
   move rejection, use-after-field-move rejection, whole-move-after-partial
   rejection, and borrow-plus-field-move rejection.
3. Add one realistic no-GC demo, such as a JSON parser, HTTP parser,
   grep-style CLI, or small arena-backed key-value store.
4. Add benchmark cases for that demo against C, Rust, and Go. The initial
   goal is credible measurement, not a claim that S is faster.
5. Stabilize the MVP language surface: functions, structs, owned fields,
   borrowing, arrays or slices, modules, errors, and C ABI calls.
6. Improve diagnostics before adding advanced language features.

## What to avoid for now

These are valuable later, but they should not block the MVP:

- full Rust-style trait power
- C++-style templates or overload-heavy APIs
- a large macro system
- a broad standard library
- a default GC runtime path
- performance claims without repeated benchmark evidence

## Comparison goals

Against C, S should show memory safety wins while keeping predictable output
and straightforward FFI.

Against Rust, S should show a smaller mental model for common ownership cases,
with fewer annotations and simpler diagnostics.

Against Go, S should show deterministic no-GC binaries for latency-sensitive,
embedded, CLI, and systems code.

Against C++, S should intentionally avoid object-model and template complexity
until the no-GC core is already boringly reliable.

## Release bar

The MVP is credible when:

- `make compiler-check` passes on supported hosts
- `make no-gc-mvp-check` exercises real ownership semantics, not only the
  build scripts and current happy-path subset
- `make benchmark` reports S, C, Rust when available, and Go when available
- one realistic no-GC demo builds and tests cleanly
- emitted binaries pass the no-GC symbol checks
- the README states the supported subset and limitations without performance
  overclaiming

The ownership closure is credible only when field-sensitive ownership, CFG
dataflow, borrow integration, and NLL gates pass separately.
