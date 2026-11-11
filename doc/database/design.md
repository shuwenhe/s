# Native database foundation

## Scope and architecture

The requested end state is native MySQL and PostgreSQL drivers with a common API,
explicit resource lifetimes, verified TLS and native executable tests. No external
client library or process is a driver substitute. Work proceeds sequentially:
shared foundation, MySQL, real MySQL acceptance, PostgreSQL, cross-driver acceptance.

Use existing lowercase structs, receiver methods, tagged enums, option[t], and
explicit tuple error returns. Do not assume generic traits, associated types,
destructors, dynamic trait dispatch, or arbitrary syscall intrinsics work.

Shared value variants distinguish SQL NULL from empty text, empty bytes, zero and
false. Preserve unsigned 64-bit integers and decimals as exact decimal strings;
temporal, JSON and UUID values retain their exact textual representation. A native
value carries a driver type identifier plus text/bytes for future types. Protocol
metadata stays in driver packages; common column metadata carries optional native
identifiers without interpreting them.

Resource state helpers are pure bookkeeping for driver owners, not connections.
A driver registers successful native resource acquisition; callers never obtain a
connected handle from a bookkeeping constructor. A parent refuses closure while
children are active. A busy connection cannot start another command. Owners pass
state by mutable pointer; copying state does not duplicate an OS resource and is
forbidden for live driver owners. Drivers must validate native handles and
ownership, close on authentication/transport failure, and update state only after
actual protocol success. Close failures must not be fabricated into success.

Rows in this foundation are owned buffered snapshots. next returns option[row]:
none means exhaustion, some(row) can contain NULL values. Bounds errors, exhaustion,
and closure are separate. Closing releases the snapshot. This is not yet a streaming
result implementation. Future streaming drivers must drain or close the transport
before releasing the busy state.

## Approaches

Implicit traits are the documented S method-set interface model and are appropriate
for contracts. Generic traits are rejected by the current seed parser; dynamic trait
calls link to an undefined `_method_*` symbol. Type-erased callbacks and runtime
registries would add unverified runtime requirements. Therefore implement concrete
value, result, buffered rows, and lifecycle operations now, with non-generic trait
contracts describing driver obligations. These contracts do not establish working
runtime dispatch. This compiler limitation must be resolved before a usable common
polymorphic driver API can be certified.

## Test-first implementation

Compile actual production sources with the repository seed and execute native ELF
artifacts. Establish red tests before each implementation. Test exact values, NULL,
metadata absence, bounds, ownership state, packet lengths, truncation, sequence IDs,
server errors and malformed replies. Test fixtures are protocol unit inputs, never
real-server integration evidence. Public compiler and selfhosting checks stay intact.

## Non-goals for the foundation

No fake open/connect/authentication/commit success. No plaintext credential fallback.
No claim of verified TLS, live database functionality, production readiness, memory
leak freedom, or performance validation without measured evidence.
