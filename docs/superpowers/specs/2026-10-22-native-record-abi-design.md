# Native record values for compiler bootstrapping

Date: 2026-10-22
Status: DESIGN REVIEW — CONDITIONALLY APPROVED direction only; full text awaits formal review. Production implementation is not authorized. SELFHOST = NOT PROVEN.

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

## Value transfer and ownership boundary

This is a bootstrap representation/calling contract for a classified subset of
S values, not an implementation or redefinition of S ownership. Hosted recursive
copying is an oracle for the supported copyable subset only. A runtime tag is
not evidence that a value is copyable: schema and parameter descriptors carry
one of `copy_value`, `shared_borrow`, `mutable_borrow`, or `unsupported_owner`.
The analyzer propagates this classification through nested fields and arrays.
Unknown or erased ownership information is rejected before native code emission.

| Source operation/value | Transfer in this milestone | Source after transfer |
| --- | --- | --- |
| Assignment/field store of a copyable record or array | Snapshot recursively, then publish the destination | Remains valid and independent |
| Immutable strings and scalar fields | Share immutable backing or copy the tagged scalar | Remains valid |
| Explicit shared borrow | Copy the borrow handle, preserve the same referent; prohibit writes | Alias and lifetime checks remain required |
| Explicit mutable borrow/receiver | Reborrow the same referent; prohibit escaping or duplicating the exclusive borrow | Original access is suspended for the reborrow |
| Unique owner, owned pointer, resource handle, destructor-bearing record, or an array containing one | Reject copy, by-value call/return, and construction through this generic record path | No transfer or destructor has occurred |
| Explicit language move | Out of scope; reject until typed move/drop metadata and consumption checks are implemented | No implicit fallback to copying |

There are no implicit moves or copy-elision optimizations in this milestone.
Adopting a newly allocated runtime temporary into its private construction slot
is an internal initialization step, not a language-level ownership move.
Ordinary value assignment always copies. Borrow aliases are permitted only when
static qualifier/lifetime information proves them valid; otherwise compilation
fails. Raw pointers with unknown ownership are not treated as shared borrows.
A copied container may contain a proven borrow, in which case the container is
independent but the borrowed referent intentionally retains identity.

Generic record helpers never acquire, clone, close, or drop user resources.
Consequently they cannot introduce a second owner or a second destructor call.
Supporting resource-bearing records later requires a separate move/drop design;
this milestone must report an unsupported-type error rather than manufacture
apparently working ownership behavior. If the production closure requires such
a transfer, it remains a named blocker rather than grounds to weaken this rule.

Reading a field as an expression returns its stored tagged value. A subsequent
value binding applies the transfer table. Traversing a field as an assignment
place does not copy its parent: `state.lex.pos = n` updates the selected owner's
nested field. Validate the place first; prepare the new value completely before
replacing the destination. An invalid field or failed copy leaves it unchanged.
Array-element places preserve siblings and use the same field-store rule.

### Static rejection before effects — mandatory preflight

`record_validate_transfer_contracts(ast_node *unit, record_contracts *out,
compile_error *err) -> bool` is the semantic preflight for the complete typed
compilation unit. It resolves record/array ownership transitively and validates
copy/move operations, receiver qualifiers, and borrow lifetime/exclusivity.
Run it after name/type resolution and before record IR lowering or opening the
requested output for replacement. Unsupported owner copies, explicit moves,
illegal writes through shared borrows, escaping/exclusivity violations, and
unknown ownership/lifetime facts are compile errors even inside a branch that
would not run. They are not emitted as runtime-error stubs.

The native IR consumer also runs
`standalone_validate_record_contracts(module, err) -> bool` after metadata loading
and before assembly emission or spawning assembler/linker processes. This guards
IR supplied independently of the source frontend; erased, forged, or
contradictory descriptors cannot bypass the static contract. For external IR
without source spans, diagnostics identify the IR input and record index rather
than inventing a source location.

On static rejection: return a nonzero compiler status and an
unsupported-transfer/illegal-borrow diagnostic located in the source (or external
IR as specified above); preserve preexisting output
bytes; create no executable or replacement artifact; invoke no native tools and
execute no source code, resource acquisition, drop, or destructor. Diagnostic
output and retained failure logs are permitted compiler effects. Validation is
whole-unit, not postponed until an argument expression starts running.

Runtime helper status 2 remains a defensive response to corrupted runtime values
or invalid dynamic field access. It is not an alternative implementation of a
statically known unsupported ownership or borrow operation.

### Allocation lifetime and copy failure

Copyable record/table/array backing uses the bootstrap process arena. Successful
objects live until compiler-process exit; this milestone adds neither per-object
freeing nor resource destructors. This limitation is explicit and must not be
advertised as production ownership/GC support.

