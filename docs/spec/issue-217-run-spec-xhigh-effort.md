# Issue #217: run-spec.sh に xhigh effort レベル対応を追加

## Overview

Claude Opus 4.7 では `xhigh` が新しいデフォルト effort レベルとして導入された。Anthropic の推奨では `max` は 4.7 において diminishing returns とオーバーシンクのリスクがあるとされている。

`scripts/run-spec.sh` の `--opus` パスのデフォルト effort を `max` から `xhigh` へ変更する。`max` は `--max` フラグによる明示指定時のみ使用する構成とする。Sonnet パス（`--opus` 未指定時）は本 Issue のスコープ外（現状維持）。

## Changed Files

- `scripts/run-spec.sh`: `EFFORT` 変数を追加、`--opus` 時に `xhigh` をデフォルト設定、`--max` フラグを追加、Usage 文字列と echo メッセージ・`--effort` 引数を変数化
- `docs/tech.md`: Phase-specific model and effort matrix の run-spec.sh 行を更新（Effort 欄に model 別の effort を記載）、Axis 2 の対応レベル一覧に `xhigh` を追加
- `tests/run-spec.bats`: `--opus` デフォルト effort が xhigh であることの検証ケースを追加、`--opus --max` の明示 max 指定の検証ケースを追加

## Implementation Steps

1. `scripts/run-spec.sh` を以下の通り変更する（→ 受け入れ基準 A）：
   - `MODEL="sonnet"` の直後に `EFFORT="max"` を追加
   - `--opus)` case に `EFFORT="xhigh"` を追加（`MODEL="opus"` の後）
   - オプションパーサーに `--max)` case を追加して `EFFORT="max"` を設定
   - Usage 文字列（`echo "Usage: run-spec.sh ..."` の2箇所）に `[--max]` を追加
   - `echo "Effort: max"` を `echo "Effort: ${EFFORT}"` に変更
   - `--effort max \` を `--effort "${EFFORT}" \` に変更

2. `docs/tech.md` を以下の通り変更する（→ 受け入れ基準 B）：
   - Axis 2 の説明行（`supports low/medium/high/max levels`）に `xhigh` を追加: `low/medium/high/xhigh/max`
   - Phase-specific model and effort matrix の run-spec.sh 行の Effort 欄を更新:
     `max` → `Sonnet: max; Opus: xhigh (default), max (explicit --max)`

3. `tests/run-spec.bats` に2つのテストケースを追加する（→ 受け入れ基準 C）：
   - `@test "success: --opus default effort is xhigh"`: `bash "$SCRIPT" 123 --opus` を実行し、`EFFORT_VALUE=xhigh` が CLAUDE_CALL_LOG に記録されることを確認
   - `@test "success: --opus --max explicit effort is max"`: `bash "$SCRIPT" 123 --opus --max` を実行し、`EFFORT_VALUE=max` が CLAUDE_CALL_LOG に記録されることを確認

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/run-spec.sh" "xhigh" --> `scripts/run-spec.sh` が `--opus` パスでデフォルト effort に xhigh を使用する
- <!-- verify: section_contains "docs/tech.md" "Phase-specific model and effort matrix" "xhigh" --> `docs/tech.md` matrix に xhigh のデフォルト採用方針と `max` の明示指定条件が記載されている
- <!-- verify: file_contains "tests/run-spec.bats" "xhigh" --> `tests/run-spec.bats` に xhigh デフォルト挙動の検証ケースが含まれる
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" --> bats テストが CI で成功

### Post-merge

- L サイズ Issue で `/auto N` を実行し、spec phase ログに `Effort: xhigh` が表示される <!-- verify-type: opportunistic -->
- xhigh 導入前後で spec phase の time / cost / quality 差分を benchmark Issue (#226) で記録 <!-- verify-type: manual -->

## Notes

- Sonnet パスの effort（`max`）は本 Issue のスコープ外。`--max` フラグは `--opus` との組み合わせ専用に設計されているが、単独使用も技術的には動作する（Sonnet + max、実質的に現状と同じため害なし）
- `--max` フラグを `--opus` なしで使用した場合のガード処理は本 Issue のスコープ外
- patch route（Size=S）のため `gh pr checks` は使用不可 → `gh run list --workflow=test.yml` に自動修正済み

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
