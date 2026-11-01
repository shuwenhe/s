Run `bash test/native-global/check.sh`.

Globals retain a qualified identity, concrete type, and optional initializer function identity through MIR and SSA. A load has no operands and returns the declared type. A store consumes exactly that type and returns unit. Unknown symbols, malformed metadata, duplicate definitions, unsupported types, invalid initializer signatures, and initialization cycles are rejected.

Initializers have no parameters and return exactly the global's type. Their dependencies include global loads and stores in every function reachable through validated direct call edges. Initialization follows a computed dependency order, including forward declarations. A missing initializer uses the native zero/default value.

The native backend emits only numeric assembler identifiers for slots and initializer call targets. Executable startup initializes globals before entry. Objects expose `s_native_initialize_globals`; library callers invoke it before entry. The helper initializes once and preserves subsequent mutations. The tests execute both startup paths and verify idempotence, mutation, default globals, string globals, and dependencies through helper calls.
