# bats Negation Assertion Audit (Issues #1292, #1304)

## Purpose

Inventory all `!`-prefixed negation assertions in `tests/*.bats` — piped (`! cmd | grep ...`),
non-piped (`! grep -q pattern file`), and bare (`! cmd`, no `grep` at all) — and classify each as
defective (non-final statement — silently defeated under `set -e`, see
`modules/test-runner.md` § "bats Negation Assertion Pitfall") or safe (true final statement of
its `@test` function). Issue #1292 covered the piped form (9 defective entries fixed). Issue
#1304 covered the two remaining forms — non-piped + `grep` (26 defective) and bare `!` (2
defective) — closing the pipe-scoped gap `modules/test-runner.md` left in #1292 (see `## Scope —
the pipe is irrelevant` there). All defective entries across both Issues were rewritten to the
`if cmd; then false; fi` form in their respective implementation commits.

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

## Non-Piped Form Audit (Issue #1304)

### Search Command and Scope

```bash
grep -rnE '^\s*!\s*.*grep' tests/*.bats | grep -vE '\|\s*grep'
```

**Measurement scope** (`modules/measurement-scope.md`): 2026-08-09, `HEAD=f4d8fe6d`, scoped to
`tests/*.bats` directly (non-recursive glob; #1292 confirmed via `find tests -mindepth 2 -name
"*.bats"` that no `.bats` files exist in subdirectories, so there is no coverage gap).

### Summary

**76 matches total, across 21 files** — 26 defective, 50 safe. (#1292's `## Out of Scope` recorded
this as "roughly 30 files" — a visual estimate; the actual measured file count is 21. The match
count of 76 was accurate.)

| Classification | Count |
|---|---|
| Defective (non-final statement, required fix) | 26 |
| Safe (true final statement, no change) | 50 |

### Defective (non-final statement) — 26 entries, fixed in this Issue

| File:Line | Original form | Remediation |
|---|---|---|
| `tests/ci-failure-classifier.bats:30` | `! grep -q "The runner has received a shutdown signal" "$VERIFY_SKILL"` | Rewritten to `if ...; then false; fi` |
| `tests/ci-failure-classifier.bats:35` | `! grep -q "The runner has received a shutdown signal" "$VERIFY_EXECUTOR"` | Rewritten to `if ...; then false; fi` |
| `tests/gh-graphql.bats:69` | `! grep -q "repo view" "$GH_CALL_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/gh-graphql.bats:240` | `! grep -q "api graphql" "$GH_CALL_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/gh-graphql.bats:242` | `! grep -q "repo view" "$GH_CALL_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/gh-graphql.bats:286` | `! grep -q "repo view" "$GH_CALL_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/gh-graphql.bats:333` | `! grep -q "api graphql" "$GH_CALL_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/observation-trigger.bats:76` | `! grep -q "issue comment" "$BATS_TEST_TMPDIR/gh-calls.log"` (inside `if ... fi`) | Restructured to `if [ -f ... ] && grep -q ...; then false; fi` (only entry not a 1-line replacement — the enclosing `if` guard is folded into the condition) |
| `tests/observation-trigger.bats:198` | `! grep -q "issue comment" "$BATS_TEST_TMPDIR/gh-calls.log"` | Rewritten to `if ...; then false; fi` |
| `tests/opportunistic-search.bats:513` | `! grep -q -- "--session\|--facts-file" "$MOCK_DIR/collect-run-facts-args.txt"` | Rewritten to `if ...; then false; fi` |
| `tests/orchestration-fallbacks.bats:92` | `! grep -q '^## ci-flake-retry' "$CATALOG"` | Rewritten to `if ...; then false; fi` |
| `tests/retro-proposals.bats:149` | `! grep -q "/Users/" "$GH_CALLS_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/run-code.bats:470` | `! grep -q "phase_start" "$EMIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/run-issue.bats:306` | `! grep -q "phase_start" "$EMIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/run-issue.bats:339` | `! grep -q "wrapper_exit" "$EMIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/run-merge.bats:757` | `! grep -q "phase_start" "$EMIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/run-review.bats:776` | `! grep -q "phase_start" "$EMIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/run-spec.bats:393` | `! grep -q "phase_start" "$EMIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/run-spec.bats:428` | `! grep -q "wrapper_exit" "$EMIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/worktree-merge-push.bats:212` | `! grep -q -- "-C ${WORKTREE_PATH} rebase origin/main" "$GIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/worktree-merge-push.bats:313` | `! grep -q "merge test-branch --ff-only" "$GIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/worktree-merge-push.bats:387` | `! grep -q "merge test-branch --ff-only" "$GIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/worktree-merge-push.bats:388` | `! grep -qE "^rebase " "$GIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/worktree-merge-push.bats:465` | `! grep -qE "^rebase origin/main" "$GIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/worktree-merge-push.bats:623` | `! grep -q "rebase origin/main" "$GIT_LOG"` | Rewritten to `if ...; then false; fi` |
| `tests/worktree-merge-push.bats:624` | `! grep -qE "\-C .+ rebase" "$GIT_LOG"` | Rewritten to `if ...; then false; fi` |

All existing grep flags and pattern strings were preserved unchanged — only the negation/branch
structure was rewritten (the observation-trigger.bats:76 restructure above is the sole exception,
and it too preserves the original `grep` flags and pattern verbatim).

### Safe (true final statement) — 50 entries, no change

| File:Line |
|---|
| `tests/append-consumed-comments-section.bats:248` |
| `tests/auto-recovery.bats:143` |
| `tests/claude-watchdog.bats:118` |
| `tests/claude-watchdog.bats:133` |
| `tests/observation-trigger.bats:127` |
| `tests/observation-trigger.bats:141` |
| `tests/observation-trigger.bats:155` |
| `tests/observation-trigger.bats:175` |
| `tests/orchestration-fallbacks.bats:93` |
| `tests/post-fallback-review-summary.bats:42` |
| `tests/post-fallback-review-summary.bats:113` |
| `tests/post-fallback-review-summary.bats:165` |
| `tests/retro-proposals.bats:142` |
| `tests/run-auto-sub.bats:585` |
| `tests/run-auto-sub.bats:883` |
| `tests/run-auto-sub.bats:1325` |
| `tests/run-auto-sub.bats:1374` |
| `tests/run-auto-sub.bats:1413` |
| `tests/run-auto-sub.bats:1527` |
| `tests/run-auto-sub.bats:1725` |
| `tests/run-auto-sub.bats:1988` |
| `tests/run-auto-sub.bats:2220` |
| `tests/run-code.bats:400` |
| `tests/run-code.bats:471` |
| `tests/run-issue.bats:236` |
| `tests/run-issue.bats:307` |
| `tests/run-issue.bats:340` |
| `tests/run-merge.bats:328` |
| `tests/run-merge.bats:415` |
| `tests/run-merge.bats:729` |
| `tests/run-merge.bats:758` |
| `tests/run-review.bats:563` |
| `tests/run-review.bats:748` |
| `tests/run-review.bats:777` |
| `tests/run-spec.bats:206` |
| `tests/run-spec.bats:283` |
| `tests/run-spec.bats:394` |
| `tests/run-spec.bats:429` |
| `tests/spawn-recovery-subagent.bats:142` |
| `tests/verify-executor.bats:24` |
| `tests/verify-executor.bats:37` |
| `tests/verify-executor.bats:57` |
| `tests/verify.bats:128` |
| `tests/wait-ci-checks.bats:368` |
| `tests/worktree-merge-push.bats:132` |
| `tests/worktree-merge-push.bats:162` |
| `tests/worktree-merge-push.bats:258` |
| `tests/worktree-merge-push.bats:355` |
| `tests/worktree-merge-push.bats:389` |
| `tests/worktree-merge-push.bats:670` |

These lines are each the true final statement of their enclosing `@test` function — no rewrite is
needed.

## Bare Negation Audit (Issue #1304)

### Search Command and Scope

```bash
grep -rnE '^\s*!\s' tests/*.bats | grep -v grep
```

Same measurement scope as the Non-Piped Form Audit above (2026-08-09, `HEAD=f4d8fe6d`).

### Summary

**2 matches total, across 1 file** — 2 defective, 0 safe.

| File:Line | Original form | Remediation |
|---|---|---|
| `tests/reclaim-stale-worktrees.bats:136` | `! git -C "$MAIN_REPO" branch -d worktree-code+pr-1149 2>/dev/null` | Rewritten to `if ...; then false; fi` |
| `tests/reclaim-stale-worktrees.bats:159` | `! git -C "$MAIN_REPO" branch -d worktree-code+issue-5000 2>/dev/null` | Rewritten to `if ...; then false; fi` |

Both entries immediately follow a `# sanity: plain -d must fail` comment (an explicit, intentional
assertion — not a case of deliberately-allowed failure) and are non-final statements within their
`@test` function, making them defective by the same criterion as the piped and non-piped forms
above. The preceding comment was left unchanged.

## Out of Scope

Issue #1292 explicitly scoped its target pattern to the `! cmd | grep -q ...` piped form, leaving
two related patterns — subject to the same `set -e` non-final-statement exception rule documented
in `modules/test-runner.md` — outside that audit's search command and remediation:

- **Bare `!` negations without any `grep`** (e.g. `tests/reclaim-stale-worktrees.bats:136,159`
  `! git branch -d ... 2>/dev/null`).
- **`! grep -q pattern file` without a pipe** (grep reading a file directly, rather than via a
  piped `echo`/command output).

Issue #1304 closed both gaps: see `## Non-Piped Form Audit (Issue #1304)` (76 candidates, 26
defective) and `## Bare Negation Audit (Issue #1304)` (2 candidates, 2 defective) above. Combined
with #1292's piped-form audit, the full breakdown of every `tests/*.bats` leading-`!` negation is
now accounted for (counts below are measured pre-remediation for each Issue's own scope — the
piped-form column reflects the 12 matches remaining after #1292's 9 defective entries were already
rewritten, since a rewritten entry no longer matches the `!`-prefixed search pattern):

| Category | Count | Defective | Safe |
|---|---|---|---|
| Piped (`! cmd \| grep ...`) | 12 | 0 (9 fixed in #1292, no longer match this pattern) | 12 |
| Non-piped + grep (`! grep -q pattern file`) | 76 | 26 | 50 |
| Bare (`! cmd`, no grep) | 2 | 2 | 0 |
| **Total** | **90** | **28** | **62** |

Every category above has now been audited and remediated. There is no remaining out-of-scope
category — this section is retained (heading only) as a historical record of #1292's original
scope boundary and the two gaps #1304 subsequently closed.

## Remediation Record

### Issue #1292 (piped form)

All 9 defective entries were rewritten to the `if cmd | grep -q pattern; then false; fi` form in
this Issue's implementation commit. The 12 safe entries were left unchanged. Post-remediation,
`bats tests/` was re-run to confirm the rewritten assertions preserve existing pass/fail
behavior (see Issue #1292 Code Retrospective for the run result).

### Issue #1304 (non-piped and bare forms)

All 28 defective entries — 26 from `## Non-Piped Form Audit (Issue #1304)` and 2 from
`## Bare Negation Audit (Issue #1304)` — were rewritten to the `if cmd; then false; fi` form (or,
for `tests/observation-trigger.bats:76`, the equivalent `if ... && cmd; then false; fi` structural
form, the only entry that isn't a 1-line replacement) in this Issue's implementation commit. The
50 non-piped safe entries and the 12 piped safe entries were left unchanged. Existing `grep`
flags and pattern strings were preserved verbatim throughout — only the negation/branch structure
changed. Per-file remediation:

| File | Lines rewritten |
|---|---|
| `tests/ci-failure-classifier.bats` | 30, 35 |
| `tests/gh-graphql.bats` | 69, 240, 242, 286, 333 |
| `tests/observation-trigger.bats` | 76, 198 |
| `tests/opportunistic-search.bats` | 513 |
| `tests/orchestration-fallbacks.bats` | 92 |
| `tests/retro-proposals.bats` | 149 |
| `tests/run-code.bats` | 470 |
| `tests/run-issue.bats` | 306, 339 |
| `tests/run-merge.bats` | 757 |
| `tests/run-review.bats` | 776 |
| `tests/run-spec.bats` | 393, 428 |
| `tests/worktree-merge-push.bats` | 212, 313, 387, 388, 465, 623, 624 |
| `tests/reclaim-stale-worktrees.bats` | 136, 159 (bare form) |

Post-remediation, `bats --jobs <N> tests/` was re-run to confirm the newly-activated assertions
pass (see Issue #1304 Code Retrospective for the run result and handling of any assertions that
were found to have been masking a real defect).
