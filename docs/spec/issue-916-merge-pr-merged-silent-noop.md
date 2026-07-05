# Issue #916: detect-wrapper-anomaly: merge phase の PR MERGED 状態で silent-no-op 誤検出を抑制

## Consumed Comments

No new comments since last phase.

## Overview

`scripts/detect-wrapper-anomaly.sh` の merge phase における exit code 0 判定ロジックが、実際には成功している PR merge を silent-no-op として誤検出する false positive が発生した (session `5169-1783172364`, PR #905 / Issue #897)。

原因は、merge phase の完了確認が (1) wrapper ログ内の `"matches_expected":true` 文字列検索、(2) ローカル `git log` の直近コミット検索、の 2 段階に依存しているが、いずれも merge phase には構造的に機能しないことにある。squash merge は GitHub API 経由で origin/main に対して行われるため、ローカル作業ツリーは自動的に fetch されず `git log --oneline -20` がタイミング依存で false negative になる。加えて `run-merge.sh` は `reconcile-phase-state.sh` (PR 状態を live API で確認済み) の結果を変数に capture するのみで成功時に stdout へ echo しないため、ログベースの `matches_expected:true` gate も merge phase に対しては never fire しない。

本 Spec は、`detect-wrapper-anomaly.sh` の merge phase 経路に `gh pr view <PR> --json state` による live PR MERGED 状態チェックを追加し、既存のログ/git-log ベースの判定に依存しない独立した確認手段を導入することで、false-positive な silent-no-op anomaly を抑制する (Issue 本文 Option A)。

## Reproduction Steps

1. `/auto` の pr route (または `--batch`) で Issue の merge phase を実行し、`run-merge.sh` が squash merge を GitHub API 経由で origin/main に対して成功させる (実例: PR #905 → squash merge commit `86cb279c`)。
2. `run-merge.sh` 内部で `reconcile-phase-state.sh merge <issue> --pr <PR> --check-completion` を実行し、`gh pr view` で PR state が `MERGED` であることを正しく確認する。ただし成功時 (`matches_expected:true`) は stdout に echo されないため、`run-auto-sub.sh` が保持する wrapper ログ (`$log_file`) にはこの確認結果が一切現れない。
3. `run-merge.sh` は exit code 0 を返し、`run-auto-sub.sh` が exit code 0 の分岐で `detect-wrapper-anomaly.sh --log "$log_file" --exit-code 0 --issue <PR番号> --phase merge` を呼び出す (merge phase では `--issue` に実際は PR 番号が渡される — `run_phase_with_recovery "merge" "$PR_NUMBER" ...` の既存の呼び出し規約による)。
4. `detect-wrapper-anomaly.sh` はログ内に `"matches_expected":true` を見つけられず (Step 2 参照)、成功フレーズ検索 (`commit and push` 等) にフォールスルーする。ログ内に成功フレーズが存在すると、ローカル `git log --oneline -20` でコミット検索を行うが、squash merge commit はまだローカルに fetch されておらず見つからない。
5. 既存の origin/main フォールバック fetch は `PHASE` が `code-patch`/`code` の場合のみ動作するため `merge` phase では実行されず、false-positive な `silent-no-op` anomaly が報告される。

## Root Cause

merge phase の完了確認において、`detect-wrapper-anomaly.sh` が参照できる情報源 (wrapper ログ・ローカル git log) がいずれも構造的に merge phase の実態を反映できていないことが根本原因である。

- `run-merge.sh` は `reconcile-phase-state.sh` (内部で `gh pr view --json state` という live API チェックを行い、PR MERGED 状態を正しく検出できる) を呼び出しているが、その結果 (`_reconcile_out`) は成功時に stdout へ一切 echo されない (失敗時のみ `>&2` で warning として出力される)。そのため `detect-wrapper-anomaly.sh` の第一段階チェック (`"matches_expected":true` のログ内検索) は merge phase に対して構造的に never fire しない
- squash merge は GitHub API 経由で origin/main に対して行われ、ローカル作業ツリーは自動 fetch されないため、第二段階チェック (ローカル `git log`) はタイミング依存で false negative になる
- 既存の origin/main フォールバック fetch (第三段階) は `code-patch`/`code` phase 限定で `merge` phase の対象外

Issue 本文 Option A が提案する通り、merge phase 専用に `gh pr view <PR> --json state` を直接呼び出す独立した live チェックを追加することが、上記いずれの構造的ギャップにも影響されない最も確実な修正となる。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: 変更 — `elif [[ "$EXIT_CODE" == "0" ]]` ブロック冒頭に、`PHASE == "merge"` の場合に `gh pr view "$ISSUE_NUMBER" --json state -q '.state'` で PR MERGED 状態を確認し、確認できた場合は silent-no-op 検出全体をスキップするゲートを追加 — bash 3.2+ compatible
- `tests/detect-wrapper-anomaly.bats`: 変更 — merge phase + `gh pr view` mock を用いた3ケース (MERGED で抑止 / 非MERGEDで検出継続 / `gh` 失敗時に既存ロジックへフォールスルー) を追加
- `modules/orchestration-fallbacks.md`: 変更 — `code-patch-silent-no-op` エントリの Exception Condition セクションに、merge phase 向けの live PR MERGED チェックによる抑制条件を追記
- `docs/structure.md`: [Steering Docs sync candidate] `detect-wrapper-anomaly.sh` の説明文 ("detect known failure patterns in shell wrapper output and generate Auto Retrospective markdown fragments") が本修正後も妥当か確認し、必要なら更新する
- `docs/ja/structure.md`: [Steering Docs sync candidate] 上記の日本語ミラー確認 (`docs/translation-workflow.md` Sync Procedure 準拠)

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` の `elif [[ "$EXIT_CODE" == "0" ]]; then` ブロック冒頭 (既存の `if grep -q '"matches_expected":true' "$LOG_FILE"; then` の直前) に、merge phase 専用の PR MERGED live チェックを追加する。`PHASE == "merge"` の場合のみ `gh pr view "$ISSUE_NUMBER" --json state -q '.state'` を実行し (stderr は `2>/dev/null` で抑制)、結果が `MERGED` であれば確認フラグを true にする。コマンド自体が失敗した場合 (非ゼロ終了、API エラーや rate limit 等) は確認フラグを false のまま維持する (fail-safe: MERGED 確認不能時は抑止しない。fail-open にはしない)。確認フラグが true の場合は既存の `matches_expected:true` チェック・成功フレーズ検索・git log 検索のいずれも実行せず silent-no-op 検出全体をスキップする。非 merge phase の既存ロジックには一切変更を加えない (→ acceptance criteria 1, 2)

2. `tests/detect-wrapper-anomaly.bats` の既存の "silent no-op: ..." テスト群の直後に3ケースを追加する (after 1) (→ acceptance criteria 3):
   - "silent no-op: suppressed for merge phase when gh pr view confirms MERGED" — `$BATS_TEST_TMPDIR/bin/gh` mock (`echo "MERGED"; exit 0`) と既存パターンの `git` mock (空返し) を用意し、成功フレーズを含むログで `--phase merge --issue 905` を実行、出力が空 (抑止) であることを検証する
   - "silent no-op: still detected for merge phase when gh pr view returns non-MERGED state" — `gh` mock が `echo "OPEN"; exit 0` を返すケースで、同条件でも `silent-no-op` が出力される (over-suppression していないことの回帰確認) ことを検証する
   - "silent no-op: falls through to existing logic when gh pr view fails" — `gh` mock が `exit 1` (出力なし) を返すケースで、`silent-no-op` が出力される (fail-safe デフォルトで抑止しないことの確認) ことを検証する

3. `modules/orchestration-fallbacks.md` の `code-patch-silent-no-op` エントリの Exception Condition セクションに、merge phase では `gh pr view --json state` による live PR MERGED チェックが独立した抑制条件として追加されている旨の一文を追記する (Implementation Step 1 と並行)

## Verification

### Pre-merge

- <!-- verify: rubric "detect-wrapper-anomaly.shがmerge phaseでPR状態がMERGEDの場合にsilent-no-op anomalyを出力しないよう修正されている" --> `detect-wrapper-anomaly.sh` の merge phase silent-no-op 検出が、PR が MERGED 状態の場合には anomaly を報告しないよう修正されている
- <!-- verify: file_contains "scripts/detect-wrapper-anomaly.sh" "MERGED" --> 上記の MERGED 状態チェックが `scripts/detect-wrapper-anomaly.sh` 内に実装されている
- <!-- verify: rubric "detect-wrapper-anomaly系bats に、merge phase かつ PR MERGED 状態のケースで silent-no-op anomaly が抑止されるテストが含まれる" --> bats test で、PR MERGED 状態の merge phase 完了ケースに対して anomaly が発生しないことが検証されている

### Post-merge

- 次回 `/auto` の pr route merge phase 完了時、false-positive silent-no-op が発生しないことを観察 <!-- verify-type: opportunistic -->

## Notes

- **fail-safe デフォルトの根拠**: Issue 本文の指示通り、`gh pr view` 自体が失敗した場合 (API エラー・rate limit 等) は MERGED 確認不能として扱い、既存の silent-no-op 判定ロジックにフォールスルーする。抑止側にフォールバックする fail-open ではなく、既存ロジック (誤検出リスクはあるが安全側) にフォールスルーする fail-safe を採用する。
- **`gh pr view --json state -q '.state'` の内部先例**: 同一パターンが `scripts/reconcile-phase-state.sh` の `_completion_merge()` (line 306) で既に本番稼働しており、対応する bats mock パターン (`tests/reconcile-phase-state.bats` の "merge completion" テスト群) も存在する。外部公式ドキュメントの再確認ではなく、この実績あるコードベース内先例に倣う。
- **`--issue` パラメータの意味論**: `detect-wrapper-anomaly.sh` の `--issue` 引数は、merge phase では実際には PR 番号を受け取る (`scripts/run-auto-sub.sh` の `run_phase_with_recovery "merge" "$PR_NUMBER" "$SCRIPT_DIR/run-merge.sh"` という既存の呼び出し規約により、`run_phase_with_recovery` 内のローカル変数 `issue` が merge phase では PR 番号を保持する)。これは本 Issue で新規導入する前提ではなく、既存コード (silent-no-op の `ANOMALY_DESC` が実際に PR 番号 `#905` を表示していた実インシデント) が示す既存の挙動であり、本修正はこの既存の値をそのまま `gh pr view` に渡す。`run-auto-sub.sh` 側の呼び出し規約・パラメータ命名の変更は本 Issue のスコープ外とする。
- **Option B (origin/main フォールバック適用範囲拡張) を不採用とした理由**: Issue 本文が推奨する通り Option A (live PR 状態チェック) を主軸として採用した。Option B は「ローカル git log が確認できない」という症状に対する間接的な緩和策に過ぎず、Option A (根本的な確認手段) を実装すれば merge phase 側では効果を発揮する場面がなくなるため、本 Spec の Changed Files には含めない。
- **`modules/orchestration-fallbacks.md` 更新は SHOULD レベル**: Issue 本文の Acceptance Criteria (Pre-merge 3件) はいずれも `scripts/detect-wrapper-anomaly.sh` とそのテストのみを対象としており、`modules/orchestration-fallbacks.md` の更新には専用の verify command が設定されていない。本 Spec でも Issue 本文の3件と件数・内容を完全一致させるため、`## Verification > Pre-merge` には追加の verify item を設けない (ドキュメント同期は Implementation Step 3 で対応する SHOULD 項目として扱う)。
- **Verify command sync 確認**: 本 Spec の `## Verification > Pre-merge` は Issue 本文 `## Acceptance Criteria > Pre-merge` の3項目と verify コマンドを含め完全に一致 (件数一致: Issue側3件 / Spec側3件)。Post-merge も Issue本文の1件と一致。
- **Issue body vs 実装の整合性確認**: Issue Background に記載の「既存の origin/main フォールバック fetch は `code-patch`/`code` phase 限定」という記述は `scripts/detect-wrapper-anomaly.sh` 現行実装 (line 103: `if [[ "$PHASE" == "code-patch" || "$PHASE" == "code" ]]`) と一致していることを確認済み。コンフリクトなし。
