# Bootstrap subset v1

Scope: source-dependent native execution in the C-produced minimal Stage1.
This is bootstrap machinery, not the canonical S compiler implementation.
Production parser, type checking, and all other production authority remain
unproven. Stage2's historical template path is outside this slice.
It is available only through `--emit-artifact-stage2`, never as a fallback
from `build`. The historical `modular-selfhost-check` target exercises that
artifact path and explicitly reports that canonical compilation is unproven.

Grammar (keywords are reserved; whitespace and C-style comments are skipped):

```text
unit       = "package" identifier function+ EOF
function   = "func" identifier "(" ")" "int" "{" "return" expression [";"] "}"
expression = decimal_integer | identifier "(" ")" | "(" expression ")"
identifier = [A-Za-z_][A-Za-z_0-9]*
```

Exactly one package declaration is required. Its identifier is recorded in
the compilation unit and is independent of the `main` entry function.
Dotted names, imports, multiple files, package resolution, namespaces and
visibility are outside this subset.

Integers range from 0 through 2147483647 and always mean decimal, including
leading zeros. Identifiers are at most 63 bytes. Limits: 256 functions and
64 nested parentheses. Functions take no arguments, return one integer, and
may call functions declared later. Call cycles are rejected. Exactly one `main`
is required; duplicate definitions and unresolved calls are errors. Each
body has exactly one return. Unsupported constructs, malformed tokens,
unterminated comments, and trailing input are errors, never fallback triggers.

Translation: tokenize the entire input, construct function/return-expression
records, resolve calls to function indices, emit C definitions and prototypes,
then invoke host `cc` without a shell. The host compiler supplies the native
calling convention and executable format (Mach-O arm64 on an arm64 macOS
host). This slice does not implement a native object writer. C identifiers
are generated from indices; input text is never injected as C expressions.

The generated Stage1 carries this machinery in its binary. It does not read
the implementation source at execution time or delegate to an existing S
compiler. The C Stage0 generator embeds `bootstrap_subset.c` verbatim; it
does not implement production grammar rules. The freeze check scans both
files to keep this boundary visible.

`make stage1-source-execution-check` requires native executions of constant
returns and ordinary calls to match their source. It also checks rejection
and absence of a newly emitted artifact for unsupported/malformed inputs.
Shell exit statuses expose the low eight bits; the gate uses values below 256.
PASS proves this subset only:

```text
bootstrap-subset-source-execution=PASS
canonical-source-compilation=NOT_PROVEN
production-compiler-bootstrap=NOT_PROVEN
```
