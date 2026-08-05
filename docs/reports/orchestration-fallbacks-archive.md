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

An entry or pattern is archived here only when **both** axes are zero, per `modules/orchestration-fallbacks.md`'s `### Entry Retention Criterion` (Operational Notes):

- **Axis A — firing history**: zero occurrences recorded in `docs/reports/orchestration-recoveries.md`
- **Axis B — live reference**: no reference from outside `docs/spec/` / `docs/sessions/` (a script's pointer comment, a detector's `IMPROVEMENT_HINT`, a SKILL.md, a steering doc, or an implemented handler)

An entry with either axis non-zero stays in the live catalog, even with zero firings — a live reference means deleting it would break a working pointer or leave a procedure orphaned.

## Restoration Procedure

If the same symptom resurfaces after archival:

1. Move the relevant section back into `modules/orchestration-fallbacks.md` (catalog entries) or re-add the corresponding `elif` branch to `scripts/detect-wrapper-anomaly.sh` (detector patterns), preserving the original Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale structure recorded below
2. Re-point any pointer comments (`# See modules/orchestration-fallbacks.md#<anchor>`) that were redirected to this archive file back to the restored live anchor
3. Note the restoration in the triggering Issue's Spec retrospective, referencing this archive entry as prior art

## Archived catalog entries

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
- 退避理由: 発火実績ゼロ、live 参照元は `scripts/apply-fallback.sh` の未実装コメント (`not yet implemented`) のみで実装済みハンドラなし
- 退避日: 2026-08-06
- 退避 Issue: #1180

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
- 退避理由: 発火実績ゼロ、live 参照元なし (実装未着手のまま参照も存在しない)
- 退避日: 2026-08-06
- 退避 Issue: #1180

---

## Retired detector patterns

### watchdog-kill

- **trigger 文字列**: `watchdog: kill and state not reached`
- **失効経緯**: この trigger 文字列を発行するスクリプトが現行コードに存在しない。現行の `scripts/claude-watchdog.sh` (`:78,98`) は `watchdog: no output for <N>s, killing process` を発行しており、文字列が一致しないため `scripts/detect-wrapper-anomaly.sh` の `watchdog-kill` 分岐は構造的に到達不能だった（退役前から実質的に不在）
- **復帰時に使うべき現行シグナル**: `scripts/claude-watchdog.sh` が出す `watchdog: no output for <N>s, killing process`。汎用 watchdog kill (json mode 以外) の Tier 2 検出を復旧する場合は、この文字列に合わせて trigger を再実装すること
- **退避理由**: 発火実績ゼロかつ trigger 文字列の live 発行元が存在しない (到達不能コード)
- **退避日**: 2026-08-06
- **退避 Issue**: #1180

---

### dirty-working-tree (detector pattern)

- **trigger 文字列**: `VERIFY_FAILED` AND `uncommitted` の共起
- **失効経緯**: AND 条件の `VERIFY_FAILED` を発行する `run-verify.sh` が #485 で削除されて以降、この文字列を発行する箇所がどこにも存在しない。#485 の retro で既知の dead pattern として言及済み
- **復帰時に使うべき現行シグナル**: `skills/verify/SKILL.md` Step 1 / `scripts/check-verify-dirty.sh` が出す `Cannot run verify because there are uncommitted changes`
- **注意**: これは検出器側パターンのみの退役であり、`modules/orchestration-fallbacks.md` の `## dirty-working-tree` カタログエントリ (手順そのもの) は現役のまま残置されている。手順は `check-verify-dirty.sh` 経由で今も有効なシナリオに対応するため
- **退避理由**: 発火実績ゼロかつ trigger 文字列の live 発行元が存在しない (到達不能コード)
- **退避日**: 2026-08-06
- **退避 Issue**: #1180
