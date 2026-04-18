# Sonnet Effort Recalibration Report

**Report date**: 2026-04-18
**Issue**: #229
**Scope**: `run-code.sh`, `run-review.sh`, `run-merge.sh`, `run-verify.sh`, `run-issue.sh`
**Status**: Final — all settings confirmed as appropriately calibrated

## Background

The five Sonnet-based `run-*.sh` scripts carry fixed `--effort` flags (`high`, `medium`, or `low`).
These settings were established incrementally without a systematic review of whether each phase's
workload justifies its assigned effort level.

The `xhigh` effort level (Opus 4.7 recommended default) is unavailable for Sonnet; this report
therefore evaluates only `low / medium / high` for the five Sonnet scripts.
`run-spec.sh` (Opus / `xhigh` path) is outside this scope — see Issue #217.

This review is independent of the Opus 4.7 recalibration work in `docs/reports/claude-opus-4-7-optimization-strategy.md`.

## Current Configuration

| Script | Model | Effort | Primary task |
|--------|-------|--------|--------------|
| `run-code.sh` | Sonnet | high | Spec-driven implementation + PR/patch creation |
| `run-review.sh` | Sonnet | high | Review orchestration (sub-agents: Opus) |
| `run-merge.sh` | Sonnet | low | PR merge decision + conflict resolution |
| `run-verify.sh` | Sonnet | medium | Acceptance condition verification + AI retrospective |
| `run-issue.sh` | Sonnet | high | Issue triage + refinement (sub-agents for L/XL: Opus) |

## Workload Analysis

### run-code.sh — `high`

The code phase executes 14 distinct steps: worktree entry, spec loading, uncertainty resolution,
steering document review, implementation, test execution, verify command consistency check,
commit/push or PR creation, retrospective writing, and worktree exit.

Each step involves multi-file reads, edit decisions, and conditional branching. `high` effort
allows the model to reason through ambiguous implementation choices, detect spec gaps, and select
correct file placement — all decisions that compound across the lifecycle if wrong.

**Time/cost/quality tradeoff**: At `medium`, shallow reasoning in early steps tends to cause
rework in later steps, increasing total wall-clock time despite lower per-token cost. `high` is
justified to minimize cumulative rework.

### run-review.sh — `high`

The review orchestrator waits for CI checks, then launches `review-spec` (Opus) and `review-bug`
(Opus) as parallel sub-agents. Per `docs/tech.md`, effort is inherited by sub-agents from their
parent invocation. Downgrading the orchestrator from `high` to `medium` would therefore reduce
sub-agent effort, directly affecting bug detection and spec compliance accuracy.

**Key constraint**: Sub-agent effort inheritance makes the orchestrator's effort level a shared
ceiling for all sub-agents in the review phase. `high` must be maintained to preserve the current
quality level of `review-bug` (Opus) and `review-spec` (Opus).

**Time/cost/quality tradeoff**: Review is run once per PR. The absolute cost of one `high`-effort
review session is low relative to the cost of a missed bug reaching `phase/verify`.

### run-merge.sh — `low`

The merge phase performs a deterministic sequence: fetch PR metadata, read review verdict, decide
approve-or-reject, and execute `gh pr merge`. Each decision is structurally constrained: the
skill reads explicit review output and applies a fixed rule set.

Conflict resolution is the one non-mechanical sub-task. However, conflicts in this workflow are
rare (worktrees isolate branches; most PRs target `main` with minimal cross-file overlap), and
when they occur the resolution path is still structurally guided by git conflict markers.

`low` effort under Sonnet means the model executes what is literally required without exploring
alternatives — which is exactly what a deterministic merge decision should do. `medium` would add
cost without improving correctness for the primary path; `high` would risk overthinking a
mechanical operation.

**Time/cost/quality tradeoff**: `low` is well-matched to merge's deterministic nature. If
conflict resolution failure rates become observable, upgrading to `medium` is the appropriate
next step (tracked as "Requires Observation" in §Notes).

