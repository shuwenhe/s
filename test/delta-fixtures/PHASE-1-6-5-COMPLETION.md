# Phase 1.6.5 - DOT Tokenization Lexical Carry

## Status: ✅ COMPLETE

## What Was Implemented

**Scope**: Minimal lexical-only change
```c
enum { BS_EOF = 256, BS_NAME, BS_INT, BS_STRING, BS_WALRUS, BS_DOT };

// In tokenizer bs_next():
} else if (*p == '.') {
    u->token = BS_DOT;
    p++;
}
```

**What Was NOT Implemented**:
- ✗ No qualified-name-expression parsing
- ✗ No member-access semantics  
- ✗ No symbol resolution
- ✗ No parser changes

## Failure Migration Proof

### Before Phase 1.6.5

```
canonical source byte 537: unsupported character '.'
                            (tokenizer rejected dot)
```

### After Phase 1.6.5

```
canonical source byte 538: unexpected token
                            (parser receives BS_DOT token but doesn't handle it)
```

**Significance**: Failure moved from lexer → parser layer
- ✅ Dot is now a recognized token
- ✅ First blocker (tokenization) has been pierced
- ⏳ Next blocker is parser-level (qualified expression syntax)

## Four-Layer Delta Fixture Results

### Layer Analysis (BEFORE Phase 1.6.5)

| Layer | Code | Error | Type |
|-------|------|-------|------|
| A | `x := std` | "unexpected token" @55 | Parser fail |
| B-D | `x := std.env[...]` | **"unsupported character" @44** | **Tokenizer fail** |

### Four-Layer Delta Fixture Results (AFTER Phase 1.6.5)

| Layer | Code | Error | Type |
|-------|------|-------|------|
| A | `x := std` | "unexpected token" @55 | Parser fail (unchanged) |
| B-D | `x := std.env[...]` | **"unexpected token" @45** | **Parser fail (migrated)** |

**Interpretation**:
- Layer A: No change. Still parser fail because "std" is undefined local or function call
- Layers B-D: Byte 44→45 shift due to tokenizer consuming '.'. Error type changed from "unsupported character" to "unexpected token"
- Proof: Tokenizer successfully recognized '.' and created BS_DOT token

## Gate Suite Results

✅ All existing gates pass (no regression):
- Phase 1.6.3: Local binding execution - **PASS** (6/6 tests)
- Stage0 freeze check - **PASS**
- Stage0 reproducibility - **PASS**

## Canonical Compilation Status

```
before: byte 537 unsupported character '.'
after:  byte 538 unexpected token
```

**Interpretation**: 
- Tokenizer has successfully parsed dot
- Parser now encounters unhandled BS_DOT token
- This is expected for Phase 1.6.5 scope

## What Phase 1.6.6 Must Address

Based on canonical's new error, Phase 1.6.6 will likely need one of:

1. **Parser-level qualified-name support**
   Error: "unexpected token '.'"
   → Need to parse `identifier.identifier[.identifier]*` as expression

2. **Symbol resolution for qualified names**
   Error: "undefined symbol std"
   → Need builtin package/module definitions

3. **Member access syntax**
   Error: "expected identifier after '.'"
   → Need to parse member expressions

The canonical failure at byte 538 will guide Phase 1.6.6's exact scope.

## Phase 1.6.5 Verification Checklist

✅ First-proven-gap identified: dot-tokenization
✅ Implementation minimal and scoped: tokenizer only
✅ No semantic changes: BS_DOT is recognized but unused by parser
✅ Failure migration demonstrated: lexer→parser layer shift
✅ No regressions: all prior gates still pass
✅ Ready for next phase: canonical now reports new error

## Code Review

**File**: `src/cmd/compile/stage0/bootstrap_subset.c`

**Changes**:
1. Line 13: Added `BS_DOT` to token enum
2. Lines 95-97: Added dot recognition in tokenizer

**Rationale**:
- Minimal change principle maintained
- Token ID auto-assigned by enum (no hardcoding)
- Tokenizer handles dot like other single-char tokens
- Parser left unchanged (will report "unexpected token" when encountering BS_DOT)

## Commitment Record

**What This Phase Proves**:
- Dot tokenization is feasible in bootstrap subset
- First-proven-gap in qualified-name roadmap has been isolated
- Bootstrap methodology scales: identify gap → isolate with fixtures → implement minimal → iterate

**What This Phase Does NOT Prove**:
- Qualified names work
- Member access works
- Symbol resolution works
- Canonical source compiles

All of those are future phases, guided by canonical's next error report.
