# Self-Hosting Sources

This directory contains the first S-native compiler building blocks.

Current scope:

- `frontend/ast.s`: S-native AST data model mirroring `compiler/ast.py`
- `frontend/tokens.s`: S-native token definitions mirroring `compiler/lexer/tokens.py`
- `frontend/lexer.s`: S-native lexer mirroring `compiler/lexer/lexer.py`
- `frontend/parser.s`: S-native parser skeleton mirroring `compiler/parser/parser.py`
- `cmd/lex_dump.s`: minimal self-hosting driver for `source -> tokens -> dump`

These files are intentionally foundational. They are the first step toward replacing the Python prototype with S implementations in the order described by [docs/self_hosting.md](/app/s/docs/self_hosting.md).
