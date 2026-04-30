# Industrialization Burndown Plan

Program window:
- Start: 2026-05-01
- End: 2026-07-24

Scope baseline:
- Total tasks: 12
- Task IDs: T01 to T12

## Weekly Burndown Targets

| Week | Date Range | Planned Done by End of Week | Planned Remaining | Key Focus |
|---|---|---:|---:|---|
| W1 | 2026-05-01 to 2026-05-07 | 3 | 9 | Governance and CI gates (T01 T02 T03) |
| W2 | 2026-05-08 to 2026-05-14 | 5 | 7 | Freeze MVP and normalize CLI (T04 T05) |
| W3 | 2026-05-15 to 2026-05-21 | 6 | 6 | Test layering rollout start (T06) |
| W4 | 2026-05-22 to 2026-05-28 | 8 | 4 | Benchmark baseline and bootstrap stability (T07 T08) |
| W5 | 2026-05-29 to 2026-06-04 | 9 | 3 | Tagged release workflow (T09) |
| W6 | 2026-06-05 to 2026-06-11 | 11 | 1 | Security SLA and LTS policy (T10 T11) |
| W7 | 2026-06-12 to 2026-06-19 | 12 | 0 | Final readiness review sign-off (T12) |

## Suggested Daily Tracking Format

Use one row per day.

| Date | Planned Done | Actual Done | Delta | Blockers | Risk Level | Actions |
|---|---:|---:|---:|---|---|---|
| YYYY-MM-DD | 0 | 0 | 0 | None | low | None |

Delta formula:
- Delta = Actual Done minus Planned Done
- Negative means behind plan.

## Burnup and Burndown Calculation

Variables:
- total_scope = 12
- completed = number of tasks with Done status
- remaining = total_scope - completed

Commands:
```bash
# Example checklist status source file:
# doc/industrial_task_status.csv with columns: task_id,status
# status values: todo,in_progress,done

awk -F, 'NR>1 && $2=="done" {c++} END {print c+0}' doc/industrial_task_status.csv

awk -F, 'BEGIN{total=12} NR>1 && $2=="done" {c++} END {print total-(c+0)}' doc/industrial_task_status.csv
```

## Risk Thresholds

- Green: remaining is on or below weekly target.
- Yellow: remaining exceeds weekly target by 1 task.
- Red: remaining exceeds weekly target by 2 or more tasks.

Escalation rule:
- Two consecutive yellow weeks triggers scope triage meeting.
- Any red week triggers blocker review within 24 hours.

## Weekly Review Checklist

- Confirm completed tasks with evidence links.
- Compare actual remaining to planned remaining.
- Re-estimate tasks in progress.
- Record scope changes and owner approvals.
- Update next week mitigation actions.

## Evidence Requirements Per Completed Task

For each task marked done, attach:
- Link to merged pull request.
- Output of acceptance script.
- One short note describing residual risk.

## Minimal Status File Template

Create doc/industrial_task_status.csv and update daily.

```csv
task_id,status,owner,start_date,due_date
T01,todo,PL,2026-05-01,2026-05-04
T02,todo,LA,2026-05-02,2026-05-06
T03,todo,BE,2026-05-03,2026-05-07
T04,todo,LA,2026-05-05,2026-05-12
T05,todo,CE,2026-05-08,2026-05-15
T06,todo,QE,2026-05-10,2026-05-20
T07,todo,QE,2026-05-12,2026-05-22
T08,todo,CE,2026-05-15,2026-05-29
T09,todo,BE,2026-05-25,2026-06-05
T10,todo,SE,2026-05-28,2026-06-08
T11,todo,PL,2026-06-02,2026-06-12
T12,todo,PL,2026-06-15,2026-06-19
```
