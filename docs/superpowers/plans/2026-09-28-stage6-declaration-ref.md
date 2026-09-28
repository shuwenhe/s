# Stage 6 DeclarationRef Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Stage 6 DeclarationRef gate and real compiler proof path so Stage 6 can close only from observable canonical declaration identity evidence.

**Architecture:** Mirror the proven Stage 5 pattern: a shell gate attributes the first unmet `S6.x` contract from machine-checkable compiler proof output, while `bin/s_compiler declaration-ref-proof` is the only real producer of Stage 6 evidence. Closure happens one contract at a time: first RED attribution, then minimal producer evidence, then gate GREEN for that contract, then repeat until Stage 6 is CLOSED and the pipeline frontier advances to Stage 7.

**Tech Stack:** POSIX shell gate scripts, project `makefile`, S compiler source in `src/cmd/compile/compiler.s`, existing `bin/s_compiler` build flow.

**Spec:** `doc/stage6-declaration-ref-contract.md`

## Global Constraints

- Do not modify `doc/stage6-declaration-ref-contract.md` to match existing implementation.
- Stage 5 owns `name -> declaration candidate`.
- Stage 6 owns `declaration candidate -> canonical declaration identity`.
- Stage 7 owns `declaration/expression -> type reasoning`.
- Stage 6 proof must come from real compiler execution, not grep, hardcoded PASS lines, or test-only producer simulation.
- Stage 6 must not prove type checking, `CanonicalTypeRef`, MIR, layout, ABI, codegen, or any Stage 7+ authority.
- Existing `declaration_ref` code is an implementation candidate, not proof, until the real producer emits observable contract evidence.

## Review Focus

- Gate false positives: tests must reject hardcoded `S6.x=PASS` without evidence and any placeholder/PENDING output.
- Mock producer leakage: mock proof is allowed only for gate self-tests and must be explicitly labeled mock, never counted as real compiler proof.
- Stage boundary leakage: proof output must reject `Type Checking`, `CanonicalTypeRef`, `MIR`, layout, ABI, and codegen claims.
- Re-resolution regressions: Stage 6 proof must assert candidate input and no name lookup from raw textual identifiers.
- Pipeline attribution: `make compile-pipeline-check` must report Stage 6 as the first unproven stage until Stage 6 proof is real, then advance to Stage 7.

---

### Task 1: Stage 6 Gate Skeleton And RED Attribution

**Files:**
- Create: `scripts/canonical-declaration-ref-check.sh`
- Create: `misc/scripts/test-canonical-declaration-ref-check.sh`
- Modify: `makefile`

**Interfaces:**
- Consumes: compiler path `${SOURCE_ROOT}/bin/s_compiler`
- Produces: report `.bootstrap/stage6/declaration-ref-gate.txt`
- Produces: make target `canonical-declaration-ref-check`

- [ ] **Step 1: Write the failing gate self-test**

Create `misc/scripts/test-canonical-declaration-ref-check.sh` with cases matching Stage 5 gate style:

```sh
# no real proof command exposed
S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/no-proof.out" 2>&1 || status=$?
test "$status" -eq 1
grep -qx 'result=FAIL' "$report"
grep -qx 'first-unmet-contract=S6.1' "$report"
grep -qx 'stage6-declaration-ref=NOT_CLOSED' "$report"
grep -q 'reason=.*observable Stage 6 proof' "$report"

# mock RED attribution
S_STAGE6_ALLOW_MOCK_PROOF=1 S_STAGE6_PROOF_REPORT="$tmp/mock-red.txt" \
  S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/mock-red.out" 2>&1 || status=$?
test "$status" -eq 4
grep -qx 'S6.4 Stable Identity=FAIL' "$report"
grep -qx 'first-unmet-contract=S6.4' "$report"

# mock GREEN requires evidence for every S6.x
S_STAGE6_ALLOW_MOCK_PROOF=1 S_STAGE6_PROOF_REPORT="$tmp/mock-green.txt" \
  S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/mock-green.out" 2>&1
grep -qx 'stage6-declaration-ref=CLOSED' "$report"
grep -qx 'result=PASS' "$report"

# placeholder and forbidden later-stage claims are not proof
if grep -Eq 'PENDING|PENDING_IMPLEMENTATION|PLACEHOLDER|TODO' "$report" "$tmp/no-proof.out"; then exit 1; fi
```

