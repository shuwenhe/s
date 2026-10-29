# Invalid result constructor with a tuple return signature

This was the observed e3008 frontier in `ok_write_ops` at
`src/cmd/compile/internal/core/backend.s:38`. Investigation established a source
contract inconsistency: the helper returns a tagged result enum and its consumers
expect `result[...]`, while its old signature declared a tuple. Eight such helper
signatures have been corrected to explicit result types; no type compatibility
rule was relaxed.

This fixture deliberately keeps the invalid tuple signature and should continue
to be rejected:

```sh
bin/s_compiler --compile-unit /tmp/result-tuple.sasm \
  test/selfhost/result-constructor-tuple-return/main.s src/result/result.s
```

Keep this input order to inspect `wrap` before unrelated library methods.
`canonical_backend_result_contract_check.sh` checks the actual corrected helpers,
their tagged-result consumers, valid tuple returns, and six strict type-error
cases. See `doc/selfhost-result-contract-20261029.md` for measured full-source
progress and the subsequent frontier.
