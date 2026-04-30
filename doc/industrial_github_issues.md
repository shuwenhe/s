# Industrialization GitHub Issues Backlog

This file maps task board items to ready-to-paste GitHub issue templates.
Source board: /app/s/doc/industrial_task_board.md

## Issue 01: T01 Add governance baseline docs

Title:
- [IND][T01] Add governance baseline docs

Labels:
- industrialization
- governance
- p0

Assignee:
- PL

Start date:
- 2026-05-01

Due date:
- 2026-05-04

Dependencies:
- None

Description:
- Add the governance baseline documents required for production readiness.
- Files required: LICENSE.md, SECURITY.md, CONTRIBUTING.md, CHANGELOG.md.
- Add .github/pull_request_template.md with mandatory sections for risk, testing, and breaking changes.

Definition of done:
- All required files exist and are reviewed.
- PR template is active and used by at least one merged pull request.

Acceptance script:
```bash
test -f LICENSE.md && test -f SECURITY.md && test -f CONTRIBUTING.md && test -f CHANGELOG.md
test -f .github/pull_request_template.md
```

## Issue 02: T02 Publish versioning and compatibility policy

Title:
- [IND][T02] Publish versioning and compatibility policy

Labels:
- industrialization
- policy
- p0

Assignee:
- LA

Start date:
- 2026-05-02

Due date:
- 2026-05-06

Dependencies:
- T01

Description:
- Define semver usage policy for 0.x and post-1.0 stages.
- Define compatibility guarantees for language syntax, CLI commands, and standard library APIs.
- Add a breaking-change declaration process for each release.

Definition of done:
- Policy exists in docs and linked from README.
- Compatibility scope is explicit and testable.

Acceptance script:
```bash
rg -n "compat|breaking|semver|version policy" doc README.md
rg -n "compatibility" doc/spec.md
```

## Issue 03: T03 Enforce mandatory CI gates on pull request

Title:
- [IND][T03] Enforce mandatory CI gates on pull request

Labels:
- industrialization
- ci
- p0

Assignee:
- BE

Start date:
- 2026-05-03

Due date:
- 2026-05-07

Dependencies:
- T01

Description:
- Require CI checks on pull_request and main branch updates.
- Gate merge on compiler checks, smoke fuzz, and reproducible build checks.
- Document gate ownership and escalation path.

Definition of done:
- Required checks are configured in repository settings.
- Failing checks block merge.

Acceptance script:
```bash
rg -n "pull_request" .github/workflows/compiler-ci.yml
rg -n "smoke fuzz|reproducible build|compiler checks" .github/workflows/compiler-ci.yml
```

## Issue 04: T04 Freeze MVP language subset

Title:
- [IND][T04] Freeze MVP language subset

Labels:
- industrialization
- language-spec
- p0

Assignee:
- LA

Start date:
- 2026-05-05

Due date:
- 2026-05-12

Dependencies:
- T02

Description:
- Freeze MVP syntax and semantic subset.
- Explicitly mark deferred items and open questions with owners and review date.
- Add compatibility note for frozen MVP behavior.

Definition of done:
- MVP frozen list is in docs.
- Deferred list has owner and target review date.

Acceptance script:
```bash
rg -n "frozen|mvp|deferred|open questions" doc/minimum_language_subset.md doc/spec.md
```

## Issue 05: T05 Normalize CLI behavior and exit codes

Title:
- [IND][T05] Normalize CLI behavior and exit codes

Labels:
- industrialization
- cli
- p0

Assignee:
- CE

Start date:
- 2026-05-08

Due date:
- 2026-05-15

Dependencies:
- T04

Description:
- Normalize command behavior for check, build, run, test, mod init, mod tidy.
- Standardize usage/help output and error prefixes.
- Standardize exit codes for parse errors, semantic errors, and runtime failures.

Definition of done:
- CLI behavior is documented and reproducible across commands.
- Basic command suite passes on CI.

Acceptance script:
```bash
s check /app/s/misc/examples/s/hello.s
s build /app/s/misc/examples/s/hello.s -o /tmp/s_hello
s run /app/s/misc/examples/s/sum.s
s test
s mod init demo.app && s mod tidy
```

## Issue 06: T06 Split tests into four quality layers

Title:
- [IND][T06] Split tests into four quality layers

Labels:
- industrialization
- testing
- p1

Assignee:
- QE

Start date:
- 2026-05-10

Due date:
- 2026-05-20

Dependencies:
- T04

Description:
- Define and implement four layers: core-language, backend, runtime, selfhost.
- Add per-layer pass/fail reporting.
- Document fixture ownership and update policy.

