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

## UCP-2.4 Struct Literal Compatibility Investigation

Observed FIRST RED:

```text
PARSE_FAIL at 1914:24 near ':' (tok=:)
error[4] at 1914:24: expected expression, got :
```

Mapped source:

```text
src/cmd/compile/internal/parser/parser.s:1191
```

Relevant context:

```text
func (parser* self) parse_switch_expr() (expr, parse_error) {
    ...
    switch_arm[] arms = switch_arm[]()
    for !self.eat_symbol("}") {
        ...
        expr, err := self.parse_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
            pattern: pattern, expr expr,
        })
        self.eat_symbol(",")
    }
    expr::switch(switch_expr {
        subject: box(subject), arms arms, inferred_type option::none,
    })
}
```

### Observed

The failing line is not a complete struct literal. The source currently has
orphan struct fields followed by `})`:

```text
pattern: pattern, expr expr,
})
```

There is no enclosing call such as:

```text
arms = append(arms, switch_arm { ... })
```

or:

```text
arms.push(switch_arm { ... })
```

`git show HEAD:src/cmd/compile/internal/parser/parser.s` has the same orphan
field sequence, so this is not introduced by UCP-2.3 edits.

### Type Definition

`switch_arm` is defined in `src/cmd/compile/internal/ast/ast.s`:

```text
struct switch_arm {
    pattern pattern
    expr expr
}
```

### Minimal Reproduction

Stage1 accepts all tested struct literal field forms:

```text
switch_arm { pattern: pattern }
-> PASS

switch_arm { pattern pattern }
-> PASS

switch_arm { pattern: pattern, expr: expr }
-> PASS

switch_arm { pattern pattern, expr expr }
-> PASS

switch_arm { pattern: pattern, expr expr }
-> PASS
```

Therefore the current root cause is not general named-field struct literal
incompatibility, not mixed field initialization, and not the field name `expr`.

### Root Cause

The proven root cause is:

```text
parse_switch_expr() contains an incomplete/orphan switch_arm construction.
Stage1 reaches `pattern:` while parsing a statement/expression position and
correctly reports `expected expression, got :`.
```

This is a malformed production parser source fragment in the dependency closure,
not a missing Stage1 struct literal capability.

### Affected Sites

Direct `switch_arm` construction sites:

```text
src/cmd/compile/internal/parser/parser.s:1191
src/cmd/compile/internal/bloop/bloop.s:621
src/cmd/compile/internal/mono/monomorphization.s:896
src/cmd/compile/internal/mono/monomorphization.s:1363
```

The bloop and mono sites have complete wrappers, for example:

```text
arms.push(switch_arm {
    pattern: switch_value.arms[i].pattern,
    expr edit_expr(switch_value.arms[i].expr, in_bloop),
})
```

and:

```text
arms = append(arms, switch_arm {
    pattern: v.arms[i].pattern,
    expr finalize_expr(v.arms[i].expr),
})
```

Only the parser site is currently malformed.

### Compatible Rewrite

The minimal semantic-preserving rewrite is to append the constructed arm to the
`arms` array after parsing `pattern` and `expr`:

```text
arms = append(arms, switch_arm {
    pattern: pattern, expr: expr,
})
```

This preserves:

```text
1. one arm per parsed switch branch
2. field binding: pattern -> switch_arm.pattern, expr -> switch_arm.expr
3. evaluation order: pattern is parsed before expr, then appended
4. caller contract: parse_switch_expr() still returns expr::switch(...)
```

Using all-colon fields is preferred for clarity, but Stage1 also accepts the
existing mixed style when it is inside a complete struct literal.

### Next Action

Do not mark UCP-2 as passing. The next single implementation task is:

```text
UCP-2.4 implementation:
restore the missing append/push wrapper around the switch_arm literal in
parse_switch_expr(), then rerun the UCP syntax probe and stop at the next FIRST
RED.
```

Do not modify `compiler_compile()`, do not add a bootstrap parser, and do not
continue into Semantic or IR until `compile.internal.syntax.parse_source()` is
actually executed by Stage1.

## UCP-2.4 Implementation Result

Files changed:

```text
src/cmd/compile/internal/parser/parser.s
```

Exact fix:

```text
arms = append(arms, switch_arm {
    pattern: pattern, expr: expr,
})
```

