---
type: report
description: Cross-Issue orchestration recovery log. Append-only. Newest entries first.
---

# Orchestration Recovery Log

This file records cross-Issue recovery events, fallback applications, and diagnostics from `/auto` orchestration.

## Purpose and Role Division

**This file (orchestration-recoveries.md):**
- Scope: cross-Issue, persistent
- Role: Append-only log of symptom → recovery → outcome for recurrence detection
- Consumed by: `/audit recoveries` for frequency-based candidate detection

**Spec retrospective (per-Issue `docs/spec/issue-N-*.md`):**
- Scope: per-Issue, disposable (Spec-first principle)
- Role: Implementation-phase record of anomalies and improvement proposals
- These files are not long-term storage for cross-Issue knowledge

## Entry Format

```markdown
## YYYY-MM-DD HH:MM UTC: <symptom-short>

### Context
- Issue #N, phase: <code-pr|code-patch|review|merge|verify>
- Source: <fallback-catalog|recovery-sub-agent|wrapper-anomaly-detector>
- Wrapper: <run-*.sh name>, exit code: <N>
- Log tail: "<last relevant log line>"

### Diagnosis
- <observed state inspection result and root cause hypothesis>

### Recovery Applied
- <catalog anchor (e.g., orchestration-fallbacks.md#anchor) or sub-agent plan excerpt or manual steps>

### Outcome
- <success|partial|failed>

### Improvement Candidate
- <未起票|起票済み #NNN|N/A (resolved by known catalog)>
```

## Field Definitions

| Field | Description |
|-------|-------------|
| `symptom-short` | Short identifier for the symptom pattern (kebab-case, used for frequency grouping) |
| `Source` | Which mechanism detected and handled this recovery event |
| `Outcome` | `success` = phase completed; `partial` = partial recovery; `failed` = stopped |
| `Improvement Candidate` | `未起票` = not yet filed; `起票済み #NNN` = filed as Issue #NNN; `N/A` = no action needed |

## Sources

| Source | Description | Dependency |
|--------|-------------|------------|
| `fallback-catalog` | Known pattern in `orchestration-fallbacks.md` was matched and applied | Available (#315 shipped) |
| `wrapper-anomaly-detector` | `detect-wrapper-anomaly.sh` detected a known failure pattern | Available (#313 shipped) |
| `recovery-sub-agent` | `orchestration-recovery` sub-agent diagnosed unknown failure | Dependent on #316 shipping |

---

<!-- Log entries appear below, newest first. -->

## 2026-06-03 16:15 UTC: verify worktree FF merge failed (concurrent push advanced base)

### Context
- Issue #505, phase: verify (Step 13 worktree exit, merge-to-main)
- Source: fallback-catalog
- Wrapper: worktree-merge-push.sh, exit code: 128
- Log tail: "fatal: Not possible to fast-forward, aborting."

### Diagnosis
- A concurrent /auto run pushed #517's verify retrospective (`f305822`) to origin/main while the #505 verify worktree (branched from `0a33f9e`) was active. Local/remote main advanced one commit ahead of the worktree branch, so the worktree branch was no longer an ancestor of base. The `ff-only-merge-fallback` (`git pull --rebase origin main`) only syncs the local base to remote — it does not rebase the worktree branch onto an advanced base — so it could not resolve the divergence (`git merge-base --is-ancestor main <branch>` → NO).

### Recovery Applied
- Consulted `modules/orchestration-fallbacks.md#ff-only-merge-fallback`; its steps did not cover the worktree-branch-behind-base case. Changed files were on a different Spec (#505 vs #517) and non-conflicting, so the parent session cherry-picked the single retrospective commit onto base: `git cherry-pick b0aa50a` → `git push origin main` (`f305822..d84705f`). Verified `Signed-off-by` preserved. Worktree + branch cleaned up.

### Outcome
- success

### Improvement Candidate
- 起票済み #522（worktree-merge-push: 長時間フェーズ中の base 前進による ff-only 失敗の rebase フォールバックを追加）。本 #505 verify での再発は #522 の優先度を補強する。提案内容: `worktree-merge-push.sh` の FF fallback を worktree-branch-behind-base ケースに拡張し、worktree ブランチを更新後の base へ rebase/cherry-pick してから ff-merge を再試行する。
