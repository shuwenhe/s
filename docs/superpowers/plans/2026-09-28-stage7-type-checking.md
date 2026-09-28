# Stage 7 Type Checking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Stage 7 Type Checking gate and real compiler proof path so Stage 7 can close only from observable type-checking evidence that consumes Stage 6 `DeclarationRef` output.

**Architecture:** Copy the Stage 6 closure pattern: a shell gate attributes the first unmet `S7.x` contract from machine-checkable compiler proof output, while `bin/s_compiler type-checking-proof` is the only real producer of Stage 7 evidence. Closure happens one contract at a time: first RED attribution, then minimal real producer evidence, then gate GREEN for that contract, then repeat until Stage 7 is CLOSED and the pipeline frontier advances to Stage 8.

**Tech Stack:** POSIX shell gate scripts, project `makefile`, S compiler source in `src/cmd/compile/compiler.s`, existing `bin/s_compiler` build flow.

**Spec:** `doc/stage7-type-checking-contract.md`

## Global Constraints

- Do not modify `doc/stage7-type-checking-contract.md` to match existing implementation.
- Stage 5 owns `name -> declaration candidate`.
- Stage 6 owns `declaration candidate -> canonical declaration identity`.
- Stage 7 owns `DeclarationRef + expressions -> type reasoning`.
- Stage 8 owns `type -> canonical type identity`.
- Stage 7 proof must come from real compiler execution, not grep, hardcoded PASS lines, or test-only producer simulation.
- Stage 7 must consume Stage 6 `DeclarationRef` evidence and must not re-run name lookup or reconstruct declaration identity.
- Stage 7 must not prove `CanonicalTypeRef`, MIR, layout, ABI, codegen, or any Stage 8+ authority.
- Existing semantic/type-checking code is an implementation candidate, not proof, until the real producer emits observable contract evidence.

## Review Focus

- Gate false positives: tests must reject hardcoded `S7.x=PASS` without evidence and any placeholder/PENDING output.
- Mock producer leakage: mock proof is allowed only for gate self-tests and must be explicitly labeled mock, never counted as real compiler proof.
- Stage boundary leakage: proof output must reject `CanonicalTypeRef`, MIR, layout, ABI, codegen, and other Stage 8+ claims.
- Ownership regressions: Stage 7 proof must assert it consumed Stage 6 `DeclarationRef` output and did not reconstruct identity from strings.
- Negative cases: Stage 7 closure requires at least one real type error rejection after Stage 5 and Stage 6 have succeeded.
- Pipeline attribution: `make compile-pipeline-check` must report Stage 7 as first unproven until Stage 7 proof is real, then advance to Stage 8.

---

### Task 1: Stage 7 Gate Skeleton And RED Attribution

**Files:**
- Create: `scripts/canonical-type-checking-check.sh`
- Create: `misc/scripts/test-canonical-type-checking-check.sh`
- Modify: `makefile`

**Interfaces:**
- Consumes: compiler path `${SOURCE_ROOT}/bin/s_compiler`
- Produces: report `.bootstrap/stage7/type-checking-gate.txt`
- Produces: make target `canonical-type-checking-check`

- [ ] **Step 1: Write the failing gate self-test**

Create `misc/scripts/test-canonical-type-checking-check.sh` with cases for no proof command, mock RED attribution, mock GREEN requiring evidence for every S7.x, placeholder rejection, and Stage 8+ boundary leakage rejection.

Required mock RED assertion:

```text
first-unmet-contract=S7.1
stage7-type-checking=NOT_CLOSED
result=FAIL
```

Required mock GREEN assertion:

```text
first-unmet-contract=NONE
stage7-type-checking=CLOSED
result=PASS
```

- [ ] **Step 2: Run the self-test and verify RED**

Run: `sh misc/scripts/test-canonical-type-checking-check.sh`

Expected: FAIL because `scripts/canonical-type-checking-check.sh` does not exist.

- [ ] **Step 3: Implement `scripts/canonical-type-checking-check.sh`**

Use `scripts/canonical-declaration-ref-check.sh` as the template. Required differences:

- contracts: `S7.1` through `S7.8`
- titles: `Input Boundary`, `Type Environment Authority`, `Declaration Type Facts`, `Expression Type Facts`, `Compatibility Semantics`, `Type Error Rejection`, `No Re-Resolution Or Identity Reconstruction`, `Output Boundary`
- report path: `.bootstrap/stage7/type-checking-gate.txt`
- proof command: `type-checking-proof`
- real proof source label: `compiler-type-checking-proof`
- closed key: `stage7-type-checking=CLOSED`
- not closed key: `stage7-type-checking=NOT_CLOSED`
- forbidden output markers: placeholder terms and Stage 8+ claims from Review Focus

