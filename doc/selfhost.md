# Self-Hosting Sources

This directory contains the first S-native compiler building blocks.

Current scope:

- `std/*.s`: minimal self-hosting runtime skeleton for Option / Result / Vec / IO / FS / prelude helpers
- `std/env.s` and `std/process.s`: command-entry ABI for argv / exit during self-hosted execution
- `frontend/ast.s`: S-native AST data model mirroring `compiler/ast.py`
- `frontend/tokens.s`: S-native token definitions mirroring `compiler/lexer/tokens.py`
- `frontend/lexer.s`: S-native lexer mirroring `compiler/lexer/lexer.py`
- `frontend/parser.s`: S-native parser skeleton mirroring `compiler/parser/parser.py`
- `cmd/lex_dump.s`: minimal self-hosting driver for `source -> tokens -> dump`
- `cmd/ast_dump.s`: minimal self-hosting driver for `source -> AST dump`
- `cmd/s.s`: minimal self-hosted compiler command wrapper around `compiler.main`

These files are intentionally foundational. They are the first step toward replacing the Python prototype with S implementations in the order described by [docs/self_hosting.md](/app/s/doc/self_hosting.md).

Supporting docs:

- [docs/selfhost_lex_dump.md](/app/s/doc/selfhost_lex_dump.md)
- [docs/ast_dump.md](/app/s/doc/ast_dump.md)
- [docs/runtime_intrinsics.md](/app/s/doc/runtime_intrinsics.md)
