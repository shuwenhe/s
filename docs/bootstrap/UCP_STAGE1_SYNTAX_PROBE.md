# UCP Stage1 Syntax Probe

Current HEAD:

```text
fc484f32daae13f3adde6e8dc33ca2049cd292ac
```

## Observed

UCP-2 attempts to prove that Stage1 can execute the production parser entry:

```text
compile.internal.syntax.parse_source()
```

The probe is tracked by:

```text
test/native-bootstrap-diagnostic/ucp_syntax_probe_first_red_check.sh
```

The probe builds an isolated source closure importing `compile.internal.syntax`.

Initial failure:

```text
PARSE_FAIL at 668:21 near ':=' (tok=:=)
error[4] at 668:21: expected {, got :=
```

The actual Stage1 input and map were saved under:

```text
.bootstrap/ucp-syntax-probe-first-red/actual-stage1-input.s
.bootstrap/ucp-syntax-probe-first-red/actual-stage1-input.map
```

The mapped file was:

```text
src/cmd/compile/internal/lexer/token/token.s
```

The failing construct was not the preceding enum switch case. The actual token was from the next function:

```text
for _for_idx_31 := 0; _for_idx_31 < len(tokens); _for_idx_31++ {
```

Minimal reproductions:

```text
c_for_short_decl:
  for i := 0; i < 1; i++ { }
  -> PARSE_FAIL near :=

c_for_predecl:
  for i = 0; i < 1; i++ { }
  -> PARSE_FAIL near ;

while_style_loop:
  while i < 1 { i = i + 1 }
  -> PASS
```

## Root Cause

The first proven blocker was:

```text
Stage1/seed cannot parse the C-style for form used by the production syntax dependency closure.
```

This was a legal production dependency syntax issue, not a source closure mapping bug and not an enum switch `::` issue.

## Minimal Fix

Only `src/cmd/compile/internal/lexer/token/token.s` was changed.

The C-style loop in `dump_tokens` was rewritten to an equivalent `while` loop:

```text
_for_idx_31 := 0
while _for_idx_31 < len(tokens) {
    ...
    _for_idx_31 = _for_idx_31 + 1
}
```

This keeps Production and Stage1 using the same `token.s`. No duplicate parser or bootstrap-only copy was introduced.

`compiler_compile()` was not modified.

## Regression Evidence

Direct `token.s` compile after the change no longer fails with the original parse error. It advances to semantic checking:

```text
bin/s_seed --compile-unit .bootstrap/ucp-syntax-min-repro/token_after_fix.ir \
  src/cmd/compile/internal/lexer/token/token.s

error[5] at 24:29: if condition expects bool/int, got '()'
```

That confirms the original parse blocker was removed.

The UCP syntax probe still fails before runtime execution of `parse_source`, but at a later dependency:

```text
PARSE_FAIL at 746:18 near 'parse_tokens' (tok=IDENTIFIER)
error[4] at 746:18: expected 'case', 'default', pattern, or '_'
```

Mapped source:

```text
src/cmd/compile/internal/parser/parser.s
```

Relevant construct:

```text
func parse_source(string source) (source_file, parse_error) {
    switch new_lexer(source).tokenize() {
        tokens : parse_tokens(tokens),
        err : parse_error {
            message: err.message, line: err.line, column: err.column,
        },
    }
}
```

## Next FIRST RED

```text
UCP-2.2 FIRST RED:
Stage1 cannot parse production parser's result-style switch pattern in parser.s.
```

This still blocks before:

```text
compile.internal.syntax.parse_source()
```

has been executed by Stage1.

## Stop Condition

If UCP-2 continues to reveal unrelated Stage1 language gaps in the production syntax closure, stop and compare:

```text
A. shrink the production syntax bootstrap surface while preserving one parser authority
B. improve the trusted Stage1 build toolchain so it can compile production syntax
```

Do not resume broad `compiler_compile()` syntax patching.

## UCP-2.2 Result-style Switch

Observed blocker:

```text
src/cmd/compile/internal/parser/parser.s

func parse_source(string source) (source_file, parse_error) {
    switch new_lexer(source).tokenize() {
        tokens : parse_tokens(tokens),
        err : parse_error {
            message: err.message, line err.line, column err.column,
        },
    }
}
```