This restores the missing `switch_arm` construction and append operation inside
`parse_switch_expr()` after `pattern` and `expr` have both been parsed.

Semantic equivalence:

```text
1. The loop still parses one pattern and one expression per switch arm.
2. The same parsed values are bound to switch_arm.pattern and switch_arm.expr.
3. The append happens before the existing optional comma consumption.
4. parse_switch_expr() still returns expr::switch(switch_expr { ... arms ... }).
```

Regression evidence:

```text
sh test/native-bootstrap-diagnostic/ucp_syntax_probe_first_red_check.sh
-> UCP-2 FIRST RED / FAIL_EXPECTED
-> advanced past parser.s:1191

make native-bootstrap-diagnostic-check
-> native bootstrap diagnostic checks passed
```

New FIRST RED:

```text
PARSE_FAIL at 1936:15 near 'else' (tok=ELSE)
error[4] at 1936:15: expected expression, got ELSE
```

Mapped source:

```text
src/cmd/compile/internal/parser/parser.s:1215
```

Relevant context:

```text
func (parser* self) parse_if_expr() (expr, parse_error) {
    ...
            } else {
                option::none
            }
    expr::if(if_expr {
        condition: box(condition), then_branch then_branch, else_branch else_branch, inferred_type option::none,
    })
}
```

Current status:

```text
UCP-2.4: PASS
UCP-2: BLOCKED
compile.internal.syntax.parse_source(): NOT EXECUTED
```

Next single task:

```text
UCP-2.5:
Investigate the incomplete control-flow/value construction in parse_if_expr(),
starting from parser.s:1215.
```

## UCP-2.5 parse_if_expr Root Cause Investigation

Observed FIRST RED:

```text
PARSE_FAIL at 1936:15 near 'else' (tok=ELSE)
error[4] at 1936:15: expected expression, got ELSE
```

Mapped source:

```text
src/cmd/compile/internal/parser/parser.s:1215
```

Actual Stage1 input and source map agree:

```text
722:2841:src/cmd/compile/internal/parser/parser.s source_line=1215
```

### Observed Source Context

Current `parse_if_expr()`:

```text
func (parser* self) parse_if_expr() (expr, parse_error) {
        self.expect_keyword("if")
        condition, err := self.parse_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
                if self.at_keyword("if") {
                    option::some(box(self.parse_if_expr()))
                } else {
                    option::some(box(expr::block(self.parse_block_expr())))
                }
            } else {
                option::none
            }
        expr::if(if_expr {
            condition: box(condition), then_branch then_branch, else_branch else_branch, inferred_type option::none,
        })
}
```

The source is missing the structure that should appear between the parsed
condition and final `expr::if(...)` construction:

```text
1. parsing and binding the then block
2. declaring and assigning else_branch
3. the outer `if self.eat_keyword("else") { ... }` guard
4. returning the constructed expr
```

`git show HEAD:src/cmd/compile/internal/parser/parser.s` has the same malformed
body, so this was not introduced by UCP-2.4.

### Minimal Reproduction

Stage1 supports ordinary `if/else` statement and expression forms:

```text
func if_stmt_basic(int x) int {
    if x {
        return 1
    } else {
        return 2
    }
}
-> PASS

func if_expr_basic(int x) int {
    y := if x { 1 } else { 2 }
    return y
}
-> PASS

func if_expr_nested(int x, int y) int {
    z := if x { if y { 1 } else { 2 } } else { 3 }
    return z
}
-> PASS
```

Stage1 does not accept `else if` as a direct shorthand:

```text
func else_if_basic(int x, int y) int {
    z := if x { 1 } else if y { 2 } else { 3 }
    return z
}
-> PARSE_FAIL near 'if': expected {, got IF
```

That is not the current FIRST RED shape. The current source is not an `else if`
input; it is a partially missing `parse_if_expr()` implementation.

A malformed snippet with an orphan `option::some(...) else option::none` shape
fails similarly before it can represent a valid if expression:

```text
option::some(1)
} else {
    option::none
}
-> PARSE_FAIL near ':'
```

### Root Cause

The proven root cause is:

