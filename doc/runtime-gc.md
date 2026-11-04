# Canonical native runtime and garbage collection

The canonical Linux/amd64 runtime embeds the generated allocator assembly via
`amd64_record_allocator` in the S emitter. Its matching checked-in assembly is
`src/runtime/native_gc_amd64.S`, generated from `native_gc.c` plus
`native_gc_entry_amd64.S`. This is a
single-threaded conservative, nonmoving mark/sweep collector. It is separate
from the C seed runtime, the seed standalone region allocator, the legacy
ownership/C path and the broader S runtime foundation APIs.

## Allocation and roots

Allocations use zero-initialized power-of-two slots, at least sixteen bytes,
in anonymous mmap slabs. Small-object slabs are at least one MiB. Metadata
tracks allocated and marked slots; freed slots are reused. Collection rebuilds
free lists and unmaps slabs containing no marked objects. A partially occupied
slab remains mapped, so retained RSS need not equal the sizes of live values.

Standalone startup records the initial stack boundary. The allocation wrapper
spills general-purpose registers and passes the spill boundary to collection.
The collector scans aligned machine words from that boundary through the stack
top, the compiler-emitted global root range, and recursively the contents of
marked allocations. Interior addresses mark their containing allocated slot.
Objects do not move, preserving pointer identity across collections.

Conservative scanning can retain an otherwise dead object when an integer or
stale stack slot resembles a managed address. No precise stack maps, generations,
compaction, finalizers or concurrent collection are implemented in this runtime.
The allocator has process-global unsynchronized state and does not support
concurrent allocation from multiple OS threads.

The initial collection period is 32 MiB of allocation; after collection it is
the greater of that amount and live slot bytes. Failed slab allocation triggers
collection and one retry. Unrecoverable allocation or metadata exhaustion exits
126. These constants are implementation choices, not resource guarantees.

## C object lifetime

Object/library entry lacks a standalone stack boundary. Its allocation policy
retains values for the process lifetime so values returned to C survive later
entries. Collection is disabled in this mode. This preserves escaping pointers
but cannot bound memory in a long-running allocating embedder. There is no
public C root-registration or per-instance teardown API. Embedding lifetime
management remains a release blocker; manually freeing a returned pointer is
unsupported because it addresses a slot inside a runtime slab.

## Verification and maintenance

```sh
python3 test/native-bootstrap-diagnostic/native_gc_check.py
python3 test/native-bootstrap-diagnostic/native_gc_oom_check.py
python3 test/native-bootstrap-diagnostic/native_gc_object_check.py
```

The first checks allocation churn, global/recursive/reference roots, snapshots
and a large live graph, with 128 or 512 MiB address-space limits and CPU/time
limits. The OOM check grows a retained string beyond a 48 MiB address-space
limit and requires defined exit 126. The object check verifies default PIE linking, repeated C entries and escaped
arrays under a 512 MiB limit. These checks are included in canonical production
and staged acceptance. Successful bounded tests do not prove that every
application has bounded memory.

When modifying the collector, regenerate the embedded assembly using
`misc/scripts/regenerate-native-gc.py`; use the same GCC toolchain as the retained assembly. Check the generated assembly against the C implementation and rerun GC,
object, native execution and fresh staged acceptance checks. Updating only the
C file does not change the assembly embedded by the compiler.

The contracts in `runtime_foundation.s` for channels, scheduling, segmented
stacks, reflection and other runtime services require separate backend
integration. Their presence does not establish those services in canonical
native executables.
