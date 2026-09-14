# Phase 1.6.5 Investigation Report - Dot Tokenization Layer Analysis

## Four-Layer Test Results

```
Layer A: x := std
         ├─ Error: "unexpected token" at byte 55
         ├─ Location: right after "std"
         ├─ Root cause: bs_expression() treats "std" as function call
         │             expects "(" but finds ";" (end of statement)
         └─ Analysis: Identifier resolution, not tokenization

Layer B: x := std.env
         ├─ Error: "unsupported character" at byte 44
         ├─ Location: at the first '.' character
         ├─ Root cause: Tokenizer doesn't recognize '.'
         └─ Analysis: Tokenization blocker

Layer C: x := std.env.args
         ├─ Error: "unsupported character" at byte 44
         ├─ Location: at the first '.' character (same as B)
         ├─ Note: Second dot never reached because tokenizer stops at first dot
         └─ Analysis: Confirms dot is the blocker

Layer D: x := std.env.args()
         ├─ Error: "unsupported character" at byte 44
         ├─ Location: at the first '.' character
         └─ Analysis: Same as B and C - dot is blocker, not call syntax
```

## Key Finding: Blocker Hierarchy

The problem decomposes into distinct layers:

```
Layer A: Identifier semantics
         "std" is recognized as a name but fails in call context
         → bs_expression() expects '(' after function call
         
Layer B-D: Tokenizer limitation
          '.' is not a recognized token
          → Stops at first dot regardless of what follows
```

## What Phase 1.6.5 Must Address

**Minimum change to progress**:
```
Add BS_DOT token to tokenizer
Recognize '.' as two-character sequence (already single char)
```

**What Phase 1.6.5 will NOT do yet**:
- Parse qualified names as expressions
- Resolve module/package references
- Handle member access semantics
- Support qualified calls

## Expected Outcome After Adding BS_DOT

After adding DOT token support, canonical will likely report:
```
"undefined symbol std"
or
"unexpected token '.'"
or
"expected identifier after '.'"
```

Each would indicate next sub-feature:
- Undefined symbol → builtin/import resolution needed
- Unexpected token → qualified expression parsing needed
- Expected identifier → member syntax parsing needed

## Investigation Complete

Phase 1.6.5 is **NOT qualified-name-expression implementation**.
Phase 1.6.5 is **ONLY dot-tokenization investigation + minimal lexical carry**.

This maintains bootstrap principle:
1. Identify proven gap (dot character)
2. Make minimal change (add token)
3. Rerun canonical
4. Let it reveal next layer
