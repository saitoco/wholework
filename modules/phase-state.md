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
| code-patch | `phase/ready` label on issue, Spec exists | `git log origin/main --grep="closes #N"` returns ≥1 commit | Precondition: `phase/ready` — Implemented; Spec exists — future scope. Completion: Implemented |
| code-pr | `phase/ready` label on issue, Spec exists | Open PR on `worktree-code+issue-N` branch (#310 SSoT) | Precondition: `phase/ready` — Implemented; Spec exists — future scope. Completion: Implemented |
| review | PR is OPEN | PR has a comment containing `## Review Response Summary` | Implemented |
| merge | PR is OPEN and reviewDecision is APPROVED | `gh pr view --json state == MERGED` | Implemented |
| verify | Issue has `phase/verify` label or is CLOSED | Issue is CLOSED or has `phase/(verify\|done)` label | Implemented |

**Note**: Stage 2 recovery (push + PR creation for code-pr after watchdog kill) is delegated to #316 recovery sub-agent. `reconcile-phase-state.sh` performs inspection only — no recovery actions.

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
| `actual.spec_file` | string\|null | When spec is checked | Path to spec file, or `null` if not found |
| `actual.issue_state` | string | When issue state is checked | `"OPEN"` or `"CLOSED"` |
| `diagnosis` | string | Always | One-line human-readable description |

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | `matches_expected: true` (state matches); also used in `--warn-only` mode for mismatches |
| 1 | `matches_expected: false` (mismatch) — only with `--strict` flag |
| 2 | Error (gh command failure, invalid arguments, etc.) |
