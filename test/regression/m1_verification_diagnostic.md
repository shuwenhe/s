# M1.1 Identity Threading Verification (NOT YET OBSERVABLE)

## Current Implementation Status

### What We Have
✅ M0 Infrastructure:
- semantic_result.declarations[] - populated from semantic phase
- mono_context.declarations - receives declarations via parameter  
- mono_work_item.declaration_ref - carries ref as value
- m1_identity_verification struct - tracks population status

### What We Cannot Yet Observe
The M1.1 proof requires observing:

1. **Existence**: Did Semantic actually create declaration_ref for Point?
   - Needed: Access to semantic_result.declarations at runtime
   - Current: No mechanism to inspect this in S language

2. **Transmission**: Did declaration_ref actually reach mono_context?
   - Needed: Ability to log mono_context.declarations values
   - Current: No logging/printing in S language

3. **Preservation**: Is the declaration_ref in mono_work_item equal to semantic version?
   - Needed: Runtime comparison and output of declaration_ref_equal() results
   - Current: Function exists but results not observable

4. **Non-Reconstruction**: Did Mono use the received ref or re-lookup by "Point"?
   - Needed: Instrumentation to detect name-based lookups in mono phase
   - Current: No such instrumentation exists

## Why Compilation Success Is Not Sufficient

```
LEVEL 1 (Current):
struct Point { x: i32; y: i32 }
func create_point(...) Point { Point { x: ..., y: ... } }
                              ↓
                       COMPILES → test passes

This proves:
  ✓ Grammar is correct
  ✓ Type checking passed
  ✓ No name conflicts

This does NOT prove:
  ✗ declaration_ref("demo", struct_kind, "Point") was created
  ✗ This ref was passed to Mono
  ✗ Mono used this ref (not re-lookup or re-construction)

LEVEL 2 (Needed for M1):
Observe the actual declaration_ref values:

semantic-phase output:
  declaration_ref = {
    package_path: "demo",
    kind: struct_kind,
    path: "Point"
  }

mono-input:
  declarations[0] = {
    package_path: "demo",
    kind: struct_kind,
    path: "Point"
  }

mono-work-item[i]:
  declaration_ref = {
    package_path: "demo",
    kind: struct_kind,
    path: "Point"
  }

verification:
  value-equal(semantic_ref, mono_ref): PASS
  (proves VALUE was transmitted)

exclusion:
  no name-lookup("Point") detected
  no re-construction from scratch detected
  (proves NO RE-LOOKUP)

THEN: M1 PASS
```

## Blocker: S Language Lacks Observation Mechanism

The S compiler has:
- ✓ Error/diagnostic system (for compilation errors)
- ✓ Type checking (compile-time)
- ✗ Runtime logging/output
- ✗ Reflection/introspection
- ✗ Debug info interface

Options to proceed:

### Option A: Extend Backend to Output M1 Diagnostic
- Add code to backend_elf64.s or compiler.s
- Generate a diagnostic file with m1_gate verification results
- Requires: File I/O in backend (if available)

### Option B: Add Temporary Instrumentation to Mono
- Modify monomorphization.s to validate declaration_refs
- Return error if validation fails (breaks build)
- Can observe via error messages
- Requires: Strict validation that makes failure observable

### Option C: Create a Separate Verification Pass
- Implement a checker that scans final binary/IR
- Reconstructs type identity chains
- Reports on re-lookup patterns
- Requires: Understanding of compiled output format

### Option D: Modify Seed Compiler Parser
- Add diagnostic mode to seed compiler
- Output intermediate structures to stderr/file
- Requires: Changes to seed compiler itself

## Recommendation

Proceed with **Option B** (temporary instrumentation):

1. Add strict M1 gate check in monomorphize_file
2. If ANY work_item lacks declaration_ref → error
3. This ensures ref was properly populated
4. Error message proves point: "M1 gate passed: all work_items have declaration_ref"

Then build m1_declaration_ref_gate.s:
- If build FAILS: M1 check caught a problem
- If build PASSES: Proves all work_items were populated with refs

This is indirect but rigorous: we cannot observe the values, but we can observe that the expected structure is present.

Next step: Implement strict M1 validation in backend.
