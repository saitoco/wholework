# Issue #869: run-code: auto-retry-on-fail を silent no-op でも発火させる

## Overview

`reconcile-phase-state.sh` が `matches_expected:false` (silent no-op) を検出したとき、`scripts/run-code.sh` 内に verify-side の `auto-retry-on-fail` と対称的な tier-gated retry ループを追加する。

現状、verify FAIL 時には `skills/verify/SKILL.md` Step 11(b) に `auto-retry-on-fail` config で制御される retry 機構があるが、code phase の silent no-op には config-level の同等機構が存在しない。`/auto` 経由の 3-Tier Recovery (Tier 2: `apply-fallback.sh`) はあるが、`run-code.sh` 単独起動時には engage しない。

本 Issue では A 案 (run-code.sh wrapper 拡張) を採用し、standalone/`/auto` 両方で動作する対称的な retry 機構を実装する。

## Consumed Comments

- Issue Retrospective (saito, MEMBER) — 3 つの曖昧ポイントの自動解決内容を Issue body に反映済み (post-merge AC2 の verify-type を manual → auto に変更、bats full suite AC 追加、verify-type observation event を manual に変更)

## Changed Files

- `scripts/run-code.sh`: config 読み込みブロック追加 + silent no-op 検出後に tier-gated retry ループ追加 — bash 3.2+ compatible
- `scripts/emit-event.sh`: `code_retry_fire` イベントスキーマをコメントブロックに追記
- `scripts/apply-fallback.sh`: `apply_code_patch_silent_no_op_retry()` に AUTO_RETRY_ENABLED ガード追加 (double-retry 防止) — bash 3.2+ compatible
- `tests/run-code.bats`: silent no-op + AUTO_RETRY_ENABLED=true 時の retry シナリオテスト追加
- `docs/tech.md`: Architecture Decisions に code-side auto-retry の Architecture Decision を追加
- `docs/ja/tech.md`: tech.md 変更を日本語ミラーに同期

## Implementation Steps

1. **`scripts/run-code.sh`: config 読み込み + retry ループ追加** (→ 受け入れ基準 1, 2)

   メイン実行ブロック開始前に、以下の config 読み込みブロックを追加 (既存の `PERMISSION_MODE` 読み込みの直後に配置):

   ```bash
   AUTONOMY_TIER=$("$SCRIPT_DIR/get-config-value.sh" autonomy L1 2>/dev/null || echo L1)
   _REPO_ROOT="$(dirname "$SCRIPT_DIR")"
   _WW_YML="${_REPO_ROOT}/.wholework.yml"
   AUTO_RETRY_ENABLED="false"
   AUTO_RETRY_MAX_ITERATIONS=3
   if [[ -f "$_WW_YML" ]]; then
     _raw_enabled=$(awk '/^auto-retry-on-fail:/{f=1; next} f && /^[[:space:]]+enabled:/{gsub(/.*enabled:[[:space:]]*/,""); gsub(/[[:space:]].*/,""); print; exit} /^[^[:space:]]/{f=0}' "$_WW_YML" | tr -d ' ')
     [[ "$_raw_enabled" == "true" ]] && AUTO_RETRY_ENABLED="true"
     _raw_max=$(awk '/^auto-retry-on-fail:/{f=1; next} f && /^[[:space:]]+(max_iterations|threshold):/{gsub(/.*:[[:space:]]*/,""); gsub(/[[:space:]].*/,""); print; exit} /^[^[:space:]]/{f=0}' "$_WW_YML" | tr -d ' ')
     if [[ -n "$_raw_max" && "$_raw_max" =~ ^[0-9]+$ && "$_raw_max" -gt 0 ]]; then
       AUTO_RETRY_MAX_ITERATIONS="$_raw_max"
     fi
   fi
   CODE_RETRY_COUNT=${CODE_RETRY_COUNT:-0}
   export CODE_RETRY_COUNT
   ```

   reconcile check で `matches_expected:false` を検出して `EXIT_CODE=1` に設定するブロック (既存) の直前に、以下の retry ロジックを追加:

   ```bash
   elif echo "$_reconcile_out" | grep -q '"matches_expected":false'; then
     echo "Warning: claude exited 0 but $_RECONCILE_PHASE phase did not complete (silent no-op). reconcile: $_reconcile_out" >&2
     if [[ ( "$AUTONOMY_TIER" == "L2" || "$AUTONOMY_TIER" == "L3" ) ]] && \
        [[ "$AUTO_RETRY_ENABLED" == "true" ]] && \
        [[ "$CODE_RETRY_COUNT" -lt "$AUTO_RETRY_MAX_ITERATIONS" ]]; then
       CODE_RETRY_COUNT=$(( CODE_RETRY_COUNT + 1 ))
       export CODE_RETRY_COUNT
       echo "auto-retry: code phase silent no-op, retry ${CODE_RETRY_COUNT}/${AUTO_RETRY_MAX_ITERATIONS}" >&2
       if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
         EMIT_ISSUE_NUMBER="$ISSUE_NUMBER" emit_event "code_retry_fire" \
           "iteration=${CODE_RETRY_COUNT}" \
           "trigger_reason=silent_no_op"
       fi
       exec bash "$0" "$@"
     else
       if [[ ( "$AUTONOMY_TIER" == "L2" || "$AUTONOMY_TIER" == "L3" ) ]] && \
          [[ "$AUTO_RETRY_ENABLED" == "true" ]]; then
         echo "auto-retry 上限 (${CODE_RETRY_COUNT}/${AUTO_RETRY_MAX_ITERATIONS}) に達しました。手動で次アクションを選択してください。" >&2
       fi
       EXIT_CODE=1
     fi
   fi
   ```

   **`exec bash "$0" "$@"` を使う理由**: 現在のプロセスを新しい run-code.sh で置き換えることで、EXIT trap (`_maybe_emit_phase_complete`) の二重発火を防ぐ。`CODE_RETRY_COUNT` は `export` 済みなので継承される。

   **double-retry 懸念への対応**: `exec` でプロセスが置き換わるため、`run-auto-sub.sh` からの呼び出しでは `apply-fallback.sh` が呼ばれる前に `run-code.sh` が自身のリトライを完了する。加えて Step 3 で `apply-fallback.sh` に AUTO_RETRY_ENABLED ガードを追加する。

