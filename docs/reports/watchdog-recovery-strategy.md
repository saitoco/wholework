# Watchdog Recovery Strategy

**Report date**: 2026-04-21
**Issue**: #308
**Scope**: watchdog recovery strategy — preventing and recovering from watchdog kill during code phase

## Background

During a `/auto` execution for Issue #303, the `claude-watchdog.sh` process killed `run-code.sh` after 1800 seconds of no stdout output. The implementation and commits were already complete, but push and PR creation had not yet occurred. Because `watchdog-reconcile.sh` determines code phase completion solely by whether an open PR exists, the partial completion state caused the reconcile to fail with exit 143, requiring manual recovery.

Two independent problems compound this issue:

1. **Prevention gap**: The code skill emits no stdout during long-thinking phases (e.g., composing a PR body). When thinking exceeds 1800s, watchdog kills the process.
2. **Recovery gap**: `_reconcile_code_pr` checks only for an open PR. The intermediate state of "commits done, push/PR not yet created" is not recoverable by the reconcile.

## Approach Comparison

| Approach | Description | Pros | Cons |
|----------|-------------|------|------|
| **A** — Timeout extension | Increase `WATCHDOG_TIMEOUT_SECONDS` default from 1800s to 2700s or 3600s | Simple implementation; absorbs Sonnet long-thinking | Increases detection lag for true hangs; treats symptom not cause |
| **B** — Liveness signal improvement | Detect CPU usage (`pidstat`) to distinguish "thinking" from "fully hung" | Kills only true hangs; tolerates long-thinking | macOS/Linux portability issues; threshold design is difficult; CPU activity is not a reliable thinking proxy |
| **C** — Reconcile strengthening | Add Stage 2 to `_reconcile_code_pr`: detect "worktree with implementation commits" and perform push + PR creation | Directly addresses the recovery gap; works within existing watchdog constraints; turns partial completions into recoverable states | Adds a new code path handling the intermediate "commits done, no push" state; risk of pushing partial work if mid-commit state is misidentified |
| **D** — Progress echo in SKILL.md | Add explicit `echo "progress: ..."` output before `git push` and `gh pr create` in skills/code/SKILL.md | Simple; no watchdog behavior change; narrows the silent window around the most expensive operations | Carpentry-level fix; similar mitigations needed throughout the skill if other long-silent sections exist |

## Adopted Strategy: Approach D + Approach C

The two adopted approaches are complementary:

- **Approach D (Prevention)**: Add progress echo statements in `skills/code/SKILL.md` immediately before `git push` and `gh pr create`. This narrows the silent window specifically around the operations most likely to be preceded by long thinking (PR body composition). The watchdog has a much smaller window to fire after the most expensive thinking completes.

- **Approach C (Recovery)**: Strengthen `_reconcile_code_pr` in `scripts/watchdog-reconcile.sh` with a Stage 2 check. If Stage 1 (open PR exists) fails, Stage 2 inspects the worktree directory for the issue's branch. If the branch exists and contains a commit with `closes #N`, it performs push + PR creation automatically, then returns success. This converts the "partial completion" state into a recoverable one without manual intervention.

### Why not Approach A alone

Approach A increases the silence tolerance window but does not prevent the kill — it only delays it. A 3600s timeout would still fire during a sufficiently long thinking session. It also doubles the time to detect a genuine hang. Approach A remains available as a per-project tuning knob via the existing `watchdog-timeout-seconds` configuration in `.wholework.yml`.

### Why not Approach B

CPU-based liveness detection introduces platform portability complexity (macOS vs. Linux `pidstat` availability) and threshold calibration difficulties. Claude's thinking process may produce irregular CPU patterns. The risk-to-benefit ratio does not justify adoption at this time.

## Implementation Summary

### Approach D: SKILL.md changes (`skills/code/SKILL.md`)

In Step 12 (pr route `git push origin HEAD`), add before the push:
```
echo "progress: Pushing branch to origin for issue #$NUMBER..."
```

In Step 11 (pr route `gh pr create`), add before the PR creation:
```
echo "progress: Creating PR for issue #$NUMBER..."
```

These echo statements ensure at least one stdout line is emitted after the longest-thinking phase (PR body composition) and before the I/O-bound operations. The watchdog resets its silence counter on any stdout.

### Approach C: watchdog-reconcile.sh changes

`_reconcile_code_pr` gains a Stage 2 block:

1. Locate the worktree via `_find_code_worktree`: searches `.claude/worktrees/code+issue-${ISSUE_NUMBER}` first (run-code.sh naming), then `.claude/worktrees/issue-${ISSUE_NUMBER}-*` (SKILL.md pr-route naming)
2. If found and `git -C <dir> log --oneline` contains a line matching `closes #${ISSUE_NUMBER}`:
   - Run `git -C <dir> push origin HEAD`
   - Detect the actual branch name via `git -C <dir> rev-parse --abbrev-ref HEAD`
   - Run `gh pr create --head "<branch>" --base main --title "(watchdog recovery) Issue #${ISSUE_NUMBER}" --body "Auto-created by watchdog-reconcile after watchdog kill."`
   - On success: return 0 (reconciled)
   - On failure: return 1 (exit 143 continues)
3. If the directory does not exist or no matching commit is found: fall through to existing exit 143 behavior

Stage 1 also checks both naming patterns: `issue-${ISSUE_NUMBER}-*` and `code+issue-${ISSUE_NUMBER}` to maintain symmetry with `_find_code_worktree`.

Safety note: Stage 2 only acts when a commit already contains `closes #N`, meaning the LLM completed its implementation intent. This minimizes the risk of pushing partial work.
