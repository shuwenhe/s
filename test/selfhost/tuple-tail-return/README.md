# Tuple tail return regression

`doc/s` permits a function's last expression to supply its return value and
supports multiple return values. Seed and the repaired full Stage1 both compile
this source to native code executing 42.

The prior full Stage1 rejected `relay` with e3004: declared `(string,string)`
versus inferred `(string, string)`. The AST was a call and both shapes had two
string members. `instantiate_type` now emits canonical compact separators,
including generic members nested inside tuples. Return checking remains strict.
The native execution and rejection regression is
`test/native-bootstrap-diagnostic/canonical_tuple_tail_production_check.sh`.
