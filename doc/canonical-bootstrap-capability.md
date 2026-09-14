# Phase 1.6: Canonical Compiler Bootstrap Capability Audit

Run `make canonical-bootstrap-capability-check`. It first verifies subset
execution and the freeze gate, then invokes ordinary Stage1 `build` on the
unchanged `src/cmd/compile/modular_build_main.s`. It uses a fresh output
directory, preserving diagnostics, the entry snapshot, the closure manifest,
control fixtures and checksums. Exit zero means the audit produced a report;
`result=BLOCKED` is not successful compiler compilation.

## First Observed Failure

The earlier line-1 failure on `package cmd` is resolved by recording an ordinary
package identifier independently of the `main` function. Identical
`func main() int { return 7 }` bodies under `package main` and `package cmd`
now both build and exit 7. The source-execution gate also covers another
package name, malformed declarations, and absence of the entry function.

The unchanged canonical entry now fails with
`bootstrap-subset: byte 18: expected bootstrap keyword` at line 2's `import`.
Byte 18 is the cursor after the import token. `bs_unit` expects a function
declaration immediately after the package. A control adding only `import ()`
after `package cmd` produces the same diagnostic and no output artifact.
No package rewriting, import removal, template command, or alternate compiler
is used for the canonical attempt.

`first-blocking-capability=import-declaration`.
This identifies declaration handling, not an observed module-resolution or
linker error: those stages have not been reached. Future handling must retain
dependencies and fail explicitly if unresolved, never silently discard imports.
This change does not implement imports, package resolution or namespaces.

## Capability Difference

PASS below is restricted to the subset probes, not arbitrary canonical
function bodies. GAP is a static comparison of the listed source requirement
against `doc/bootstrap-subset.md`; later gaps have not been reached during
the canonical build. This is a necessary capability inventory, not a complete
transitive call graph or proof that the current manifest is sufficient.

| Capability | Current evidence | Canonical requirement witness |
| --- | --- | --- |
| Integer return body and native ABI | PASS for constant returns | modular_build_main.s: main returns integer statuses |
| Ordinary and forward calls | PASS for zero-argument acyclic calls | modular_build_main.s: main calls print_usage |
| Named package declaration | PASS, paired execution controls | modular_build_main.s:1, package cmd |
| Import declaration | BLOCKED, canonical build and isolated import control | modular_build_main.s:2, import block |
| Cross-module binding | GAP by subset specification; not reached | modular_build_main.s: std.env.args call |
| Local variables and assignment | GAP by subset specification | modular_build_main.s:20, args := std.env.args() |
| Parameters and argument passing | GAP by subset specification | modular_build_main.s:87, run_check(string path) |
| Comparisons and Boolean operators | GAP by subset specification | modular_build_main.s:21, len(args) == 2 && ... |
| Conditionals and multiple statements | GAP by subset specification | modular_build_main.s:21, if and subsequent branches |
| Strings and indexing | GAP by subset specification | modular_build_main.s:21, args[1] == "--help" |
| Void and non-integer results | GAP by subset specification | modular_build_main.s:79, print_usage() () |
| Struct construction and field access | GAP by subset specification | internal/syntax/syntax.s:8, syntax_error; src/s/parser.s:29, parser value |
| Pointer receivers | GAP by subset specification | src/s/parser.s:40, (parser* self) |
| Arrays, slices, length and append | GAP by subset specification | src/s/parser.s:15, token[]; parse_source_file appends items |
| Loops and mutable state | GAP by subset specification | src/s/parser.s:55, for self.at_keyword(...) |
| Integer arithmetic | GAP by subset specification | src/s/parser.s:1823, self.index = self.index + 1 |
| Multiple results and error propagation | GAP by subset specification | src/s/parser.s:28, (source_file, parse_error) |
| Tagged values and concrete option payloads | GAP by subset specification | src/s/parser.s:103, option[string]; parse_item constructs item variants |
| Globals and initialization | GAP by subset specification | src/s/parser.s:34, global_parse_depth |
| Runtime bindings and external I/O | NOT_PROVEN | modular_build_main.s: std.env.args and std.io.eprintln |

The existing parser dependency omissions and unresolved adapter remain
documented in `parser-carry-capability.md`. This audit does not alter their
closure or production implementations. The manifest is an input snapshot,
not evidence that every required file has been included or executed.

## Boundary

```text
bootstrap-subset-source-execution=PASS
canonical-source-compilation=NOT_PROVEN
production-compiler-bootstrap=NOT_PROVEN
result=BLOCKED
```

Phase 2 remains blocked. Named package declarations are the only added
bootstrap capability; the first blocker above defines the next scope.
