# S Language Packages

This directory replaces the generic `src/go` placeholder with S-specific
language-facing packages.

Planned responsibilities:

- `ast/`: source-level syntax tree shapes and dump helpers
- `token/`: token kinds, keywords, and lexical metadata
- `parse/`: parser-facing helpers and reusable parse utilities
- `types/`: public type-model helpers intended to be shared across tools
- `format/`: formatting and pretty-printing support

Core reusable S-facing code now lives directly in `src/s`, while compiler-only
logic remains in `src/compiler`.
