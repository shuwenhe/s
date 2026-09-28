# Stage 6 DeclarationRef Closure Contract

## Core Definition

Stage 6 converts a Stage 5 resolved declaration candidate into a canonical declaration identity. It does not resolve names, type-check expressions, construct canonical type identity, lower to MIR, or generate code.

```text
Stage 5 Name / Import Resolution
   |
   |  name
   |    -> package/import environment
   |    -> declaration lookup
   |    -> unique declaration candidate
   v
Stage 6 DeclarationRef
   |
   |  declaration candidate
   |    -> canonical declaration identity
   v
Stage 7 Type Checking
   |
   |  declaration/expression
   |    -> type reasoning
   v
typed program
```

The stage ownership invariant is:

```text
Stage 5 owns:
    name -> declaration candidate

Stage 6 owns:
    declaration candidate -> canonical declaration identity

Stage 7 owns:
    declaration/expression -> type reasoning
```

This boundary prevents Stage 6 from repeating lookup, prevents Stage 6 from type-checking, and prevents Stage 7 from recovering declaration identity by string lookup.

## Closure Criteria

Stage 6 is CLOSED iff all of the following are proven by the Stage 6 gate:

1. Input boundary is proven.
2. Canonical producer authority is proven.
3. Identity authority is proven.
4. Stable identity is proven.
5. Uniqueness is proven.
6. Equality semantics are proven.
7. No re-resolution is proven.
8. The Stage 6 -> Stage 7 output boundary is proven.
9. No Stage 7+ authority is required to establish items 1-8.

Each closure item must have observable execution evidence from the real compiler producer before the gate can report `PASS / PROVEN`. Existing implementation candidates do not count as proof until real execution produces contract-specific evidence.

## S6.1 Input Boundary

Stage 6 input must be a Stage 5 `ResolvedDeclarationCandidate` or equivalent resolved declaration candidate. It must not start from an unresolved/raw name.

Required proof:

- Stage 6 consumes a candidate produced at the Stage 5 output boundary.
- Stage 6 receives enough candidate identity material to construct a `DeclarationRef` without resolving the original source name again.
- Missing or malformed candidate input fails deterministically.

Failure examples:

- Stage 6 accepts only a raw name such as `helper`.
- Stage 6 accepts package/name strings that require another lookup to find the declaration.
- Stage 6 silently invents a candidate when Stage 5 did not produce one.

## S6.2 Canonical Producer

`DeclarationRef` must be established through one authoritative identity-construction path.

Required proof:

- Successful `DeclarationRef` creation flows through the canonical producer.
- Alternate local construction paths are not accepted as Stage 6 proof.
- The producer can be named in observable output so downstream gates can attribute identity authority.

Failure examples:

- Multiple unrelated functions can create semantically independent `DeclarationRef` identities for the same declaration.
- A downstream stage constructs a `DeclarationRef` directly from package/name strings.
- The gate passes by observing a struct or type name in source without executing the producer.

## S6.3 Identity Authority

`DeclarationRef` carries sufficient canonical identity to uniquely identify its declaration independently of display text. The contract does not prescribe the exact physical representation.

Required proof:

- The identity distinguishes declarations without relying on display formatting.
- The identity remains meaningful if display text changes.
- The proof reports identity authority without requiring a specific field layout such as path, source handle, or numeric id.

Failure examples:

- Two declarations are considered identical because their display strings match.
- A formatting change changes declaration identity.
- The contract requires a particular field representation rather than the semantic ability to identify the declaration.

## S6.4 Stable Identity

The same resolved declaration candidate must produce the same canonical declaration identity.

Required proof:

- Repeated construction from the same candidate yields equal `DeclarationRef` identity.
- Stability does not depend on incidental allocation order, memory address, or transient object lifetime.
- Stability holds across at least two independent observations in one real compiler execution.

Failure examples:

- Reconstructing the same candidate produces different identities.
- Equality succeeds only because the same in-memory object is reused.
- Identity changes when unrelated declarations are added before the candidate.

## S6.5 Uniqueness

Distinct declarations must produce distinct canonical declaration identities.

Required proof:

- Same spelling in different packages/modules produces distinct identities.
- Distinct declarations within the same authority domain produce distinct identities.
- Relevant declaration kinds where collision is possible are distinguished.