2. **`scripts/emit-event.sh`: `code_retry_fire` イベントスキーマ追加** (→ 受け入れ基準 3)

   既存の `verify_retry_fire` コメントブロックの直後に以下を追加:

   ```bash
   # code_retry_fire: run-code.sh が silent no-op 検出後に auto-retry を発火
   #   iteration=<n>                 code retry iteration counter (1-based within auto-retry)
   #   trigger_reason=<reason>       silent_no_op
   ```

3. **`scripts/apply-fallback.sh`: `code-patch-silent-no-op` ハンドラへの AUTO_RETRY_ENABLED ガード追加** (→ double-retry 防止)

   `apply_code_patch_silent_no_op_retry()` 関数の冒頭に以下を追加:

   ```bash
   apply_code_patch_silent_no_op_retry() {
     # Check if run-code.sh has built-in auto-retry configured; if so, skip Tier 2
     # to prevent double-retry (run-code.sh already exhausted its retries).
     local _ww_yml
     _ww_yml="$(dirname "$SCRIPT_DIR")/.wholework.yml"
     local _auto_retry_enabled="false"
     if [[ -f "$_ww_yml" ]]; then
       local _raw
       _raw=$(awk '/^auto-retry-on-fail:/{f=1; next} f && /^[[:space:]]+enabled:/{gsub(/.*enabled:[[:space:]]*/,""); gsub(/[[:space:]].*/,""); print; exit} /^[^[:space:]]/{f=0}' "$_ww_yml" | tr -d ' ')
       [[ "$_raw" == "true" ]] && _auto_retry_enabled="true"
     fi
     if [[ "$_auto_retry_enabled" == "true" ]]; then
       echo "[apply-fallback] code-patch-silent-no-op: AUTO_RETRY_ENABLED=true, built-in retry in run-code.sh already exhausted; skipping Tier 2 retry" >&2
       return 0
     fi
     echo "[apply-fallback] code-patch-silent-no-op: retrying run-code.sh --patch for issue $ISSUE" >&2
     "$SCRIPT_DIR/run-code.sh" "$ISSUE" --patch >> "$LOG_FILE" 2>&1
     echo "[apply-fallback] code-patch-silent-no-op: done" >&2
   }
   ```

4. **`tests/run-code.bats`: silent no-op auto-retry テスト追加** (→ 受け入れ基準 4, 5)

   既存の `reconcile: exit 0 + matches_expected:false results in exit 1` テストの後に以下を追加:

   a. `@test "auto-retry: silent no-op + AUTO_RETRY_ENABLED=true fires retry (exec re-invocation)"` — `reconcile-phase-state.sh` が `matches_expected:false` を返し、`AUTO_RETRY_ENABLED=true` かつ `AUTONOMY_TIER=L3` のとき、`CODE_RETRY_COUNT=1` で run-code.sh が再実行されることを確認

   b. `@test "auto-retry: silent no-op + AUTO_RETRY_ENABLED=false → no retry, exits 1"` — `AUTO_RETRY_ENABLED=false` のとき retry を発火させないことを確認

   c. `@test "auto-retry: CODE_RETRY_COUNT at max → no retry, exits 1 with advisory"` — `CODE_RETRY_COUNT=3` (MAX に等しい) のとき retry せず exit 1 かつ advisory メッセージを出力することを確認

   **テスト実装上の注意**: `exec` による再実行を直接テストするのは困難なため、`exec` の代わりに `run-code.sh` を再起動するモックまたは `CODE_RETRY_COUNT` の状態確認でテストする。`exec` 呼び出しの検証は `mock "$0"` パターンを利用 (既存テストの mock 構造を踏襲)。

