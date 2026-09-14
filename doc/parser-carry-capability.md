# Phase 2.1c: Parser Carry Capability

Historical audit snapshot, before bootstrap subset v1. The fixed-body gap
below is now addressed only for the subset in `bootstrap-subset.md`;
canonical parser carry remains unproven. Rerun the capability audit to obtain
current probe results; do not read this snapshot as a fresh execution report.

This is a bounded source and execution audit, not a parser implementation or
an automatically proven whole-program call graph. Run
`make parser-carry-capability-check`. Exit zero means the audit ran; consult
`parser-carry-status` for its conclusion. Probe logs and binaries are retained
beside the report under `.bootstrap/modular/parser-carry.*`.

## First Blocking Capability

Stage1 must preserve source-dependent S function-body behavior before it can
carry any parser. Two inputs differing only in `return 17` / `return 29` test
this prerequisite without involving parser-specific rules. Failure is evidence
of missing basic compilation behavior, not evidence of a parser syntax bug.
Passing these probes alone would not prove general function calls or parsing.

In `src/cmd/compile/stage0/stage0.c`, `consume_closure` reduces sources to
`ClosureStats`; `write_stage1_c` receives only those statistics. Generated
`write_next_stage` selects fixed templates using substring checks.
`write_hello_native` emits a fixed hello program, discarding the function body.
There is no source-body translation or S execution engine on this path.
The immediate next capability is general S function-body translation with an
integer return ABI, followed by ordinary calls. It must derive executable
behavior from S source, with no grammar-specific dispatch or parser shortcuts.

These facts also limit the older Phase 1 PASS: it proves artifact creation and
template execution, not compilation of the canonical compiler implementation.
Reading 37 files and printing hello does not establish that semantic claim.

## Source Dependency Boundary

Intended source path (not the executable's current path):

`modular_build_main.s:run_check -> syntax.read_source -> syntax.parse_source
-> syntax.tokenize -> s.new_lexer(...).tokenize -> syntax.parse_tokens
-> parse_s_tokens [unresolved] -> intended s.parse_tokens -> parse_source_file`.

`syntax.s` calls `parse_s_tokens`, but a source search finds no explicit S
definition. Treat an implicit alias as unproven until binding is demonstrated.
The IDE's `internal/syntax/parser.s` defines a different pointer AST and
`parser_parse_program`; it is not the entry called by this adapter.

The parser's necessary source set includes `src/s/parser.s`, `lexer.s`,
`tokens.s`, and `ast.s`. The latter three are absent from the current canonical
manifest. Their presence on disk is insufficient. Further support crosses
`std.option`, `std.result`, `std.prelude`, strings and dynamic arrays, plus
`std.fs` and diagnostic I/O for the command. Imported modules alone do not
prove resolution of builtins or runtime symbols. The closure below records
necessary capabilities; exact reachable functions and runtime ABI remain
unproven while the adapter binding is unresolved.

## Necessary Capability Closure

| Requirement | Source evidence | Current Stage1 evidence |
| --- | --- | --- |
| Source-dependent bodies, integer returns | Any parser helper; paired return probes | Fixed output template; tested directly |
| Module binding and ordinary calls | syntax.s: tokenize / parse_tokens | No S declaration or call translation |
| Mutable structs, receivers and references | parser.s: parser / parse_source_file; lexer.s: lexer | No S layouts or receiver ABI |
| Strings, indexing, concatenation, comparison | lexer.s: peek / advance; parser.s: expect helpers | C file buffer exists; S string runtime unproven |
| Dynamic arrays, append/push, length | lexer.s: tokenize; parser.s: parse_source_file | No S collection implementation carried |
| Control flow and recursive calls | parser.s: parse_item / parse_expr | No S body execution |
| Tagged values and concrete option payloads | ast.s: pattern / expr; parser.s: option[string] | Layout and dispatch unproven |
| Multiple results, error propagation | syntax.s: switch; parser.s: parse_error | Return ABI and result adaptation unproven |
| AST construction and storage lifetime | ast.s: source_file and recursive expressions | No S AST produced; allocation contract unproven |
| Globals and diagnostics | parser.s: global_parse_depth / log_depth | S initialization and print/to_string bindings unproven |
| Source loading and command result | syntax.s: read_source; main: run_check | Generated check reads then succeeds |

Parser handling of generic syntax is distinct from the bootstrap mechanism
needed to represent concrete `option[T]` values. This audit does not authorize
implementing production generics, type checking, or other semantic passes.

## Decision

`parser-carry-status=BLOCKED`. The first demonstrated execution gap precedes
cross-module calls: input function bodies do not control output behavior.
Closure omissions and the unresolved adapter are additional independent gaps;
fixing the first capability will not automatically resolve them. Stage0 and
parser semantics remain unchanged by this audit.
