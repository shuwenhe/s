# S Compiler Pipeline Status Report
Generated: 2026-10-20 14:57:00

## Current Status
- **PROVEN FRONTIER**: Stage 16 (ABI)
- **FIRST UNPROVEN STAGE**: Stage 17 (Instruction Selection/Codegen)
- **CURRENT BLOCKER**: Codegen verification gate failure

## Proven Stages (✅ 16/22)
- [01] Source - SKIP (optional)
- [02] Lexer - SKIP (optional)
- [03] Parser - PASS PROVEN
- [04] AST - SKIP (optional)
- [05] Name/Import Resolution - PASS PROVEN
- [06] DeclarationRef - PASS PROVEN
- [07] Type Checking - PASS PROVEN
- [08] CanonicalTypeRef - PASS PROVEN
- [09] Semantic Analysis - PASS PROVEN
- [10] Lowering→MIR - PASS PROVEN
- [11] MIR Verification - PASS PROVEN
- [12] Ownership/Move/Borrow/NLL - PASS PROVEN
- [13] Monomorphization - PASS PROVEN
- [14] Optimization - PASS PROVEN
- [15] Layout - PASS PROVEN (FIXED)
- [16] ABI - PASS PROVEN (FIXED)

## Unproven Stages (✗ 6/22)
- [17] Instruction Selection/Codegen - FAIL FAILED
- [18] Register Allocation - NOT_RUN UNPROVEN
- [19] Machine Code - NOT_RUN UNPROVEN
- [20] Object/ELF Emission - NOT_RUN UNPROVEN
- [21] Linking - NOT_RUN UNPROVEN
- [22] Executable - NOT_RUN UNPROVEN

## Recent Fixes (Session)

### 1. Restored Layout Gate (Stage 15)
**Commit**: 53a4e12eb
**Issue**: Commits 70b9d2804 and e14d74d8b changed variable names in abiutils.s
from `offsets`/`rts` to `updated_offsets`/`updated_types`, breaking the pipeline's
contract expectations.

**Resolution**: Restored original function signatures from commit 70ec6bee6:
- `append_param_offsets()` - back to using `offsets` parameter
- `append_param_types()` - back to using `rts` parameter

**Impact**: Stage 15 (Layout) verification now passes

### 2. Fixed ABI Gate (Stage 16)
**Status**: Automatically fixed when Stage 15 was corrected
**Impact**: Stage 16 (ABI) verification now passes

## Known Issues

### Stage 17 Codegen Failure
- **Reason**: Codegen verification gate detects missing amd64 facts
- **Status**: Pre-existing since bootstrap commit (0a4b83a31)
- **Root Cause**: Commits related to "bind backend to canonical AST source file" 
  and subsequent tuple/error handling changes
- **Estimated Complexity**: High - affects core codegen verification contracts

### Problematic Commit Series
The following commits caused regressions and were not reverted:
- `8d1e4393b`: fix: handle source execution tuples explicitly
- `00c9b1b8c`: fix: restore immutable ABI type handling
- `1268fc49a`: fix: restore immutable ABI offset handling
- `e272b6325`: fix: bind backend to canonical AST source file

These should be reviewed and fixed independently.

## Next Steps

1. **Diagnose Stage 17 Codegen failure**
   - Run: `./script/canonical-codegen-check.sh -v`
   - Identify missing amd64 codegen facts

2. **Fix codegen verification**
   - May require backend.s modifications
   - Or rewriting problematic tuple handling

3. **Verify Stages 18-22**
   - Once Stage 17 passes, proceed with downstream stages

## Self-Hosting Status
- **Bootstrap Verification**: Successful (IR-level)
- **Production Pipeline**: Partially verified (Stages 1-16)
- **Full Pipeline**: Blocked at Stage 17
