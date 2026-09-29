# Stage 8 CanonicalTypeRef Closure Contract

## Core Definition

Stage 8 consumes Stage 7 type facts and establishes canonical type identity. It does not re-run type checking, repeat name resolution, reconstruct `DeclarationRef`, lower to MIR, compute layout, classify ABI, or generate code.

```text
Stage 7 Type Checking
   |
   |  stage7-type-facts
   |    -> DeclarationRef-keyed declaration type facts
   |    -> expression type facts
   |    -> compatibility result
   v
Stage 8 CanonicalTypeRef
   |
   |  type facts
   |    -> canonical type identity
   v
Stage 9 Semantic Analysis
```

The stage ownership invariant is:

```text
Stage 7 owns:
    DeclarationRef + expressions -> type facts

Stage 8 owns:
    type facts -> canonical type identity

Stage 9 owns:
    resolved + typed program assembly from canonical identities
```

This boundary prevents Stage 8 from redoing type checking and prevents later stages from inventing canonical type identity.

## Closure Criteria

Stage 8 is CLOSED iff all of the following are proven by the Stage 8 gate:

1. Input boundary is proven.
2. Canonical type identity producer authority is proven.
3. Type identity authority is proven.
4. Stable identity is proven.
5. Uniqueness / interning semantics are proven.
6. Equality semantics are proven.
7. No type-checking re-run or identity reconstruction is proven.
8. The Stage 8 -> Stage 9 output boundary is proven.
9. No Stage 9+ authority is required to establish items 1-8.

Each closure item must have observable execution evidence from the real compiler producer before the gate can report `PASS / PROVEN`. Existing implementation candidates do not count as proof until real execution produces contract-specific evidence.

## S8.1 Input Boundary

Stage 8 input must be Stage 7 `stage7-type-facts` or equivalent typed facts. It must not start from raw type spelling, source expressions, unresolved names, or ad hoc declaration identity.

Required proof:

- Stage 8 consumes declaration and expression type facts produced at the Stage 7 output boundary.
- Declaration-related inputs remain keyed by canonical `DeclarationRef` where declarations are involved.
- Missing or malformed typed facts fail deterministically.

Failure examples:

- Stage 8 accepts only a display string such as `int` or `Point`.
- Stage 8 re-runs type checking to rediscover expression types.
- Stage 8 accepts type material that is not tied to Stage 7 output evidence.

## S8.2 Canonical Type Identity Producer

`CanonicalTypeRef` must be established through one authoritative type identity producer.

Required proof:

- Successful canonical type identity creation flows through the canonical Stage 8 producer.
- Alternate local construction paths are not accepted as Stage 8 proof.
- The producer can be named in observable output so downstream gates can attribute type identity authority.

Failure examples:

- Multiple unrelated functions create independent identities for the same type.
- A downstream stage constructs canonical type identity directly from strings.
- The gate passes by observing a type token without executing the producer.

## S8.3 Type Identity Authority

`CanonicalTypeRef` carries sufficient canonical identity to uniquely identify a type independently of display text. The contract does not prescribe the physical representation.

Required proof:

- The identity distinguishes supported type forms without relying on display formatting.
- The identity remains meaningful if display text changes.
- The proof reports identity authority without requiring layout, ABI, MIR, or codegen.

Failure examples:

- `int` and an alias-like spelling are treated as identical only because display strings match.
- Pointer, reference, slice, or struct-bearing types collide because their printed names are incomplete.
- Stage 8 claims layout or ABI authority while proving type identity.

## S8.4 Stable Identity

The same Stage 7 type fact must produce the same canonical type identity.

Required proof:

- Repeated observation of the same type fact yields equal canonical type identity.
- Stability does not depend on allocation order, memory address, or transient object lifetime.
- Stability holds across at least two independent observations in one real compiler execution.

Failure examples:

- Reconstructing the same type fact produces different identities.
- Equality succeeds only because the same in-memory object is reused.

## S8.5 Uniqueness / Interning Semantics

Distinct supported type facts must produce distinct canonical type identities, and equal supported type facts must converge to the same identity.

Required proof:

- Equal type facts converge to equal canonical identities.
- Distinct type forms supported by the current compiler produce distinct canonical identities.
- The proof includes at least one declaration-related type fact and one expression-related type fact where supported.

Failure examples:

- `int` and `string` share an identity.
- Reference and owned forms share an identity accidentally.
- Struct-bearing type facts ignore their struct identity.

## S8.6 Equality Semantics

Canonical type equality must be based on canonical type identity, not display text, incidental structure, or source location.

Required proof:

- Equal canonical identities compare equal.
- Distinct canonical identities compare unequal.
- Equality can be observed through the canonical Stage 8 equality path.

Failure examples:

- Equality is string equality over display names.
- Equality depends on source token position or allocation address.

## S8.7 No Re-Typechecking Or Identity Reconstruction

Stage 8 must not re-run Stage 7 type checking and must not reconstruct type facts from source syntax or names.

Required proof:

- Stage 8 consumes Stage 7 type facts directly.
- Stage 8 does not invoke Stage 7 type checking to rediscover facts.
- Stage 8 does not invoke name resolution or `DeclarationRef` construction to rebuild declaration identity.

Failure examples:

- Stage 8 receives source text and computes expression types again.
- Stage 8 uses package/name strings to reconstruct declaration identity for declaration-bearing facts.

## S8.8 Output Boundary

Stage 8 emits observable canonical type identity evidence consumable by Stage 9.

Required proof:

- Successful output includes canonical type identities for the relevant type facts.
- The output can be consumed by Stage 9 without re-running type checking or canonical type production.
- The proof stops at canonical type identity and does not claim semantic program assembly, MIR, layout, ABI, or codegen.

Failure examples:

- Stage 8 reports only "canonical type succeeded" with no observable identity.
- Stage 8 output requires Stage 9 to repeat type checking or canonical type production.
- Stage 8 proof includes later-stage success claims.

## Gate Contract

The Stage 8 gate is `canonical-type-ref-check`.

The gate must report the first unmet Stage 8 contract in S8.1 -> S8.8 order:

```text
S8.1 ...
S8.2 ...
...
S8.8 ...
first-unmet-contract=<first failing S8.x or NONE>
stage8-canonical-type-ref=<CLOSED|NOT_CLOSED>
```

Initial expected state before implementation:

```text
S8.1 Input Boundary=FAIL
first-unmet-contract=S8.1
stage8-canonical-type-ref=NOT_CLOSED
```

After Stage 8 closes, `make compile-pipeline-check` should advance the first unproven required stage to Stage 9 Semantic Analysis.