- [ ] **Step 2: Run the self-test and verify RED**

Run: `sh misc/scripts/test-canonical-declaration-ref-check.sh`

Expected: FAIL because `scripts/canonical-declaration-ref-check.sh` does not exist.

- [ ] **Step 3: Implement `scripts/canonical-declaration-ref-check.sh`**

Use `scripts/canonical-name-resolution-check.sh` as the template. Required differences:

- contracts: `S6.1` through `S6.8`
- titles: `Input Boundary`, `Canonical Producer`, `Identity Authority`, `Stable Identity`, `Uniqueness`, `Equality Semantics`, `No Re-Resolution`, `Output Boundary`
- report path: `.bootstrap/stage6/declaration-ref-gate.txt`
- proof command: `declaration-ref-proof`
- real proof source label: `compiler-declaration-ref-proof`
- closed key: `stage6-declaration-ref=CLOSED`
- not closed key: `stage6-declaration-ref=NOT_CLOSED`
- forbidden output markers: placeholder terms and later-stage claims from Review Focus

- [ ] **Step 4: Add make target**

Modify `makefile` to add:

```make
.PHONY: canonical-declaration-ref-check
canonical-declaration-ref-check: compiler
	@chmod +x scripts/canonical-declaration-ref-check.sh
	@S_SOURCE_ROOT=$(CURDIR) scripts/canonical-declaration-ref-check.sh "$(CURDIR)"
```

Do not wire any Stage 6 PASS behavior in the make target.

- [ ] **Step 5: Run the gate self-test and verify GREEN**

Run: `sh misc/scripts/test-canonical-declaration-ref-check.sh`

Expected: PASS with `canonical declaration ref gate self-test passed`.

- [ ] **Step 6: Run the real gate and verify first RED**

Run: `make canonical-declaration-ref-check`

Expected: FAIL with:

```text
first-unmet-contract=S6.1
stage6-declaration-ref=NOT_CLOSED
result=FAIL
```

- [ ] **Step 7: Run pipeline attribution**

Run: `make compile-pipeline-check`

Expected: exit 6, Stage 5 `PASS PROVEN`, Stage 6 `FAIL FAILED` or `SKIP UNPROVEN` depending on the gate state, and current blocker remains Stage 6 DeclarationRef.

### Task 2: Real Proof Producer Command With S6.1 RED Boundary

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `test/compiler/stage6_declaration_ref_basic.s`
- Create: `misc/scripts/test-stage6-input-boundary-proof.sh`

**Interfaces:**
- Consumes: `bin/s_compiler declaration-ref-proof input.s report.txt`
- Produces: proof lines beginning with `S6.1`

- [ ] **Step 1: Write the failing producer self-test**

Create `misc/scripts/test-stage6-input-boundary-proof.sh`:

```sh
make -C "$root" compiler >/dev/null
"$root/bin/s_compiler" declaration-ref-proof "$root/test/compiler/stage6_declaration_ref_basic.s" "$report"
grep -qx 'S6.1=PASS' "$report"
grep -qx 'S6.1.input-kind=resolved-declaration-candidate' "$report"
grep -qx 'S6.1.no-raw-name-input=yes' "$report"
grep -q '^S6.1.evidence=canonical Stage 6 consumed Stage 5 resolved declaration candidate ' "$report"
if grep -Eq 'Type Checking|CanonicalTypeRef|MIR|layout|ABI|codegen' "$report"; then exit 1; fi
```

- [ ] **Step 2: Run the producer self-test and verify RED**

Run: `sh misc/scripts/test-stage6-input-boundary-proof.sh`

Expected: FAIL because `declaration-ref-proof` is not exposed by `bin/s_compiler`.

- [ ] **Step 3: Add `declaration-ref-proof` command dispatch**

Modify `src/cmd/compile/compiler.s` `main()` command allowlist and dispatch to accept:

```text
declaration-ref-proof input.s output
```

Implement `compiler_emit_stage6_declaration_ref_proof(source string) string` as a real compiler proof command. The initial version may emit only `S6.1` evidence and explicit `S6.2.reason=...` RED attribution if later contracts are not proven.

- [ ] **Step 4: Implement S6.1 producer evidence**

Use the same canonical parse/result path that feeds Stage 5 proof. Emit `S6.1=PASS` only when Stage 5 has produced a resolved declaration candidate equivalent to S5.9 output. Required lines:

```text
S6.1=PASS
S6.1.input-kind=resolved-declaration-candidate
S6.1.candidate-package=<package>
S6.1.candidate-name=<name>
S6.1.candidate-kind=<kind>
S6.1.no-raw-name-input=yes
S6.1.evidence=canonical Stage 6 consumed Stage 5 resolved declaration candidate <package>.<name>
```

Do not emit `S6.2=PASS` in this task.

- [ ] **Step 5: Run the producer self-test and verify GREEN**

Run: `sh misc/scripts/test-stage6-input-boundary-proof.sh`

Expected: PASS.

- [ ] **Step 6: Run the real Stage 6 gate**

Run: `make canonical-declaration-ref-check`

Expected: FAIL with `S6.1 Input Boundary=PASS`, `first-unmet-contract=S6.2`, and `stage6-declaration-ref=NOT_CLOSED`.

### Task 3: Canonical Producer Authority S6.2

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `misc/scripts/test-stage6-canonical-producer-proof.sh`

**Interfaces:**
- Consumes: S6.1 candidate evidence from `compiler_emit_stage6_declaration_ref_proof`
- Produces: `S6.2` proof lines

- [ ] **Step 1: Write the failing S6.2 self-test**

Assert:

```text
S6.2=PASS
S6.2.producer=canonical-declaration-ref-producer
S6.2.alternate-producers-accepted=no
S6.2.evidence=canonical Stage 6 DeclarationRef identity established by canonical-declaration-ref-producer
```

Also assert the report does not contain `grep`, `source-scan`, or `test-only-producer`.

- [ ] **Step 2: Run the test and verify RED**

Run: `sh misc/scripts/test-stage6-canonical-producer-proof.sh`

Expected: FAIL because S6.2 is not emitted.

- [ ] **Step 3: Add a canonical Stage 6 producer function**

In `src/cmd/compile/compiler.s`, introduce one helper with an explicit name such as:

```text
compiler_stage6_make_declaration_ref_candidate(...)
```

This helper is the only proof path allowed to emit S6.2 authority. Keep it representation-agnostic at the contract level; implementation may reuse existing `declaration_ref` shape if sufficient.

- [ ] **Step 4: Emit S6.2 evidence only from the helper path**

Emit the required S6.2 lines after the candidate flows through the helper.

- [ ] **Step 5: Verify S6.2 GREEN and next RED**

Run:

```sh
sh misc/scripts/test-stage6-canonical-producer-proof.sh
make canonical-declaration-ref-check
```

Expected: self-test PASS; gate first unmet becomes `S6.3`.

### Task 4: Identity Authority S6.3

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `misc/scripts/test-stage6-identity-authority-proof.sh`

**Interfaces:**
- Consumes: canonical producer helper from Task 3
- Produces: representation-agnostic identity evidence

- [ ] **Step 1: Write the failing S6.3 self-test**

Assert:

```text
S6.3=PASS
S6.3.identity-authority=canonical
S6.3.independent-of-display-text=yes
S6.3.representation-prescribed=no
S6.3.evidence=canonical Stage 6 DeclarationRef carries identity independent of display text
```

- [ ] **Step 2: Run the test and verify RED**

Run: `sh misc/scripts/test-stage6-identity-authority-proof.sh`

Expected: FAIL because S6.3 is not emitted.

- [ ] **Step 3: Add identity authority observation**

Extend the producer to compute or observe a canonical identity token internally. The gate must not require a particular field layout; proof output should describe semantic identity authority, not mandate `path`, `source handle`, or `numeric id`.