```text
parse_if_expr() is structurally incomplete in the production parser source.
The ELSE token is a downstream symptom of missing then_branch and else_branch
construction, not evidence that Stage1 lacks basic if/else support.
```

Root class:

```text
Production Parser source integrity defect
```

### Affected Source

Primary affected source:

```text
src/cmd/compile/internal/parser/parser.s:1201-1218
```

Related data contract from `src/cmd/compile/internal/ast/ast.s`:

```text
struct if_expr {
    box[expr] condition
    then_branch block_expr
    option[box[expr]] else_branch
    option[string] inferred_type
}
```

Existing downstream transformations show the intended field contract:

```text
src/cmd/compile/internal/bloop/bloop.s:
then_block := edit_block(if_value.then_branch, in_bloop)
else_expr := option::none
...
expr::if(if_expr { condition: ..., then_branch then_block, else_branch else_expr, ... })

src/cmd/compile/internal/mono/monomorphization.s:
else_branch := option.none
...
expr::if(if_expr { condition: ..., then_branch finalize_block(v.then_branch), else_branch else_branch, ... })
```

### Proposed Fix

The minimal semantic repair is to restore the missing `parse_if_expr()` shape:

```text
self.expect_keyword("if")
condition, err := self.parse_expr()
...
then_branch, err := self.parse_block_expr()
...
else_branch := option::none
if self.eat_keyword("else") {
    if self.at_keyword("if") {
        else_branch = option::some(box(self.parse_if_expr()))
    } else {
        else_block, err := self.parse_block_expr()
        ...
        else_branch = option::some(box(expr::block(else_block)))
    }
}
return expr::if(if_expr {
    condition: box(condition),
    then_branch then_branch,
    else_branch else_branch,
    inferred_type option::none,
})
```

Semantic preservation:

```text
1. condition remains parsed before branches.
2. then_branch is parsed as a block_expr, matching the AST contract.
3. else_branch remains optional and stores either nested if_expr or block expr.
4. final returned value remains expr::if(if_expr { ... }).
```

### Investigation Result

```text
UCP-2.5:
  investigation = COMPLETE
  root_class = Production Parser source integrity defect
  root_cause = parse_if_expr() is missing then_branch/else_branch construction
  minimal_repro = ordinary if/else PASS; malformed orphan option/else FAIL
  affected_source = src/cmd/compile/internal/parser/parser.s:1201-1218
  proposed_fix = restore parse_if_expr() branch parsing and final return
  implementation = NOT_STARTED

UCP-2 = BLOCKED
syntax.parse_source() = NOT_EXECUTED
Self-host = NOT_PROVEN
```

## UCP-2.6 Implementation Result

Files changed:

```text
src/cmd/compile/internal/parser/parser.s
```

Exact fix scope:

```text
parse_for_expr()
```

Restored branch integrity:

```text
block-only:
  parses body with parse_block_expr()
  returns expr::for(for_expr { init none, condition none, post none, iterable none, body body })

C-style:
  parses init ; condition ; post ) body
  returns expr::for(for_expr { init some, condition some, post some, iterable none, body body })

range-style:
  recognizes `name := iterable` or `name in iterable`
  parses iterable expression and body
  returns expr::for(for_expr { names [name], iterable some, condition none, body body })

condition-style:
  parses condition expression and body
  returns expr::for(for_expr { condition some, iterable none, body body })
```

This removes the two proven extra `)` instances, restores missing body parsing
for the range and condition branches, and changes the final condition-style
construction to an explicit return.

Targeted branch evidence:

```text
condition-style input:
  bin/s_seed --compile-unit .bootstrap/ucp-for-branch-repro/condition_style.ir \
    .bootstrap/ucp-for-branch-repro/condition_style.s
  -> PASS

C-style input using assignment post:
  bin/s_seed --compile-unit .bootstrap/ucp-for-branch-repro/c_style_assign.ir \
    .bootstrap/ucp-for-branch-repro/c_style_assign.s
  -> PASS

block-only input:
  parsed by Stage1, then semantic failed with "function does not return on all paths"
  -> PARSER COVERED, SEMANTIC FAIL

range-style input:
  Stage1 seed syntax does not accept `for x := xs { ... }`
  -> NOT TESTED as a legal Stage1 source loop
```

Coverage note:

