# P2 Structured SSA Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Lower the accepted P1 multi-function Program IR into a verified structured SSA program while preserving functions, calls, control flow, and value definitions.

**Architecture:** Add one SSA representation directly coupled to `compile.internal.mir.program`, rather than extending the existing text-based SSA statistics pipeline or the incomplete machine-lowering stub. The first supported subset is the accepted P1 straight-line integer/call form plus explicit branch/merge fixtures using block parameters or Phi nodes; native lowering remains out of scope.

**Tech Stack:** S sources compiled by the existing Seed test executor; P1 `mir_program` data model; hosted behavioral fixtures and structural verifier tests.

**Spec:** P2 approval in the user request: `lower_function_to_ssa(function, context)` and `lower_program_to_ssa(program)` with valid values, CFG, calls, memory ordering, and Phi/block-parameter joins.

## Global Constraints

- Do not modify Seed language semantics, Stage0, Bootstrap scripts, or Stage1/P3/P4 code.
- Do not use source interpretation or compile-time execution to construct SSA.
- Preserve all P1 functions, parameters, result types, calls, and call edges.
- Do not reuse the text/metrics SSA pipeline as the P2 semantic representation.
- Do not modify `core/ssa_lower.s`; it is a later Machine IR boundary, not the P2 builder.
- P1 regression must remain passing after every P2 change.

## Review Focus

- Forward calls: function order must not change call resolution or SSA symbol identity.
- Branch joins: a value defined on both predecessors must become one Phi/block parameter with matching predecessor order.
- Dominance: no SSA operand may refer to a value defined in a non-dominating block.
- Side effects: calls and memory operations must remain ordered in their original block.
- Invalid input: unknown blocks, duplicate value IDs, missing predecessors, and malformed Phi arity must be rejected by the verifier.

### Task 1: Freeze the P2 representation and verifier boundary

**Files:**
- Create: `src/cmd/compile/internal/ssa/program.s`
- Create: `src/cmd/compile/internal/ssa/verify.s`
- Test: `test/ssa/p2_representation_test.s`

**Interfaces:**
- Consumes: `compile.internal.mir.mir_program`, `mir_program_function`, `mir_program_block`, and `mir_program_instruction`.
- Produces: `ssa_program`, `ssa_function`, `ssa_block`, `ssa_value`, `ssa_phi`, `ssa_call`, and `verify_ssa_program(program) string`.

- [ ] **Step 1: Write failing structural tests**

  Construct a two-function P1 program and assert that the expected SSA records, function symbols, parameter types, call target, and block IDs exist. Add invalid cases for duplicate value IDs and an operand defined in a later block.

- [ ] **Step 2: Run the fixture and verify the expected missing-interface failure**

  Run the fixture through the isolated Seed executor. Expected: failure because the P2 SSA types or verifier do not yet exist.

- [ ] **Step 3: Implement the representation and verifier**

  Use explicit arrays and IDs. The verifier must validate unique function/block/value IDs, valid operand references, predecessor/successor symmetry, Phi incoming arity, call targets, and block-local dominance for the supported subset.

- [ ] **Step 4: Run the structural tests**

  Expected: representation and invalid-input assertions pass; no native code generation is involved.

### Task 2: Implement straight-line MIR-to-SSA lowering

**Files:**
- Create: `src/cmd/compile/internal/ssa/lower.s`
- Modify: `src/cmd/compile/internal/ssa/program.s`
- Test: `test/ssa/p2_lower_linear_test.s`

**Interfaces:**
- Consumes: `mir_program`, `ssa_program`, and Task 1 verifier.
- Produces: `lower_function_to_ssa(mir_program_function) ssa_function_result` and `lower_program_to_ssa(mir_program) ssa_program_result`.

- [ ] **Step 1: Add the failing add/call fixture**

  Use `add(int,int)` and `main()` calling `add(3,4)`. Assert both functions survive, the call target is `sample.add`, operands and result IDs are present, and no result is computed as a constant by the lowerer.

- [ ] **Step 2: Verify RED**

  Run the fixture and record the first missing lowering symbol or empty-result failure.

- [ ] **Step 3: Implement linear lowering**

  Translate P1 `const_int`, `copy`, arithmetic, and `call` instructions into SSA values in source block order. Preserve function result types and call edges. Reject unsupported MIR operations with a diagnostic rather than silently dropping them.

- [ ] **Step 4: Run the linear lowering and P1 regressions**

  Expected: structural SSA assertions pass and the accepted P1 module behavior remains passing.

### Task 3: Add structured branch/merge lowering

**Files:**
- Modify: `src/cmd/compile/internal/ssa/lower.s`
- Modify: `src/cmd/compile/internal/ssa/program.s`
- Test: `test/ssa/p2_branch_merge_test.s`

**Interfaces:**
- Consumes: Task 2 lowering and Task 1 verifier.
- Produces: CFG blocks with explicit successors/predecessors and Phi or block-parameter joins.

- [ ] **Step 1: Add the failing choose fixture**

  Build a MIR fixture with `entry → then/else → merge`, where both predecessors provide a distinct integer value for the merged result. Assert the merge has exactly two incoming edges and one join value.

- [ ] **Step 2: Verify RED**

  Expected: current linear lowering rejects the terminators or fails to create the merge value.

- [ ] **Step 3: Implement CFG and join lowering**

  Preserve edge order, create explicit predecessor/successor lists, and emit a Phi/block parameter only when multiple predecessor definitions reach the merge. Do not evaluate the branch condition.

- [ ] **Step 4: Run branch/merge tests and the verifier**

  Expected: CFG, join arity, value types, and dominance checks pass.

### Task 4: Add calls, side effects, and verifier negative coverage

**Files:**
- Modify: `src/cmd/compile/internal/ssa/lower.s`
- Modify: `src/cmd/compile/internal/ssa/verify.s`
- Test: `test/ssa/p2_calls_and_invalid_test.s`

**Interfaces:**
- Consumes: Tasks 1–3 SSA model and lowering.
- Produces: verified call values, ordered side-effect markers, and stable diagnostics.

- [ ] **Step 1: Add failing call/order/invalid fixtures**

  Cover a forward call, two calls in one block, an unknown target, a mismatched call result type, malformed Phi arity, and a use that violates dominance.

- [ ] **Step 2: Verify RED**

  Expected: unsupported validation or missing call/order behavior is observed.

- [ ] **Step 3: Implement the bounded checks**

  Keep call instructions in source order, retain their result types, and reject each invalid case with a nonempty diagnostic. Memory operations should be represented as ordered side-effecting values; no Machine IR is introduced.

- [ ] **Step 4: Run all P2 tests and P1 regression**

  Expected: all P2 structural/negative tests and the P1 behavior test pass.

### Task 5: Record the P2 gate

**Files:**
- Create: `test/ssa/P2_VERIFICATION.txt`

- [ ] **Step 1: Record exact commands and outputs**

  Include the isolated Seed executor command, all P2 fixture results, P1 regression result, and any unsupported MIR subset explicitly marked `NOT_REACHED` or `NOT_SUPPORTED`.

- [ ] **Step 2: Confirm scope**

  Confirm `core/ssa_lower.s`, Machine IR, ABI, native codegen, Bootstrap, and Stage1 remain untouched.

P2 is accepted only when Tasks 1–5 pass together. Passing structural tests alone does not prove native code generation or self-hosting; those remain P3–P6 work.
