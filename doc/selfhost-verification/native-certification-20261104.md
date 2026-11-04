# Native certification work ledger — 2026-11-04

Scope: certify complete deterministic native self-hosting. Floating point is a
separate P1 language project. This document is an execution checklist, not an
acceptance certificate.

## Baseline and evidence

- Initial HEAD: `901c1fede18a6ad876236039ce8adf7ce8a4b1a9`, clean main.
- Work branch: `native-certification-20261104`.
- New retained evidence: `.bootstrap/native-certification-20261104/`.
- Initial compiler SHA256: `5badee3a885832bdfd862da5170726f4394003995f2892b55ec0da0971a81232`.
- Initial seed SHA256: `78a36a65f0f3acc78f1c85aae739169d1dd4405322d337cd820c09f7c301e58f`.
- Both binaries copied before rebuilding. Previous `.bootstrap` and `/tmp`
  evidence remains untouched. The earlier external production-mission directory
  is unavailable; its reported running bootstrap does not establish acceptance.
- Historical `.bootstrap/selfhost-20261103/ACCEPTED.json` describes a recovered
  `6f0712321` source snapshot, not current HEAD. Fresh acceptance remains required.

## P0 implementation and verification

- [x] Reproduce missing five canonical bitwise operations; implement MIR/SSA
  integer validation and native AMD64 emission. Preserve arithmetic right shift
  and counts modulo 64.
- [x] Independent Python oracle passes 1,185 full-width cases through canonical
  native and current seed execution, including precedence, compound assignment,
  loop values and use of a fourth parameter after RCX serves a variable shift.
- [x] Historical seed comparison passes 231 carrier-safe cases. Historical seed
  lacks bitwise compound assignment syntax; equivalent explicit updates retain
  the same operations/assertions. Both syntax-attempt failures are preserved.
- [x] Reproduce new seed minimum-literal miscompile. Check integer range during
  IR lowering and fold unary int64 minimum directly; eleven original signed
  subcases fail with preserved initial seed, then pass after the fix.
- [x] Review identifies numeric array elements bypassing scalar checks; reproduce
  output clobber risk/unchecked acceptance and route through checked lowering.
- [x] Preserve concrete enum int/float conversions and expected-any payloads at
  the IR validation boundary; keep generic identities invariant and reject
  unresolved/incorrect concrete payloads. Float/any executable representations
  remain separate P1 work.
- [x] Reintroduce the tutorial as a permanent test fixture after the user commit
  removed the example. Execute it through the native driver and verify its ELF.
- [x] Initial controller suite: 21 tests pass with child-process tracing enabled.
- [ ] Complete integrated compiler build and all production recipes, recording
  commands, exit receipts, compiler hash and source identity.
- [x] First complete broader native-record and production runs pass, including OOM exit 126. Final generic concrete-payload adjustment is under full rerun.
- [ ] Review complete diff and commit verified increments.

## Frozen acceptance

- [ ] Record exact final source SHA and complete tracked-file manifest.
- [ ] Verify the complete ordered 268-file compiler closure against Git blobs.
- [ ] Start full clean-room controller in a new directory and separate checkout.
- [ ] Fresh C Seed → Stage1 → Stage2 → Stage3 → next generation.
- [ ] Verify each stage's ELF, invocation, function inventory, behavior, types,
  roots/GC and object lifetime tests.
- [ ] Compare raw assembly and ELF bytes and SHA256 at every convergence gate.
- [ ] Run all production tests with the newly built Stage3; prove its hash is
  unchanged and all source manifests remain intact.
- [ ] Run the same full pipeline in GitHub Actions on fresh Ubuntu runners and
  retain artifacts. Certification branches trigger the existing full job when
  their frozen commit message includes `[verify-full-bootstrap]`.
- [ ] Publish a precise local/CI evidence report only after actual success.

No cached stage or historical receipt substitutes for any unchecked gate.

## Additional evidence

- First complete preflight production run: 395.05 seconds, exit 0; source,
  seed and compiler hashes unchanged. Broader native-record run: 85.33 seconds,
  exit 0, same immutability checks. These precede the final generic concrete-leaf
  compatibility correction; they do not replace its complete rerun.
- Generic enums with a literal any/float payload and unrelated type parameter
  are accepted by general seed semantics. Isolated red/green tests preserve
  that behavior without widening payloads that name generic parameters.
- Baseline Actions run 41772854094 succeeds for core but skips full. No baseline
  full-bootstrap CI acceptance is claimed.

## Final P0 rerun

The final development compiler rebuilt with SHA256
`a7f405de3d34b6106cbb59dd1e56779e75d96aa50f17d681da478fd0ee5c7a2c`,
identical to the first preflight compiler. The current complete 268-file S
closure successfully compiled to seed IR. The final complete production and
record runs are required after concrete generic-payload compatibility and
seed enum discriminant overflow checks. Focused signed/hex/array/enum range
checks pass; the seed's maximum enum tag retains its exact decimal value.
Independent final review found no blockers. Fresh staged and CI gates remain
unchecked until their actual receipts exist.
