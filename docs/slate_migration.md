# Slate Migration Into `s`

This document tracks the migration of the Slate compiler implementation into the main `s` repository.

## Current State

The Slate sources have now been moved into `/app/s`:

- S-language Slate compiler sources live in `/app/s/slatec`
- Python bootstrap Slate compiler sources live in `/app/s/slate_bootstrap`
- Slate examples live in `/app/s/examples/slate`
- Slate self-hosting notes live in `/app/s/docs/slate_self_hosting.md`

Imported S-language files:

- `/app/s/slatec/ast.s`
- `/app/s/slatec/lexer.s`
- `/app/s/slatec/parser.s`
- `/app/s/slatec/semantic.s`
- `/app/s/slatec/backend_elf64.s`
- `/app/s/slatec/main.s`

Imported bootstrap files:

- `/app/s/slate_bootstrap/slatec/__main__.py`
- `/app/s/slate_bootstrap/slatec/ast.py`
- `/app/s/slate_bootstrap/slatec/lexer.py`
- `/app/s/slate_bootstrap/slatec/parser.py`
- `/app/s/slate_bootstrap/slatec/semantic.py`
- `/app/s/slate_bootstrap/slatec/backend_elf64.py`

Imported examples:

- `/app/s/examples/slate/hello.s`
- `/app/s/examples/slate/sum.s`

## Why The Bootstrap Compiler Still Exists

This keeps the migration practical:

- `/app/s/slatec` is the S-language implementation target
- `/app/s/slate_bootstrap` is the currently runnable compiler path
- future work can replace bootstrap behavior module by module without losing the ability to build examples

## Next Steps

1. Align `/app/s/slatec` with the long-term compiler layout inside `s`
2. Decide which Slate modules should merge into `compiler`, `frontend`, `cmd`, and `runtime`
3. Replace pieces of `/app/s/slate_bootstrap` with the corresponding `/app/s/slatec` modules
4. Retire the bootstrap path once the S implementation can carry the same example set
