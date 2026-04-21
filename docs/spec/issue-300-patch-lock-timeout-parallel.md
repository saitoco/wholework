# Issue #300: patch lock timeout を並列実行に対応する値に拡張する

## Overview

`/auto` XL route で複数の patch route sub-issue が並列実行される場合、`scripts/run-auto-sub.sh` の `acquire_patch_lock()` がデフォルト 300 秒 timeout で終了し、2 番目以降の sub-issue が失敗する問題を修正する。CI wait 込みの code phase が 30 分を超えるケースがあり、XL 並列 5 件までを想定すると 300 秒では到底足りない。

- デフォルト timeout を 3600 秒に延長（最悪ケースの 5 並列 × 最長 30 分をカバー）
- `.wholework.yml` の `patch-lock-timeout` キーでプロジェクトごとに調整可能に
- ロック待ちログのデフォルト間隔を 60→30 秒に短縮し、保持中 sub-issue 番号を表示

## Changed Files

- `scripts/run-auto-sub.sh`: `acquire_patch_lock()` の timeout デフォルト 300→3600 秒、`.wholework.yml` 読み込み追加（`get-config-value.sh` 経由）、ログ間隔 60→30 秒、ロックディレクトリに `sub-issue` ファイルを書き込み、ログメッセージに holder の sub-issue 番号を追加 — bash 3.2+ 互換
- `modules/detect-config-markers.md`: marker 定義テーブルに `patch-lock-timeout` 行を追加、YAML Parsing Rules と Output Format セクションを更新
- `docs/guide/customization.md`: Available Keys テーブルと YAML サンプルに `patch-lock-timeout` を追加（SSoT）
- `docs/ja/guide/customization.md`: 英語版との翻訳同期
- `tests/run-auto-sub.bats`: `setup()` に `get-config-value.sh` デフォルトモック追加、`.wholework.yml` 経由の timeout 読み込みテスト追加、既存ログテストに sub-issue 番号アサーション追加

## Implementation Steps

1. `scripts/run-auto-sub.sh` — `acquire_patch_lock()` を以下のように修正する (→ 受け入れ基準 1, 2):
   - 関数冒頭に `.wholework.yml` 読み込みと validation を追加:
     ```bash
     local yml_timeout
     yml_timeout=$("$SCRIPT_DIR/get-config-value.sh" patch-lock-timeout "" 2>/dev/null || true)
     { echo "$yml_timeout" | grep -qE '^[0-9]+$' && [[ "$yml_timeout" -gt 0 ]]; } || yml_timeout=""
     ```
   - timeout デフォルトを変更: `local timeout="${WHOLEWORK_PATCH_LOCK_TIMEOUT:-${yml_timeout:-3600}}"`
   - ログ間隔デフォルトを変更: `local log_interval="${WHOLEWORK_PATCH_LOCK_LOG_INTERVAL:-30}"`
   - lock 取得後（`echo "$$" > "${PATCH_LOCK_DIR}/pid"` の直後）に `echo "${SUB_NUMBER}" > "${PATCH_LOCK_DIR}/sub-issue"` を追加
   - while ループ内の `existing_pid` 取得行の直後に `existing_sub=$(cat "$PATCH_LOCK_DIR/sub-issue" 2>/dev/null || true)` を追加
   - ログメッセージを変更: `"waiting for lock held by pid=${existing_pid:-unknown} sub-issue=#${existing_sub:-unknown} (age=${elapsed}s, my sub-issue=#${SUB_NUMBER})"`

