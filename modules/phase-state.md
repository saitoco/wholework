---
type: steering
ssot_for:
  - phase-signatures
  - reconcile-json-schema
---

# phase-state

SSoT module for phase-level state definitions used by `scripts/reconcile-phase-state.sh` and `/auto` SKILL.md.

## Purpose

Define the expected preconditions and success signatures (completion state) for each phase, and specify the JSON output schema (v1) emitted by `scripts/reconcile-phase-state.sh`.

## Input

No direct inputs — this module is read-only. Callers reference this file to understand phase definitions.

## Processing Steps

### Actual State Inspection (--check-completion)

For completion checks, `reconcile-phase-state.sh` verifies whether the phase's success signature has been reached by inspecting live state (GitHub labels, PR state, git log, file existence). Returns `matches_expected: true` when the success signature is satisfied, `false` otherwise.

### Precondition Inspection (--check-precondition)

For precondition checks, `reconcile-phase-state.sh` verifies whether the required conditions are in place before a phase runs. Returns `matches_expected: true` when all preconditions are met, `false` otherwise. Default mode is `--warn-only`: mismatch exits 0 with a stderr warning rather than aborting, to tolerate GitHub API eventual consistency.

## Output

### Phase Table

| Phase | Precondition | Success Signature (Completion) | Implementation Status |
|-------|-------------|-------------------------------|----------------------|
| issue | Issue exists and state != CLOSED | `triaged` label on issue | Implemented |
| spec | `phase/issue` or `phase/spec` label on issue | `$SPEC_PATH/issue-N-*.md` exists AND `phase/(ready\|code\|review\|merge\|verify\|done)` label | Implemented |
| code-patch | `phase/ready` label on issue, Spec exists OR Size=XS | `git log origin/main --after=<reopen_ts> --grep="closes #N"` returns ≥1 fresh commit (reopen timestamp obtained via `get-last-reopen`); falls back to `git log origin/main --grep="closes #N"` when reopen timestamp unavailable; OR an operate route completion marker comment is found (see "Operate Route Completion Signature" below) | Precondition: `phase/ready` — Implemented; Spec exists OR Size=XS — Implemented (Spec exists OR Size=XS). Completion: Implemented |
| code-pr | `phase/ready` label on issue, Spec exists OR Size=XS | Open PR on `worktree-code+issue-N` branch (#310 SSoT) | Precondition: `phase/ready` — Implemented; Spec exists OR Size=XS — Implemented (Spec exists OR Size=XS). Completion: Implemented |
| review | PR is OPEN | PR has a comment containing `<!-- review-summary -->` marker (primary); or `## Review Response Summary` / `## レビュー回答サマリ` (fallback for marker-absent posts) | Implemented |
| merge | PR is OPEN and reviewDecision is APPROVED | `gh pr view --json state == MERGED` | Implemented |
| verify | Issue has `phase/verify` label or is CLOSED | Issue is CLOSED or has `phase/done` label | Implemented |

**Note**: Stage 2 recovery (push + PR creation for code-pr after watchdog kill) is delegated to #316 recovery sub-agent. `reconcile-phase-state.sh` performs inspection only — no recovery actions.

### Operate Route Completion Signature

The `code-patch` phase reuses the same completion signature for both patch route and operate route (`/code --patch` when Step 0 detects `ROUTE=operate`; see `skills/code/SKILL.md`). Operate route produces no implementation diff — Step 11's commit/push/PR block is skipped entirely — so it never emits a `closes #N` commit. Checking only the `closes #N` signature therefore misreports a successful operate route run as incomplete.

To close this gap, `_completion_code_patch()` in `scripts/reconcile-phase-state.sh` treats an operate route completion marker comment as an alternate success signature:

- **L2/L3** (external operations executed): the Issue comment posted by Step 11 begins with `<!-- wholework-event: type=execution-log phase=code issue=N -->`.
- **L1 advisory** (Execution Plan only, no operations executed): the Issue comment posted by Step 8 begins with `<!-- wholework-event: type=execution-plan phase=code issue=N -->`. L1 advisory is a normal, successful completion of `/code` (see `skills/code/SKILL.md` Step 13), so its marker is accepted as a completion signal on equal footing with the L2/L3 marker.

**Freshness gate**: identical semantics to the existing `closes #N` signature — when a reopen timestamp is available (via `get-last-reopen`), the marker comment's `createdAt` must be after it; when unavailable, no freshness constraint is applied (unbounded, same as the existing `closes #N` fallback).

**Check order**: commit (`closes #N`) → operate marker → label/state fallback (`phase/verify`/`phase/done`/`CLOSED`). The operate marker check runs before the label/state fallback so that it also applies during a fix-cycle re-run (when `reopen_ts` is non-null, the label/state fallback is unconditionally skipped — placing the operate marker check earlier lets it still catch a successful operate route re-run and prevents `run-code.sh` from re-executing the external write).

**Known limitation**: if a reopen timestamp is unavailable and an Issue's Spec is rewritten from operate route to patch route without being reopened, a stale marker from the previous operate cycle can mask a genuine patch route silent no-op. This mirrors the same-shaped limitation already present in the `closes #N` fallback (unbounded grep when no reopen timestamp is available) and is accepted for the same reason — adding asymmetric freshness handling for only one signature would introduce a new class of failure mode.

### JSON Schema (v1)

`reconcile-phase-state.sh` outputs the following JSON to stdout on every invocation:

```json
{
  "schema_version": "v1",
  "phase": "<phase-name>",
  "matches_expected": true,
  "actual": {
    "labels": ["phase/code"],
    "pr_state": "OPEN",
    "pr_number": 309,
    "commits_found": true,
    "spec_file": "docs/spec/issue-N-short-title.md",
    "issue_state": "OPEN"
  },
  "diagnosis": "Human-readable one-line description of the check result"
}
```

**Field contract (downstream #315, #316, #317, #319 depend on this schema):**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `schema_version` | string | Always | Fixed `"v1"`; increment on breaking changes |
| `phase` | string | Always | One of the 7 phase names |
| `matches_expected` | boolean | Always | `true` = state matches expected; `false` = mismatch |
| `actual` | object | Always | Phase-specific actual state; only relevant keys are included |
| `actual.labels` | string[] | When labels are checked | Current GitHub labels on the issue |
| `actual.pr_state` | string | When PR state is checked | `"OPEN"`, `"MERGED"`, `"CLOSED"`, or `null` |
| `actual.pr_number` | number\|null | When PR is checked | PR number, or `null` if not found |
| `actual.commits_found` | boolean | When git log is checked | `true` if matching commit found on origin/main |
| `actual.operate_signal` | boolean | When `code-patch` completion does not find a `closes #N` commit | `true` if an operate route completion marker comment (execution-log or execution-plan) was found; see "Operate Route Completion Signature" above |
| `actual.spec_file` | string\|null | When spec is checked | Path to spec file, or `null` if not found |
| `actual.issue_state` | string | When issue state is checked | `"OPEN"` or `"CLOSED"` |
| `actual.size` | string | When spec precondition is checked with Size check | Issue size value (e.g., `"M"`, `"XS"`, `""`) returned by `get-issue-size.sh`. Present when Spec is missing and Size check is performed. |
| `actual.hint_recent_commit` | string\|null | When phase label mismatch detected | Most recent git commit referencing the issue, or `null`. Added for phase label recovery. |
| `actual.hint_pr_state` | string\|null | When phase label mismatch detected | PR state (`"OPEN"`, `"MERGED"`, `"CLOSED"`) if found, otherwise `null`. Added for phase label recovery. |
| `diagnosis` | string | Always | One-line human-readable description |

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | `matches_expected: true` (state matches); also used in `--warn-only` mode for mismatches |
| 1 | `matches_expected: false` (mismatch) — only with `--strict` flag |
| 2 | Error (gh command failure, invalid arguments, etc.) |
