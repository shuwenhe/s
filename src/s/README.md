# S Frontend Packages

This directory replaces the generic `src/go` placeholder with S-specific
language-facing packages.

Planned responsibilities:

- `ast/`: source-level syntax tree shapes and dump helpers
- `token/`: token kinds, keywords, and lexical metadata
- `parse/`: parser-facing helpers and reusable parse utilities
- `types/`: public type-model helpers intended to be shared across tools
- `format/`: formatting and pretty-printing support

Existing production code still lives in `src/frontend` and `src/compiler`.
These subdirectories are the long-term package layout for reusable S-facing APIs.

