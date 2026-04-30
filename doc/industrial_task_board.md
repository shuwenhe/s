# S Language Industrialization Task Board

Owner map:
- PL: Product Lead
- LA: Language Architect
- CE: Compiler Engineer
- BE: Build and Release Engineer
- QE: Quality Engineer
- SE: Security Engineer
- DX: Developer Experience Engineer

Timeline baseline:
- Program start date: 2026-05-01
- Program target completion: 2026-07-24

## Board

| ID | Task | Owner | Start | Due | Depends On | Deliverable | Acceptance Script |
|---|---|---|---|---|---|---|---|
| T01 | Add governance baseline docs | PL | 2026-05-01 | 2026-05-04 | None | LICENSE.md, SECURITY.md, CONTRIBUTING.md, CHANGELOG.md and pull request template | 1) test -f LICENSE.md && test -f SECURITY.md && test -f CONTRIBUTING.md && test -f CHANGELOG.md  2) test -f .github/pull_request_template.md |
| T02 | Publish versioning and compatibility policy | LA | 2026-05-02 | 2026-05-06 | T01 | Semver policy and compatibility matrix in docs | 1) rg -n "compat|breaking|semver|version policy" doc README.md  2) rg -n "compatibility" doc/spec.md |
| T03 | Enforce mandatory CI gates on pull request | BE | 2026-05-03 | 2026-05-07 | T01 | Branch protection and required checks configured for main | 1) rg -n "pull_request" .github/workflows/compiler-ci.yml  2) rg -n "smoke fuzz|reproducible build|compiler checks" .github/workflows/compiler-ci.yml |
| T04 | Freeze MVP language subset | LA | 2026-05-05 | 2026-05-12 | T02 | Frozen MVP section and deferred list with owner and review date | 1) rg -n "frozen|mvp|deferred|open questions" doc/minimum_language_subset.md doc/spec.md |
| T05 | Normalize CLI behavior and exit codes | CE | 2026-05-08 | 2026-05-15 | T04 | Stable command behavior for check build run test mod init mod tidy | 1) s check /app/s/misc/examples/s/hello.s  2) s build /app/s/misc/examples/s/hello.s -o /tmp/s_hello  3) s run /app/s/misc/examples/s/sum.s  4) s test  5) s mod init demo.app && s mod tidy |
| T06 | Split tests into four quality layers | QE | 2026-05-10 | 2026-05-20 | T04 | Core-language backend runtime selfhost layers with per-layer pass report | 1) rg -n "core-language|backend|runtime|selfhost" doc  2) s test /app/s/src/cmd/compile/internal/tests/fixtures |
| T07 | Add deterministic benchmark baseline | QE | 2026-05-12 | 2026-05-22 | T05 | Benchmark output format and threshold policy | 1) chmod +x scripts/benchmark-compiler.sh && ./scripts/benchmark-compiler.sh  2) rg -n "threshold|regression" doc README.md |
| T08 | Stabilize bootstrap stage checks | CE | 2026-05-15 | 2026-05-29 | T05 | Stage1 and stage2 reproducibility report with failure taxonomy | 1) rg -n "bootstrap" doc/bootstrap_flow.md doc/runtime_transition.md  2) rg -n "bootstrap two-stage check passed" src/cmd/compile/seed/s_seed.c src/cmd/compile/seed/code/native_backend.c |
| T09 | Add release workflow for tagged builds | BE | 2026-05-25 | 2026-06-05 | T01,T03,T05 | Release workflow that publishes artifacts and checksums | 1) ls .github/workflows  2) rg -n "release|tag|artifact|checksum" .github/workflows/*.yml |
| T10 | Add security response SLA and process | SE | 2026-05-28 | 2026-06-08 | T01 | Severity SLA matrix and incident workflow | 1) rg -n "SLA|severity|response|disclosure" SECURITY.md doc |
| T11 | Define LTS and support window policy | PL | 2026-06-02 | 2026-06-12 | T02,T09 | Support matrix and deprecation schedule | 1) rg -n "LTS|support window|deprecation" doc README.md |
| T12 | Industrial readiness review and sign-off | PL | 2026-06-15 | 2026-06-19 | T01,T02,T03,T04,T05,T06,T07,T08,T09,T10,T11 | Go or no-go report with scorecard | 1) rg -n "go/no-go|readiness|scorecard" doc  2) test -f doc/industrial_readiness_report.md |

## Dependency Graph

- T01 is the first milestone and unblocks governance dependent work.
- T02 depends on T01.
- T03 depends on T01.
- T04 depends on T02.
- T05 depends on T04.
- T06 depends on T04.
- T07 depends on T05.
- T08 depends on T05.
- T09 depends on T01, T03, and T05.
- T10 depends on T01.
- T11 depends on T02 and T09.
- T12 depends on all prior tasks.

## Weekly Milestones

- Week 1 target: T01 T02 T03 complete.
- Week 2 target: T04 and T05 complete.
- Week 3 target: T06 T07 underway, T08 started.
- Week 4 target: T06 T07 T08 complete.
- Week 5 target: T09 and T10 complete.
- Week 6 target: T11 complete, T12 review package ready.
- Week 7 target: T12 sign-off and publish readiness report.

## Daily Execution Cadence

- Daily standup fields:
  - Yesterday done
  - Today plan
  - Blockers
  - Risk level
- Weekly report fields:
  - Tasks due this week
  - Tasks at risk
  - Scope changes
  - Score delta

## Readiness Scorecard Template

- Spec stability: 0 to 15
- Compiler and toolchain completeness: 0 to 15
- Testing and CI quality gates: 0 to 15
- Release governance and operations: 0 to 15
- Security and support process: 0 to 10
- Ecosystem and package workflow: 0 to 10
- Performance and reproducibility: 0 to 10
- Documentation quality and discoverability: 0 to 10

Total: 0 to 100