The matching pattern was unique in the production syntax closure:

```text
rg -n 'switch .*tokenize\(' src/cmd/compile
src/cmd/compile/internal/parser/parser.s:22
```

Root cause:

```text
Stage1 cannot compile the result-style switch pattern used by parser.s before the probe can execute syntax.parse_source().
```

Minimal fix:

```text
Use the existing result API style already used by parser/syntax/syntax.s:
  token_result := new_lexer(source).tokenize()
  if token_result.is_err() { ... token_result.unwrap_err() ... }
  parse_tokens(token_result.unwrap())
```

Files changed:

```text
src/cmd/compile/internal/parser/parser.s
```

`compiler_compile()` was not modified.

Regression evidence:

```text
sh test/native-bootstrap-diagnostic/ucp_syntax_probe_first_red_check.sh

UCP-2 FIRST RED
stage=Stage1 production syntax probe
result=FAIL_EXPECTED
root_class=Stage1 cannot compile production parser dependency closure
evidence=seed compiler fails before probe binary exists
blocked_before=compile.internal.syntax.parse_source runtime execution
```

The FIRST RED advanced past result-style switch to:

```text
PARSE_FAIL at 1350:16 near ',' (tok=,)
error[4] at 1350:16: expected expression, got ,
```

Mapped source:

```text
src/cmd/compile/internal/parser/parser.s
```

Relevant construct:

```text
generics, parse_error { message: "" }
```

## Current Next FIRST RED

```text
UCP-2.3 FIRST RED:
Stage1 cannot parse tuple-style return expression in parser.s.
```

The probe still has not executed:

```text
compile.internal.syntax.parse_source()
```

## UCP-2.3 Tuple-style Return Capability Decision

Observed blocker:

```text
src/cmd/compile/internal/parser/parser.s:622

func (parser* self) parse_generic_params() (string[], parse_error) {
    ...
    generics, parse_error { message: "" }
}
```

The generated Stage1 input maps the failing location to `parser.s`:

```text
722:2841:src/cmd/compile/internal/parser/parser.s
```

The exact diagnostic remains:

```text
PARSE_FAIL at 1350:16 near ',' (tok=,)
error[4] at 1350:16: expected expression, got ,
```

### Root Cause

The proven blocker is narrower than "tuple returns are unsupported".

Minimal reproductions show:

```text
func pair_explicit() (int, int) {
    return 1, 2
}
-> PASS

func pair_bare() (int, int) {
    1, 2
}
-> parsed, then semantic error: function does not return on all paths

func void_tuple_empty_return() ((), parse_error) {
    return , parse_error { message: "" }
}
-> PARSE_FAIL near ','

func void_tuple_unit_return() ((), parse_error) {
    return (), parse_error { message: "" }
}
-> PASS
```

So the current root cause is:

```text
Stage1 accepts explicit multi-return forms, but the production parser dependency
closure uses bare final multi-return expressions and empty first return values
that Stage1 does not accept as return statements.
```

This is a production syntax closure compatibility issue. It is not evidence that
multi-return function signatures are unsupported.

### Affected Callers

`parse_generic_params()` is shared by these parser paths:

```text
parse_struct_decl()
parse_enum_decl()
parse_trait_decl()
parse_function()
```

Therefore the failing expression affects all production parser support for
generic struct, enum, trait, and function declarations.

### Compatible Rewrite Feasibility

The immediate failing expression appears rewriteable without changing the
function signature or caller contract:

```text
generics, parse_error { message: "" }
```

can become:

```text
return generics, parse_error { message: "" }
```

because Stage1 already compiles explicit multi-return statements.

The void tuple cases need a second, explicit compatibility rule. Minimal
reproduction shows:

```text
return , parse_error { message: "" }
```

does not parse, while:

```text
return (), parse_error { message: "" }
```

does parse.

### Estimated Remaining Syntax Gap

Within `src/cmd/compile/internal/parser/parser.s`, the production syntax closure
contains eight bare final multi-return expressions:

```text
168:  result, parse_error{ message: "", line 0, column 0 }
586:  params, parse_error { message: "" }
622:  generics, parse_error { message: "" }
638:  (), parse_error { message: "" }
685:  segment, parse_error { message: "" }
1662: join_strings(parts, "."), parse_error { message: "" }
1700: normalize_type_text(join_strings(parts, " ")), parse_error { message: "" }
1882: t, parse_error { message: "" }
```

