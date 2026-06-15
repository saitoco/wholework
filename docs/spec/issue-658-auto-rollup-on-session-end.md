# Issue #658: auto-events-rollup: /auto セッション終了時に rollup を自動実行する

## Overview

`/auto` スキルの最終フェーズ完了後に `scripts/auto-events-rollup.sh` を自動呼び出しし、セッション終了ごとに daily rollup が更新されるようにする。

設計決定（#645 より）:
- session_id フィルタリングは実施しない（全イベント処理、シンプル実装を優先）
- rollup 失敗時は best-effort: warning 出力のみでセッション完了をブロックしない
- `--cleanup` フラグは発火しない（手動操作のまま）

## Changed Files

- `skills/auto/SKILL.md`: 2 箇所変更
  1. `allowed-tools` frontmatter に `${CLAUDE_PLUGIN_ROOT}/scripts/auto-events-rollup.sh:*` を追加
  2. Step 5 の observation trigger の直後に rollup 呼び出し（best-effort）を追加 — bash 3.2+ compatible

## Implementation Steps

1. `skills/auto/SKILL.md` の `allowed-tools` フロントマターに `${CLAUDE_PLUGIN_ROOT}/scripts/auto-events-rollup.sh:*` を追加する（`scripts/observation-trigger.sh:*` の直後に挿入） (→ AC1)
2. `skills/auto/SKILL.md` の Step 5 の末尾、observation trigger (`scripts/observation-trigger.sh --event auto-run`) の直後に以下を追加する (→ AC1, AC2, AC3):

   ```
   **Daily rollup (best-effort, runs after observation scan regardless of success/failure):**

   Run `${CLAUDE_PLUGIN_ROOT}/scripts/auto-events-rollup.sh`. If the command fails, output "Warning: auto-events-rollup failed. Session will continue." and proceed without blocking.
   ```

## Verification

### Pre-merge

- <!-- verify: grep "auto-events-rollup.sh" "skills/auto/SKILL.md" --> `skills/auto/SKILL.md` に `auto-events-rollup.sh` の呼び出しが追加される
- <!-- verify: rubric "skills/auto/SKILL.md において auto-events-rollup.sh の呼び出しが best-effort（失敗時は warning を出力してセッションを継続）として記述されている" --> <!-- verify: file_contains "skills/auto/SKILL.md" "best-effort" --> rollup 失敗時にセッションが異常終了しない（best-effort 呼び出し）
- <!-- verify: file_not_contains "skills/auto/SKILL.md" "auto-events-rollup.sh --cleanup" --> `--cleanup` フラグが自動呼び出しに含まれない

### Post-merge

- `/auto` 実行後に `docs/reports/auto-events-rollup-YYYY-MM-DD.md` が自動生成されることを確認

## Notes

- AC2 は `rubric` と `file_contains` の 2 つの verify command を持つ。`best-effort` という文字列は Step 2 の挿入テキストに含まれるため、`file_contains` で確実に検証できる。`rubric` は意味的な best-effort 記述の確認を担う。
- 挿入位置は Step 5 末尾の observation trigger 直後（`Run ${CLAUDE_PLUGIN_ROOT}/scripts/observation-trigger.sh --event auto-run` の後）。`### Step 6` の直前に追加することで Step 6 の Failure ハンドラとの境界が明確になる。

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- None

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `allowed-tools` に `auto-events-rollup.sh:*` を `observation-trigger.sh:*` の直後に挿入した（Spec 指定通り）
- rollup 呼び出しは Step 5 末尾の observation scan 直後、`### Step 6` 直前に配置（Step 6 Failure ハンドラとの境界を明確化）
- best-effort 記述は「If the command fails, output "Warning: auto-events-rollup failed. Session will continue." and proceed without blocking.」で表現

### Deferred Items
- session_id フィルタリングは不要と判断（Issue の自動解決済み曖昧ポイントに記載通り）
- `--cleanup` は手動操作のまま（実装に含まない）
- Post-merge AC（rollup ファイル生成確認）は manual verify のまま

### Notes for Next Phase
- 全 pre-merge AC が PASS 済み（チェックボックス更新済み）
- テスト全 PASS（bats 846 件）、SKILL.md 構文検証 OK、禁止表現チェック OK
- verify フェーズでは rubric AC の意味的検証が残っている
