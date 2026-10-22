# Native recursive AST borrowing audit — 2026-10-22

SELFHOST = NOT_PROVEN.

## Main integration verification

Merged into main as `a937ba96b` after fetching origin, preserving the three
subsequent main commits. The sections below retain the isolated-worktree audit
as historical evidence; their statement that the branch was unmerged describes
that earlier run.

On the merged main tree:

- `make selfhost-native-record-check`: exit **0**.
- `make selfhost-protocol-check`: exit **0**.
- `make selfhost`: exit **2**, source closure **252 files**.
- Latest FIRST RED: `src/cmd/compile/internal/parser/frontend_parser.s:152:5`,
  `p.peek_token = lexer_next_token(p.lexer*)`, diagnostic:
  `unproven record borrow: escaping handle or unsupported call/body`.
- No full Stage1, Stage2 or Stage3 was generated. Selfhosting remains unproven.

Merged validation logs: `/tmp/s-main-merged-record.log`,
`/tmp/s-main-merged-protocol.log`, `/tmp/s-main-merged-selfhost.log`.

## Reproduction boundary

Worktree: `/tmp/s-ast-borrow`, branch `fix/owned-recursive-ast-borrow`, based on
`9b46bb583431a57cade54a1052e8cc462d0f15c6`. The primary checkout was changing
concurrently (including deletion of the IR builder visitors). This branch
restores the full builder from `bd78ae79d` before fixing it. It neither deletes
compiler functions to pass the check nor changes either Lexer implementation.
The branch has not been merged into the primary checkout.

The first primary-checkout run resolved 254 files, including a transient source
file that disappeared before reading. Its open-input error is a concurrency
artifact, not an authoritative borrowing reproduction. The isolated source
closure has 253 files throughout the stable runs.

Command: `make selfhost` in this worktree. Baseline exit code: **2**.
Baseline diagnostic:

```
src/cmd/compile/internal/ir/middlend_ir_builder.s:47:1:
error[5]: unproven record borrow: escaping handle or unsupported call/body
```

The requested line 49 is blank in the restored source. Relevant original code:

```s
func ir_builder_build(ast* parser.ast_node) (ir_module, string[]) { // 47
    ctx := ir_builder_context_new()                              // 48
                                                                // 49
    ir_builder_visit_node(ctx, ast)                              // 50
                                                                // 51
    return ctx.module, ctx.errors                                // 52
}
```

The source gate `borrow_leaf`, `AST_RETURN_STMT`, requires at most one return
value. It rejects line 52, but formerly reported the function's line 47.
Signature resolution already identifies `compile.internal.parser.ast_node`;
this is not a recurrence of unresolved imported type identity. Later resource
validation would independently reject `ast_node*[] children`.

## Ownership and correction

Originally `ast_new` used `alloc` and returned `ast_node*`; children were raw
pointer arrays. No owning root/drop path established a lifetime for those
pointers. The builder reads nodes and descendants; its context and IR result
contain scalar, string, record and array values, with no AST pointer fields.
Allowing arbitrary recursive pointer arrays would therefore bypass an actual
missing ownership contract.

The frontend AST now owns `ast_node[] children`. `ast_new` returns a value;
`ast_add_child` snapshots an owned child value using the existing record/array
value-copy ABI. Frontend parser return annotations and its infix left operand
use AST values. Traversal borrows a root only during the call, snapshots each
child into a local value, and borrows that local during recursive traversal.
This represents a tree, not an arbitrary identity-preserving cyclic graph.
There is no new GC, raw-pointer exception, AST-specific checker exemption,
resource-owner copy permission or hosted fallback.

The source gate recognizes record ownership for LET snapshots of eligible
projections and verified record-returning calls. The independent native IR gate
tracks type and ownership separately through the CFG: raw parameters permit
root reborrow; MOV snapshots and checked user-function returns produce owners;
READ and runtime index CALL results remain aliases. All predecessors participate
in the ownership meet. Calls still require matching canonical schemas, exact
borrow descriptors, nonescaping body/return proof and distinct exclusive roots.
Source raw-handle copies, returns and array storage remain rejected.

Builder visitors now borrow `ctx`, so mutations reach the caller. They append
the updated current function/block, rather than stale copies. `ir_build_result`
returns both module and errors as one owned record; the old API had no callers
in this checkout. This is an explicit API correction, **not** general native
multi-return support. Unsupported multi-result borrowed functions still reject.
Expression dispatch handles the existing integer/identifier/binary/call visitors;
unimplemented if/for/while/struct lowering reports errors. Full frontend parser
execution and complete-language builder behavior have not been established.

Real-builder validation also exposed an instruction constructor writing an
undeclared `var_name` field; the call target now lives in `result.var_name`.
Qualified AST constants resolve by declaration package, with initializer scope,
local-shadow protection and bounded recursion. No package-name ownership bypass
was introduced.

## Verification

- `make selfhost-native-record-check`: exit **0**, including the new recursive
  AST test and existing ownership, receiver reborrow, imported type isolation,
  allocation rollback, ABI, append and native 1030-token Lexer regressions.
- `make selfhost-protocol-check`: exit **0**. Hosted diagnostic compatibility
  checks in this suite do not supply a compiler fallback for the bootstrap.
- `native_recursive_ast_borrow_check.sh`: native tree sum and real AST helpers
  return 42; actual AST + middlend IR + restored builder preserve function,
  parameter and integer-return IR data. Only the unused type-system map
  dependency is represented by an isolated test schema.
- Negative cases reject before artifact replacement or external assembler/linker:
  raw-handle return/copy/array storage, duplicate mutable roots, raw-pointer tree,
  multi-result borrowed return, CALL/READ aliases without MOV snapshots, and a
  branch that loses ownership on one predecessor. Constant initializer scope
  and local member shadowing have native regression tests.

## Latest FIRST RED and stage artifacts

Final command: `make selfhost`, exit **2**, unchanged 253-file source closure.

```
src/cmd/compile/internal/lexer/lexer.s:31:5:
error[5]: unproven record borrow: escaping handle or unsupported call/body
```

Exact source: `token[] tokens = token[]()` inside `tokenize`.
This is a different Lexer module from the previously verified
`parser/syntax/lexer.s`; neither was modified here. A minimal `int[] values =
int[]()` declaration reproduces the rejection without Lexer code. Seed
`--dump-ast` parses it as two EXPR_STMT nodes rather than a LET: the leading
empty-index type expression is rejected by `borrow_read_expr`'s INDEX rule,
which requires a real index. The next investigation should address general
seed parsing of type-leading array locals, not weaken borrowing or rewrite Lexer.

| Artifact under `.bootstrap/native-imports/` | Result |
| --- | --- |
| `stage1.sources` | 253-file manifest generated |
| `stage1-compile.log` | exact rejection captured |
| `stage1.ir`, `stage1` | absent |
| `stage2.sasm`, `stage2` | absent |
| `stage3.sasm`, `stage3` | absent |
| `.complete` | absent |

Local evidence is under `.bootstrap/ast-borrow-audit/`: stable baseline and final
logs/exit codes, `seed-command.sh` (fully expanded 253-input command),
`source-sha256.txt`, `stage-artifacts.json`, and the typed-local minimal source,
AST dump and diagnostic. Stage2/3 convergence was not run because Stage1 does
not exist. Existing protocol requires raw byte equality for both assembly and
ELF binaries; no normalization was added.