5. **`docs/tech.md` + `docs/ja/tech.md`: Architecture Decision 追加** (→ 受け入れ基準 post-merge 2)

   `docs/tech.md` の `## Architecture Decisions` セクション末尾に追加:

   ```markdown
   - **code-side auto-retry (silent no-op)**: When `auto-retry-on-fail.enabled: true` and `autonomy: L2/L3`, `run-code.sh` internally retries after detecting `matches_expected: false` (silent no-op) from `reconcile-phase-state.sh`. Max retries from `auto-retry-on-fail.max_iterations` (also accepts legacy `threshold` key; default: 3). Retry counter (`CODE_RETRY_COUNT`) is passed via exported env var across `exec`-based re-invocations. Symmetric with verify-side auto-retry in `skills/verify/SKILL.md` Step 11(b) (same tier gate: L2/L3 + `AUTO_RETRY_ENABLED=true` + count < max). When built-in retry is active, `apply-fallback.sh`'s `code-patch-silent-no-op` Tier 2 handler is suppressed to prevent double-retry.
   ```

   `docs/ja/tech.md` の対応セクションを日本語で同期更新する。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-code.sh で reconcile-phase-state.sh の matches_expected:false 判定後、AUTONOMY_TIER が L2/L3 かつ AUTO_RETRY_ENABLED=true かつ retry 回数が max_iterations 未満の場合に claude を再起動するロジックが実装されている" --> run-code.sh に silent no-op auto-retry ループが追加されていること
- <!-- verify: rubric "code-side の retry 条件が skills/verify/SKILL.md Step 11(b) Tier-gated auto-retry check の発火条件と意味的に同等である (event 名と context のみ差異)" --> retry トリガ条件が verify-side と対称
- <!-- verify: file_contains "scripts/emit-event.sh" "code_retry_fire" --> `code_retry_fire` イベントが emit-event.sh に追加されていること
- <!-- verify: rubric "tests/run-code.bats もしくは新規 bats ファイルに、AUTO_RETRY_ENABLED=true 時の silent no-op recovery シナリオが含まれている" --> bats テストで silent no-op → auto-retry シナリオがカバーされていること
- <!-- verify: command "bats tests/" --> すべての bats テストがパスすること

### Post-merge

- 次回 silent no-op が観測された session で `code_retry_fire` イベントが `.tmp/auto-events.jsonl` に記録される <!-- verify-type: manual -->
- `docs/tech.md` の Architecture Decisions セクションに code-side auto-retry の言及が追加されている <!-- verify: rubric "docs/tech.md の Architecture Decisions セクションに code-side auto-retry (silent no-op 検出時の retry ロジック) への言及が含まれている" --> <!-- verify: section_contains "docs/tech.md" "## Architecture Decisions" "auto-retry" --> <!-- verify-type: auto -->

## Notes

### 双方向 retry 防止設計

- `run-auto-sub.sh` の Tier 2 (`apply-fallback.sh`) と `run-code.sh` 内部 retry の二重発火を防ぐため、`apply_code_patch_silent_no_op_retry()` に `AUTO_RETRY_ENABLED` ガードを追加する
- ガードが発火すると Tier 2 は `return 0` (skip) し、`run-auto-sub.sh` は recovery 成功として扱う。これにより max_iterations (3) × 2 = 6 回の試行になる問題を防止する
- `exec bash "$0" "$@"` を使う理由: `bash "$0" "$@"` (サブシェル) では呼び出し元の run-code.sh の残処理 (phase_complete emit 等) が続行されて二重 emit が発生する。`exec` はプロセスを置き換えるため EXIT trap の二重発火が起きない

### config キーの非対称性

- `detect-config-markers.md` は `auto-retry-on-fail.max_iterations` を定義しているが、本リポジトリの `.wholework.yml` は `threshold: 3` を使用している
- `run-code.sh` では両キー (`max_iterations` / `threshold`) を awk で読み取り、どちらか最初に見つかった値を使用する (後方互換)
- `detect-config-markers.md` の更新 (`threshold` キーのサポート追加) は本 Issue スコープ外

### WHOLEWORK_SCRIPT_DIR mock への影響

- 新規スクリプトを追加しないため (既存 `run-code.sh` の修正のみ)、`$MOCK_DIR` への mock 追加は不要
