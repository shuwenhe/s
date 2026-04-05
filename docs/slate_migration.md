# Slate Migration Into `s`

This document tracks the staged migration of the Slate compiler implementation into the main `s` repository.

## Current Step

The first migration step is complete:

- the S-language Slate compiler sources from `/app/slate/slatec_s`
- have been copied into `/app/s/slatec`
- without deleting the original `/app/slate` repository

Current imported files:

- `/app/s/slatec/ast.s`
- `/app/s/slatec/lexer.s`
- `/app/s/slatec/parser.s`
- `/app/s/slatec/semantic.s`
- `/app/s/slatec/backend_elf64.s`
- `/app/s/slatec/main.s`

## Why This Step Comes First

This keeps the migration safe:

- `/app/slate` still preserves the working bootstrap compiler
- `/app/s` now contains the S-language Slate compiler sources
- future work can consolidate implementation inside `s` without losing a known-good path

## Next Steps

1. Align `/app/s/slatec` with the evolving directory conventions in `s`
2. Decide which Slate modules should merge into existing `compiler`, `frontend`, `cmd`, and `runtime` layers
3. Move examples and docs from `/app/slate` into `/app/s`
4. Shrink `/app/slate` down to repository metadata such as `README.md` and `.gitignore`