- [ ] **Step 4: Add make target**

Modify `makefile` to add:

```make
.PHONY: canonical-type-checking-check
canonical-type-checking-check: compiler
	@chmod +x scripts/canonical-type-checking-check.sh
	@S_SOURCE_ROOT=$(CURDIR) scripts/canonical-type-checking-check.sh "$(CURDIR)"
```

Do not wire any Stage 7 PASS behavior in the make target.

- [ ] **Step 5: Run the gate self-test and verify GREEN**

Run: `sh misc/scripts/test-canonical-type-checking-check.sh`

Expected: PASS with `canonical type checking gate self-test passed`.

- [ ] **Step 6: Run the real gate and verify first RED**

Run: `make canonical-type-checking-check`

Expected: FAIL with:

```text
first-unmet-contract=S7.1
stage7-type-checking=NOT_CLOSED
result=FAIL
```

- [ ] **Step 7: Run pipeline attribution**

Run: `make compile-pipeline-check`

Expected: exit 7, Stage 6 `PASS PROVEN`, Stage 7 `FAIL FAILED` or `SKIP UNPROVEN` depending on the gate state, and current blocker remains Stage 7 Type Checking.

### Task 2: Real Proof Producer Command With S7.1 Input Boundary

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `test/compiler/stage7_type_checking_basic.s`
- Create: `misc/scripts/test-stage7-input-boundary-proof.sh`

**Interfaces:**
- Consumes: Stage 6 `DeclarationRef` evidence from the compiler proof path
- Produces: `bin/s_compiler type-checking-proof input.s report.txt`
- Produces: proof lines beginning with `S7.1`

- [ ] **Step 1: Write the failing producer self-test**

Create `misc/scripts/test-stage7-input-boundary-proof.sh` to run `type-checking-proof` on `test/compiler/stage7_type_checking_basic.s` and assert:

```text
S7.1=PASS
S7.1.input-stage=stage6
S7.1.input-kind=declaration-ref-plus-expressions
S7.1.declaration-ref-consumed=yes
S7.1.no-raw-name-input=yes
S7.1.evidence=canonical Stage 7 consumed Stage 6 DeclarationRef output with expression input
```

Reject `CanonicalTypeRef`, MIR, layout, ABI, codegen, and `S7.2=PASS`.

- [ ] **Step 2: Run the producer self-test and verify RED**

Run: `sh misc/scripts/test-stage7-input-boundary-proof.sh`

Expected: FAIL because `type-checking-proof` is not exposed by `bin/s_compiler`.

- [ ] **Step 3: Add `type-checking-proof` command dispatch**

Modify `src/cmd/compile/compiler.s` `main()` command allowlist and dispatch to accept:

```text
type-checking-proof input.s output
```

Implement `compiler_emit_stage7_type_checking_proof(source string) string` as a real compiler proof command. The initial version may emit only `S7.1` evidence and explicit `S7.2.reason=...` RED attribution if later contracts are not proven.

- [ ] **Step 4: Implement S7.1 producer evidence**

Use the real compiler path that already proves Stage 5 and Stage 6. Emit `S7.1=PASS` only when Stage 7 receives Stage 6 `DeclarationRef` evidence plus expression/declaration input from the compiled source.

Do not emit `S7.2=PASS` in this task.

- [ ] **Step 5: Run the producer self-test and verify GREEN**

Run: `sh misc/scripts/test-stage7-input-boundary-proof.sh`

Expected: PASS.

- [ ] **Step 6: Run the real Stage 7 gate**

Run: `make canonical-type-checking-check`

Expected: FAIL with `S7.1 Input Boundary=PASS`, `first-unmet-contract=S7.2`, and `stage7-type-checking=NOT_CLOSED`.

### Task 3: Type Environment Authority S7.2

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `misc/scripts/test-stage7-type-environment-authority-proof.sh`

**Interfaces:**
- Consumes: S7.1 proof path from `compiler_emit_stage7_type_checking_proof`
- Produces: `S7.2` proof lines

- [ ] **Step 1: Write the failing S7.2 self-test**

Assert:

```text
S7.2=PASS
S7.2.producer=canonical-type-checking-producer
S7.2.environment-binds-by-declaration-ref=yes
S7.2.alternate-type-environments-accepted=no
S7.2.evidence=canonical Stage 7 type environment established by canonical-type-checking-producer
```