### run-verify.sh — `medium`

The verify phase runs structured verify commands (`file_exists`, `section_contains`,
`github_check`) against a fixed rule set derived from Issue acceptance conditions, then writes an
AI retrospective.

Verify command execution is mechanical and pattern-driven; `low` effort would suffice for
command dispatch alone. However, the AI retrospective (lessons learned, drift analysis, follow-up
issue creation) benefits from moderate reasoning depth. `medium` balances both sub-tasks well.

`high` would add meaningful cost for a phase where the primary value driver is retrospective
quality, which is already adequate at `medium`. `low` would risk inadequate retrospective depth.

**Time/cost/quality tradeoff**: `medium` is the well-calibrated midpoint for a phase that
combines structured mechanical work with moderate analytical output.

### run-issue.sh — `high`

The issue phase performs triage (Type/Size/Priority/Value assignment) and Issue body refinement.
For L/XL Issues, it spawns three parallel Opus sub-agents (`issue-scope`, `issue-risk`,
`issue-precedent`) — their effort is inherited from the orchestrator.

Issue quality is foundational: errors in scope definition, acceptance conditions, or size
estimation propagate through spec → code → review → verify. A poorly triaged Issue multiplies
cost across all subsequent phases.

For XS/S/M Issues the orchestrator itself performs the triage without sub-agents; `high` effort
is needed for accurate size/scope assessment. For L/XL, `high` must be maintained to preserve
sub-agent accuracy (same inheritance constraint as `run-review.sh`).

**Time/cost/quality tradeoff**: Issue triage is infrequent relative to code/review cycles.
The cost of one `high`-effort triage session is negligible compared to the downstream cost of
a misclassified Issue.

## Recommendations

All five scripts are confirmed to be appropriately calibrated. No effort changes are recommended.

| Script | Current | Recommendation | Rationale |
|--------|---------|----------------|-----------|
| `run-code.sh` | `high` | **Maintain** | 14-step implementation requires sustained reasoning depth. |
| `run-review.sh` | `high` | **Maintain** | Sub-agent effort inheritance: downgrade would reduce Opus sub-agent accuracy. |
| `run-merge.sh` | `low` | **Maintain** | Deterministic merge logic; `low` prevents overthinking. Conflict escalation: see Notes. |
| `run-verify.sh` | `medium` | **Maintain** | Balanced for structured command execution + moderate retrospective depth. |
| `run-issue.sh` | `high` | **Maintain** | Issue quality is foundational; sub-agent effort inheritance applies. |

## Notes

### Requires Observation

- **`run-merge.sh` conflict resolution**: If conflict resolution failure rates become observable
  in production (conflicts not resolved or incorrectly resolved), upgrading to `medium` is the
  recommended corrective action. Current evidence does not justify preemptive upgrade.
- **`run-verify.sh` retrospective depth**: If retrospective output quality is found insufficient
  for learning purposes across multiple verify cycles, upgrading to `high` is the candidate fix.
  Current output quality is adequate.

### Out of Scope

- `run-spec.sh`: Opus / `xhigh` path — handled in Issue #217.
- `xhigh` for Sonnet: Not available; excluded from all recommendations.
- Quantitative benchmarks (token counts, wall-clock time): Tracked in Issue #226
  (Opus 4.7 vs 4.6 benchmark). This report uses workload-based qualitative analysis only.
- Advisor strategy (`advisor_20260301`): Not yet implemented in `run-*.sh`; tracked as a
  follow-up in `docs/tech.md` §Effort optimization strategy Axis 3.

### Relationship to docs/tech.md Matrix

The Phase-specific model and effort matrix in `docs/tech.md` is the SSoT for all model/effort
settings. No matrix updates are needed as a result of this report (all settings confirmed
unchanged). Future changes to any `run-*.sh` effort level must update the matrix in the same PR.
