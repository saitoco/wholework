# Issue #748: tech.md: Add 4 Undocumented Environment Variables to Environment Variables Table

## Overview

`/audit drift` detected a discrepancy between `docs/tech.md` and the implementation: 4 environment variables
actively used in scripts have no entries in the Environment Variables table, making them undiscoverable
without reading bash source code.

The 4 missing variables are:

| Variable | Default | Script |
|----------|---------|--------|
| `WHOLEWORK_MAX_RECOVERY_SUBAGENTS` | `1` | `scripts/spawn-recovery-subagent.sh:51` |
| `WHOLEWORK_PATCH_LOCK_TIMEOUT` | `300` (env > `.wholework.yml` `patch-lock-timeout` > 300) | `scripts/worktree-merge-push.sh:48` |
| `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` | `30` | `scripts/worktree-merge-push.sh:49` |
| `WHOLEWORK_YML` | `${CLAUDE_PROJECT_DIR:-}/.wholework.yml` | `scripts/hook-rename-on-auto.sh:9` |

## Changed Files

- `docs/tech.md`: add 4 rows to the Environment Variables table (→ all pre-merge ACs)
- `docs/ja/tech.md`: add corresponding 4 rows in Japanese (translation sync per `docs/translation-workflow.md`)

## Implementation Steps

1. In `docs/tech.md`, add 4 new rows to the Environment Variables table (after the existing `WHOLEWORK_ISSUE_BODY_DIR` row):
   - `WHOLEWORK_MAX_RECOVERY_SUBAGENTS` | `1` | Maximum number of concurrent Tier 3 recovery sub-agents spawned by `spawn-recovery-subagent.sh`. Defaults to 1 (serial recovery) to bound cost during XL parallel runs.
   - `WHOLEWORK_PATCH_LOCK_TIMEOUT` | `300` | Timeout seconds for the patch lock in `worktree-merge-push.sh`. Priority: env var > `patch-lock-timeout` in `.wholework.yml` > 300.
   - `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` | `30` | Log output interval seconds while waiting for the patch lock in `worktree-merge-push.sh`.
   - `WHOLEWORK_YML` | `${CLAUDE_PROJECT_DIR:-}/.wholework.yml` | Path to `.wholework.yml` used by `hook-rename-on-auto.sh`. Derived from `CLAUDE_PROJECT_DIR`; not an operator-override pattern (see Notes).
   (→ AC 1, 2, 3, 4, 5)

2. In `docs/ja/tech.md`, add corresponding 4 rows in Japanese to the Environment Variables table (translation sync).
   (→ translation-workflow.md sync obligation)

## Verification

### Pre-merge

- <!-- verify: grep "WHOLEWORK_MAX_RECOVERY_SUBAGENTS" "docs/tech.md" --> tech.md に `WHOLEWORK_MAX_RECOVERY_SUBAGENTS` が記載されている
- <!-- verify: grep "WHOLEWORK_PATCH_LOCK_TIMEOUT" "docs/tech.md" --> tech.md に `WHOLEWORK_PATCH_LOCK_TIMEOUT` が記載されている
- <!-- verify: grep "WHOLEWORK_PATCH_LOCK_LOG_INTERVAL" "docs/tech.md" --> tech.md に `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` が記載されている
- <!-- verify: grep "WHOLEWORK_YML" "docs/tech.md" --> tech.md に `WHOLEWORK_YML` が記載されている
- <!-- verify: section_contains "docs/tech.md" "Environment Variables" "WHOLEWORK_PATCH_LOCK_TIMEOUT" --> Environment Variables セクション配下に追加されている

### Post-merge

- `docs/ja/tech.md` の Environment Variables 表に対応する 4 行が日本語で追加されていることを目視確認

## Notes

**WHOLEWORK_YML の性質 (Auto-resolve: non-interactive):**
`hook-rename-on-auto.sh:9` は `WHOLEWORK_YML="${CLAUDE_PROJECT_DIR:-}/.wholework.yml"` と代入している。これは `${WHOLEWORK_YML:-...}` パターン（env override）ではないため、`WHOLEWORK_YML` はオペレーター設定可能な env var として設計されていない。ただし Issue body が明示的に記載しているため、hook 内部変数として実態に合った記述でテーブルに追加する。将来オペレーター override に変更する場合はスクリプト側の修正が別途必要。

**WHOLEWORK_PATCH_LOCK_TIMEOUT の優先順位:**
`${WHOLEWORK_PATCH_LOCK_TIMEOUT:-${yml_timeout:-300}}` — env var が `.wholework.yml` の `patch-lock-timeout` より高優先。両方とも未設定の場合は 300 秒。

## Consumed Comments

No new comments since last phase.
