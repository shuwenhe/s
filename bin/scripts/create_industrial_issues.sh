#!/usr/bin/env bash
set -euo pipefail

# Create industrialization issues in GitHub from the task board plan.
# Usage:
#   ./scripts/create_industrial_issues.sh
# Optional env vars:
#   REPO=owner/name      # default: current gh repo context
#   DRY_RUN=1            # print commands without creating issues

DRY_RUN="${DRY_RUN:-0}"
REPO="${REPO:-}"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command not found: $cmd" >&2
    exit 1
  fi
}

run_gh_issue_create() {
  local title="$1"
  local labels="$2"
  local assignee="$3"
  local body="$4"

  local cmd=(gh issue create --title "$title" --label "$labels" --assignee "$assignee" --body "$body")
  if [[ -n "$REPO" ]]; then
    cmd+=(--repo "$REPO")
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY_RUN: '
    printf '%q ' "${cmd[@]}"
    printf '\n'
  else
    "${cmd[@]}"
  fi
}

require_cmd gh

if ! gh auth status >/dev/null 2>&1; then
  echo "error: gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

create_issue() {
  local id="$1"
  local title="$2"
  local labels="$3"
  local assignee="$4"
  local start_date="$5"
  local due_date="$6"
  local depends_on="$7"
  local acceptance_script="$8"

  local body
  body=$(cat <<EOF
Task ID: $id
Start Date: $start_date
Due Date: $due_date
Depends On: $depends_on

Acceptance Script:
\`\`\`bash
$acceptance_script
\`\`\`

Source Docs:
- doc/industrial_task_board.md
- doc/industrial_github_issues.md
- doc/industrial_burndown_plan.md
EOF
)

  run_gh_issue_create "$title" "$labels" "$assignee" "$body"
}

create_issue "T01" "[IND][T01] Add governance baseline docs" "industrialization,governance,p0" "PL" "2026-05-01" "2026-05-04" "None" $'test -f LICENSE.md && test -f SECURITY.md && test -f CONTRIBUTING.md && test -f CHANGELOG.md\ntest -f .github/pull_request_template.md'
create_issue "T02" "[IND][T02] Publish versioning and compatibility policy" "industrialization,policy,p0" "LA" "2026-05-02" "2026-05-06" "T01" $'rg -n "compat|breaking|semver|version policy" doc README.md\nrg -n "compatibility" doc/spec.md'
create_issue "T03" "[IND][T03] Enforce mandatory CI gates on pull request" "industrialization,ci,p0" "BE" "2026-05-03" "2026-05-07" "T01" $'rg -n "pull_request" .github/workflows/compiler-ci.yml\nrg -n "smoke fuzz|reproducible build|compiler checks" .github/workflows/compiler-ci.yml'
create_issue "T04" "[IND][T04] Freeze MVP language subset" "industrialization,language-spec,p0" "LA" "2026-05-05" "2026-05-12" "T02" $'rg -n "frozen|mvp|deferred|open questions" doc/minimum_language_subset.md doc/spec.md'
create_issue "T05" "[IND][T05] Normalize CLI behavior and exit codes" "industrialization,cli,p0" "CE" "2026-05-08" "2026-05-15" "T04" $'s check /app/s/misc/examples/s/hello.s\ns build /app/s/misc/examples/s/hello.s -o /tmp/s_hello\ns run /app/s/misc/examples/s/sum.s\ns test\ns mod init demo.app && s mod tidy'
create_issue "T06" "[IND][T06] Split tests into four quality layers" "industrialization,testing,p1" "QE" "2026-05-10" "2026-05-20" "T04" $'rg -n "core-language|backend|runtime|selfhost" doc\ns test /app/s/src/cmd/compile/internal/tests/fixtures'
create_issue "T07" "[IND][T07] Add deterministic benchmark baseline" "industrialization,performance,p1" "QE" "2026-05-12" "2026-05-22" "T05" $'chmod +x scripts/benchmark-compiler.sh && ./scripts/benchmark-compiler.sh\nrg -n "threshold|regression" doc README.md'
create_issue "T08" "[IND][T08] Stabilize bootstrap stage checks" "industrialization,bootstrap,p1" "CE" "2026-05-15" "2026-05-29" "T05" $'rg -n "bootstrap" doc/bootstrap_flow.md doc/runtime_transition.md\nrg -n "bootstrap two-stage check passed" src/cmd/compile/seed/s_seed.c src/cmd/compile/seed/code/native_backend.c'
create_issue "T09" "[IND][T09] Add release workflow for tagged builds" "industrialization,release,p1" "BE" "2026-05-25" "2026-06-05" "T01,T03,T05" $'ls .github/workflows\nrg -n "release|tag|artifact|checksum" .github/workflows/*.yml'
create_issue "T10" "[IND][T10] Add security response SLA and process" "industrialization,security,p1" "SE" "2026-05-28" "2026-06-08" "T01" $'rg -n "SLA|severity|response|disclosure" SECURITY.md doc'
create_issue "T11" "[IND][T11] Define LTS and support window policy" "industrialization,support-policy,p1" "PL" "2026-06-02" "2026-06-12" "T02,T09" $'rg -n "LTS|support window|deprecation" doc README.md'
create_issue "T12" "[IND][T12] Industrial readiness review and sign-off" "industrialization,readiness,p1" "PL" "2026-06-15" "2026-06-19" "T01,T02,T03,T04,T05,T06,T07,T08,T09,T10,T11" $'rg -n "go/no-go|readiness|scorecard" doc\ntest -f doc/industrial_readiness_report.md'

echo "industrialization issue creation completed"