Definition of done:
- Layers are visible in docs and CI logs.
- s test can target fixtures root for at least one layer.

Acceptance script:
```bash
rg -n "core-language|backend|runtime|selfhost" doc
s test /app/s/src/cmd/compile/internal/tests/fixtures
```

## Issue 07: T07 Add deterministic benchmark baseline

Title:
- [IND][T07] Add deterministic benchmark baseline

Labels:
- industrialization
- performance
- p1

Assignee:
- QE

Start date:
- 2026-05-12

Due date:
- 2026-05-22

Dependencies:
- T05

Description:
- Define benchmark output format and regression threshold policy.
- Add baseline storage and update protocol.
- Wire benchmark regression warning into CI.

Definition of done:
- Benchmarks run with deterministic output format.
- Regression threshold documented and enforced.

Acceptance script:
```bash
chmod +x scripts/benchmark-compiler.sh && ./scripts/benchmark-compiler.sh
rg -n "threshold|regression" doc README.md
```

## Issue 08: T08 Stabilize bootstrap stage checks

Title:
- [IND][T08] Stabilize bootstrap stage checks

Labels:
- industrialization
- bootstrap
- p1

Assignee:
- CE

Start date:
- 2026-05-15

Due date:
- 2026-05-29

Dependencies:
- T05

Description:
- Stabilize stage1/stage2 transition checks.
- Add reproducibility report and failure taxonomy.
- Ensure bootstrap diagnostics are explicit and actionable.

Definition of done:
- Bootstrap checks are documented and reproducible.
- Failure classes are listed with remediation notes.

Acceptance script:
```bash
rg -n "bootstrap" doc/bootstrap_flow.md doc/runtime_transition.md
rg -n "bootstrap two-stage check passed" src/cmd/compile/seed/s_seed.c src/cmd/compile/seed/code/native_backend.c
```

## Issue 09: T09 Add release workflow for tagged builds

Title:
- [IND][T09] Add release workflow for tagged builds

Labels:
- industrialization
- release
- p1

Assignee:
- BE

Start date:
- 2026-05-25

Due date:
- 2026-06-05

Dependencies:
- T01, T03, T05

Description:
- Add release workflow triggered by tags.
- Publish build artifacts and checksums.
- Generate release notes with compatibility section.

Definition of done:
- Tagged commit produces release artifacts and checksum file.
- Release note template includes compatibility and risk section.

Acceptance script:
```bash
ls .github/workflows
rg -n "release|tag|artifact|checksum" .github/workflows/*.yml
```

## Issue 10: T10 Add security response SLA and process

Title:
- [IND][T10] Add security response SLA and process

Labels:
- industrialization
- security
- p1

Assignee:
- SE

Start date:
- 2026-05-28

Due date:
- 2026-06-08

Dependencies:
- T01

Description:
- Define severity levels and response SLA.
- Add disclosure process and contact channel.
- Add incident handling flow and communication rules.

Definition of done:
- SECURITY.md includes SLA matrix and disclosure process.
- Team can execute incident process in tabletop review.

Acceptance script:
```bash
rg -n "SLA|severity|response|disclosure" SECURITY.md doc
```

## Issue 11: T11 Define LTS and support window policy

Title:
- [IND][T11] Define LTS and support window policy

Labels:
- industrialization
- support-policy
- p1

Assignee:
- PL

Start date:
- 2026-06-02

Due date:
- 2026-06-12

Dependencies:
- T02, T09

Description:
- Define support windows for current and previous versions.
- Define deprecation timeline and migration policy.
- Link policy from README and release process.

Definition of done:
- LTS and deprecation policy are published and referenced.
- Upgrade guidance exists for one sample breaking change.

Acceptance script:
```bash
rg -n "LTS|support window|deprecation" doc README.md
```

## Issue 12: T12 Industrial readiness review and sign-off

Title:
- [IND][T12] Industrial readiness review and sign-off

Labels:
- industrialization
- readiness
- p1

Assignee:
- PL

Start date:
- 2026-06-15

Due date:
- 2026-06-19

Dependencies:
- T01,T02,T03,T04,T05,T06,T07,T08,T09,T10,T11

Description:
- Run final go or no-go review using scorecard.
- Collect objective evidence from all prior tasks.
- Publish final readiness report and decision.

Definition of done:
- Review completed with explicit decision and follow-ups.
- Report stored in doc/industrial_readiness_report.md.

Acceptance script:
```bash
rg -n "go/no-go|readiness|scorecard" doc
test -f doc/industrial_readiness_report.md
```
