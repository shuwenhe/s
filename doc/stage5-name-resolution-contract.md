# Stage 5 Name / Import Resolution Closure Contract

## Core Definition

Stage 5 resolves names in the source program to a unique declaration candidate within a determined package/import/declaration environment. It does not create canonical declaration identity.

```text
Stage 4 AST
   |
   v
Stage 5 Name / Import Resolution
   |
   |  name
   |    -> package/import environment
   |    -> declaration lookup
   |    -> unique declaration candidate
   v
Stage 6 DeclarationRef
   |
   |  candidate
   |    -> canonical identity
   v
DeclarationRef
```

## Closure Criteria

Stage 5 is CLOSED iff all of the following are proven by the Stage 5 gate:

1. Canonical input authority is proven.
2. Package identity is proven.
3. Import registration is proven.
4. Declaration indexing is proven.
5. Unqualified lookup is proven.
6. Qualified lookup is proven.
7. Ambiguity rejection is proven.
8. Unresolved-name rejection is proven.
9. The Stage 5 -> Stage 6 output boundary is proven.
10. No Stage 6+ authority is required to establish items 1-9.

Each closure item must have at least one positive or negative fixture/assertion before the gate can report `PASS / PROVEN`.

## S5.1 Input Authority

Stage 5 input must come from the canonical AST / semantic entry path.

Required proof:

- The gate receives AST/package units from the canonical parser/semantic entry.
- Stage 5 does not re-parse source to rediscover declarations.
- Stage 5 does not reconstruct declarations by ad hoc string scanning.

Failure examples:

- The gate passes when fed text that bypasses the canonical AST.
- Name resolution succeeds by reparsing source inside Stage 5.
- A declaration is inferred from string matching instead of AST declaration data.

## S5.2 Package Identity

Every compilation unit handled by Stage 5 must have a determined package identity.

Required proof:

- A source unit maps to exactly one package identity.
- Package identity is stable for all declarations and lookups in that unit.
- Missing, malformed, or conflicting package identity has deterministic failure behavior.

Failure examples:

- Two package identities are accepted for one unit.
- A declaration is indexed without package identity.
- Lookup succeeds after silently inventing a package identity.

## S5.3 Import Registration

Imports establish a local import name -> package identity mapping.

Required proof:

- A valid import creates the expected local binding.
- Qualified lookup uses the registered import binding.
- Unknown imports fail deterministically.
- Duplicate or conflicting imports have deterministic behavior.

Failure examples:

- An unknown import silently falls back to a global package search.
- Conflicting imports are resolved by order-dependent first match.
- A qualified lookup succeeds without a registered package binding.

## S5.4 Declaration Index

Package-level declarations must be indexed into a queryable declaration set.

Required declaration candidate metadata:

- package identity
- declaration name
- declaration kind
- declaration source/handle
- arity, if required by language semantics
- any additional metadata needed to disambiguate names without using Stage 6+ identity

Required proof:

- Functions, consts, structs, traits, and methods that Stage 5 owns are indexed under package identity and name.
- Declarations preserve kind and source/handle information.
- Duplicate declarations produce deterministic ambiguity or duplicate-declaration behavior.

Failure examples:

- Lookup succeeds without preserving declaration kind.
- Declarations from different packages collapse into one namespace unintentionally.
- Duplicate declarations are resolved by first-match-wins.

## S5.5 Unqualified Lookup

An unqualified name such as `foo` resolves through the Stage 5 lexical/package lookup rules to 0, 1, or N candidates. Only exactly one candidate succeeds.

Required proof:

- A single in-scope declaration resolves successfully.
- A missing declaration produces unresolved-name failure.
- Multiple legal candidates produce ambiguity failure.
- Lookup order is deterministic and documented by fixtures.

Failure examples:

- `foo` resolves by scanning unrelated packages.
- Ambiguous `foo` succeeds by choosing the first candidate.
- Missing `foo` silently creates a placeholder declaration.

## S5.6 Qualified Lookup

A qualified name such as `pkg.foo` first resolves `pkg`, then resolves `foo` inside the resolved package identity. Only exactly one declaration candidate succeeds.

Required proof:

- A valid imported package qualifier resolves to the expected package identity.
- A valid member name inside that package resolves to exactly one candidate.
- Unknown qualifier fails deterministically.
- Unknown member fails deterministically.
- Multiple matching members fail as ambiguity.

Failure examples:

- `pkg.foo` succeeds when `pkg` is not registered.
- `pkg.foo` falls back to unqualified `foo`.
- Multiple `foo` declarations in `pkg` are accepted by first match.

## S5.7 Ambiguity

Multiple legal candidates must be rejected explicitly.

Required proof:

- Ambiguity is reported with enough information to identify the name and candidate set.
- Stage 5 never chooses a candidate by incidental iteration order.
- Ambiguity rejection applies to unqualified and qualified names.

Failure examples:

- Any first-match-wins behavior.
- Ambiguous names are deferred silently to Stage 6.
- Ambiguous names are treated as unresolved instead of ambiguous.

## S5.8 Unresolved Name

Zero candidates must produce a deterministic unresolved-name failure.

Required proof:

- Unknown unqualified names fail.
- Unknown qualified package names fail.
- Unknown qualified member names fail.
- The failure includes enough location/name context for attribution.

Failure examples:

- Unknown names produce synthetic declarations.
- Unknown names are silently accepted for later phases.
- Unknown qualified members fall back to unqualified lookup.

## S5.9 Output Boundary

Stage 5 outputs a resolved declaration candidate or binding. It does not output the final canonical DeclarationRef.

Required output shape:

```text
ResolvedDeclarationCandidate {
    package_identity
    declaration_source_or_handle
    declaration_kind
    name
    required_disambiguating_metadata
}
```

Required proof:

- Successful lookup output contains enough data for Stage 6 to construct canonical identity.
- Stage 5 output does not claim canonical identity.
- Stage 6 can consume the candidate without re-resolving the original name string.

Failure examples:

- Stage 5 returns only a string name and package path for downstream re-lookup.
- Stage 5 constructs canonical DeclarationRef identity.
- Stage 6 must repeat Stage 5 name lookup to continue.

## Negative Contract

Stage 5 MUST NOT own:

- type inference
- type compatibility
- overload selection based on types, if the language later supports overloads
- generic monomorphization
- CanonicalTypeRef
- layout
- ABI classification
- MIR lowering
- codegen
- canonical DeclarationRef identity construction

If a fixture needs any of these to pass, it is not a Stage 5 closure fixture.

## Stage Boundary

```text
Stage 5
name
  -> ResolvedDeclarationCandidate
        package identity
        declaration source/handle
        declaration kind
        name
        required disambiguating metadata

------------------------------ Stage boundary

Stage 6
ResolvedDeclarationCandidate
  -> DeclarationRef
        canonical declaration identity
```

## First Real Gate Goal

The next `stage5-name-resolution-check` should not try to make Stage 5 green immediately. Its first useful goal is to replace `PENDING_IMPLEMENTATION` with a RED gate that reports the first unmet Stage 5 closure criterion.

Expected first milestone:

```text
stage5-name-resolution-check
  result = FAIL
  first-unmet-contract = S5.x
  reason = <specific missing proof or semantic failure>
```

Only after that attribution exists should Stage 5 implementation work begin.
