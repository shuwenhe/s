# Independent native generic-call frontier

The preserved pre-tuple-fix Stage1 and the new compiler reject even this scalar
generic call during monomorphization: missing concrete type arguments for
main.identity. This is independent of tuple formatting and tail-return checking.
Seed accepts compilation, but the optimized Seed native executable tested here
crashes with signal 11 for argument 1; do not claim a reference execution pass.
Track this as an unresolved native lowering issue; semantic generic-tuple positive/negative tests
remain in canonical_tuple_semantic_check.sh. No fallback or placeholder is used.
