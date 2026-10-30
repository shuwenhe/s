# Full-source native self-hosting execution, 2026-10-30

Status: **in progress; stage2/stage3 convergence has not been established.**

The earlier text in this file described a hosted bootstrap as running and marked
unverified goals as complete. That report was not supported by artifacts:
`src/cmd/dist/hosted-bootstrap.sh` is a failing explanatory stub, not an operating
bootstrap. It must not be used as evidence of self-hosting.

Acceptance remains the native pipeline in
`src/cmd/dist/native-bootstrap-no-manifest.sh`: use the C seed only for stage1,
compile all 268 source modules with stage1, rebuild them with stage2, compare
stage2/stage3 assembly and executable bytes, and run independent source-dependence
and execution checks. All stages must use the same compiler source hashes.

Measured continuation evidence:

- Fresh original-source stage1 built and passed `verify_true_selfhost.sh`.
  Full-source compilation is traced in `.bootstrap/selfhost-complete.log`.
  This attempt predates the continuation fixes and cannot establish acceptance
  for the final sources.
- Imported record fields reproduced `unsupported record field type: Graph`.
  Carrying Semantic's nominal identities into canonical declarations,
  constructors and signatures passes `canonical_nominal_layout_check.sh` with
  `.bootstrap/selfhost-nominal/stage1`.
- The receiver regression then reproduced a qualified type-elaboration alias
  losing its package. The alias fix still requires rebuilt-stage1 verification.
- Nested `.push` reproduced `qualified call requires package identity`.
  Lowering through existing named-place reconstruction is under verification.
- The previous uncommitted native array capacity change reproduced a crash on
  append to a default array (139), and alias length corruption (43, expected 42).
  The established persistent layout has been restored; regression verification
  is pending.

The ongoing decision and test ledger is
`selfhost-plan-2026-10-30.md`. No stage3 has been installed by this continuation.