- [ ] **Step 4: Verify S6.3 GREEN and next RED**

Run:

```sh
sh misc/scripts/test-stage6-identity-authority-proof.sh
make canonical-declaration-ref-check
```

Expected: self-test PASS; gate first unmet becomes `S6.4`.

### Task 5: Stable Identity S6.4

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `misc/scripts/test-stage6-stable-identity-proof.sh`

**Interfaces:**
- Consumes: canonical producer helper
- Produces: repeated-construction equality evidence

- [ ] **Step 1: Write the failing S6.4 self-test**

Assert:

```text
S6.4=PASS
S6.4.same-candidate-equal=yes
S6.4.observation-count=2
S6.4.not-address-identity=yes
S6.4.evidence=canonical Stage 6 repeated construction from the same candidate yields the same DeclarationRef identity
```

- [ ] **Step 2: Run the test and verify RED**

Run: `sh misc/scripts/test-stage6-stable-identity-proof.sh`

Expected: FAIL because S6.4 is not emitted.

- [ ] **Step 3: Construct identity twice from one candidate**

In the proof producer, pass the same Stage 5 candidate through the canonical producer twice and compare using the Stage 6 equality function or helper. Do not use pointer/address equality.

- [ ] **Step 4: Verify S6.4 GREEN and next RED**

Run:

```sh
sh misc/scripts/test-stage6-stable-identity-proof.sh
make canonical-declaration-ref-check
```

Expected: self-test PASS; gate first unmet becomes `S6.5`.

### Task 6: Uniqueness S6.5

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `test/compiler/stage6_declaration_ref_uniqueness_a.s`
- Create: `test/compiler/stage6_declaration_ref_uniqueness_b.s`
- Create: `misc/scripts/test-stage6-uniqueness-proof.sh`

**Interfaces:**
- Consumes: canonical producer helper and equality helper
- Produces: distinct declaration identity evidence

- [ ] **Step 1: Write the failing S6.5 self-test**

Assert at least:

```text
S6.5=PASS
S6.5.same-spelling-different-package-distinct=yes
S6.5.same-domain-distinct-declarations-distinct=yes
S6.5.kind-collision-distinguished=yes
S6.5.evidence=canonical Stage 6 distinct declarations produce distinct DeclarationRef identities
```

- [ ] **Step 2: Run the test and verify RED**

Run: `sh misc/scripts/test-stage6-uniqueness-proof.sh`

Expected: FAIL because S6.5 is not emitted.

- [ ] **Step 3: Add uniqueness fixtures**

Create small S sources that exercise same spelling across different packages/modules and distinct declarations in the same authority domain. Keep fixtures free of type checking, `CanonicalTypeRef`, MIR, layout, ABI, and codegen requirements.

- [ ] **Step 4: Emit S6.5 uniqueness evidence**

In the proof producer, create DeclarationRefs for the distinct candidates and assert canonical identity inequality.

- [ ] **Step 5: Verify S6.5 GREEN and next RED**

Run:

```sh
sh misc/scripts/test-stage6-uniqueness-proof.sh
make canonical-declaration-ref-check
```

Expected: self-test PASS; gate first unmet becomes `S6.6`.

### Task 7: Equality Semantics S6.6

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `misc/scripts/test-stage6-equality-semantics-proof.sh`

**Interfaces:**
- Consumes: equality helper used by the proof producer
- Produces: canonical-identity equality evidence

- [ ] **Step 1: Write the failing S6.6 self-test**

Assert:

```text
S6.6=PASS
S6.6.equal-canonical-identities-equal=yes
S6.6.distinct-canonical-identities-unequal=yes
S6.6.not-display-name-equality=yes
S6.6.not-address-equality=yes
S6.6.evidence=canonical Stage 6 DeclarationRef equality is based on canonical declaration identity
```

- [ ] **Step 2: Run the test and verify RED**

Run: `sh misc/scripts/test-stage6-equality-semantics-proof.sh`

Expected: FAIL because S6.6 is not emitted.

- [ ] **Step 3: Route proof comparisons through canonical equality**

