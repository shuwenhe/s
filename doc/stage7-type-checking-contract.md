# Stage 7 Type Checking Closure Contract

## Core Definition

Stage 7 consumes canonical `DeclarationRef` output from Stage 6 and performs type reasoning for declarations and expressions. It does not resolve names, construct declaration identity, construct `CanonicalTypeRef`, lower to MIR, compute layout, classify ABI, or generate code.

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
   |  DeclarationRef + expressions
   |    -> type reasoning
   |    -> expression/declaration type facts
   v
Stage 8 CanonicalTypeRef
   |
   |  type facts
   |    -> canonical type identity
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
    DeclarationRef + expressions -> type reasoning

Stage 8 owns:
    type -> canonical type identity
```

This boundary prevents Stage 7 from repeating name lookup, prevents Stage 7 from reconstructing `DeclarationRef`, and prevents Stage 7 from claiming Stage 8 canonical type identity.

## Closure Criteria

Stage 7 is CLOSED iff all of the following are proven by the Stage 7 gate:

1. Input boundary is proven.
2. Type environment authority is proven.
3. Declaration type facts are proven.
4. Expression type facts are proven.
5. Assignment and return compatibility are proven.
6. Rejection of type errors is proven.
7. No re-resolution or declaration identity reconstruction is proven.
8. The Stage 7 -> Stage 8 output boundary is proven.
9. No Stage 8+ authority is required to establish items 1-8.

Each closure item must have observable execution evidence from the real compiler producer before the gate can report `PASS / PROVEN`. Existing implementation candidates do not count as proof until real execution produces contract-specific evidence.

## S7.1 Input Boundary

Stage 7 input must include Stage 6 canonical `DeclarationRef` output plus the expression/declaration surface being type-checked. It must not start from unresolved names, raw package/name strings, or ad hoc declaration identity.

Required proof:

- Stage 7 consumes `DeclarationRef` evidence produced at the Stage 6 output boundary.
- Stage 7 receives expression/declaration input from the real compiler path.
- Missing or malformed `DeclarationRef` input fails deterministically.

Failure examples:

- Stage 7 accepts only raw names such as `helper` or `Point`.
- Stage 7 reconstructs declaration identity from package/name display text.
- A test fixture directly invents the declaration identity consumed by Stage 7.

## S7.2 Type Environment Authority

Stage 7 must establish type reasoning through one authoritative type-checking environment for the current compilation unit or package context.

Required proof:

- Successful type checking flows through the canonical Stage 7 type-checking producer.
- The environment binds declarations by `DeclarationRef`, not by display strings.
- The producer can be named in observable output so downstream gates can attribute type-checking authority.

Failure examples:

- Multiple unrelated type environments can independently decide conflicting types for the same declaration.
- Type checking consults package/name strings and re-runs lookup to find declarations.
- The gate passes by observing a type-related source token without executing the type-checking producer.

## S7.3 Declaration Type Facts

Stage 7 must establish type facts for declarations that need type reasoning, such as function signatures, variable declarations, constants, structs, fields, and relevant declaration kinds supported by the compiler.

Required proof:

- Declaration type facts are attached to or keyed by canonical `DeclarationRef`.
- The proof covers at least one function declaration and one data/field-bearing declaration where supported by the compiler.
- Declaration type facts do not require `CanonicalTypeRef` identity to be considered proven.

Failure examples:

- Function return type is accepted without checking the declaration's typed signature.
- Struct field or variable declaration types are represented only as raw display strings.
- Stage 7 claims Stage 8 canonical type identity while proving declaration type facts.

## S7.4 Expression Type Facts

Stage 7 must infer or check expression type facts for the expression forms required by the current language surface.

Required proof:

- Literal, reference, call, and operator expression facts are produced where those forms are supported.
- Expression type facts are derived from Stage 7 type reasoning and Stage 6 `DeclarationRef` inputs where declarations are referenced.
- The proof distinguishes expression type facts from canonical type identity.

Failure examples:

- A call expression is accepted without checking callee and argument type facts.
- A reference expression is typed by re-looking up its textual name.
- Expression output claims a `CanonicalTypeRef` instead of a Stage 7 type fact.

## S7.5 Compatibility Semantics

Stage 7 must enforce type compatibility for required semantic edges such as assignments, returns, call arguments, and operator operands.

Required proof:

- Compatible assignment or initialization succeeds.
- Compatible return expression succeeds against the declared return type.
- Compatible call arguments or operator operands succeed where those constructs are supported.
- Compatibility is based on Stage 7 type facts, not string equality of type names.

Failure examples:

- `int` and `bool` are treated as compatible because their display text is non-empty.
- A function can return an expression incompatible with its declared return type.
- Call argument checking succeeds without consulting the callee declaration's type facts.

## S7.6 Type Error Rejection

Stage 7 must reject type errors deterministically and report them as Stage 7 failures.

Required proof:

- At least one incompatible assignment, return, call, or operator case is rejected.
- The rejection occurs after Stage 5 and Stage 6 have succeeded for the relevant names/declarations.
- The rejection is attributed to Type Checking, not Parser, Name Resolution, DeclarationRef, `CanonicalTypeRef`, MIR, or backend stages.

Failure examples:

- A type error is accepted and deferred until MIR or codegen.
- A type error is reported as unresolved name or missing declaration identity.
- The gate passes only positive cases and never observes a real type error rejection.

## S7.7 No Re-Resolution Or Identity Reconstruction

Stage 7 type checking must not perform another name lookup from textual identifiers and must not reconstruct `DeclarationRef` identity.

Required proof:

- Stage 7 consumes the `DeclarationRef` produced by Stage 6.
- Stage 7 does not invoke Stage 5 lookup to rediscover declarations.
- Stage 7 does not invoke the Stage 6 declaration identity producer to rebuild identity from package/name strings.

Failure examples:

- Stage 7 receives `package` and `name`, then performs qualified or unqualified lookup again.
- Stage 7 constructs a fresh declaration identity instead of consuming Stage 6 output.
- Stage 7 accepts ambiguity or unresolved-name cases that Stage 5 should already have rejected.

## S7.8 Output Boundary

Stage 7 emits observable type-checking evidence consumable by Stage 8.

Required proof:

- Successful output includes typed declaration/expression facts keyed by canonical `DeclarationRef` where declarations are involved.
- The output can be consumed by Stage 8 without re-running type checking or name resolution.
- The proof stops at type facts and does not claim `CanonicalTypeRef`, MIR, layout, ABI, or codegen.

Failure examples:

- Stage 7 reports only "type check succeeded" with no observable type facts.
- Stage 7 output requires Stage 8 to repeat type checking.
- Stage 7 proof includes `CanonicalTypeRef`, MIR, layout, ABI, or codegen claims.

## Negative Contract

Stage 7 MUST NOT own:

- source parsing
- name lookup
- import resolution
- ambiguity rejection for unresolved names
- declaration candidate construction
- `DeclarationRef` identity construction
- `DeclarationRef` equality authority
- `CanonicalTypeRef`
- layout
- ABI classification
- MIR lowering
- codegen

If a fixture needs any of these to pass, it is not a Stage 7 closure fixture.

## Stage Boundary

```text
Stage 6
ResolvedDeclarationCandidate
  -> DeclarationRef
        canonical declaration identity

------------------------------ Stage boundary

Stage 7
DeclarationRef + declarations + expressions
  -> TypeCheckFacts
        declaration type facts
        expression type facts
        compatibility verdicts
        type error diagnostics

------------------------------ Stage boundary

Stage 8
TypeCheckFacts
  -> CanonicalTypeRef
        canonical type identity
```

`TypeCheckFacts` is a semantic role, not a prescribed representation. The contract requires Stage 7 to output enough typed evidence for Stage 8 to consume; it does not require a particular struct layout, field list, or serialization format.

## Gate Shape

The Stage 7 gate is `canonical-type-checking-check`.

The gate must report the first unmet Stage 7 contract in S7.1 -> S7.8 order:

```text
S7.1 ...
S7.2 ...
S7.3 ...
S7.4 ...
S7.5 ...
S7.6 ...
S7.7 ...
S7.8 ...

first-unmet-contract=S7.x
stage7-type-checking=NOT_CLOSED
result=FAIL
```

The final closed state is:

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

After Stage 7 closes, `make compile-pipeline-check` should advance the first unproven required stage to Stage 8 CanonicalTypeRef.
