# Issue #927: detect-wrapper-anomaly: review phase の clean review 完了時に silent-no-op を誤検出

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (triage 実行結果: タイトル正規化・Type=Bug・Size=M 判定根拠・Ambiguity 自動解決1件の記録。AC/verify command は変更なしとの判断) / https://github.com/saitoco/wholework/issues/927#issuecomment-4885506786

## Overview

`scripts/detect-wrapper-anomaly.sh` の silent-no-op 検出ロジックが、`review` phase において誤検出を起こすケースを修正する。`review` phase で "Acceptance Criteria Verification Results" を含む Review が PR に既に投稿済みであれば、新規コミットの有無に関わらず silent-no-op anomaly の報告を抑止する。#916 で `merge` phase に導入した `gh pr view --json state` による live チェックと同型のパターンを `review` phase に適用する。

## Reproduction Steps

1. `/auto` が Size M/L の Issue を PR route で実行し、review phase (`run-review.sh`) が MUST 修正不要の clean review (Acceptance Criteria Verification Results を含む Review 投稿のみ、新規コミットなし) で正常終了する (exit code 0)
2. `run-auto-sub.sh` が `detect-wrapper-anomaly.sh --log <log> --exit-code 0 --issue <PR番号> --phase review` を呼び出す
3. ログに完了フレーズ (例: "完了しました") が含まれる一方、直近の git log に該当 Issue 番号のコミットが見つからないため、`silent-no-op` anomaly が誤って報告される (実際には review 自体は正常完了している)

## Root Cause