Reject `S7.3=PASS` and Stage 8+ claims.

- [ ] **Step 2: Run the self-test and verify RED**

Run: `sh misc/scripts/test-stage7-type-environment-authority-proof.sh`

Expected: FAIL while S7.2 proof is absent.

- [ ] **Step 3: Implement minimal S7.2 producer evidence**

Route successful Stage 7 proof through one canonical type-checking producer. The producer must consume the Stage 6 `DeclarationRef` evidence and record that environment binding is keyed by `DeclarationRef`, not display text.

Do not emit `S7.3=PASS` in this task.

- [ ] **Step 4: Run the self-test and verify GREEN**

Run: `sh misc/scripts/test-stage7-type-environment-authority-proof.sh`

Expected: PASS.

- [ ] **Step 5: Run directed regressions**

Run S7.1 and S7.2 directed tests sequentially plus gate self-test.

Expected: all PASS.

- [ ] **Step 6: Run the real Stage 7 gate**

Run: `make canonical-type-checking-check`

Expected: FAIL with `S7.1 PASS`, `S7.2 PASS`, and `first-unmet-contract=S7.3`.

### Task 4: Declaration Type Facts S7.3

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `test/compiler/stage7_type_checking_declarations.s`
- Create: `misc/scripts/test-stage7-declaration-type-facts-proof.sh`

**Interfaces:**
- Consumes: S7.2 canonical type-checking producer
- Produces: `S7.3` proof lines

- [ ] **Step 1: Write the failing S7.3 self-test**

Use a fixture with at least one function declaration and one data or field-bearing declaration supported by the current compiler. Assert:

```text
S7.3=PASS
S7.3.function-declaration-type-fact=yes
S7.3.data-or-field-declaration-type-fact=yes
S7.3.keyed-by-declaration-ref=yes
S7.3.no-canonical-type-ref-required=yes
S7.3.evidence=canonical Stage 7 produced declaration type facts keyed by DeclarationRef
```

Reject `S7.4=PASS` and Stage 8+ claims.

- [ ] **Step 2: Run the self-test and verify RED**

Run: `sh misc/scripts/test-stage7-declaration-type-facts-proof.sh`

Expected: FAIL while S7.3 proof is absent.

- [ ] **Step 3: Implement minimal S7.3 producer evidence**

Add declaration type fact observation to the canonical Stage 7 producer. The evidence may use a representation-agnostic `TypeFact` role, but it must prove that declaration facts are keyed by the Stage 6 `DeclarationRef`.

Do not construct or claim `CanonicalTypeRef`.

- [ ] **Step 4: Run the self-test and verify GREEN**

Run: `sh misc/scripts/test-stage7-declaration-type-facts-proof.sh`

Expected: PASS.

- [ ] **Step 5: Run directed regressions**

Run S7.1-S7.3 directed tests sequentially plus gate self-test.

Expected: all PASS.

- [ ] **Step 6: Run the real Stage 7 gate**

Run: `make canonical-type-checking-check`

Expected: FAIL with `S7.1-S7.3 PASS` and `first-unmet-contract=S7.4`.

### Task 5: Expression Type Facts S7.4

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `test/compiler/stage7_type_checking_expressions.s`
- Create: `misc/scripts/test-stage7-expression-type-facts-proof.sh`

**Interfaces:**
- Consumes: S7.3 declaration type facts
- Produces: `S7.4` proof lines

- [ ] **Step 1: Write the failing S7.4 self-test**

Use a fixture that exercises supported literal, reference, call, and operator expression forms. Assert:

```text
S7.4=PASS
S7.4.literal-expression-type-fact=yes
S7.4.reference-expression-type-fact=yes
S7.4.call-expression-type-fact=yes
S7.4.operator-expression-type-fact=yes
S7.4.distinct-from-canonical-type-identity=yes
S7.4.evidence=canonical Stage 7 produced expression type facts without canonical type identity
```

If the current compiler does not support one expression class, the test must record `unsupported-by-language-surface=<class>` and still require all supported classes named by the fixture. Reject `S7.5=PASS` and Stage 8+ claims.

- [ ] **Step 2: Run the self-test and verify RED**

Run: `sh misc/scripts/test-stage7-expression-type-facts-proof.sh`

Expected: FAIL while S7.4 proof is absent.

- [ ] **Step 3: Implement minimal S7.4 producer evidence**

Add expression type fact observation to the canonical Stage 7 producer. Derive reference/call expression facts through Stage 6 `DeclarationRef` inputs where declarations are referenced.

