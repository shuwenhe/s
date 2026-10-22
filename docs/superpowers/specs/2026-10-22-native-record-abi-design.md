# Native record values for compiler bootstrapping

Date: 2026-10-22
Status: proposed for review; implementation has not started.

## Goal and boundary

The user selected fixing the seed native backend's record ABI before expanding
the S native frontend. The first deliverable is a native compiler executable
whose record constructors, copies, field reads/writes, parameters, and returns
preserve the same plain-value behavior as the hosted seed executor.

Passing ELF inspection is insufficient. The full production source closure
must build native stage1, and that executable must compile a small integer S
program without a record-related crash. This milestone does not claim complete
self-hosting: native process/file services and the S frontend's language coverage
remain separate prerequisites for stage2/stage3.

## Evidence

The production closure contains 253 source files. With backend helper symbol
prefixes and function/literal section collection, it produces a static amd64
stage1 that passes `verify_true_selfhost.sh`.

Running that executable's `--compile-unit` on a small integer function faults
in `s_value_cmp`, called from `native_advance`. The compared `state.lex.error`
value is null. `standalone_amd64_backend.c` currently represents record fields
as independent local slots. Copying or returning the root value does not carry
those slots into the caller. A fallback also guesses offset 8 for ordinary
fields; this cannot encode a record with multiple or nested fields.

Hosted execution explicitly copies/remaps record fields across calls and
returns in `runtime.c`. Native code must implement equivalent value behavior,
rather than initialize the missing error field to hide this particular crash.

## Alternatives

1. **Tagged record objects in the bootstrap runtime — selected.** Preserve the
   existing tagged-value calling convention and seed IR, and make record values
   explicit native heap objects. Field helpers use field names rather than
   guessed offsets. This is a bootstrap ABI with straightforward correctness
   tests; it is not the final optimized language ABI.
2. Fully typed, unboxed aggregate layout and platform ABI lowering. This is
   suitable for the later production backend, but requires type/layout facts,
   aggregate register classification, and lowering changes before the current
   record-copy failure can be isolated.
3. Continue through the hosted C executor. Useful for differential tests, but
   does not satisfy the user's native bootstrap objective.

## Native representation

Retain odd tagged integers and existing string/array representations. Reserve
heap tag 8 for plain S records (the runtime currently uses 2 for flat strings,
4 for arrays, and 6 for ropes). The 32-byte record header contains tag 8 at
offset 0, qualified type-identity pointer at offset 8, field count at offset 16,
and a field-table pointer at offset 24.
Each field entry contains an interned field-name pointer and one tagged value.
Entries are 16 bytes each: field-name pointer, then tagged value.
Names are compared by full contents; hash equality alone cannot identify a field.

Constructors allocate a fresh record object. The native adapter recognizes the
existing seed IR constructor and `.__type` metadata and initializes field entries
from the constructor's named stores. This preserves the IR's logical contract
without changing `SSEED-TARGET-V1` or requiring the compatibility executor to
consume a new instruction set. Type identity remains attached to the value.

Missing or invalid fields produce a native runtime error with a nonzero exit.
They never return an uninitialized slot or guess that every field is at offset 8.
The existing enum/result runtime representation remains distinct; compatibility
cases must be classified explicitly rather than treated as plain records.

## Copying and places

Plain record assignment has value semantics. A generic native value-copy helper
clones a record's field table and recursively copies nested plain records.
Immutable strings can be shared. Arrays and their nested record elements are
recursively copied, matching `runtime.c:value_copy` and the record-alias
remapping at call boundaries. Explicit
pointer/borrow values preserve their existing alias identity and are not deep
copied as ordinary records.

Reading a field for use as a value returns the field's tagged value. Storing that
value into a new value binding applies the copy rule. A field used as an
assignment place traverses its owning record directly, so `state.lex.pos = n`
updates that record's nested field rather than an unrelated temporary copy.
Assignments through array element places must continue to update the selected
element and preserve siblings.

## Calls and returns

Each plain record occupies one tagged machine-word argument. The existing
SysV register/stack argument rules remain in place. A by-value parameter receives
an independent record snapshot at function entry; a return value is copied out
before the callee's local storage becomes invalid. Copies may be elided only
after correctness is established with observable mutation tests.

Record constructors in loops and repeated calls must allocate independent
objects. No pointer may refer to a callee's stack-local flattened field slots.
Receiver/borrow parameters remain explicitly aliased according to their current
contract. Unsupported combinations fail with a diagnostic instead of silently
using by-value behavior.

## Implementation boundaries

- `seed/intermediate/ir.c`: document and test constructor/field/copy patterns;
  retain their current logical meaning and encoded format.
- `seed/code/standalone_amd64_backend.c`: recognize record operations, remove
  record-field access through unrelated local slots, and call runtime helpers.
- `runtime/selfhost_linux_amd64.S`: allocate, look up, store, and copy tagged
  records; report invalid operations; preserve callee-saved registers and stack
  alignment at every helper boundary.
- `seed/runtime/runtime.c`: differential oracle, with changes only if a test
  identifies an inconsistent record-value contract that needs an explicit
  language decision.
- Native bootstrap tests: keep complete-source compilation and ELF validation;
  add execution evidence rather than weakening the verifier or excluding source.

Add every declared field with its language-defined default before applying
explicit constructor initializers; constructor field order must not change
field identity. Preserve package-qualified type identity in module schemas,
so equally named types in different packages do not share a layout.

No C compiler/interpreter fallback, hardcoded compiler output, or fixture-specific
handling is permitted in the native implementation.

## Validation and acceptance

Start with the smallest failing nested-record call/return example, independent
of the full compiler. Run the same S fixtures through hosted and native seed
execution and compare literal exit codes/output. Cover multiple fields, nested
records, copy then mutate, parameter mutation, return then mutate, multiple
parameters, stack arguments, loop constructors, repeated calls, array record
elements, and invalid field rejection.

Require the standalone reachability and source-reader tests, native frontend,
codegen, native build, and protocol suites to remain passing. Run the broader
pipeline and report its existing Stage 15 layout gate failure separately.

The record milestone closes only when native stage1 built from the full closure
runs `--compile-unit` on the small integer fixture without a crash and emits the
versioned native assembly artifact. Native `--emit-bin` still needs real process
and temporary-directory service implementations; these are the next bounded
work item and must not be bypassed to claim this record milestone or full
self-hosting.
