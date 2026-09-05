# S ownership compiler (no tracing GC)

This is an executable, deliberately restricted S compiler implemented in
`src/cmd/compile/nogc/compiler.s`. It checks ownership and lexical borrows and
lowers accepted source to C11. The host C compiler generates the executable.
The application links only the host allocator and the small inline helpers in
`src/runtime/nogc_runtime.h`; it does not link the seed runtime or S's GC.

This is not full-language Rust parity, and it is not a converged self-hosted
compiler. The existing C seed builds `bin/s_nogc_compiler`, supplying its host
I/O and value-management runtime. That runtime uses explicit allocation and
recursive value cleanup rather than a tracing collector. The new compiler's
semantic analysis and lowering are S code; its C header is the host allocation
and checked-integer ABI. Existing S compilation modes are unchanged.

## Build and use

On macOS/arm64 or Linux/amd64 with a C11 GCC/Clang toolchain:

```sh
make nogc-compiler
./misc/scripts/s-nogc.sh check test/nogc/ownership.s
./misc/scripts/s-nogc.sh build test/nogc/ownership.s -o /tmp/s-owned
/tmp/s-owned
# Exit status: 42
./misc/scripts/s-nogc.sh --emit-c test/nogc/ownership.s /tmp/s-owned.c
make nogc-check
```

The regression target additionally requires Python 3, `nm`, AddressSanitizer
and UndefinedBehaviorSanitizer. This change has been exercised on macOS/arm64;
Linux support uses the existing seed host backend and needs platform CI.
`CC` selects a compiler executable, not a shell command containing flags.

## Supported source

A file must contain `package name` and one `func main() int { ... }`.
Statements require semicolons. Blocks, `if`/`else` and `while` do not.

```s
package example
func main() int {
    owner := box(20);
    {
        reference := &mut owner;
        *reference = *reference + 1;
    }
    moved := owner;
    moved = box(*moved * 2);
    return *moved;
}
```

- `:=` infers an integer, an owning integer box, or a lexical reference.
- Integer values copy. Assigning a box variable moves it and invalidates the
  source. A moved owner can be reinitialized. Owner replacement evaluates the
  new value before dropping the old value, so `x = box(*x + 1)` is valid.
- `&owner` creates a shared borrow; `&mut owner` creates an exclusive borrow.
  `*owner`/`*reference` reads the integer. Writes require an unborrowed owner
  or a mutable reference. Loans end at the reference's lexical scope exit or
  explicit `drop(reference)`; they do not end automatically at last use.
- Shared references copy with `other := reference`. Each copy keeps the owner
  borrowed independently; dropping the original does not release its copies.
  Mutable references cannot be copied.
- `child := &*reference` creates a shared reborrow;
  `child := &mut *reference` creates a mutable reborrow from a mutable reference.
  A mutable child blocks parent reads, writes and further borrows. Shared
  children permit parent reads and further shared borrows, but block writes
  and mutable borrows. A parent cannot be explicitly dropped while any child
  remains live. Scope exit or `drop(child)` restores parent access once all
  conflicting children end. Shared child copies preserve this restriction.
  These are lexical borrows of the same integer, not reference-to-reference
  values, and do not implement Rust's non-lexical lifetimes.
- `drop(owner)` explicitly destroys an unborrowed owner. Otherwise destruction
  is inserted in reverse declaration order at scope exit, return, break and
  continue. Moved pointers become null; conditional destruction uses this
  per-slot state, never an object registry or heap scan.
- Branches merge live/dead state conservatively. A possibly moved value cannot
  be used. A possibly live loan still prevents conflicting access. Returning
  branches do not unnecessarily invalidate values on the continuing path.
- Loops may allocate and move local owners. Consuming/replacing an owner or
  ending a loan declared outside the current loop is rejected; this avoids
  assuming a first-iteration state on subsequent iterations. Nested loop
  cleanup preserves objects owned by the enclosing loop.
- Expressions support decimal literals (up to 18 digits), parentheses,
  arithmetic, comparisons, logical short circuiting, unary minus and `!`.
  Integer operations use checked signed 64-bit arithmetic. `true`/`false`
  lower to integers. Normal process status is the low 8 bits of the return.
- `assert(integer_expression)` traps on false. `live_allocations()` is a test
  intrinsic requiring `-DS_NOGC_CHECK_ALLOCATIONS` when compiling emitted C.
  The public release driver omits allocation counting.
- Line and nested block comments are supported. Nesting is bounded. Rejection
  reports a line and leaves an existing output untouched.

There are no user functions beyond main, function parameters, imports, FFI,
raw pointers, arrays, strings, structs, general generics, user destructors,
reference reassignment, mutable-reference moves/copies, shadowing, or owner/reference
returns in this subset. Unsupported constructs fail instead of falling back
to unchecked or GC compilation. The `box` constructor denotes an owned
`box[int]`; other box element types are not implemented yet.

Allocation failure, arithmetic failure and failed assertions terminate with
status 70 and do not unwind. The OS reclaims process memory on those paths;
normal scope exit and return perform deterministic cleanup. This backend does
not provide Rust's full panic/unwind or concurrency semantics.

## Implementation and verification

The S parser carries typed slots, initialization/move state, loan origins and
reborrow parents. Every child retains the original owner as its root; parent
links additionally restrict access through the reference that created it.
Branch snapshots are independent values. Pointer operations are emitted only
after checking the relevant state. The C output contains ordinary local
pointers and compiler-inserted move/drop calls. There is no GC-disable toggle
that can leave allocations without an owner.

`test/nogc/check.py` compiles and executes positive source fixtures with
ASan/UBSan and allocation-count assertions, checks expected rejection reasons
and output preservation, exercises arithmetic traps and the public driver,
and checks application symbols for GC/seed execution entry points. The main
example is `test/nogc/ownership.s`. These tests validate this subset; they are
not a proof of full-language memory safety.

Building this compiler exposed a seed bug where a string equal to a record
variable's name was treated as a record handle. The seed now tags record
handles explicitly. `test_runtime_string_record_collision` covers copying,
passing and returning such a string while preserving genuine record copies.

The next language extensions need explicit contracts and tests: ownership
across function calls and returns; field-level move paths and aggregate drop
glue; references tied to parameters; loop fixed-point analysis; owned
containers and closure captures. General no-GC S compilation and compiling
this compiler with itself remain future work.
