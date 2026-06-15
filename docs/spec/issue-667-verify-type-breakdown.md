# Issue #667: audit/auto-session verify phase 残 verify-type サブカテゴリ分解

## Overview

`/audit auto-session` レポートの `## Verify Phase Residuals` セクションを拡張し、残存 Issue ごとに未チェック AC の verify-type (observation/opportunistic/manual) 内訳テーブルを追加する。`/audit stats` Section 7 メトリクス (Observation waiting / Opportunistic remaining / Manual waiting) と同等の分類を session-report 側にも持たせ、backlog の健全性判断を可能にする。

## Changed Files

- `scripts/get-auto-session-report.sh`: 
  - `ISSUE_BODY_DIR="${WHOLEWORK_ISSUE_BODY_DIR:-}"` 変数追加 (`NO_GITHUB` 初期化直後)
  - `VERIFY_RESIDUALS` ループの前に verify-type breakdown 計算ブロック追加 (`VERIFY_RESIDUALS_TABLE` / `VERIFY_RESIDUALS_AGGREGATE` 変数生成)
  - `## Verify Phase Residuals` heredoc セクション (現行 lines 409-416) をテーブル形式に置換
  - bash 3.2+ compatible (associative array 不使用)
- `tests/audit-auto-session.bats`: `@test "success: verify-type breakdown appears in Verify Phase Residuals section"` 追加 (fixture: `issue-bodies/471.md`, `issue-bodies/645.md`、`WHOLEWORK_ISSUE_BODY_DIR` 経由で注入)
- `docs/tech.md`: Environment Variables テーブルに `WHOLEWORK_ISSUE_BODY_DIR` 行追加

## Implementation Steps

1. `scripts/get-auto-session-report.sh` — breakdown 計算ブロック追加 (→ AC 1, 4, 5)

   `VERIFY_RESIDUALS` 計算直後、heredoc (`cat > "$OUTPUT_PATH"`) の前に以下を追加:

   ```bash
   ISSUE_BODY_DIR="${WHOLEWORK_ISSUE_BODY_DIR:-}"
   ```

   次に、`VERIFY_RESIDUALS_TABLE=""` と `VERIFY_RESIDUALS_AGGREGATE=""` および集計変数 (`_total_obs=0` 等) を初期化し、`$VERIFY_RESIDUALS` をループで処理するブロックを追加:

   - body 取得: `WHOLEWORK_ISSUE_BODY_DIR` が設定されている場合 `${ISSUE_BODY_DIR}/${_r}.md` を読む; NO_GITHUB=false の場合 `gh issue view "$_r" --json body,title`; それ以外は body/title 空文字
   - post-merge 未チェック行抽出: body を行ループで処理し、`### Post-merge` 以降かつ次の `###` 手前の `- [ ]` 行を対象に verify-type を判定
     - `verify-type: observation event=<name>` → obs カウント増加、event 名を記録
     - `verify-type: opportunistic` → opp カウント増加
     - それ以外 (verify-type: manual または マーカーなし) → manual カウント増加
   - テーブル行: `| #${_r} | ${_title:-#${_r}} | ${_obs_str} | ${_opp_count} | ${_manual_count} |`
   - observation の event 内訳: `_obs_str` は obs_count が 0 なら `0`、そうでなければ `N (event=<names>)`
   - 集計: `_total_obs`, `_total_opp`, `_total_manual` を加算、観測イベント名リストを文字列連結で構築

   `VERIFY_RESIDUALS_TABLE` にテーブル行を蓄積し、`VERIFY_RESIDUALS_AGGREGATE` に集計行 (`- observation waiting: N` 等) を生成する。テーブルが空の場合は `VERIFY_RESIDUALS_TABLE="| (none) | — | — | — | — |"` とする。

