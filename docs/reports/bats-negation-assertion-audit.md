# bats Negation Assertion Audit (Issue #1292)

## Purpose

Inventory all `! cmd | grep ...` negation assertions in `tests/*.bats` and classify each as
defective (non-final statement — silently defeated under `set -e`, see
`modules/test-runner.md` § "bats Negation Assertion Pitfall") or safe (true final statement of
its `@test` function). This audit is the Spec-phase investigation input for Issue #1292; the
defective entries were rewritten to the `if cmd | grep -q pattern; then false; fi` form in the
same Issue.

## Search Command and Scope

```bash
grep -rnE '^\s*!\s*.*\|\s*grep' tests/*.bats
```

Scope: all `.bats` files directly under `tests/` (116 files as of this audit). Confirmed via
`find tests -mindepth 2 -name "*.bats"` that no `.bats` files exist in subdirectories, so the
non-recursive glob `tests/*.bats` has no coverage gap.

## Judgment Criteria

For each matched line, inspect the enclosing `@test "..." { ... }` function body:

- **Defective (non-final statement)**: at least one more statement follows the negation line
  before the function's closing `}`. Under `set -e`, a negated pipeline's exit status never
  triggers automatic termination (POSIX/bash semantics for `!`), so if the pattern is found —
  the exact condition the assertion exists to catch — execution continues past it and the test
  still reports PASS.
- **Safe (true final statement)**: the negation line is the last statement before the function's
  closing `}`. bats evaluates the function's own return value directly, so the negated
  pipeline's exit status correctly determines pass/fail without an intervening `set -e`
  non-final-statement context.

## Summary

**21 matches total, across 7 files.**

| Classification | Count |
|---|---|
| Defective (non-final statement, required fix) | 9 |
| Safe (true final statement, no change) | 12 |

## Defective (non-final statement) — 9 entries, fixed in this Issue

| File:Line | Original form | Remediation |
|---|---|---|
| `tests/audit-auto-session.bats:66` | `! echo "$output" \| grep -q "Issues processed \| 2"` | Rewritten to `if ...; then false; fi` |
| `tests/get-auto-session-report.bats:32` | `! echo "$output" \| grep -q "\| #200 \|"` | Rewritten to `if ...; then false; fi` |
| `tests/get-auto-session-report.bats:70` | `! echo "$output" \| grep -q "\| #501 \|"` | Rewritten to `if ...; then false; fi` |
| `tests/filter-session-verified-issues.bats:39` | `! echo "$output" \| grep -qx "984"` | Rewritten to `if ...; then false; fi` |
| `tests/collect-recovery-candidates.bats:376` | `! echo "$output" \| grep -E $'^manual-recovery-review-rerun\t'` | Rewritten to `if ... grep -qE ...; then false; fi` (added `-q`, absent in the original) |
| `tests/reclaim-stale-worktrees.bats:90` | `! git -C "$MAIN_REPO" worktree list \| grep -q "wt1006"` | Rewritten to `if ...; then false; fi` |
| `tests/reclaim-stale-worktrees.bats:144` | `! git -C "$MAIN_REPO" worktree list \| grep -q "wt1149"` | Rewritten to `if ...; then false; fi` |
| `tests/reclaim-stale-worktrees.bats:168` | `! git -C "$MAIN_REPO" worktree list \| grep -q "wt5000"` | Rewritten to `if ...; then false; fi` |
| `tests/verify.bats:154` | `! step6_section \| grep -q -F "Re-verify even if already checked"` | Rewritten to `if ...; then false; fi` |

Except for `collect-recovery-candidates.bats:376` (missing `-q`, added to match the
`tests/collect-recovery-candidates.bats:604-605` precedent), all existing grep flags and pattern
strings were preserved unchanged — only the negation/branch structure was rewritten.

## Safe (true final statement) — 12 entries, no change

| File:Line |
|---|
| `tests/audit-auto-session.bats:46` |
| `tests/audit-auto-session.bats:103` |
| `tests/get-auto-session-report.bats:71` |
| `tests/get-auto-session-report.bats:199` |
| `tests/collect-recovery-candidates.bats:460` |
| `tests/collect-recovery-candidates.bats:611` |
| `tests/reclaim-stale-worktrees.bats:91` |
| `tests/reclaim-stale-worktrees.bats:145` |
| `tests/reclaim-stale-worktrees.bats:181` |
| `tests/reclaim-stale-worktrees.bats:206` |
| `tests/triage-backlog-filter.bats:52` |
| `tests/triage-backlog-filter.bats:130` |

These lines are each the true final statement of their enclosing `@test` function, so bats
evaluates the function's own return value directly — no `set -e` non-final-statement exception
applies, and no rewrite is needed.

## Out of Scope

Bare `!` negations without a `| grep` pipeline (e.g. `tests/reclaim-stale-worktrees.bats:136,159`
`! git branch -d ... 2>/dev/null`) can be subject to the same `set -e` exception rule, but Issue
#1292 explicitly scopes its target pattern to `! ... | grep` form. These are noted for reference
only and are not covered by this audit's remediation.

## Remediation Record

All 9 defective entries were rewritten to the `if cmd | grep -q pattern; then false; fi` form in
this Issue's implementation commit. The 12 safe entries were left unchanged. Post-remediation,
`bats tests/` was re-run to confirm the rewritten assertions preserve existing pass/fail
behavior (see Issue #1292 Code Retrospective for the run result).
