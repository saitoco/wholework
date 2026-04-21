---
type: report
description: Test fixture for audit-recoveries.bats
---

# Orchestration Recovery Log (test fixture)

## 2026-03-01 10:00 UTC: gh-pr-list-head-glob

### Context
- Issue #100, phase: code-pr
- Source: fallback-catalog
- Wrapper: run-code.sh, exit code: 1
- Log tail: "error: No PR found"

### Diagnosis
- gh pr list --head glob pattern not supported

### Recovery Applied
- orchestration-fallbacks.md#gh-pr-list-head-glob

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-03-02 11:00 UTC: gh-pr-list-head-glob

### Context
- Issue #101, phase: code-pr
- Source: fallback-catalog
- Wrapper: run-code.sh, exit code: 1
- Log tail: "error: No PR found"

### Diagnosis
- gh pr list --head glob pattern not supported

### Recovery Applied
- orchestration-fallbacks.md#gh-pr-list-head-glob

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-03-03 12:00 UTC: gh-pr-list-head-glob

### Context
- Issue #102, phase: code-pr
- Source: fallback-catalog
- Wrapper: run-code.sh, exit code: 1
- Log tail: "error: No PR found"

### Diagnosis
- gh pr list --head glob pattern not supported

### Recovery Applied
- orchestration-fallbacks.md#gh-pr-list-head-glob

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-03-04 09:00 UTC: verify-timeout-exceeded

### Context
- Issue #103, phase: verify
- Source: wrapper-anomaly-detector
- Wrapper: run-verify.sh, exit code: 124
- Log tail: "Timeout after 1200s"

### Diagnosis
- CI wait exceeded WHOLEWORK_CI_TIMEOUT_SEC limit

### Recovery Applied
- manual: re-ran verify after CI completed

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-03-05 14:00 UTC: verify-timeout-exceeded

### Context
- Issue #104, phase: verify
- Source: wrapper-anomaly-detector
- Wrapper: run-verify.sh, exit code: 124
- Log tail: "Timeout after 1200s"

### Diagnosis
- CI wait exceeded WHOLEWORK_CI_TIMEOUT_SEC limit

### Recovery Applied
- manual: re-ran verify after CI completed

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-03-06 15:00 UTC: verify-timeout-exceeded

### Context
- Issue #105, phase: verify
- Source: wrapper-anomaly-detector
- Wrapper: run-verify.sh, exit code: 124
- Log tail: "Timeout after 1200s"

### Diagnosis
- CI wait exceeded WHOLEWORK_CI_TIMEOUT_SEC limit

### Recovery Applied
- manual: re-ran verify after CI completed

### Outcome
- success

### Improvement Candidate
- 起票済み #311

## 2026-03-07 16:00 UTC: code-pr-extraction-fail

### Context
- Issue #106, phase: code-pr
- Source: wrapper-anomaly-detector
- Wrapper: run-code.sh, exit code: 1
- Log tail: "Could not retrieve PR number"

### Diagnosis
- PR extraction via gh pr list failed

### Recovery Applied
- manual: gh pr list --json with exact headRefName

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-03-08 10:00 UTC: code-pr-extraction-fail

### Context
- Issue #107, phase: code-pr
- Source: wrapper-anomaly-detector
- Wrapper: run-code.sh, exit code: 1
- Log tail: "Could not retrieve PR number"

### Diagnosis
- PR extraction via gh pr list failed

### Recovery Applied
- manual: gh pr list --json with exact headRefName

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-03-09 11:00 UTC: code-pr-extraction-fail

### Context
- Issue #108, phase: code-pr
- Source: wrapper-anomaly-detector
- Wrapper: run-code.sh, exit code: 1
- Log tail: "Could not retrieve PR number"

### Diagnosis
- PR extraction via gh pr list failed

### Recovery Applied
- manual: gh pr list --json with exact headRefName

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-03-10 12:00 UTC: merge-conflict-rebase-fail

### Context
- Issue #109, phase: merge
- Source: wrapper-anomaly-detector
- Wrapper: run-merge.sh, exit code: 1
- Log tail: "CONFLICT (content): Merge conflict in skills/auto/SKILL.md"

### Diagnosis
- Rebase conflict during worktree merge

### Recovery Applied
- manual conflict resolution

### Outcome
- success

### Improvement Candidate
- N/A (resolved by known catalog)
