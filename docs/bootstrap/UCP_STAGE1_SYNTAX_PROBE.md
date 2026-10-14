# UCP Stage1 Syntax Probe

Current HEAD:

```text
5f18ce225fa6825ac4e4fc957f66150bf5779927
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
