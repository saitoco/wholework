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

- <!-- verify: grep "observation|opportunistic|manual" "scripts/get-auto-session-report.sh" --> verify-type 分類ロジックが実装されている
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

## Code Retrospective

### Deviations from Design

- Spec の heredoc 出力で `printf '%s\n'` を使用。`printf '%s'` では末尾改行が欠けてテーブル行が次の行と結合するため改行付きに変更した。

### Design Gaps/Ambiguities

- Spec AC #1 の `grep "observation\|opportunistic\|manual"` は BRE 記法 (`\|`) を使用しており、ERE (ripgrep) では literal `|` として扱われ false FAIL になる。実装後に miscalibrated と判定し `observation|opportunistic|manual`（bare pipe）に修正した。

### Rework

- None

## review retrospective

### Spec vs. implementation divergence patterns

- Spec の heredoc 内で `printf '%s'` と記述したが実装は `printf '%s\n'` を採用。Code Retrospective に記録済み。今後 Spec 記述時は `printf` の末尾改行有無を明示すると divergence が防げる。

### Recurring issues

- Nothing to note. AC の verify command ERE/BRE 誤記 (BRE `\|` を ERE 文脈で使用) は Code Retrospective に記録済み。発生源は Spec 記述時のレギュラー表現フレーバー未確認。grep verify command は常に ERE として記述する慣習の徹底で再発防止可能。

### Acceptance criteria verification difficulty

- すべての AC が PASS または POST-MERGE で、UNCERTAIN なし。`command "bats ..."` は safe モードで CI 代替検証が成立 (CI ジョブ "Run bats tests" SUCCESS)。verify command の品質は良好。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- コンフリクト解決: `tests/audit-auto-session.bats` の衝突は両側テストを両方取り込む保守的マージで解決 (phase-666 テストと verify-type テストを並置)
- スクワッシュマージ完了 (PR #676 は既にマージ済み状態を確認)
- 7/7 bats テスト全グリーン確認後にプッシュ・マージ

### Deferred Items
- Post-merge observation AC: 次回 `/auto` 完走後に `## Verify Phase Residuals` セクションが verify-type 内訳テーブル形式で出力されることを確認 (event=auto-run)
- 複数 event 重複除去 (event=auto-run,auto-run 問題) は引き続き未解決 — 別 Issue にて追跡予定

### Notes for Next Phase
- verify フェーズでは post-merge observation AC (次回 /auto 完走後の動作確認) が主要残タスク
- `WHOLEWORK_ISSUE_BODY_DIR` 環境変数は BATS テスト専用; 本番では `gh issue view` にフォールバック
- label は `verify` に移行済み

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- AC 5 件すべて自動検証可能 (grep × 2、command × 1、rubric × 1、section_contains × 1)。triage 段階で `section_contains` を rubric 補助として追加した判断が verify で機能 (UNCERTAIN ゼロ)。

#### spec
- Size 当初 S → spec 段階で L に upgrade。phase/verify 残 Issue 別の API 呼び出し + verify-type マッピングロジック追加で実装範囲が当初予測より大きくなったため適切な判断。
- pr route (full review) に移行で review 効果を最大化。

#### code
- 1 PR (#676) で完了。tests/audit-auto-session.bats でコンフリクトあり（並行 batch session の他 PR と衝突）。保守的マージで両側テストを取り込んで解決。

#### review
- full review 実施。具体的な指摘内容は PR コメント参照だが、CONSIDER level の議論で深掘り。

#### merge
- squash merge `--delete-branch` で main 統合。前述コンフリクトを解決済みで CI green、conflict なし。
- 複数 event 重複除去 (event=auto-run,auto-run 問題) を Deferred Item として記録。

#### verify
- 5/5 PASS。bats 7 件全 PASS。
- 本実装によりこのセッション (`22090-1781508629`) 以降の `/audit auto-session` で verify-type breakdown が表示される。

### Improvement Proposals
- (CONSIDER) `verify-type: observation event=auto-run,auto-run` のような重複 event 名のパース処理を別 Issue で追跡。本実装では deferred。merge phase handoff にも記載済み。
- (HIGH) tests/audit-auto-session.bats のコンフリクト発生は #666 / #667 / #669 系列の並行 PR で頻発。session-report 拡張系 Issue は同時並行で進めると merge 順序で必ず衝突するため、batch 順序最適化（同領域 Issue を逐次配置 or 統合 spec）を検討すべき。

