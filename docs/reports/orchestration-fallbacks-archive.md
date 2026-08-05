---
type: report
description: Archive for orchestration fallback catalog entries and anomaly detector patterns retired due to zero firing history and no live reference. Not consumed by any runtime script.
---

# Orchestration Fallbacks Archive

This file archives entries and patterns removed from `modules/orchestration-fallbacks.md` (fallback catalog) and `scripts/detect-wrapper-anomaly.sh` (anomaly detector) once they no longer carry any live maintenance value, while preserving them as diagnostic material in case the same failure resurfaces.

## Role

- **Scope**: cross-Issue, persistent archive — not a per-Issue Spec artifact
- **Role**: preserve the full Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale content of retired catalog entries and detector patterns, so the diagnostic knowledge is not lost when the live copy is deleted
- **Not consumed by**: any runtime script (`apply-fallback.sh`, `detect-wrapper-anomaly.sh`, `run-auto-sub.sh`) — this file is documentation only, not a resolvable anchor target for Tier 2 lookups
- **Not subject to**: `docs/translation-workflow.md` sync or `modules/doc-checker.md` candidate detection (both exclude `docs/reports/`), so archiving here does not introduce an ongoing maintenance obligation

## Archival Criterion

An entry or pattern is archived here only when **all three** axes are zero, per `modules/orchestration-fallbacks.md`'s `### Entry Retention Criterion` (Operational Notes):

- **Axis A — firing history**: zero occurrences recorded in `docs/reports/orchestration-recoveries.md`
- **Axis B — live reference**: no reference from outside `docs/spec/`, `docs/sessions/`, `tests/fixtures/` (synthetic test data), or this archive file itself (a script's pointer comment that guards implemented fallback logic — not a placeholder annotated `(not yet implemented)` with no handler — a detector's `IMPROVEMENT_HINT`, a SKILL.md, a steering doc, or an implemented handler)
- **Axis C — procedure applicability**: the recovery procedure itself no longer applies to any scenario reachable in current code

An entry with any axis non-zero stays in the live catalog, even with zero firings — a live reference means deleting it would break a working pointer or leave a procedure orphaned, and a still-applicable procedure means the manual recovery steps remain usable even without an anchor pointer.

## Restoration Procedure

If the same symptom resurfaces after archival:

1. Move the relevant section back into `modules/orchestration-fallbacks.md` (catalog entries) or re-add the corresponding `elif` branch to `scripts/detect-wrapper-anomaly.sh` (detector patterns), preserving the original Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale structure recorded below
2. Re-point any pointer comments (`# See modules/orchestration-fallbacks.md#<anchor>`) that were redirected to this archive file back to the restored live anchor
3. Note the restoration in the triggering Issue's Spec retrospective, referencing this archive entry as prior art

**Archived catalog entries** — full 5-section structure preserved; the H2 anchors below mirror the live catalog's own H2-anchor / H3-subsection schema:

## gh-pr-list-head-glob

### Symptom
- `gh pr list --head "*issue-N-*"` (glob pattern) returns no results even though matching PRs exist
- `gh` CLI does not support glob/wildcard expansion in `--head`; the filter is applied as a literal string match

### Applicable Phases
- code (PR route — branch lookup)
- merge

### Fallback Steps
1. Drop the `--head` glob filter and instead fetch all open PRs: `gh pr list --state open --json number,headRefName`
2. Filter client-side with a substring match: `| jq '.[] | select(.headRefName | contains("issue-N"))'`
3. Return the matched PR number(s) for downstream use

### Escalation
- If multiple PRs match the substring pattern, select the most recently created one (highest PR number) and log a warning
- If no PR is found after client-side filtering, treat as "no PR exists" and proceed accordingly

### Rationale
- Fixed in #311: `gh pr list --head` does not support glob; client-side filtering is the canonical workaround
- Cataloged here to prevent recurrence; the fix is already applied in affected scripts

### Archival Note
- Reason for archival: zero firing history; the only live reference was an unimplemented-anchor pointer comment (`not yet implemented`) in `scripts/apply-fallback.sh`, with no corresponding handler
- Archived on: 2026-08-06
- Archival Issue: #1180

---

## ci-flake-retry

### Symptom
- A CI check fails with a transient error unrelated to the code change (e.g., network timeout, runner capacity issue, external service outage)
- Typical signals: check name contains "flake" in the error message, or the same check passes on re-run without any code change

### Applicable Phases
- code (after PR creation — waiting for CI)
- merge (pre-merge CI gate)

### Fallback Steps
1. Identify the failing check name via `gh pr checks <pr-num>`
2. Confirm the failure is transient (no code change between runs, error message indicates infrastructure issue)
3. Re-trigger the check: `gh run rerun <run-id> --failed` (requires appropriate permissions)
4. Wait for the re-triggered run to complete: `scripts/wait-ci-checks.sh <pr-num>`
5. If the re-triggered run passes, continue the normal workflow

### Escalation
- Maximum 1 automatic re-trigger attempt per CI run
- If the check fails again after re-trigger, treat as a genuine failure and require human investigation before proceeding
- Do not re-trigger checks that fail due to code-related errors (test failures, lint errors, syntax errors)

### Rationale
- CI flake is a known pattern in shared infrastructure; retrying once is a standard mitigation
- Runtime integration (automatic re-trigger from `run-*.sh`) is deferred to a follow-up Issue; see #315 (catalog entry) for context
- `scripts/wait-ci-checks.sh` already handles the wait logic; re-trigger is the missing piece

### Archival Note
- Reason for archival: zero firing history, no live reference (never implemented, and never referenced either)
- Archived on: 2026-08-06
- Archival Issue: #1180

---

## Retired detector patterns

### watchdog-kill

- **Trigger string**: `watchdog: kill and state not reached`
- **How it went dead**: no script in current code emits this trigger string. The current `scripts/claude-watchdog.sh` (`:78,98`) emits `watchdog: no output for <N>s, killing process` instead, so the string never matched — the `watchdog-kill` branch in `scripts/detect-wrapper-anomaly.sh` was structurally unreachable well before retirement
- **Current signal to use on restoration**: `scripts/claude-watchdog.sh`'s `watchdog: no output for <N>s, killing process`. To restore generic (non-json-mode) watchdog-kill Tier 2 detection, re-implement the trigger against this current string
- **Reason for retirement**: zero firing history and no live emitter of the trigger string (unreachable code)
- **Retired on**: 2026-08-06
- **Retirement Issue**: #1180

---

### dirty-working-tree (detector pattern)

- **Trigger string**: co-occurrence of `VERIFY_FAILED` AND `uncommitted`
- **How it went dead**: the AND condition's `VERIFY_FAILED` string has not been emitted by anything since `run-verify.sh` was removed in #485; already noted as a dead pattern in the #485 retrospective
- **Current signal to use on restoration**: `/verify` outputs `Cannot run verify because there are uncommitted changes` (`skills/verify/SKILL.md` Step 1, triggered by `scripts/check-verify-dirty.sh` exit 1)
- **Note**: only the detector-side pattern was retired here. The `## dirty-working-tree` catalog entry in `modules/orchestration-fallbacks.md` (the procedure itself) remains live, since the procedure still applies to a scenario surfaced directly via `check-verify-dirty.sh`
- **Reason for retirement**: zero firing history and no live emitter of the trigger string (unreachable code)
- **Retired on**: 2026-08-06
- **Retirement Issue**: #1180
