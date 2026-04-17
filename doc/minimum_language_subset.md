# S Minimum Language Subset

This document fixes the smallest language-and-toolchain subset that S should
keep stable before broadening the language further.

The goal is the same as Go's early implementation goal: establish a complete
loop before chasing a large feature surface.

## Phase 1 Core Loop

The minimum complete loop is:

1. define a small language subset
2. lex and parse it reliably
3. check it consistently
4. build it through one stable command path
5. run the generated program through the current runtime bridge

Primary directories:

- `/app/s/src/s`
- `/app/s/src/cmd/compile/internal/compiler`
- `/app/s/src/runtime`
- `/app/s/src/cmd`

## 1. Stable Language Subset

This is the source subset that should remain stable first.

### File Shape

Each source file follows this top-level shape:

1. `package <name>`
2. zero or more `use ...`
3. zero or more top-level items

The top-level AST container is `SourceFile` with:

- `package`
- `uses`
- `items`

### Top-Level Items

Phase 1 keeps these declarations as the core public syntax surface:

- `func`
- `struct`
- `enum`
- `trait`
- `impl`

### Statements

The minimum statement set is:

- variable declaration
- assignment
- increment
- return
- expression statement

### Expressions

The minimum expression set is:

- integer literals
- string literals
- booleans
- names
- binary expressions
- function calls
- member access
- index access
- block expressions
- `if`
- `while`
- `switch`

### Keywords

The current stable keyword set should be treated as the language contract for
Phase 1. It lives in `/app/s/src/s/tokens.s` and includes the core words needed
by examples and the compiler itself, including `package`, `use`, `func`, `let`,
`var`, `return`, `if`, `else`, `while`, `for`, `switch`, `struct`, `enum`,
`trait`, `impl`, `pub`, `true`, and `false`.

## 2. Frontend Boundary

The public frontend lives in `/app/s/src/s`.

Phase 1 public entry points:

- `TokenKind`
- `Token`
- `dump_tokens`
- `LexError`
- `Lexer`
- `new_lexer`
- `ParseError`
- `Parser`
- `parse_source`
- `parse_tokens`
- `SourceFile`
- `Item`
- `Stmt`
- `Expr`
- `Pattern`
- `dump_source_file`

The compiler should treat these as the reusable language-facing surface, similar
to how Go keeps reusable syntax packages under `src/go/*`.

## 3. Minimal Compiler Boundary

The compiler implementation lives in `/app/s/src/cmd/compile/internal/compiler`.

Phase 1 compiler responsibilities:

- parse source through `src/s`
- run semantic checking
- keep diagnostics stable enough for fixtures
- build simple native executables

Success means these commands stay working:

```bash
cd /app/s/src
python3 -m compiler check /app/s/src/cmd/compile/internal/tests/fixtures/check_ok.s
python3 -m compiler build /app/s/misc/examples/s/hello.s -o /app/tmp/s_hello
python3 -m compiler build /app/s/misc/examples/s/sum.s -o /app/tmp/s_sum
```

## 4. Minimal Runtime And Command Entry

The runtime bridge lives in `/app/s/src/runtime`.

The command entry layer lives in:

- `/app/s/src/cmd/s/main.s`
- `/app/s/src/cmd/lex_dump/main.s`
- `/app/s/src/cmd/ast_dump/main.s`
- `/app/s/src/cmd/test_compiler/main.s`

Phase 1 runtime scope:

- keep hosted command execution working
- keep native runner bootstrap working
- keep intrinsic boundaries explicit
- avoid pushing parser or semantic logic into runtime

## 5. Current Working Examples

The current minimum example set is:

- `/app/s/misc/examples/s/hello.s`
- `/app/s/misc/examples/s/sum.s`

If a language or compiler change breaks these programs, it is a Phase 1
regression unless the change deliberately updates the minimum subset contract.
