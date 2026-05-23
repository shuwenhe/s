#!/bin/bash
SRC="/c/Users/shuwen/s/src/cmd/compile/seed"
OUT="/c/Users/shuwen/s/bin/s.exe"
/mingw64/bin/gcc -std=c11 -o "$OUT" "$SRC/s_seed.c" "$SRC/bootstrap/bootstrap.c" "$SRC/code/generator.c" "$SRC/code/native_backend.c" "$SRC/debug/debug.c" "$SRC/error/error.c" "$SRC/intermediate/ir.c" "$SRC/lexical/lexer.c" "$SRC/runtime/runtime.c" "$SRC/semantic/analyzer.c" "$SRC/syntax/parser.c" "$SRC/testing/tests.c"
echo "Exit: $?"