# Issue #552: auto-rename hook を plugin 配布化し .wholework.yml で opt-in 化

## Overview

`scripts/hook-rename-on-auto.sh`（`/auto` 実行時のセッション自動リネーム hook）を wholework plugin 経由で配布可能にする。`.wholework.yml` に `session-auto-rename: true` を書いたリポジトリだけで動作する opt-in 方式にすることで、plugin 利用者への強制適用を回避しつつ配布性を高める。

変更の柱は3つ:
1. **opt-in マーカー登録** — `modules/detect-config-markers.md` に `session-auto-rename` 行を追加
2. **hook script への opt-in チェック追加** — `scripts/hook-rename-on-auto.sh` の冒頭で `.wholework.yml` を参照し、opt-in されていない場合は即時 exit
3. **plugin-level hook 登録** — `hooks/hooks.json` を新規作成し plugin マニフェストから hook を起動

## Changed Files

- `modules/detect-config-markers.md`: Marker Definition Table に `session-auto-rename` / `HAS_SESSION_AUTO_RENAME` 行追加、Output Format にも同変数追記
- `scripts/hook-rename-on-auto.sh`: `INPUT=$(cat)` の直後に opt-in チェック追加（`CLAUDE_PROJECT_DIR/.wholework.yml` を grep）— bash 3.2+ 互換
- `hooks/hooks.json`: 新規作成 — plugin-level `UserPromptSubmit` hook 定義（command: `${CLAUDE_PLUGIN_ROOT}/scripts/hook-rename-on-auto.sh`, timeout: 5000）
- `docs/guide/customization.md`: YAML 例と Available Keys テーブルに `session-auto-rename` 追記
- `docs/ja/guide/customization.md`: 翻訳ミラー同期（`docs/guide/customization.md` の変更を日本語に反映）
- `tests/hook-rename-on-auto.bats`: `setup()` に `CLAUDE_PROJECT_DIR` + `.wholework.yml(session-auto-rename: true)` 設定を追加（既存テスト維持）；opt-in 3 パターンのテスト追加
- `docs/structure.md`: Directory Layout に `hooks/` ディレクトリと `hooks.json` を追記

## Implementation Steps

1. **`modules/detect-config-markers.md` に `session-auto-rename` マーカー追加**（→ AC1, AC2）
   - Marker Definition Table の `skill-proposals` 行の下に追加:
     `| \`session-auto-rename\` | \`HAS_SESSION_AUTO_RENAME\` | \`true\` | \`false\` |`
   - Output Format セクションに `HAS_SESSION_AUTO_RENAME: true if session-auto-rename: true is set (default: false)` を追記

2. **`scripts/hook-rename-on-auto.sh` に opt-in チェック追加**（→ AC3）
   - `INPUT=$(cat)` の直後（Early exit の前）に以下を挿入:
     ```bash
     WHOLEWORK_YML="${CLAUDE_PROJECT_DIR:-}/.wholework.yml"
     if [ ! -f "$WHOLEWORK_YML" ] || ! grep -q "^session-auto-rename:[[:space:]]*true" "$WHOLEWORK_YML"; then
       exit 0
     fi
     ```

3. **`hooks/hooks.json` 新規作成**（after 2）（→ AC4, AC5）
   - プロジェクトルートに `hooks/` ディレクトリを作成し、以下の内容で `hooks.json` を作成:
     ```json
     {
       "hooks": {
         "UserPromptSubmit": [
           {
             "matcher": "",
             "hooks": [
               {
                 "type": "command",
                 "command": "${CLAUDE_PLUGIN_ROOT}/scripts/hook-rename-on-auto.sh",
                 "timeout": 5000
               }
             ]
           }
         ]
       }
     }
     ```

4. **ドキュメント更新**（parallel with 1, 2）（→ AC6）
   - `docs/guide/customization.md`:
     - YAML 例ブロックの `opportunistic-verify: true` 行の前後適切箇所に `session-auto-rename: true  # Rename session title when /auto is invoked` 追記
     - Available Keys テーブルに行追加: `| \`session-auto-rename\` | boolean | \`false\` | Rename session title to issue number and title when \`/auto N\` is invoked |`
   - `docs/ja/guide/customization.md`: 同内容を日本語で反映（マーカー名は英語のまま）
   - `docs/structure.md`: Directory Layout の `.claude-plugin/` ブロック直後に `hooks/` ディレクトリエントリを追加

