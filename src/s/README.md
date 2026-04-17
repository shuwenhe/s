# S Language Packages

This directory is the reusable language-facing surface for S. It plays the role
that `src/go/*` plays in Go: public syntax and parsing building blocks that can
be shared by the compiler and other tools.

Current implementation files:

- `ast.s`
- `tokens.s`
- `lexer.s`
- `parser.s`

## Current Public Entry Points

The current public surface is intentionally small:

- `TokenKind`
- `Token`
- `token_kind_name`
- `dump_tokens`
- `is_keyword`
- `LexError`
- `Lexer`
- `new_lexer`
- `ParseError`
- `Parser`
- `parse_source`
- `parse_tokens`
- `SourceFile`
- `UseDecl`
- `Item`
- `FunctionDecl`
- `StructDecl`
- `EnumDecl`
- `TraitDecl`
- `ImplDecl`
- `Stmt`
- `Expr`
- `Pattern`
- `dump_source_file`

## Stable Contract For Phase 1

These parts should be treated as stable during Phase 1:

- `parse_source(source)` is the main parsing entry point
- `parse_tokens(tokens)` is the token-to-AST entry point
- `new_lexer(source).tokenize()` is the lexer entry point
- `dump_tokens(tokens)` keeps a one-token-per-line golden format
- `SourceFile` stays the top-level syntax container with:
  - `package`
  - `uses`
  - `items`

## Minimum Language Subset

Before broadening the language, the following source subset should stay stable:

- top-level file shape: `package`, then `use`, then items
- top-level items: `func`, `struct`, `enum`, `trait`, `impl`
- statements: variable declaration, assignment, increment, return, expr stmt
- expressions: literals, names, binary, call, member, index, block, `if`,
  `while`, and `switch`

This is the subset that parser, semantic checking, build, and runtime support
should protect first. The fuller contract lives in
`/app/s/doc/minimum_language_subset.md`.

## AST Model Summary

The current AST is intentionally split into a few predictable layers:

- top level: `SourceFile  UseDecl + Item`
- declarations: `FunctionDecl`, `StructDecl`, `EnumDecl`, `TraitDecl`, `ImplDecl`
- statements: `Var`, `Assign`, `Increment`, `CFor`, `Return`, `Expr`
- expressions: literals, names, borrow, binary, member, index, call, switch, if,
  while, for, and block
- patterns: `Name`, `Wildcard`, `Variant`

The repeated `inferred_type` field on expressions is intentional for now. It is
the current semantic-analysis attachment point, so it should not be removed
until the compiler has a replacement type-carrying strategy.

## Compiler Dependency Surface

The current compiler and command packages rely mainly on:

- `parse_source`
- `new_lexer`
- `dump_tokens`
- `dump_source_file`
- `SourceFile`
- expression, statement, item, and pattern node types consumed by semantic and
  backend code

That means the highest-risk churn in `src/s` is:

- changing `SourceFile`
- renaming `Item` variants
- renaming `Stmt` variants
- renaming `Expr` variants
- changing `Token` fields or `dump_tokens` output format

## Phase 1 Direction

Short term:

- keep `ast.s`, `tokens.s`, `lexer.s`, and `parser.s` stable
- avoid broad API expansion
- move compiler-private helpers into `src/compiler` or `src/internal`

Later:

- split reusable APIs into subpackages such as `ast/`, `token/`, `parse/`,
  `types/`, and `format/` once the current surface has settled