Ensure all producer comparisons for same and distinct identities use the canonical equality helper, not display strings or object addresses.

- [ ] **Step 4: Verify S6.6 GREEN and next RED**

Run:

```sh
sh misc/scripts/test-stage6-equality-semantics-proof.sh
make canonical-declaration-ref-check
```

Expected: self-test PASS; gate first unmet becomes `S6.7`.

### Task 8: No Re-Resolution S6.7

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `misc/scripts/test-stage6-no-reresolution-proof.sh`

**Interfaces:**
- Consumes: Stage 5 candidate and canonical producer helper
- Produces: no re-resolution evidence

- [ ] **Step 1: Write the failing S6.7 self-test**

Assert:

```text
S6.7=PASS
S6.7.from-resolved-candidate=yes
S6.7.lookup-from-text=no
S6.7.accepts-unresolved-name=no
S6.7.evidence=canonical Stage 6 constructs DeclarationRef from resolved candidate without textual name re-resolution
```

Reject reports containing:

```text
lookup-source=canonical-compiler-find-func
qualified-lookup
unqualified-lookup
```

within S6.7 evidence.

- [ ] **Step 2: Run the test and verify RED**

Run: `sh misc/scripts/test-stage6-no-reresolution-proof.sh`

Expected: FAIL because S6.7 is not emitted.

- [ ] **Step 3: Add no-re-resolution instrumentation**

In the proof producer, make the candidate-to-DeclarationRef path explicitly record that it consumed the candidate already selected by Stage 5 and did not call textual lookup helpers during Stage 6 construction.

- [ ] **Step 4: Verify S6.7 GREEN and next RED**

Run:

```sh
sh misc/scripts/test-stage6-no-reresolution-proof.sh
make canonical-declaration-ref-check
```

Expected: self-test PASS; gate first unmet becomes `S6.8`.

### Task 9: Output Boundary S6.8 And Stage 6 Closure

**Files:**
- Modify: `src/cmd/compile/compiler.s`
- Create: `misc/scripts/test-stage6-output-boundary-proof.sh`

**Interfaces:**
- Consumes: full S6.1-S6.7 proof output
- Produces: Stage 6 closed proof and Stage 7 consumable boundary evidence

- [ ] **Step 1: Write the failing S6.8 self-test**

Assert:

```text
S6.8=PASS
S6.8.output-kind=canonical-declaration-ref
S6.8.next-stage-input=declaration-ref
S6.8.stage7-consumable=yes
S6.8.no-type-checking=yes
S6.8.no-canonical-type-ref=yes
S6.8.no-mir=yes
S6.8.evidence=canonical Stage 6 output boundary exposes DeclarationRef identity consumable by Stage 7
```

Reject `Type Checking`, `CanonicalTypeRef`, `MIR`, `layout`, `ABI`, and `codegen` in the proof report.

- [ ] **Step 2: Run the test and verify RED**

Run: `sh misc/scripts/test-stage6-output-boundary-proof.sh`

Expected: FAIL because S6.8 is not emitted.

- [ ] **Step 3: Emit S6.8 boundary evidence**

Add only Stage 6 output boundary proof. Do not add Stage 7 behavior or type reasoning.

- [ ] **Step 4: Verify S6.8 GREEN**

Run: `sh misc/scripts/test-stage6-output-boundary-proof.sh`

Expected: PASS.

- [ ] **Step 5: Verify full Stage 6 closure gate**

Run: `make canonical-declaration-ref-check`

Expected:

```text
S6.1 Input Boundary=PASS
S6.2 Canonical Producer=PASS
S6.3 Identity Authority=PASS
S6.4 Stable Identity=PASS
S6.5 Uniqueness=PASS
S6.6 Equality Semantics=PASS
S6.7 No Re-Resolution=PASS
S6.8 Output Boundary=PASS
first-unmet-contract=NONE
stage6-declaration-ref=CLOSED
result=PASS
```

- [ ] **Step 6: Verify pipeline frontier advances**

Run: `make compile-pipeline-check`

Expected: Stage 5 and Stage 6 `PASS PROVEN`; first unproven required stage becomes Stage 7 Type Checking.
