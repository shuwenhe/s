#!/bin/bash
# Hosted Bootstrap - Documentation 
#
# This file exists for documentation purposes. The real issue preventing
# selfhost is NOT about bootstrap structure (that's working fine), but an
# architectural limitation in the IR backend:
#
# Problem:
#  - Seed compiler generates IR with generic method definitions like:
#    FUNC_BEGIN|option[t].is_none|_|_
#  - These are NOT monomorphized (no concrete instantiations like 
#    s_fn_option_string___is_none)
#  - IR backend's native code generator cannot handle generic methods
#  - Linker fails with 28 undefined references
#
# Root Cause:
#  - Monomorphization code exists in compile.internal.mono but is only
#    used by the hosted compiler
#  - Seed compiler (C-based) has no monomorphization support
#  - Bootstrap process tries to compile compiler code that uses generics
#    before monomorphization is available
#
# Why Go doesn't have this problem:
#  - Go stdlib/compiler has NO generics (pre-Go 1.18)
#  - New generics in Go 1.18+ are NOT used in bootstrap code
#  - S uses generics pervasively (option[t], result[t,e], box[t])
#    These are essential parts of the language design
#
# Solutions (in order of feasibility):
#
# 1. SHORT TERM: Use hosted compiler to compile stage1.ir
#    Status: VERIFIED WORKING (hosted compiler can read IR)
#    Next: Implement IR -> C compilation in hosted compiler if not present
#          OR find if native backend supports this
#
# 2. MEDIUM TERM: Implement generic monomorphization in seed compiler
#    Status: Would fix IR generation to emit monomorphized methods
#    Effort: ~1-2 weeks of C coding
#    Benefit: Native bootstrap would then work
#
# 3. LONG TERM: Implement generic support in native IR backend
#    Status: Most complete solution
#    Effort: ~3-4 weeks
#    Benefit: Eliminates bootstrap vs production compiler divergence
#
# Current Recommendation:
#  Focus on solution #2: Add monomorphization to seed compiler's IR generation.
#  This is smaller than #3 and fixes the immediate bootstrap issue without
#  needing hosted compiler involvement.
#
# Files involved:
#  - src/cmd/compile/seed/code/generator.c - IR generation entry point
#  - src/cmd/compile/seed/code/standalone_records.h - Record validation
#  - src/cmd/compile/internal/mono/monomorphization.s - Mono algorithm
#
# The fact that we got 253 S modules to compile to IR and pass validation
# before hitting linker errors proves the bootstrap pipeline is sound—
# the issue is purely in the IR backend's code generation.

set -e
echo "Hosted Bootstrap - Architectural Limitation Note" >&2
echo "================================================" >&2
echo "" >&2
echo "S cannot self-host because:" >&2
echo "  1. Compiler source uses generics (option[t], result[t,e], box[t])" >&2
echo "  2. Seed compiler's IR backend cannot generate code for generic methods" >&2
echo "  3. Linker fails with undefined references to monomorphized methods" >&2  
echo "" >&2
echo "See comments above for solutions." >&2
exit 1
