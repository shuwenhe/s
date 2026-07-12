# S libc FFI

The seed compiler preserves libc declarations and lowers calls to the host C ABI:

```s
extern "libc" func strlen(string text) int
extern "libc:socket" func c_socket(int domain, int kind, int protocol) int
```

`libc` resolves a symbol with the S function name. `libc:<symbol>` provides an
explicit symbol name, allowing an S-safe wrapper name without colliding with a
public S function.

The seed ABI currently supports:

- up to six arguments;
- `int`, `bool`, and `string` arguments;
- integer, boolean, unit, and copied C-string returns;
- the platform C calling convention on macOS and Linux.

The current seed `--emit-bin` output embeds the IR runtime. FFI calls still enter
libc directly through the platform dynamic symbol table; they do not use a
function-specific file or socket bridge.

Pointer arithmetic, mutable buffers, C struct layout, variadic calls, floating
point registers, callbacks, and ownership annotations are not yet part of this
ABI. APIs such as `bind`, `connect`, and `read` therefore still require an
intrinsic until those facilities are implemented.
