# Issue #64: feat: PR マージ後の Issue クローズタイミングを制御可能にする

## Overview

GitHub の「Auto-close issues with merged linked pull requests」設定を無効化しているリポジトリでは、`closes #N` を含む PR をマージしても Issue は自動クローズされず OPEN のまま残る。

現状の `/verify` Step 9 は Issue が auto-close された前提（CLOSED 状態）でのみ動作しており、auto-close 無効リポジトリ（Issue が OPEN のまま）での挙動が定義されていない。

本 Issue では、`/verify` 実行時に Issue の OPEN/CLOSED 状態を検出し、OPEN の場合は全受け入れ条件（opportunistic/manual を含む）が checked になるまで Issue を OPEN のまま保持し、完了時点で `phase/done` + close するロジックを追加する。

また、`docs/workflow.md` に auto-close 無効ケースのクローズフローを記述する。

**ユーザー確認済み設計方針（Issue Design Decisions より）:**
- 検出方法: 実行時 Issue 状態検出（`gh issue view` の `.state` フィールド）
- クローズ基準: Issue OPEN の場合、pre-merge + post-merge（opportunistic/manual 含む）の全条件が checked であること
- phase/verify → phase/done 遷移: `/verify` 再実行のみ（polling/webhook 等は本スコープ外）

## Changed Files

- `skills/verify/SKILL.md`: Step 9 を拡張 — Issue OPEN/CLOSED 状態分岐を追加、旧仮定テキストを削除
- `docs/workflow.md`: Auto-close 無効時のクローズフローを記述する節を追加
- `docs/ja/workflow.md`: 上記の日本語ミラーを追加

## Implementation Steps

1. `skills/verify/SKILL.md` Step 9 を変更する（→ 受け入れ基準 1, 2, 4）
   - 先頭の "Assuming Issues are auto-closed via `closes #N` in PR body on merge" を削除
   - Issue 状態チェックを追加: `gh issue view "$NUMBER" --json state --jq '.state'`
   - **Issue CLOSED 時**（従来挙動）と **Issue OPEN 時**（新規追加）に分岐
   - Issue OPEN 時のロジック:
     - 全 auto-verify 条件 PASS/SKIPPED かつ opportunistic/manual 未チェックあり → `phase/verify` を付与、Issue は OPEN 保持（close しない）
     - 全 auto-verify 条件 PASS/SKIPPED かつ全 checked → `phase/done` + `gh issue close "$NUMBER"`
     - FAIL/UNCERTAIN → phase/* ラベルを削除（Issue は既に OPEN のため reopen 不要）

2. `docs/workflow.md` に "When Auto-close is Disabled" 節を追加する（→ 受け入れ基準 3）
   - `### Standard Flow via \`closes #N\`` 節の直後に追加
   - "Auto-close" というテキストを含む節見出しを使用

3. `docs/ja/workflow.md` に日本語ミラー節を追加する（→ verify コマンドなし）
   - `### \`closes #N\` による標準フロー` 節の直後に追加
   - 内容は手順 2 の日本語訳

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/verify/SKILL.md" "Step 9" "Issue OPEN" --> `skills/verify/SKILL.md` Step 9 に、verify 実行時の Issue OPEN/CLOSED 状態で分岐する記述が追加されている
- <!-- verify: section_contains "skills/verify/SKILL.md" "Step 9" "opportunistic" --> `skills/verify/SKILL.md` Step 9 に、Issue OPEN かつ opportunistic/manual 未チェック時は close せず `phase/verify` のまま据え置く記述がある
- <!-- verify: file_contains "docs/workflow.md" "Auto-close" --> `docs/workflow.md` に GitHub の auto-close 無効設定への対応フローが記述されている（既存「Standard Flow via `closes #N`」と並列の節）
- <!-- verify: file_not_contains "skills/verify/SKILL.md" "Assuming Issues are auto-closed via" --> 旧仕様前提の記述（`Assuming Issues are auto-closed via closes #N in PR body on merge`）が削除または書き換えられている

### Post-merge

- auto-close 設定を無効化したリポジトリで実際に `/auto N` を走らせ、全条件 checked 完了まで Issue が OPEN を維持することを確認
- opportunistic/manual を手動チェック後に `/verify N` を再実行し、`phase/done` + close に遷移することを確認

## Notes

- `docs/ja/workflow.md` の更新には verify コマンドを付与しない（日本語ミラーは英語ファイルの従属更新）
- Issue OPEN 時の FAIL/UNCERTAIN ケースでは `gh issue reopen` は不要（既に OPEN のため）