```text
The direct loop fixtures exercise Stage1 source syntax, not runtime execution of
production parse_for_expr(). UCP syntax probe remains the authority for whether
Stage1 can compile the production parser dependency closure.
```

Regression evidence:

```text
scripts/canonical-parser-closure-check.sh
-> PASS, with limited coverage: 2 parsed files and 4 skipped missing files

make native-bootstrap-diagnostic-check
-> native bootstrap diagnostic checks passed

sh test/native-bootstrap-diagnostic/ucp_syntax_probe_first_red_check.sh
-> UCP-2 FIRST RED / FAIL_EXPECTED
-> advanced past parse_for_expr()
```

New FIRST RED:

```text
PARSE_FAIL at 2052:58 near ')' (tok=))
error[4] at 2052:58: expected expression, got )
```

Current source list mapping places the failing line in:

```text
src/cmd/compile/internal/parser/parser.s
```

Relevant visible source family:

```text
parse_pattern() literal pattern constructors:
return pattern::literal(literal_pattern { ... }))
```

The exact source-line map produced by the UCP script is not currently refreshed
as a first-class artifact, so the next investigation should regenerate a fresh
line map before assigning the precise source line.

Current status:

```text
UCP-2.6 implementation = COMPLETE
original_first_red = RESOLVED
regression = PARTIALLY_VERIFIED
full_branch_coverage = NOT_PROVEN
block-only branch = PARSER_COVERED_SEMANTIC_FAIL
C-style branch = PASS
range-style branch = NOT_TESTED
condition-style branch = PASS

Production Parser regression = PASS_LIMITED
Bootstrap diagnostic = PASS
UCP Syntax Probe = FAIL_EXPECTED
Next FIRST RED = parse_pattern() literal pattern constructor family

syntax.parse_source() = NOT_EXECUTED
Self-host = NOT_PROVEN
```

Next single task:

```text
UCP-2.7:
Regenerate an accurate Stage1 source map for the syntax probe, then investigate
the parse_pattern() literal pattern constructor FIRST RED. Do not repair it until
the exact source line and constructor shape are proven.
```

## UCP-2.7 Literal Pattern Constructor Investigation

Observed FIRST RED:

```text
PARSE_FAIL at 2052:58 near ')' (tok=))
error[4] at 2052:58: expected expression, got )
```

The syntax probe source list maps this line into:

```text
src/cmd/compile/internal/parser/parser.s
```

The generated line map artifact is not refreshed by the current probe script, so
the investigation used the current `syntax-probe.sources` file to map the
concatenated input. The mapped region is `parse_pattern()`, around the literal
pattern constructors.

### AST Contract

`literal_pattern` is defined in `src/cmd/compile/internal/ast/ast.s`:

```text
struct literal_pattern {
    value expr
}

enum pattern {
    name(name_pattern),
    wildcard(wildcard_pattern),
    variant(variant_pattern),
    literal(literal_pattern),
}
```

### Observed Source Context

`parse_pattern()` currently contains literal constructors shaped like:

```text
return pattern::literal(literal_pattern {
    value: expr::int(int_expr {
        value: token.value, inferred_type option::none,
    }),
}))
```

The same `... }))` shape appears in the string, true, and false literal
constructors.

The function also contains other constructor sites with the same visible extra
right parenthesis shape:

```text
return pattern::wildcard(wildcard_pattern {}))
return pattern::variant(variant_pattern { ... }))
```

Those are affected constructors by inspection, but only the literal constructor
family is proven as the current FIRST RED.

### Minimal Reproduction

Stage1 accepts the correct constructor shape:

```text
return pattern::literal(literal_pattern {
    value: int_expr { value: 1 },
})
-> PASS
```

Adding the extra right parenthesis reproduces the current failure class:

```text
return pattern::literal(literal_pattern {
    value: int_expr { value: 1 },
}))
-> PARSE_FAIL near ')': expected expression, got )
```

Therefore the current failure is not evidence that Stage1 lacks enum variant
payload construction or struct literal payload support.

### Root Cause

Proven root cause:

```text
parse_pattern() literal pattern constructors have an extra `)` after the
pattern::literal(literal_pattern { ... }) construction.
```

Root class:

```text
Production Parser source integrity defect
```

### Affected Constructors

Proven current FIRST RED family:

```text
pattern::literal(literal_pattern { ... }))
```

Suspicious same-function constructors requiring implementation-time review:

```text
pattern::wildcard(wildcard_pattern {}))
pattern::variant(variant_pattern { ... }))
```

Additional source-integrity risk:

```text
parse_pattern() also shows incomplete branch guards around token.kind checks and
variant parsing. Do not batch-repair those until each branch shape is audited.
```

### Proposed Fix

The minimal UCP-2.7 implementation should be bounded to constructor integrity in
`parse_pattern()`:

```text
1. remove the proven extra `)` from literal pattern constructors.
2. review wildcard and variant constructors in the same function for the same
   proven extra-parenthesis shape.
3. do not modify AST definitions, compiler_compile(), Semantic, IR, or Codegen.
4. do not rewrite the whole function unless a separate FIRST RED proves the
   branch-guard issue.
```

### Investigation Result

```text
UCP-2.7 investigation = COMPLETE
root_class = Production Parser source integrity defect
root_cause = extra `)` in parse_pattern() literal pattern constructors
affected_constructors = literal proven; wildcard/variant suspicious by inspection
minimal_repro = valid literal constructor PASS; extra `)` constructor FAIL
proposed_fix = bounded constructor-parenthesis repair in parse_pattern()
implementation = NOT_STARTED

UCP-2 = BLOCKED
syntax.parse_source() = NOT_EXECUTED
Self-host = NOT_PROVEN
```

## UCP-2.5 Implementation Result

Files changed:

```text
src/cmd/compile/internal/parser/parser.s
```

Exact fix:

```text
self.expect_keyword("if")
condition, err := self.parse_expr()
...
then_branch, err := self.parse_block_expr()
...
else_branch := option::none
if self.eat_keyword("else") {
    if self.at_keyword("if") {
        nested, err := self.parse_if_expr()
        ...
        else_branch = option::some(box(nested))
    } else {
        else_block, err := self.parse_block_expr()
        ...
        else_branch = option::some(box(expr::block(else_block)))
    }
}
return expr::if(if_expr {
    condition: box(condition),
    then_branch then_branch,
    else_branch else_branch,
    inferred_type option::none,
})
```

This restores the missing `then_branch` parse, optional `else_branch` parse, and
explicit return of the `expr::if(if_expr { ... })` node. It does not change the
AST type contract and does not add a new parser API.

Regression evidence:

```text
bin/s_seed --compile-unit .bootstrap/ucp-if-repro/if_stmt_basic.ir \
  .bootstrap/ucp-if-repro/if_stmt_basic.s
-> PASS

bin/s_seed --compile-unit .bootstrap/ucp-if-repro/if_expr_basic.ir \
  .bootstrap/ucp-if-repro/if_expr_basic.s
-> PASS

bin/s_seed --compile-unit .bootstrap/ucp-if-repro/if_expr_nested.ir \
  .bootstrap/ucp-if-repro/if_expr_nested.s
-> PASS

scripts/canonical-parser-closure-check.sh
-> PASS, with limited coverage: 2 parsed files and 4 skipped missing files

make native-bootstrap-diagnostic-check
-> native bootstrap diagnostic checks passed
```