A top-level copy starts a transaction with the arena cursor as a checkpoint.
Nested copies allocate only from that arena and do not publish references or
invoke user callbacks/destructors. On failure, restore the cursor to the
checkpoint, discard all unpublished nodes, and report allocation failure. The
reserved high-water capacity may remain mapped for reuse. Initialize the arena
before taking its first checkpoint. No rewind may include source objects or
allocations from evaluating an argument expression.

This rollback contract assumes single-threaded record allocation with no
reentrant user code, signal-handler allocator use, or callbacks during copying.
Concurrent allocation and resource-bearing cycles are unsupported and rejected.
By-value recursive schemas are rejected before construction. Borrow cycles are
not traversed by copy and therefore do not cause recursive cloning.

Helper result convention is `%rax = value`, `%rdx = untagged status`: 0 success,
1 allocation failure, 2 invalid record/field/transfer descriptor. A zero value is
not by itself a failure indicator. Generated code checks status before publishing
any result. An unrecoverable generated-call failure emits a diagnostic and exits
with status 70 (allocation) or 71 (invalid operation); it never invokes the target
callee or exposes a partial return. Already completed argument snapshots stay in
the arena until process teardown; the currently failing copy is rolled back.
This is fail-stop behavior, not a recoverable exception or rollback of earlier
source-level side effects.

## Caller/callee ABI — fixed contract

All plain record values are one aligned tagged heap pointer. The caller passes
the **already copied** pointer for a by-value argument. The callee adopts that
snapshot as its parameter and does not make a second entry copy. Adopting a
call-result temporary is likewise copy-free; a subsequent source-level value
assignment is a separate transfer governed by the value-transfer table.

| Boundary | Caller responsibility | Callee responsibility | Machine interface |
| --- | --- | --- | --- |
| By-value argument | Evaluate argument, snapshot according to its descriptor, check helper status, stage pointer | Bind staged pointer without copying again | Arguments 1–6: `%rdi`, `%rsi`, `%rdx`, `%rcx`, `%r8`, `%r9`; later arguments: stack slots |
| Borrow argument/receiver | Validate allowed borrow and stage the same borrow handle; never clone the referent | Honor shared/exclusive qualifier and lifetime; no escaping return without a proven contract | Same one-word argument placement |
| Ordinary record return | Adopt the returned snapshot; no automatic second copy at call-result storage | Copy the return expression, check status, then return the committed snapshot | `%rax`; no hidden sret pointer |
| Record assignment or field store | Prepare copy and check success before committing destination | Not a call boundary | Copy-helper result in `%rax`, helper status in `%rdx` |
| Copy helper failure | Do not commit destination or call the target function; report and terminate | Roll back the helper's unpublished allocation transaction | Status 1 or 2 in `%rdx`; generated failure exits 70 or 71 |

Arguments are evaluated **left to right**, with each argument's snapshot taken
immediately after its expression and before evaluating the next expression.
A later expression therefore cannot retroactively mutate an earlier argument's
snapshot. A failure stops before evaluating subsequent arguments. Side effects
of earlier expressions remain observable and are not rolled back.

Stage arguments outside the ABI argument registers until every expression and
copy succeeds. Then load registers and stack slots and issue `call`. Copy helpers
may clobber caller-saved registers, including `%rdx`; no pending argument may
remain live only in those registers. Each helper and function preserves `%rbx`,
`%rbp`, and `%r12`–`%r15`. The caller aligns `%rsp` to 16 bytes immediately before
`call`; at ordinary callee entry `%rsp mod 16 = 8`. With a standard frame, the
seventh argument is at `16(%rbp)` and later arguments at successive 8-byte slots.
The caller removes stack arguments/padding after return.

Only allocation/copy helpers use `%rdx` as a status register. Ordinary S functions
return their one-word result in `%rax`; generated code inside the callee handles
return-copy failure before returning. Multiple language return values and
resource-moving return conventions are outside this ABI milestone and must be
rejected if they cannot use an independently supported existing convention.
Repeated constructors/calls produce independent objects, with no pointer to
callee-local flattened slots.

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

## Validation and independent acceptance gates

Start with the smallest failing nested-record call/return example, independent
of the compiler. Run the same S fixtures through hosted and native execution and
compare literal exit codes/output for the supported copyable subset. Include
fields, defaults, nested copies, mutation after copies, record arrays, seventh
arguments, stack alignment/register preservation, repeated calls, borrow alias
identity, rejected owners/moves, and malformed field/transfer metadata.

