# Self-hosting: statement-leading if and negative tails (2026-10-29)

The subsequent source result-contract correction and latest measured frontier are
in [selfhost-result-contract-20261029.md](selfhost-result-contract-20261029.md).

## Token and AST evidence

The preserved complete-source Stage1 from the preceding if/never change rejects
`test/selfhost/newline-negative-tail/main.s` with e3018. The original full-source
failure is in `compiler_struct_field_struct`, `compiler/frontend.s:703`.

Raw Seed tokens retain the closing `}` on line 3 and `-`, `1` on line 4. Seed's
parser dispatches a statement-leading `if` directly to `parse_if_statement`:

```text
IF_STMT line=3
  ...
EXPR_STMT line=4
  UNARY_EXPR op=-
    NUMBER_EXPR value=1
```

The canonical tokenizer also retains those lines. However, `canonical_block`
previously routed a statement-leading `if` through the general Pratt expression
parser. Its infix loop consumed the following minus, before semantic checking:

```text
function=fallback statements=0
final=BINARY(-,IF_EXPR,INT(1))
```

There is no subsequent AST normalization pass between canonical parsing and
semantic checking on this path. The erroneous subtraction is already present
in the parser output. The repaired output is:

```text
function=fallback statements=1
statement=IF_EXPR
final=BINARY(-,INT(0),INT(1))
```

The canonical parser represents unary minus as `0 - operand`; that representation
is intentional. A native AST regression checks that the first node really is
an independent if statement and that the final expression has integer operands
zero and one. The diagnostic dump prints the statement count and final tree.

Raw diagnostics are preserved under `.bootstrap/selfhost-boundary/`:
`seed-tokens-ast.txt`, `canonical-before.txt`, `canonical-after.txt`, and the
standalone diagnostic sources `seed-ast.c` and `canonical-dump.s`.

## Parser change and syntax boundary

Only the statement-head dispatch in `canonical_block` and legacy
`canonical_case_body` changes: when the statement starts with `if`, parse the
whole if/else chain directly, retaining its closing branch as the statement
boundary. This matches the Seed's existing distinction between statements and
expressions.

The general expression parser and tokenizer remain unchanged. In particular,
operator-before-newline and operator-after-newline subtraction remain supported
in bindings, returns and parentheses, including if-valued expressions in those
contexts. Parentheses distinguish an if expression used as a larger expression
from a bare if statement. There is no global newline/semicolon insertion rule.

Semantic source is byte-identical to the previously verified if/never source.
The fix does not allow `unit - int`, change arithmetic typing, or rewrite the
compiler's negative tail expressions to bypass the parser.

## Regression evidence

Both new regressions were run before implementation. The AST test failed its
independent-if/negative-tail structure assertion; the native reproduction failed
with e3018. After the fix:

- `canonical_statement_boundary_ast_check.sh` passes six structural cases:
  newline, CRLF, line/block comments, else-if chain and explicit semicolon.
- `canonical_statement_boundary_production_check.sh` passes 17 native programs
  with three inputs each (51 executions), plus two e3018 rejection cases that
  preserve the existing output.
- Legal subtraction controls include ordinary `a - 1`, unary `-1`, `a - -1`,
  both binary newline placements, parentheses, comment-separated continuation,
  and if-valued bindings/returns/parenthesized expressions. These controls also
  passed on the preserved pre-fix production compiler.
- Both checks are registered in `selfhost-canonical-production-check`, alongside
  all 37 existing checks.
- Independent review found no actionable correctness issue in the statement-head
  dispatch or the preservation of expression-context multiline subtraction.

Full-source build and Stage2 results are recorded below once measured. Complete
self-hosting requires independently generated Stage2 and Stage3, with converged
assembly and executable bytes; clearing this parser error alone is not that proof.

## Production suite and full-source progress

`make -o compiler selfhost-canonical-production-check` exited 0 with all 39 checks
passing (the existing 37 plus the two new checks), using the freshly rebuilt
native production compiler. Its frozen 268-file compile advanced past the old
e3018 and stopped at e3008 after 104.470 s, peak RSS 1227612 KiB.

The diagnostic native semantic component identifies:

```text
function=compile.internal.ok_write_ops
location=src/cmd/compile/internal/core/backend.s:38
source=return result.ok(value)
expected=(compile.internal.write_op[],compile.internal.backend_error)
actual=unknown
error=e3008: return type mismatch
```

The reduced unresolved fixture is
`test/selfhost/result-constructor-tuple-return/`, with its exact dependency and
input-order command in the README. This evidence does not establish that result
enum constructors and tuple signatures should be interchangeable. The next
investigation must distinguish historical source-signature inconsistency from
constructor/context inference behavior without loosening type compatibility.

## Complete-source Stage1 build

The optimized trusted seed built native Stage1 from a frozen copy of all 268
patched compiler sources. All per-file hashes match the working source.

| Step | Time | Result |
| --- | ---: | --- |
| Seed to Stage1 IR | 163.557 s | PASS |
| Native Stage1 emission | 328.075 s | PASS |
| Total | 491.632 s | PASS, peak RSS 723468 KiB |

The native executable passed `verify_true_selfhost.sh`, the 51-execution
statement-boundary regression with strict arithmetic rejections, and the if/never,
break and continue suites. Stage1-to-Stage2 measurements follow below.

## Complete Stage1 to Stage2 result

The actual complete-source Stage1 compiled the same frozen 268-file closure,
finished parsing and reached e3008 in semantic checking after 103.635 s. It
exited 1 with peak RSS 1227804 KiB. Thus the former negative-tail e3018 is cleared
by the real Stage1, consistent with the production compiler and minimized tests.
Stage1 SHA-256:

```text
3cc68df109ec60a188a46c2d8d9131204013ee229ff6eeea5cf59ac7a7a9d41f
```

| Gate | Result |
| --- | --- |
| Seed to complete native Stage1 | PASS |
| Native Stage1 verification/execution | PASS |
| Negative-tail e3018 reproduction | FIXED |
| Existing 37 production checks | PASS |
| Two new AST/native boundary checks | PASS |
| Stage1 to Stage2 | e3008 at `ok_write_ops` |
| Stage2 to Stage3 | NOT RUN |
| Stage2/Stage3 byte convergence | NOT PROVEN |

No Stage2 assembly/binary or completion marker was generated. Complete
self-hosting is not claimed. Raw measurements and logs are
`stage1-measurements.json`, `stage1-check.log`, `stage2-measurements.json`,
`stage2-compile.log`, `production-full-measurements.json`, `diagnostic/run.log`,
`before.json`, and `source-hashes.json` in `.bootstrap/selfhost-boundary/`.
Full production test output is `/tmp/s-boundary-production.log`.