2. `scripts/get-auto-session-report.sh` — heredoc セクション置換 (→ AC 2, 5)

   現行の `## Verify Phase Residuals` ブロック:
   ```
   ## Verify Phase Residuals

   $(if [[ -z "$VERIFY_RESIDUALS" ]]; then
     echo "(none)"
   else
     for _r in $VERIFY_RESIDUALS; do
       echo "- Issue #${_r}: phase/verify not completed"
     done
   fi)
   ```

   を以下に置換:
   ```
   ## Verify Phase Residuals

   $(
     if [[ -z "$VERIFY_RESIDUALS" ]]; then
       echo "(none)"
     else
       # verify-type breakdown: observation / opportunistic / manual
       echo "Total: ${VERIFY_RESIDUALS_TOTAL} phase/verify remaining"
       echo ""
       echo "| Issue | Title | observation event=* | opportunistic | manual |"
       echo "|---|---|---|---|---|"
       printf '%s' "${VERIFY_RESIDUALS_TABLE}"
       echo ""
       printf '%s' "${VERIFY_RESIDUALS_AGGREGATE}"
     fi
   )
   ```

   これにより `section_contains` が `"## Verify Phase Residuals"` セクション内で `"observation"` を検出できる。

3. `tests/audit-auto-session.bats` と `docs/tech.md` 更新 (→ AC 3)

   bats テスト追加: `@test "success: verify-type breakdown appears in Verify Phase Residuals section"` 内で
   - event fixture: issue 471 (phase_start verify あり、phase_complete なし)、issue 645 (同様)
   - `$BATS_TEST_TMPDIR/issue-bodies/471.md` に `- [ ] ... <!-- verify-type: observation event=auto-run -->` 1行
   - `$BATS_TEST_TMPDIR/issue-bodies/645.md` に `- [ ] ... <!-- verify-type: opportunistic -->` 1行 + `- [ ] ... <!-- verify-type: manual -->` 1行
   - `export WHOLEWORK_ISSUE_BODY_DIR="$BATS_TEST_TMPDIR/issue-bodies"` を設定して `--no-github` で実行
   - assert: `grep -q "observation" "$OUTPUT_PATH"`, `grep -q "opportunistic" "$OUTPUT_PATH"`, `grep -q "#471" "$OUTPUT_PATH"`, `grep -q "auto-run" "$OUTPUT_PATH"`

   `docs/tech.md` 更新: Environment Variables テーブルの既存行 (`WHOLEWORK_CONFIG_PATH` の後) に追加:
   ```
   | `WHOLEWORK_ISSUE_BODY_DIR` | *(unset)* | Override the issue body source used by `scripts/get-auto-session-report.sh` when fetching verify-type breakdown. When set, reads `${WHOLEWORK_ISSUE_BODY_DIR}/<issue_number>.md` instead of calling `gh issue view`. Used in BATS tests for hermetic execution. When unset or empty, falls back to `gh issue view` (or skips when `--no-github`). |
   ```

## Verification

### Pre-merge

- <!-- verify: grep "observation\|opportunistic\|manual" "scripts/get-auto-session-report.sh" --> verify-type 分類ロジックが実装されている
- <!-- verify: grep "Verify Phase Residuals" "scripts/get-auto-session-report.sh" --> セクション heading が維持されている
- <!-- verify: command "bats tests/audit-auto-session.bats" --> bats テストが green (verify-type fixture を追加)
- <!-- verify: rubric "Verify Phase Residuals section shows per-issue verify-type breakdown table (observation event=*, opportunistic, manual columns) and aggregate counts matching /audit stats Section 7 conventions" --> rubric 基準を満たす
- <!-- verify: section_contains "scripts/get-auto-session-report.sh" "## Verify Phase Residuals" "observation" --> Verify Phase Residuals セクションに observation 分類ロジックが含まれる

### Post-merge

- 次回 `/auto` 完走後の `/audit auto-session` レポートで本セクションが期待通り集計されることを確認 <!-- verify-type: observation event=auto-run -->

## Notes

- `WHOLEWORK_ISSUE_BODY_DIR` は BATS 専用。`WHOLEWORK_SCRIPT_DIR` / `WHOLEWORK_CONFIG_PATH` と同じパターン
- `--no-github` かつ `WHOLEWORK_ISSUE_BODY_DIR` 未設定の場合: body 空文字扱い → per-type カウントはすべて 0 (`—` ではなく 0 を表示。テーブル構造を維持する)
- observation の event 別内訳は文字列連結で構築 (bash 3.2+ で associative array 不使用)
- 既存の `VERIFY_REMAINING` (GitHub labels から算出) とは別のカウント。`VERIFY_RESIDUALS` はイベントログから算出
