# Issue #754: patch-lock YAML Key Config for .wholework.yml

## Overview

`scripts/worktree-merge-push.sh` の `WHOLEWORK_PATCH_LOCK_TIMEOUT` env var は、`patch-lock-timeout` YAML key としても設定可能になっている (`#303` で実装済み) が、`docs/guide/customization.md` の該当エントリが env var override との優先関係を説明していない。

Rubric AC3 (`docs/guide/customization.md に patch lock config key が記載され、env var override も合わせて説明されている`) を満たすため、`patch-lock-timeout` エントリに `WHOLEWORK_PATCH_LOCK_TIMEOUT` env var override の説明を追加する。なお、以下は**既に実装済み**で変更不要:

- `modules/detect-config-markers.md`: `patch-lock-timeout` YAML key 登録済み (#742)
- `scripts/worktree-merge-push.sh`: `yml_timeout` = `get-config-value.sh patch-lock-timeout` で読み込み済み (#303)
- `docs/tech.md`: `WHOLEWORK_PATCH_LOCK_TIMEOUT` env var 文書化済み (#748)

## Changed Files

- `docs/guide/customization.md`: `patch-lock-timeout` テーブル行の説明に `WHOLEWORK_PATCH_LOCK_TIMEOUT` env var override (優先順位) の説明を追記 — bash 3.2+ 非対象 (ドキュメントのみ)
- `docs/ja/guide/customization.md`: 上記の日本語訳を同期

## Implementation Steps

1. `docs/guide/customization.md` の `patch-lock-timeout` テーブル行 (現 line 133) 説明末尾に追記: `To override per-run without editing \`.wholework.yml\` (emergency use), set the \`WHOLEWORK_PATCH_LOCK_TIMEOUT\` env var; priority: env var > this key > \`300\`.` (→ AC3 rubric)
2. `docs/ja/guide/customization.md` の対応行の説明を日本語で同期: `ファイルを編集せずに per-run で上書きする (緊急用) には \`WHOLEWORK_PATCH_LOCK_TIMEOUT\` env var を設定する。優先順位: env var > このキー > \`300\`。` (→ AC3 rubric, after Step 1)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/detect-config-markers.md の marker テーブルに patch-lock-timeout キー (or 同等) が追加されている" --> <!-- verify: section_contains "modules/detect-config-markers.md" "### 2. Interpret YAML Keys" "patch-lock-timeout" --> `detect-config-markers.md` Section "### 2. Interpret YAML Keys" に `patch-lock-timeout` YAML key が登録済み (既存、変更不要)
- <!-- verify: file_contains "scripts/worktree-merge-push.sh" "yml_timeout" --> <!-- verify: grep "WHOLEWORK_PATCH_LOCK_TIMEOUT.*yml_timeout" "scripts/worktree-merge-push.sh" --> `worktree-merge-push.sh` で YAML 値を参照し env var で override できる (既存)
- <!-- verify: rubric "docs/guide/customization.md に patch lock config key が記載され、env var override も合わせて説明されている" --> <!-- verify: file_contains "docs/guide/customization.md" "patch-lock-timeout" --> `customization.md` に `patch-lock-timeout` と `WHOLEWORK_PATCH_LOCK_TIMEOUT` override の優先関係が説明されている (Step 1 対象)
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> All bats tests pass (PR route)

### Post-merge

- なし

## Consumed Comments

- saito (MEMBER / first-class): Issue Retrospective コメント (Auto-Resolve Log: `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` の YAML key 追加はスコープ外と判断)

## Notes

- **実装済み確認 (conflict detection)**: Issue body の Background では "`.wholework.yml` config 表にも記載がない" とあるが、調査時点で `detect-config-markers.md` と `customization.md` には既に `patch-lock-timeout` が登録済み (#742、2026-06-21)。audit 起票後に他 Issue で部分実装が完了した状態。残ギャップは customization.md の env var override 説明のみ (rubric AC3)。
- **優先順位の conflict auto-resolution**: Issue body は "YAML 値を優先参照 (env var は fallback)" と記述しているが、verify command `grep "WHOLEWORK_PATCH_LOCK_TIMEOUT.*yml_timeout"` は現行実装 (`${WHOLEWORK_PATCH_LOCK_TIMEOUT:-${yml_timeout:-300}}`) にマッチする (env var が技術的には高優先)。"YAML 値を優先参照" は「通常設定は YAML が推奨経路」の意味であり、技術的優先順位は env var > YAML > default が正しい (緊急 override セマンティクス)。他の watchdog-timeout 系 key と同じパターン。コード変更不要と判断。
- **Auto-Resolve Log**: `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` の YAML key 追加はスコープ外 (Issue body の Auto-Resolved Ambiguity で明示判断済み)。