2. `modules/detect-config-markers.md` — 3 箇所を更新する (→ 受け入れ基準 3):
   - Marker Definition Table の `verify-max-iterations` 行の直後に追加:
     `| \`patch-lock-timeout\` | \`PATCH_LOCK_TIMEOUT_SECONDS\` | Integer string (extract as-is; use \`3600\` if ≤0 or non-numeric) | \`3600\` (used by \`scripts/run-auto-sub.sh\`) |`
   - YAML Parsing Rules の `verify-max-iterations` 行の直後に追加:
     `- \`patch-lock-timeout\` is treated as an integer: extract the numeric string; if the value is ≤0 or non-numeric, fall back to the default \`3600\` (used by \`scripts/run-auto-sub.sh\`)`
   - Output Format コードブロックの `VERIFY_MAX_ITERATIONS` 行の直後に追加:
     `PATCH_LOCK_TIMEOUT_SECONDS: integer from patch-lock-timeout (default: "3600"; falls back to "3600" if ≤0 or non-numeric)`

3. `docs/guide/customization.md` + `docs/ja/guide/customization.md` — ドキュメント更新 (→ ドキュメント整合性):
   - YAML サンプルの `watchdog-timeout-seconds` 行の直後に追加:
     ```yaml
     # Patch lock timeout for parallel XL sub-issue execution (default: 3600 seconds)
     patch-lock-timeout: 3600
     ```
   - Available Keys テーブルの `watchdog-timeout-seconds` 行の直後に追加:
     `| \`patch-lock-timeout\` | integer | \`3600\` | Patch lock acquisition timeout in seconds. Increase when XL parallel sub-issues time out waiting for the lock. Values ≤0 or non-numeric fall back to \`3600\`. |`
   - `docs/ja/guide/customization.md` に同内容を日本語で翻訳同期する

4. `tests/run-auto-sub.bats` — 3 箇所を更新する:
   - `setup()` 末尾に `get-config-value.sh` デフォルトモックを追加（任意キーに対して空文字を返す）:
     ```bash
     cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
     #!/bin/bash
     echo ""
     exit 0
     MOCK
     chmod +x "$MOCK_DIR/get-config-value.sh"
     ```
   - 既存テスト `PATCH_LOCK: diagnostic log is output when waiting for a live lock holder` に `[[ "$output" == *"sub-issue=#"* ]]` を追加
   - 新テスト `PATCH_LOCK: timeout is read from .wholework.yml via get-config-value.sh` を追加（`get-config-value.sh` が `5` を返すモックで、live lock 保持下で timeout 5s が適用されることを確認）

## Verification

### Pre-merge
- <!-- verify: rubric "The patch lock acquisition timeout in scripts/run-auto-sub.sh (or wherever the patch lock logic lives) has been extended from 300 seconds to a value of at least 1800 seconds, with the new value documented inline or via a constant" --> lock timeout が 1800 秒以上に拡張されている
- <!-- verify: rubric "The patch lock implementation allows the timeout to be overridden via .wholework.yml configuration (e.g., patch-lock-timeout: 3600 key), with detection following the existing detect-config-markers.md pattern" --> `.wholework.yml` で上書き可能
- <!-- verify: file_contains "modules/detect-config-markers.md" "patch-lock-timeout" --> detect-config-markers.md に設定キーが追加されている

### Post-merge
- #292 と同様に 3 並列 sub-issue を持つ XL Issue を作成し、`/auto` 実行で全 sub-issue が lock timeout 失敗なく完走することを確認

## Notes

- 優先度: `WHOLEWORK_PATCH_LOCK_TIMEOUT` 環境変数 > `.wholework.yml` の `patch-lock-timeout` 値 > デフォルト 3600 秒
- `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` 環境変数は引き続き有効（テスト用に短縮可能）
- `existing_sub` はロックディレクトリの `sub-issue` ファイルから読む。旧バージョンの `run-auto-sub.sh` が lock を保持している場合は `unknown` が表示される
- `docs/ja/guide/customization.md` は top-level `docs/*.md` ではないが、`English | [日本語]` リンクが存在するため翻訳同期を含める
- `docs/tech.md` の Architecture Decisions を確認済み。`patch-lock-timeout` は bash スクリプト内ロジックで使用するものであり、`claude -p` への CLI フラグ渡しには該当しないため更新不要
