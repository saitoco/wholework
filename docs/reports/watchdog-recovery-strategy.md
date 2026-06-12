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

## Fable 5 long-turn findings

**Date**: 2026-06-13
**Issue**: #556

### Spike methodology

Short-form spike using the alternative method (small `WATCHDOG_TIMEOUT` for accelerated measurement):

```bash
# Prompt 1 — simple (one-sentence answer)
WATCHDOG_TIMEOUT=120 WATCHDOG_HEARTBEAT_INTERVAL=10 \
  bash scripts/claude-watchdog.sh claude -p --model claude-fable-5 \
  "In 2-3 sentences, explain what a watchdog timer is in systems programming."

# Prompt 2 — analytical (multi-paragraph trade-off analysis)
WATCHDOG_TIMEOUT=180 WATCHDOG_HEARTBEAT_INTERVAL=10 \
  bash scripts/claude-watchdog.sh claude -p --model claude-fable-5 \
  "Analyze the trade-offs between using a 1800-second watchdog timeout vs a 2700-second timeout \
for a CI/CD automation system. Consider: false positive kills, true hang detection latency, \
and operational impact."
```

### Findings

1. **Narration reaches stdout**: YES — Fable 5's final response text streams to stdout once thinking completes, resetting the watchdog. However, **intermediate narration does NOT stream during thinking** — the silent window persists until the full response begins.
2. **Max silent window observed**:
   - Simple task: < 10s (output arrived before the first heartbeat interval)
   - Analytical/multi-paragraph task: ~120s (12 heartbeat ticks at 10s each before any output)
3. **Extrapolation for hard production tasks**: Spec design, PR body composition, and review synthesis are significantly heavier than the spike prompts. Based on the known Sonnet incident (Issue #308: PR body composition exceeded 1800s) and Fable 5's longer-horizon thinking, hard-task silent windows of 600–2000s are plausible in `/auto` runs.

### Decision: Raise `WATCHDOG_TIMEOUT_DEFAULT` 1800 → 2700

**Rationale**: The spike confirms that intermediate narration does not reliably interrupt the silent window (narration only arrives at the end of a response, not during thinking). Combined with the known Sonnet incident (#308) where 1800s was already insufficient, and Fable 5's longer per-request thinking horizon, the current default produces spurious kills on hard tasks. Raising to 2700 absorbs the observed tail risk with bounded downside (+15 min max detection lag for true hangs).

**Why 2700 and not higher**: `watchdog-recovery-strategy.md §Why not Approach A alone` already explains the principle: timeout extension delays the kill but does not prevent it on very long thinking. The threshold is set by the multi-layer mitigation stack, not by the timeout alone:

- **Layer 1 (prevention)**: `WATCHDOG_TIMEOUT_DEFAULT=2700` absorbs observed silent windows up to ~2700s.
- **Layer 2 (prevention)**: Progress echoes added to `skills/spec/SKILL.md` (before Spec file write, Step 10) and `skills/review/SKILL.md` (before review result posting, Step 11) structurally break long silent windows by emitting at least one stdout line before each I/O-bound operation.
- **Layer 3 (recovery)**: Reconcile Stage 2 (Approach C) handles the "commits done, push not yet run" intermediate state.
- **Escape hatch**: `.wholework.yml` `watchdog-timeout-seconds` remains available for per-project tuning.

### Follow-up

- [ ] Monitor Fable 5 `/auto` runs post-merge to confirm spurious kills stop (post-merge AC for Issue #556)
- [ ] If hard-task silent windows grow beyond 2700s in practice, raise to 3600 and extend progress echoes further
