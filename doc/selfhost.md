# self-hosting sources

this directory contains the first s-native compiler building blocks.

current scope:

- `std/*.s`: minimal self-hosting runtime skeleton for option / result / vec / io / fs / prelude helpers
- `std/env.s` and `std/process.s`: command-entry abi for argv / exit during self-hosted execution
- `s/ast.s`: s-native ast data model mirroring `compiler/ast.py`
- `s/tokens.s`: s-native token definitions mirroring `compiler/lexer/tokens.py`
- `s/lexer.s`: s-native lexer mirroring `compiler/lexer/lexer.py`
- `s/parser.s`: s-native parser skeleton mirroring `compiler/parser/parser.py`
- `cmd/lex_dump.s`: minimal self-hosting driver for `source  tokens  dump`
- `cmd/ast_dump.s`: minimal self-hosting driver for `source  ast dump`
- `cmd/s.s`: minimal self-hosted compiler command wrapper around `compiler.main`

these files are intentionally foundational. they are the first step toward replacing the python prototype with s implementations in the order described by [docs/self_hosting.md](/app/s/doc/self_hosting.md).

supporting docs:

- [docs/selfhost_lex_dump.md](/app/s/doc/selfhost_lex_dump.md)
- [docs/ast_dump.md](/app/s/doc/ast_dump.md)
- [docs/runtime_intrinsics.md](/app/s/doc/runtime_intrinsics.md)