Do not emit compatibility verdict closure in this task.

- [ ] **Step 4: Run the self-test and verify GREEN**

Run: `sh misc/scripts/test-stage7-expression-type-facts-proof.sh`

Expected: PASS.

- [ ] **Step 5: Run directed regressions**

Run S7.1-S7.4 directed tests sequentially plus gate self-test.

Expected: all PASS.

- [ ] **Step 6: Run the real Stage 7 gate**

Run: `make canonical-type-checking-check`

Expected: FAIL with `S7.1-S7.4 PASS` and `first-unmet-contract=S7.5`.

### Task 6: Compatibility Semantics S7.5

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `test/compiler/stage7_type_checking_compatibility.s`
- Create: `misc/scripts/test-stage7-compatibility-semantics-proof.sh`

**Interfaces:**
- Consumes: S7.4 expression type facts
- Produces: `S7.5` proof lines

- [ ] **Step 1: Write the failing S7.5 self-test**

Use a fixture with compatible assignment or initialization, compatible return, and compatible call arguments or operator operands where supported. Assert:

```text
S7.5=PASS
S7.5.assignment-compatible=yes
S7.5.return-compatible=yes
S7.5.call-or-operator-compatible=yes
S7.5.not-display-type-string-equality=yes
S7.5.evidence=canonical Stage 7 compatibility is based on type facts
```

Reject `S7.6=PASS` and Stage 8+ claims.

- [ ] **Step 2: Run the self-test and verify RED**

Run: `sh misc/scripts/test-stage7-compatibility-semantics-proof.sh`

Expected: FAIL while S7.5 proof is absent.

- [ ] **Step 3: Implement minimal S7.5 producer evidence**

Add compatibility verdict observation to the canonical Stage 7 producer. Compatibility must be derived from Stage 7 type facts, not display string equality of type names.

Do not emit type error rejection closure in this task.

- [ ] **Step 4: Run the self-test and verify GREEN**

Run: `sh misc/scripts/test-stage7-compatibility-semantics-proof.sh`

Expected: PASS.

- [ ] **Step 5: Run directed regressions**

Run S7.1-S7.5 directed tests sequentially plus gate self-test.

Expected: all PASS.

- [ ] **Step 6: Run the real Stage 7 gate**

Run: `make canonical-type-checking-check`

Expected: FAIL with `S7.1-S7.5 PASS` and `first-unmet-contract=S7.6`.

### Task 7: Type Error Rejection S7.6

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `test/compiler/stage7_type_checking_type_error.s`
- Create: `misc/scripts/test-stage7-type-error-rejection-proof.sh`

**Interfaces:**
- Consumes: S7.5 compatibility semantics
- Produces: `S7.6` proof lines

- [ ] **Step 1: Write the failing S7.6 self-test**

Use a fixture where names resolve and `DeclarationRef` construction succeeds, but a type compatibility error must be rejected. Assert:

```text
S7.6=PASS
S7.6.type-error-rejected=yes
S7.6.stage5-succeeded-before-rejection=yes
S7.6.stage6-succeeded-before-rejection=yes
S7.6.rejection-attributed-to-stage7=yes
S7.6.evidence=canonical Stage 7 rejects incompatible type facts after name and declaration identity are proven
```

Reject `S7.7=PASS` and Stage 8+ claims.

- [ ] **Step 2: Run the self-test and verify RED**

Run: `sh misc/scripts/test-stage7-type-error-rejection-proof.sh`

Expected: FAIL while S7.6 proof is absent.

- [ ] **Step 3: Implement minimal S7.6 producer evidence**

Add negative type-checking evidence to the canonical Stage 7 producer. Ensure the proof observes Stage 5 and Stage 6 success before attributing rejection to Stage 7.

Do not turn parser/name-resolution failures into type-checking proof.

- [ ] **Step 4: Run the self-test and verify GREEN**

Run: `sh misc/scripts/test-stage7-type-error-rejection-proof.sh`

Expected: PASS.

- [ ] **Step 5: Run directed regressions**

Run S7.1-S7.6 directed tests sequentially plus gate self-test.

Expected: all PASS.

- [ ] **Step 6: Run the real Stage 7 gate**

Run: `make canonical-type-checking-check`

Expected: FAIL with `S7.1-S7.6 PASS` and `first-unmet-contract=S7.7`.

### Task 8: No Re-Resolution Or Identity Reconstruction S7.7

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `misc/scripts/test-stage7-no-reresolution-proof.sh`

