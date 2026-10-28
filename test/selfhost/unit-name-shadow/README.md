# Unit name shadowing regression

The old Stage1 rejected create with e3116, although its string parameter unit
was present in the lexical environment. Both Seed and the repaired complete
Stage1 now compile and execute this program with exit 42.

The native parameter/local/nested-shadow and real-unit regression is
`test/native-bootstrap-diagnostic/canonical_unit_shadow_production_check.sh`.
True () literals and generated unit returns are kept distinct from a source
identifier named unit. Type and name checking are not bypassed.
