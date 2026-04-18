# s language packages

this directory is the reusable language-facing surface for s. it plays the role
that `src/go/*` plays in go: public syntax and parsing building blocks that can
be shared by the compiler and other tools.

current implementation files:

- `ast.s`
- `tokens.s`
- `lexer.s`
- `parser.s`

## current public entry points

the current public surface is intentionally small:

- `tokenkind`
- `token`
- `token_kind_name`
- `dump_tokens`
- `is_keyword`
- `lexerror`
- `lexer`
- `new_lexer`
- `parseerror`
- `parser`
- `parse_source`
- `parse_tokens`
- `sourcefile`
- `usedecl`
- `item`
- `functiondecl`
- `structdecl`
- `enumdecl`
- `traitdecl`
- `impldecl`
- `stmt`
- `expr`
- `pattern`
- `dump_source_file`

## stable contract for phase 1

these parts should be treated as stable during phase 1:

- `parse_source(source)` is the main parsing entry point
- `parse_tokens(tokens)` is the token-to-ast entry point
- `new_lexer(source).tokenize()` is the lexer entry point
- `dump_tokens(tokens)` keeps a one-token-per-line golden format
- `sourcefile` stays the top-level syntax container with:
  - `package`
  - `uses`
  - `items`

## minimum language subset

before broadening the language, the following source subset should stay stable:

- top-level file shape: `package`, then `use`, then items
- top-level items: `func`, `struct`, `enum`, `trait`, `impl`
- statements: variable declaration, assignment, increment, return, expr stmt
- expressions: literals, names, binary, call, member, index, block, `if`,
  `while`, and `switch`

this is the subset that parser, semantic checking, build, and runtime support
should protect first. the fuller contract lives in
`/app/s/doc/minimum_language_subset.md`.

## ast model summary

the current ast is intentionally split into a few predictable layers:

- top level: `sourcefile  usedecl + item`
- declarations: `functiondecl`, `structdecl`, `enumdecl`, `traitdecl`, `impldecl`
- statements: `var`, `assign`, `increment`, `cfor`, `return`, `expr`
- expressions: literals, names, borrow, binary, member, index, call, switch, if,
  while, for, and block
- patterns: `name`, `wildcard`, `variant`

the repeated `inferred_type` field on expressions is intentional for now. it is
the current semantic-analysis attachment point, so it should not be removed
until the compiler has a replacement type-carrying strategy.

## compiler dependency surface

the current compiler and command packages rely mainly on:

- `parse_source`
- `new_lexer`
- `dump_tokens`
- `dump_source_file`
- `sourcefile`
- expression, statement, item, and pattern node types consumed by semantic and
  backend code

that means the highest-risk churn in `src/s` is:

- changing `sourcefile`
- renaming `item` variants
- renaming `stmt` variants
- renaming `expr` variants
- changing `token` fields or `dump_tokens` output format

## phase 1 direction

short term:

- keep `ast.s`, `tokens.s`, `lexer.s`, and `parser.s` stable
- avoid broad api expansion
- move compiler-private helpers into `src/compiler` or `src/internal`

later:

- split reusable apis into subpackages such as `ast/`, `token/`, `parse/`,
  `types/`, and `format/` once the current surface has settled
