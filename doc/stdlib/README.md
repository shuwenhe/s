# Verified native standard library

The new standard-library work uses native S packages and real Linux/amd64 execution. It does not advertise the thousands of historical ready/name placeholders as functional packages.

## Audit

`python3 misc/scripts/audit-stdlib.py --output doc/stdlib/inventory.json` inventories all tracked library sources, public function signatures, placeholder-shaped files and intrinsic dependencies. It intentionally does not equate source or test filenames with passing execution. Existing `doc/production-readiness/stdlib-inventory-20261105.json` is preserved.

The initial audit identifies these important implementation gaps:

| Area | Existing source | Verified scope / work needed |
|---|---|---|
| Time | `src/time/time.s`: legacy src.time, syscall/float/channel dependencies; empty formatters/nil timers/fixed dates | Not a verified std.time implementation. New native package first. |
| Terminal/input | No first-class public implementation found; vendor terminal source mostly historical placeholders | Implement OS-backed dimensions/raw mode/poll/byte I/O and S escape parsing. |
| System calls/I/O | `src/std/syscall.s`, `runtime_nostdlib.s`, `io_syscall.s` | Several calls pass null path/buffer pointers or return success without I/O. Preserve compatibility history, do not reuse as functioning wrappers. |
| Strings/collections | Native string/array operations and real vec source; most strings/maps/container trees are placeholders | Reuse compiler/runtime operations; add coherent namespaced APIs and boundary tests. |
| Errors | Real option/result/prelude | Actual sources executed by `test/stdlib-native/check.py`, including panic paths. |
| Files/processes | Real host-wrapper declarations | Compiler-host support does not imply complete public native behavior. Test actual installed user programs. |
| Math/memory | Partial numeric/AI APIs and native allocator/GC | No float or manual deallocation contract may be invented. Provide checked integer utilities and safe value/array wrappers before broader APIs. |
| Network/sync/thread/encoding/crypto | Mixed experimental APIs and many placeholders | Each needs real implementation, native runtime integration and error/security tests before support claims. |

## Module design standard

- Public packages use `std.name`; use existing `func`, `struct`, `:=`, arrays, tuples and receiver syntax. Explicit parameter/result types are required.
- Fallible APIs return a typed error with `int code` (zero success, positive Linux errno), optionally alongside a value in an S tuple. Never silently return success after a failed or unperformed operation.
- Strings/arrays/records follow existing value/snapshot semantics. No untyped integer-as-pointer API is exposed. OS resources use explicit sessions and documented restoration/close requirements.
- Validate range/overflow before operations; preserve existing state after a failed update. Document EOF/would-block separately from errors.
- Every implemented module needs actual native compile/link/execute, API/unit/boundary/error/integration tests and appropriate CPU/performance evidence. Retain exact commands and results under `.bootstrap/stdlib-mission-20261105`.
- Verified initial platform: Linux/amd64. Other platforms return no implicit support claim. Experimental packages retain their own names.
- New module APIs are developmental until their listed acceptance criteria pass. Backward-incompatible changes require an explicit documented version decision; historical APIs are not silently rewritten.

The native OS boundary is authored in `src/runtime/native_os_amd64.S`. `generate-native-os.py` embeds the same raw routines into the canonical native runtime and tagged seed runtime. MIR/SSA validate each intrinsic signature; the standard-library S layer owns API validation and typed errors. No C++/ncurses or external `sleep` process performs library operations.

Implemented API references: [time](time.md), [terminal](terminal.md), [input](input.md), [string](string.md), [collections](collections.md). Each describes its tested scope and remaining limitations; full staged compatibility is recorded separately from development-compiler execution.