The first actual FIRST RED is line 622 because earlier lines are not reached by
the parser's dependency compilation order before this location in the generated
Stage1 input.

The current evidence suggests UCP-2.3 is still one syntax class:

```text
bare final multi-return expression -> explicit return multi-return statement
```

However, Stage1 has now exposed three unrelated production syntax compatibility
classes in sequence:

```text
C-style for
result-style switch pattern
bare final multi-return expression / empty tuple return form
```

This keeps the broader Stage1 production-frontend execution risk open.

### Recommended Next Action

Proceed with one bounded implementation task only if the project accepts this
compatibility route:

```text
UCP-2.3 implementation:
rewrite the eight bare final multi-return expressions in parser.s to explicit
return statements, and replace empty first return values with explicit () where
needed.
```

Required verification:

```text
1. tuple explicit-return minimal repro passes
2. void tuple explicit () return minimal repro passes
3. UCP syntax probe advances past parser.s:622
4. if a new FIRST RED appears, record it and stop
```

Do not treat this as proof that `compile.internal.syntax.parse_source()` has run.
The probe must explicitly reach and execute that function before UCP-2 syntax
execution can be considered proven.

## UCP-2.3 Implementation Result

Files changed:

```text
src/cmd/compile/internal/parser/parser.s
```

The implementation changed only the proven compatibility class:

```text
bare final multi-return expression -> explicit return multi-return statement
empty first return value            -> explicit () value
```

Changed locations:

```text
parse_import_block():      return result, parse_error{ ... }
parse_params():            return params, parse_error { ... }
parse_generic_params():    return generics, parse_error { ... }
parse_where_clause():      return (), parse_error { ... }
parse_where_clause():      return (), err
parse_token_segment():     return segment, parse_error { ... }
parse_path():              return join_strings(...), parse_error { ... }
parse_type_text():         return normalize_type_text(...), parse_error { ... }
advance():                 return t, parse_error { ... }
```

Semantic equivalence evidence:

```text
1. Each bare expression was the final expression of a function whose signature
   already returns the corresponding tuple.
2. Existing callers already consume the same tuple contracts.
3. Minimal Stage1 probes prove explicit multi-return is accepted.
4. Minimal Stage1 probes prove `return (), parse_error { ... }` is accepted for
   `((), parse_error)`.
```

Verification:

```text
awk scan for bare final multi-return expressions in parser.s
-> count=0

rg -n 'return[[:space:]]*,' src/cmd/compile/internal/parser/parser.s
-> no matches

bin/s_seed --compile-unit .bootstrap/ucp-tuple-repro/explicit_return.ir \
  .bootstrap/ucp-tuple-repro/explicit_return.s
-> PASS

bin/s_seed --compile-unit .bootstrap/ucp-tuple-repro/void_unit_return.ir \
  .bootstrap/ucp-tuple-repro/void_unit_return.s
-> PASS

make native-bootstrap-diagnostic-check
-> native bootstrap diagnostic checks passed
```

The UCP syntax probe now advances past the UCP-2.3 tuple-return blocker, but it
still does not execute `compile.internal.syntax.parse_source()`.

Current probe result:

```text
sh test/native-bootstrap-diagnostic/ucp_syntax_probe_first_red_check.sh

UCP-2 FIRST RED
stage=Stage1 production syntax probe
result=FAIL_EXPECTED
root_class=Stage1 cannot compile production parser dependency closure
evidence=seed compiler fails before probe binary exists
blocked_before=compile.internal.syntax.parse_source runtime execution
```

New FIRST RED:

```text
PARSE_FAIL at 1914:24 near ':' (tok=:)
error[4] at 1914:24: expected expression, got :
```

Mapped source:

```text
src/cmd/compile/internal/parser/parser.s:1191
```

Relevant construct:

```text
switch_arm {
    pattern: pattern, expr expr,
}
```

Current status:

```text
UCP-2.3: PASS
UCP-2: BLOCKED
compile.internal.syntax.parse_source(): NOT EXECUTED
```

Next single task:

```text
UCP-2.4:
Investigate Stage1 compatibility for named-field struct literals inside
parse_switch_expr(), starting from parser.s:1191.
```
