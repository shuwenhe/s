# Type System and Call Resolution Rules

This document defines the consistency rules for the structured type system and overload resolution used by `compile.internal.semantic` and `compile.internal.typesys`.

## 1. Canonical Type Form

All type comparisons must be performed on canonical form:

- Strip leading/trailing whitespace.
- Normalize prefixes recursively: `&mut T`, `&T`, `[]T`.
- Keep generic arguments in-order and canonicalized recursively.

Invariant:

- `same_type(a, b)` iff `parse_type(a) == parse_type(b)`.

## 2. Structured Type Projection

`parse_type_ref` must preserve these projections:

- `canonical`: normalized full type text.
- `base`: root constructor name.
- `is_ref`: true for `&T` and `&mut T`.
- `is_mut_ref`: true only for `&mut T`.
- `is_slice`: true for `[]T`.
- `args`: generic arguments in source order.

Invariant:

- `same_type_ref(x, y)` implies equal `canonical`.
- If `same_type_ref(x, y)`, all structural projections are equal.

## 3. Compatibility Rule

`types_compatible(left, right)` is defined as:

- true when either side is `unknown` (error-recovery permissive mode).
- otherwise equivalent to `same_type(left, right)`.

This makes the checker monotonic under partial information and prevents cascading false negatives.

## 4. Overload Candidate Matching

Candidate matching uses structured recursion:

1. Arity must match exactly.
2. Generic type variable occurrences are bound on first use and must unify on reuse.
3. Ref/mut/slice qualifiers must match exactly.
4. Base constructors must match.
5. Generic argument lists recurse pairwise.

A candidate is valid only when all parameters match.

## 5. Deterministic Overload Ranking

Among valid candidates, choose by strict tuple order:

1. Higher `score` wins.
2. Lower `unknown_arg_count` wins.
3. Lower `generic_bind_count` wins.

Ambiguous overload is reported only when all tuple fields tie.

Determinism guarantee:

- For a fixed call site and fixed candidate set, winner is stable and order-independent.

## 6. Method Return Mapping

Built-in method return kinds are interpreted as:

- `t` -> first type argument.
- `e` -> second type argument.
- `option[t]` -> `option[first argument]`.
- otherwise parse as a normal type.

This ensures return inference is compositional with structured type arguments.

## 7. Rule Consistency Checklist

When adding new type constructors or overload behavior:

- Extend canonicalization (`parse_type`).
- Extend `parse_type_ref` projections.
- Update recursive matcher for new constructor shape.
- Keep ranking tuple deterministic.
- Add tests for both exact and generic overloads.