5. **`tests/hook-rename-on-auto.bats` 更新**（after 2）（→ AC7）
   - `setup()` を更新: `CLAUDE_PROJECT_DIR` を `BATS_TEST_TMPDIR/wholework-proj` に設定し、`.wholework.yml`（`session-auto-rename: true`）を作成（既存テストが opt-in チェックを通過できるようにする）
   - `teardown()` はそのまま（既存 mock 削除で十分）
   - 以下の 3 テストを追加:
     - `"no .wholework.yml → empty output"`: `CLAUDE_PROJECT_DIR` に空ディレクトリを設定（`.wholework.yml` なし）→ `/auto 123` で空出力
     - `"session-auto-rename: false → empty output"`: `.wholework.yml` に `session-auto-rename: false` → `/auto 123` で空出力
     - `"session-auto-rename: true → hook fires and returns sessionTitle"`: `.wholework.yml` に `session-auto-rename: true` → `/auto 123` で JSON 出力・sessionTitle 確認

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/detect-config-markers.md" "session-auto-rename" --> `modules/detect-config-markers.md` の Marker Definition Table に `session-auto-rename` 行が追加されている
- <!-- verify: file_contains "modules/detect-config-markers.md" "HAS_SESSION_AUTO_RENAME" --> `HAS_SESSION_AUTO_RENAME` 変数が定義されている
- <!-- verify: file_contains "scripts/hook-rename-on-auto.sh" "session-auto-rename" --> hook script の冒頭で `.wholework.yml` の `session-auto-rename` キーを参照する opt-in チェックが実装されている
- <!-- verify: file_contains "hooks/hooks.json" "UserPromptSubmit" --> wholework plugin の `hooks/hooks.json` に `UserPromptSubmit` hook エントリが追加されている
- <!-- verify: file_contains "hooks/hooks.json" "hook-rename-on-auto.sh" --> `hooks/hooks.json` の hook command が `hook-rename-on-auto.sh` を参照している
- <!-- verify: file_contains "docs/guide/customization.md" "session-auto-rename" --> `docs/guide/customization.md` に新マーカーの説明が追加されている
- <!-- verify: github_check "gh pr checks" "bats" --> CI で bats テストが pass（opt-in チェックの 3 パターンを含む）

### Post-merge

- 別の git リポジトリ（wholework plugin を enable 済み）で `.wholework.yml` に `session-auto-rename: true` を追加して新セッション起動、`/auto N` でセッション名が変わることを確認
- `.wholework.yml` に `session-auto-rename` を書かない（または `false`）リポジトリで `/auto N` を打ち、セッション名が変わらないことを確認

## Notes

### Auto-Resolve Log（非対話モードによる自動決定）

1. **Plugin hook 登録の配置先**: `hooks/hooks.json`（plugin.json ではない）に決定。
   - 根拠: Claude Code 公式ドキュメントにて、plugin level hooks は `hooks/` ディレクトリの `hooks.json` に記述すると明記されている（`plugin.json` 内 `hooks` フィールドは存在しない）。
   - Issue body AC4/AC5 の verify command を `.claude-plugin/plugin.json` → `hooks/hooks.json` に更新済み。

2. **`.wholework.yml` 読み込み方式**: 直接 grep を使用（`get-config-value.sh` ヘルパ呼び出しではない）。
   - 根拠: `get-config-value.sh` は CWD 相対で `.wholework.yml` を読む。hook が起動される際の CWD は不定だが、`CLAUDE_PROJECT_DIR` は Claude Code が確実に設定する環境変数。`log-permission.sh` でも同パターンを使用済み。
   - bash 3.2 互換: `grep -q` は 3.2 対応。

3. **既存 bats テストの setup 更新必要性**: opt-in チェック追加後、`CLAUDE_PROJECT_DIR` が未設定の既存テストはすべて空出力を返すため実装手順 5 で setup 更新が必要。

### conflict detection

Issue body の AC4/AC5 は `file_contains ".claude-plugin/plugin.json"` を verify command として記載していたが、実際の plugin hooks 登録場所は `hooks/hooks.json` と確定したため、spec 段階で verify command を修正した（AC4/AC5 の注釈「spec で別ファイル分離が決まった場合は spec 時点で verify command を更新」に従う）。Issue body の AC も同様に更新する。

### 既存 `.claude/settings.json.template` エントリの扱い

当面は残す（plugin hook との二重起動になるが、両方が opt-in チェックを通過した場合は同じ JSON を出力するため冪等。先に exit したほうの出力が使われ、後発は無害）。Plugin 経由配布が定着したら別 Issue で削除を検討。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `hooks/hooks.json` を新規作成して plugin-level hook 登録（`plugin.json` への hooks フィールド追加ではない）
- opt-in チェックは `CLAUDE_PROJECT_DIR/.wholework.yml` を直接 `grep -q` で参照（`get-config-value.sh` 呼び出しではなく bash 3.2 互換の直接 grep を採用）
- `docs/ja/structure.md` は Spec の Changed Files に含まれていなかったが、`translation-workflow.md` 準拠で追加更新した

### Deferred Items
- 既存 `.claude/settings.json.template` の `UserPromptSubmit` hook エントリは残存（二重起動だが冪等）。Plugin 配布定着後に削除 Issue を別途起票予定
- AC7（`github_check "gh pr checks" "bats"`）は PR 作成後 CI で確認

### Notes for Next Phase
- `hooks/hooks.json` が Claude Code plugin hooks schema として正しいかどうかは CI（bats は PASS、hooks の実動作は手動後確認）
- PR #553 作成済み。Post-merge 手動確認 2 項目が残っている

## Code Retrospective

### Deviations from Design

- None — 実装ステップはすべて Spec 通りに実行。順番の変更なし。

### Design Gaps/Ambiguities

- `docs/ja/structure.md` の同期が Spec の Changed Files リストに含まれていなかった。`docs/structure.md` を変更したため `docs/translation-workflow.md` の手順に従い `docs/ja/structure.md` も更新した（追加コミットで対応）。

### Rework

- None