**Interfaces:**
- Consumes: S7.6 proof path
- Produces: `S7.7` proof lines

- [ ] **Step 1: Write the failing S7.7 self-test**

Assert dynamic evidence that Stage 7 used Stage 6 `DeclarationRef` directly:

```text
S7.7=PASS
S7.7.declaration-ref-consumed-directly=yes
S7.7.lookup-from-text=no
S7.7.declaration-ref-reconstructed=no
S7.7.stage5-resolution-count-before-stage7=<N>
S7.7.stage5-resolution-count-after-stage7=<same N>
S7.7.stage6-identity-construction-count-before-stage7=<M>
S7.7.stage6-identity-construction-count-after-stage7=<same M>
S7.7.evidence=canonical Stage 7 type checking consumes DeclarationRef without re-resolution or identity reconstruction
```

Reject `S7.8=PASS` and Stage 8+ claims.

- [ ] **Step 2: Run the self-test and verify RED**

Run: `sh misc/scripts/test-stage7-no-reresolution-proof.sh`

Expected: FAIL while S7.7 proof is absent.

- [ ] **Step 3: Implement minimal S7.7 producer evidence**

Instrument the real proof path so Stage 5 resolution counts and Stage 6 identity construction counts are observed before and after Stage 7 type checking. Emit `S7.7=PASS` only when both counts remain unchanged and the consumed `DeclarationRef` matches Stage 6 output.

Do not pass S7.7 by source grep.

- [ ] **Step 4: Run the self-test and verify GREEN**

Run: `sh misc/scripts/test-stage7-no-reresolution-proof.sh`

Expected: PASS.

- [ ] **Step 5: Run directed regressions**

Run S7.1-S7.7 directed tests sequentially plus gate self-test.

Expected: all PASS.

- [ ] **Step 6: Run the real Stage 7 gate**

Run: `make canonical-type-checking-check`

Expected: FAIL with `S7.1-S7.7 PASS` and `first-unmet-contract=S7.8`.

### Task 9: Output Boundary S7.8 And Pipeline Attribution

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `misc/scripts/test-stage7-output-boundary-proof.sh`

**Interfaces:**
- Consumes: S7.7 proof path
- Produces: Stage 7 closed proof and Stage 8 consumable boundary evidence

- [ ] **Step 1: Write the failing S7.8 self-test**

Assert:

```text
S7.8=PASS
S7.8.type-facts-produced=yes
S7.8.declaration-facts-keyed-by-declaration-ref=yes
S7.8.expression-facts-observable=yes
S7.8.output-consumable-by-next-stage=yes
S7.8.canonical-type-ref-created=no
S7.8.mir-created=no
S7.8.lowering-performed=no
S7.8.evidence=canonical Stage 7 emits type facts at the type reasoning boundary
```

Reject `CanonicalTypeRef=PASS`, MIR, layout, ABI, codegen, and any `S8.` proof.

- [ ] **Step 2: Run the self-test and verify RED**

Run: `sh misc/scripts/test-stage7-output-boundary-proof.sh`

Expected: FAIL while S7.8 proof is absent.

- [ ] **Step 3: Implement minimal S7.8 producer evidence**

Add only Stage 7 output boundary proof. The output must expose type facts sufficient for Stage 8 to consume without re-running type checking or name resolution.

Do not create `CanonicalTypeRef` or emit Stage 8 proof.

- [ ] **Step 4: Run the self-test and verify GREEN**

Run: `sh misc/scripts/test-stage7-output-boundary-proof.sh`

Expected: PASS.

- [ ] **Step 5: Run full Stage 7 directed regressions**

Run S7.1-S7.8 directed tests sequentially plus gate self-test.

Expected: all PASS.

- [ ] **Step 6: Run the canonical Stage 7 gate**

Run: `make canonical-type-checking-check`

Expected: PASS with:

```text
S7.1 PASS
S7.2 PASS
S7.3 PASS
S7.4 PASS
S7.5 PASS
S7.6 PASS
S7.7 PASS
S7.8 PASS
first-unmet-contract=NONE
stage7-type-checking=CLOSED
result=PASS
```

- [ ] **Step 7: Run global pipeline attribution**

Run: `make compile-pipeline-check`

Expected: Stage 6 and Stage 7 `PASS PROVEN`; first unproven required stage becomes Stage 8 CanonicalTypeRef.

If the isolated worktree lacks baseline bootstrap artifacts and the pipeline stops before Stage 7, restore the prerequisite first and rerun. Do not claim global frontier movement from the local Stage 7 gate alone.