Inject allocation failures in a test-only allocator/link harness, including
nested allocations and first-arena initialization. Require rollback of the active
copy, unchanged source/destination, correct helper status, and zero target-callee
entries. Separately prove left-to-right expression/snapshot order, no evaluation
after failure, and no double-copy at function entry or call-result adoption.
No production-only fault-injection setting is required. Static-rejection
fixtures place unsupported operations after side-effecting expressions and in
unreachable branches: compilation must reject them before any generated code
runs. With sentinel outputs and fail-if-invoked native tool wrappers, assert
specific diagnostics, unchanged output bytes, absent resource/destructor markers,
and zero assembler/linker invocations. Repeat with malformed external IR to
exercise the independent native-consumer preflight.

### Gate R — record ABI milestone

Build native stage1 from the complete production closure, run the structural
verifier, and execute its `--compile-unit` on the small integer fixture. It must
produce `# S-NATIVE-AMD64-V1` assembly without crashing. A changed source must
produce a changed artifact. An independent checker may assemble/link these small
artifacts and verify literal exit codes, but its authority must be labeled; it
must not be presented as native stage1's own `--emit-bin` execution.

Closing Gate R closes only the record milestone. It does not create stage2,
prove native process/file services, or claim complete self-hosting. The closure
is regenerated from production imports; 253 files is the observed baseline,
not a hardcoded count that permits dropping new sources.

### Gate H — complete native self-hosting

| Required transition | Producer and required evidence |
| --- | --- |
| C seed → stage1 | Compile the full frozen source closure; emit independent native stage1; verify its ELF/dependencies |
| stage1 → stage2 | Actually execute stage1 on that same full closure to create stage2 assembly; execute stage1's emitter to create stage2; verify stage2 and run its compiler CLI |
| stage2 → stage3 | Actually execute stage2 on that same closure to create stage3 assembly; execute stage2's emitter to create stage3; verify stage3 and run its compiler CLI |
| stage2 ≡ stage3 | Both assembly files and both executable files compare byte-for-byte equal using raw `cmp -s` |

Convergence means **raw byte equality**, without stripping, path rewriting,
metadata removal, or any other normalization. Use a frozen source snapshot,
fixed target `linux/amd64`, identical options/environment relevant to codegen,
and the same selected assembler/linker versions. Different output paths may not
change generated artifacts. Record source/producer/artifact SHA-256 values and
tool identities as provenance; hashes supplement actual execution and `cmp`,
not replace them.

#### Reproducible build envelope

Before stage1 production, freeze a manifest of ordered root-relative source paths
and exact source hashes; check it before and after each stage. Dependency
resolution, file traversal, schema tables, emitted symbols, and fresh-label
counters use deterministic source/declaration order. Do not use filesystem
iteration order, pointer addresses, random seeds, or per-process identifiers to
name serialized fields or symbols.

Record and apply the same target, compiler flags, artifact/IR versions, complete
codegen-relevant environment allowlist, resolved tool paths and versions/hashes.
The harness fixes `LC_ALL=C`, `LANG=C`, `TZ=UTC`, `SOURCE_DATE_EPOCH=0`, and
`umask 022`; it supplies an explicit recorded `PATH` and selected assembler/linker
paths and removes unrecorded codegen overrides. These are compiler-build inputs,
not a normalization step. The source text and protocol are UTF-8 with LF newlines.
A missing or changed manifest input fails the run rather than silently reusing
an older stage or shrinking the closure.

Neither `.sasm` nor ELF output may embed current time/date, random identifiers,
PID-derived names, temporary/output-directory paths, host absolute source paths,
or ambient debug producer paths. Temporary directories may be random for process
isolation, but their names must not enter serialized output. Debug metadata is
disabled for this acceptance build; any later enabled debug mode requires
explicit deterministic path handling at generation time. Keep provenance such as
tool invocations and artifact locations in separate manifest/log files.

The test harness repeats production in different output parents with the same
frozen envelope and compares raw bytes. It also launches builds with different
ambient locale/timezone settings while the wrapper applies its recorded
allowlist; emitted bytes must still match. Different source bytes must change
the relevant fixture result. Deliberately injected timestamp-like/random/path
payload differences in assembly or ELF must fail convergence. Never strip,
rewrite, canonicalize, or otherwise repair artifacts between production and
comparison; even a difference considered harmless is a Gate H failure.

Stage2 and stage3 must each compile and emit a small changed-source fixture and
run the resulting executables with literal expected results. A runner, when
needed for the target, must actually execute these programs and record exit
statuses. Neither existence nor ELF inspection counts as running a stage.

Remove stale success evidence before a run. Mark full self-hosting complete only
after every Gate H row passes, including stage3 execution. Native service and
frontend failures remain failures, not skips or hosted fallbacks. A normalized
comparison, if later needed, would require a separately reviewed acceptance
change and cannot satisfy this contract.

The record, protocol, source-reader, reachability, native frontend/codegen/build
suites must pass. Run the broader pipeline and report its existing Stage 15
Layout failure independently. Gate R and Gate H results are reported separately
from the canonical pipeline's own layout/ABI gates.