`detect-wrapper-anomaly.sh` の `elif [[ "$EXIT_CODE" == "0" ]]` ブロックは、ログ内の完了フレーズと直近 git log のみを根拠に silent-no-op を判定しており、「review 自体は完了しているが新規コミットが発生しない」正常ケース (MUST 修正なしの clean review) を構造的に区別できない。#916 は同じ構造的ギャップを `merge` phase について `gh pr view --json state` の live チェックで解消したが、`review` phase には未適用だった。`scripts/post-fallback-review-summary.sh` が既に `gh pr view --json reviews --jq '.reviews[].body'` で "Acceptance Criteria Verification Results" を検出する実装パターンを持っており、同じ手法を `review` phase 専用の live チェックとして流用できる。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: change — `elif [[ "$EXIT_CODE" == "0" ]]` ブロック内、merge phase live チェックと並行して `PHASE == "review"` の場合に `gh pr view "$ISSUE_NUMBER" --json reviews --jq '.reviews[].body'` を実行し、出力に "Acceptance Criteria Verification Results" が含まれる場合は silent-no-op 検出をスキップするゲートを追加 — bash 3.2+ compatible
- `tests/detect-wrapper-anomaly.bats`: change — review phase + `gh pr view --json reviews` mock を用いた3ケース (Review 投稿済みで抑止 / Review 未投稿で検出継続 / `gh` 失敗時に既存ロジックへフォールスルー) を追加
- `modules/orchestration-fallbacks.md`: change — `code-patch-silent-no-op` エントリの Exception Condition セクションに、review phase 向けの live Review 投稿確認チェックによる抑制条件を追記 (SHOULD、専用 verify item なし。#916 と同様の判断)
- `docs/structure.md`: [Steering Docs sync candidate] `detect-wrapper-anomaly.sh` の説明文が本修正後も妥当か確認
- `docs/ja/structure.md`: [Steering Docs sync candidate] 上記の日本語ミラー確認 (`docs/translation-workflow.md` Sync Procedure 準拠)

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` の `elif [[ "$EXIT_CODE" == "0" ]]; then` ブロック内、既存の merge phase live チェック (`_merge_pr_confirmed_merged` の算出部分) の直後に、review phase 専用の Review 投稿 live チェックを追加する。`PHASE == "review"` の場合のみ `gh pr view "$ISSUE_NUMBER" --json reviews --jq '.reviews[].body'` を実行し (stderr は `2>/dev/null` で抑制)、コマンドが成功しかつ出力に "Acceptance Criteria Verification Results" が含まれる場合に確認フラグ (`_review_confirmed_posted`) を true にする。コマンド自体が失敗した場合 (非ゼロ終了、API エラーや rate limit 等) は確認フラグを false のまま維持する (fail-safe: 確認不能時は抑止しない。fail-open にはしない)。続く `if [[ "$_merge_pr_confirmed_merged" == "true" ]]; then ... elif grep -q '"matches_expected":true' ...` の判定チェーンに `elif [[ "$_review_confirmed_posted" == "true" ]]; then` の分岐を追加し、true の場合は既存の `matches_expected:true` チェック・成功フレーズ検索・git log 検索のいずれも実行せず silent-no-op 検出全体をスキップする。merge phase および非 review/merge phase の既存ロジックには一切変更を加えない (→ acceptance criteria 1, 2)
2. `tests/detect-wrapper-anomaly.bats` の既存の merge phase live チェックテスト群 ("silent no-op: falls through to existing logic when gh pr view fails" の直後) に3ケースを追加する (after 1) (→ acceptance criteria 3):
   - "silent no-op: suppressed for review phase when gh pr view confirms Review posted" — `$BATS_TEST_TMPDIR/bin/gh` mock (`echo "Acceptance Criteria Verification Results"; exit 0`) と既存パターンの `git` mock (空返し) を用意し、成功フレーズを含むログで `--phase review --issue <PR番号>` を実行、出力が空 (抑止) であることを検証する
   - "silent no-op: still detected for review phase when gh pr view shows no matching Review" — `gh` mock が無関係な文字列 (例: `echo ""; exit 0`) を返すケースで、同条件でも `silent-no-op` が出力される (over-suppression していないことの回帰確認) ことを検証する
   - "silent no-op: falls through to existing logic when gh pr view fails for review phase" — `gh` mock が `exit 1` (出力なし) を返すケースで、`silent-no-op` が出力される (fail-safe デフォルトで抑止しないことの確認) ことを検証する
3. `modules/orchestration-fallbacks.md` の `code-patch-silent-no-op` エントリの Exception Condition セクションに、review phase では `gh pr view --json reviews` による live Review 投稿確認チェックが独立した抑制条件として追加されている旨の一文を追記する (parallel with 1)

## Verification

### Pre-merge

- <!-- verify: rubric "detect-wrapper-anomaly.shがreview phaseでAcceptance Criteria Verification Resultsを含むReviewが既に投稿されている場合にsilent-no-op anomalyを出力しないよう修正されている" --> `detect-wrapper-anomaly.sh` の review phase silent-no-op 検出が、"Acceptance Criteria Verification Results" を含む Review が既に投稿されている場合には anomaly を報告しないよう修正されている
- <!-- verify: file_contains "scripts/detect-wrapper-anomaly.sh" "Acceptance Criteria Verification Results" --> 上記の live チェックが `scripts/detect-wrapper-anomaly.sh` 内に実装されている
- <!-- verify: rubric "detect-wrapper-anomaly系bats に、review phase かつ clean review (Acceptance Criteria Verification Results投稿済み・コミットなし) のケースで silent-no-op anomaly が抑止されるテストが含まれる" --> bats test で、review phase かつ clean review (Review 投稿済み・新規コミットなし) のケースに対して anomaly が発生しないことが検証されている

### Post-merge

- 次回 `/auto` の pr route review phase で clean review が完了した際、false-positive silent-no-op が発生しないことを観察 <!-- verify-type: opportunistic -->

## Notes

- **fail-safe デフォルトの根拠**: Issue 本文の Auto-Resolved Ambiguity Points に記載の通り、`gh pr view --json reviews` 自体が失敗した場合は Review 投稿未確認として扱い、既存の silent-no-op 判定ロジックにフォールスルーする (fail-open にはしない)。#916 の `merge` phase 修正と同一方針。
- **`gh pr view --json reviews --jq '.reviews[].body'` の内部先例**: 同一パターンが `scripts/post-fallback-review-summary.sh` (line 25) で既に本番稼働している。外部公式ドキュメントの再確認ではなく、この実績あるコードベース内先例に倣う。
- **"Acceptance Criteria Verification Results" の実装確認**: `skills/review/SKILL.md` line 496 の実際の出力見出し `## Acceptance Criteria Verification Results` と一致することを確認済み。
- **`--issue` パラメータの意味論**: review phase では `run-auto-sub.sh` の `run_phase_with_recovery "review" "$PR_NUMBER" "$SCRIPT_DIR/run-review.sh"` という既存の呼び出し規約により、`detect-wrapper-anomaly.sh` の `--issue` 引数は実際には PR 番号を受け取る (#916 の merge phase と同型)。既存の呼び出し規約の変更は本 Issue のスコープ外。
- **`modules/orchestration-fallbacks.md` 更新は SHOULD レベル**: Issue 本文の Acceptance Criteria (Pre-merge 3件) はいずれも `scripts/detect-wrapper-anomaly.sh` とそのテストのみを対象としており、専用の verify command は設定しない (#916 と同様の判断。Verify command sync のため Issue 本文と件数を完全一致させる)。
- **Verify command sync 確認**: 本 Spec の `## Verification > Pre-merge` は Issue 本文 `## Acceptance Criteria > Pre-merge` の3項目と verify コマンドを含め完全一致 (件数一致: Issue側3件 / Spec側3件)。Post-merge も Issue 本文の1件と一致。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜3 を記載順どおりに実装した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Mirrored the #916 merge-phase live-check pattern exactly for the review phase (`gh pr view --json reviews --jq '.reviews[].body'` + grep for "Acceptance Criteria Verification Results"), placed directly after the existing `_merge_pr_confirmed_merged` computation and wired as a new `elif` branch ahead of the log/git-log-based checks.
- Kept the fail-safe default: `gh pr view` failure or no matching Review falls through to the existing silent-no-op logic (not fail-open), consistent with #916 and `post-fallback-review-summary.sh`.

### Deferred Items
- `modules/orchestration-fallbacks.md` update is SHOULD-level only (no dedicated pre-merge verify command targets it), consistent with the #916 precedent.
- Post-merge AC (opportunistic observation of a real `/auto` pr-route review phase clean-review completion) is deferred to natural occurrence — no action needed at code phase.

### Notes for Next Phase
- Full `bats tests/` suite (1094 tests) passes after this change; no other test file references `scripts/detect-wrapper-anomaly.sh` or `modules/orchestration-fallbacks.md` beyond their direct-counterpart test files.
- No SKILL.md files were touched; `docs/structure.md` / `docs/ja/structure.md` descriptions of `detect-wrapper-anomaly.sh` remain accurate at the current level of detail (checked, no update needed).