The UCP syntax probe now advances past the UCP-2.5 `ELSE` blocker, but it still
does not execute `compile.internal.syntax.parse_source()`.

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
PARSE_FAIL at 1969:15 near ')' (tok=))
error[4] at 1969:15: expected expression, got )
```

Mapped source:

```text
src/cmd/compile/internal/parser/parser.s:1248
```

Relevant context:

```text
return expr::for(for_expr {
    init: option::none, condition option::none, post option::none,
    names string[](), iterable option::none, body body, inferred_type option::none,
}))
```

Current status:

```text
UCP-2.5 implementation = PASS
Production Parser regression = PASS_LIMITED
Bootstrap diagnostic = PASS
UCP Syntax Probe = FAIL_EXPECTED
Next FIRST RED = src/cmd/compile/internal/parser/parser.s:1248
syntax.parse_source() = NOT_EXECUTED
Self-host = NOT_PROVEN
```

Next single task:

```text
UCP-2.6:
Investigate parse_for_expr() around parser.s:1248. Do not assume the issue is
only an extra parenthesis until the full for-expression construction is audited.
```

## UCP-2.6 parse_for_expr Root Cause Investigation

Observed FIRST RED:

```text
PARSE_FAIL at 1969:15 near ')' (tok=))
error[4] at 1969:15: expected expression, got )
```

Mapped source:

```text
src/cmd/compile/internal/parser/parser.s:1248
```

Actual Stage1 input around the failure:

```text
return expr::for(for_expr {
    init: option::none, condition option::none, post option::none,
    names string[](), iterable option::none, body body, inferred_type option::none,
}))
```

### AST Contract

`for_expr` is defined in `src/cmd/compile/internal/ast/ast.s`:

```text
struct for_expr {
    option[box[stmt]] init
    option[box[expr]] condition
    option[box[stmt]] post
    string[] names
    option[box[expr]] iterable
    body block_expr
    option[string] inferred_type
}
```

### Observed Source Context

Current `parse_for_expr()` contains several structural issues:

```text
1. block-only branch returns expr::for(...)) with an extra `)`.
2. C-style for branch also returns expr::for(...)) with an extra `)`.
3. range-style branch references `body` without parsing a body in that branch.
4. condition-style branch references `body` without parsing a body in that branch.
5. final condition-style branch ends with a bare expr::for(...) expression rather
   than an explicit return.
```

The immediate FIRST RED is the first extra `)` in the block-only branch. The
later issues are not yet proven as FIRST RED by the syntax probe, but they are
visible source-integrity risks in the same function.

### Minimal Reproduction

Stage1 accepts a valid enum variant construction with a struct literal payload:

```text
return expr::for(for_expr {
    init: 0, condition 0, post 0, names 0, iterable 0,
    body body, inferred_type 0,
})
-> PASS
```

Adding the extra closing parenthesis reproduces the current failure class:

```text
return expr::for(for_expr {
    init: 0, condition 0, post 0, names 0, iterable 0,
    body body, inferred_type 0,
}))
-> PARSE_FAIL near ')': expected expression, got )
```

Therefore the immediate failure is not evidence that Stage1 lacks `expr::for` or
multi-field struct payload support.

### Root Cause

Immediate root cause:

```text
parse_for_expr() block-only branch has an extra `)` after the expr::for(for_expr
{ ... }) construction.
```

Root class:

```text
Production Parser source integrity defect
```

Broader function-level finding:

```text
parse_for_expr() appears partially malformed beyond the immediate extra
parenthesis. A complete implementation review is needed before applying a
single-character patch, because later branches reference `body` without parsing
it and the final branch lacks an explicit return.
```

### Affected Source

Primary current FIRST RED:

```text
src/cmd/compile/internal/parser/parser.s:1244-1246
```

Additional visible risk sites in the same function:

```text
src/cmd/compile/internal/parser/parser.s:1273-1275
src/cmd/compile/internal/parser/parser.s:1292-1294
src/cmd/compile/internal/parser/parser.s:1301-1303
```

### Proposed Fix

Do not apply only a one-character fix without auditing the whole function shape.
The minimal safe UCP-2.6 implementation should restore `parse_for_expr()` branch
construction coherently:

```text
1. remove the extra `)` from completed expr::for(...) returns.
2. ensure each branch parses and checks `body, err := self.parse_block_expr()`
   before constructing for_expr.
3. preserve existing field values:
   - block-only: no init/condition/post/names/iterable
   - C-style: init, condition, post
   - range-style: names + iterable
   - condition-style: condition only
4. use explicit return for each constructed expr::for(...).
5. do not change AST definitions, compiler_compile(), Semantic, IR, or Codegen.
```

### Investigation Result

```text
UCP-2.6:
  investigation = COMPLETE
  root_class = Production Parser source integrity defect
  root_cause = immediate extra `)` in parse_for_expr(); broader function has
               missing body parsing and missing explicit return risks
  minimal_repro = valid expr::for payload PASS; same payload with extra `)` FAIL
  affected_source = src/cmd/compile/internal/parser/parser.s:1244-1303
  proposed_fix = restore coherent parse_for_expr() branch construction
  implementation = NOT_STARTED

UCP-2 = BLOCKED
syntax.parse_source() = NOT_EXECUTED
Self-host = NOT_PROVEN
```