Failure examples:

- `pkg_a.helper` and `pkg_b.helper` collapse to one identity.
- Two declarations in the same package are accepted as the same identity because their display text overlaps.
- Function and const declarations with colliding names cannot be distinguished where the language permits or reports that collision.

## S6.6 Equality Semantics

`DeclarationRef` equality must be based on canonical declaration identity.

Required proof:

- Equal canonical identities compare equal.
- Distinct canonical identities compare unequal.
- Equality is independent of display-name equality, reconstructed package/name strings, and incidental memory/object address.

Failure examples:

- Equality compares only `package + "." + name` display text.
- Equality compares object address or allocation identity.
- Equality ignores declaration kind or authority-domain identity where those are required to distinguish declarations.

## S6.7 No Re-Resolution

Candidate-to-`DeclarationRef` construction must not perform another name lookup from textual identifiers.

Required proof:

- Stage 6 construction proceeds from the resolved candidate produced by Stage 5.
- Stage 6 does not invoke Stage 5 lookup to rediscover the declaration.
- Downstream use of `DeclarationRef` does not require package/name string reconstruction to recover identity.

Failure examples:

- Stage 6 receives `package` and `name`, then performs qualified or unqualified lookup again.
- Stage 6 accepts ambiguity or unresolved-name cases that Stage 5 should already have rejected.
- Stage 7 starts from strings and re-runs lookup instead of consuming `DeclarationRef`.

## S6.8 Output Boundary

Stage 6 emits observable canonical `DeclarationRef` evidence consumable by Stage 7.

Required proof:

- Successful output includes a canonical declaration identity for the candidate.
- The output can be consumed by Stage 7 without name re-resolution.
- The proof stops at declaration identity and does not claim type checking, `CanonicalTypeRef`, MIR, layout, ABI, or codegen.

Failure examples:

- Stage 6 reports only a display string with no canonical identity evidence.
- Stage 6 output requires Stage 7 to look up the declaration from package/name text.
- Stage 6 proof includes type-checking, `CanonicalTypeRef`, MIR, layout, ABI, or codegen claims.

## Negative Contract

Stage 6 MUST NOT own:

- name lookup
- import resolution
- ambiguity rejection for unresolved names
- type inference
- type compatibility
- overload selection based on types, if the language later supports overloads
- `CanonicalTypeRef`
- layout
- ABI classification
- MIR lowering
- codegen

If a fixture needs any of these to pass, it is not a Stage 6 closure fixture.

## Stage Boundary

```text
Stage 5
name
  -> ResolvedDeclarationCandidate
        resolved declaration candidate authority
        declaration kind
        owning package/module authority
        required disambiguating metadata

------------------------------ Stage boundary

Stage 6
ResolvedDeclarationCandidate
  -> DeclarationRef
        canonical declaration identity

------------------------------ Stage boundary

Stage 7
DeclarationRef + expressions
  -> type reasoning
```

## Gate Shape

The Stage 6 gate is `canonical-declaration-ref-check`.

The gate must report the first unmet Stage 6 contract in S6.1 -> S6.8 order:

```text
S6.1 ...
S6.2 ...
S6.3 ...
S6.4 ...
S6.5 ...
S6.6 ...
S6.7 ...
S6.8 ...

first-unmet-contract=S6.x
stage6-declaration-ref=NOT_CLOSED
result=FAIL
```

The final closed state is:

```text
S6.1 PASS
S6.2 PASS
S6.3 PASS
S6.4 PASS
S6.5 PASS
S6.6 PASS
S6.7 PASS
S6.8 PASS

first-unmet-contract=NONE
stage6-declaration-ref=CLOSED
result=PASS
```

After Stage 6 closes, `make compile-pipeline-check` should advance the first unproven required stage to Stage 7 Type Checking.

## First Real Gate Goal

The first `canonical-declaration-ref-check` implementation should not try to make Stage 6 green immediately. Its first useful goal is a RED gate that attributes the first missing Stage 6 closure criterion.

Expected first milestone:

```text
canonical-declaration-ref-check
  result = FAIL
  first-unmet-contract = S6.x
  reason = <specific missing proof or semantic failure>
```

Only after that attribution exists should Stage 6 implementation work begin.
