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
<!-- phase: merge -->

### Key Decisions
- Squash-merged #931 into main as-is (CI green, review approved, no conflicts); no additional changes made at merge phase.

### Deferred Items
- Post-merge AC (opportunistic observation of a real `/auto` pr-route review phase clean-review completion) remains deferred to natural occurrence.

### Notes for Next Phase
- verify phase should confirm the "Verification (post-merge)" opportunistic AC in the Issue body when a matching clean-review event is next observed; otherwise the merge-time verification items are already satisfied by the merged bats suite (1094 PASS).

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 特記事項なし。Issue 本文の rubric AC (3件) と Spec の Verification セクションは件数・内容とも完全一致していた。

#### design
- 特記事項なし。#916 の merge phase live check と並行する設計は妥当で、実装との乖離もなかった。

#### code
- 特記事項なし。Implementation Steps 1-3 通りに実装され、bats 39件を実行し全 PASS を確認。

#### review
- 本 Issue #927 自身の `/auto` 実行中、review phase (`run-review.sh`, PR #931) で `detect-wrapper-anomaly.sh` の **別の** anomaly パターン `review-completion-false-negative` (#547) が誤検出した。実際には review は正常完了 (`gh pr view 931` で MERGED・AC Verification Results 投稿済みを確認) しており、加えて **#915 のフォールバック機構 (`post-fallback-review-summary.sh`) が実際に発火し Response Summary を正しく自動投稿していた** ことも確認した (`<!-- review-summary -->` マーカー付きコメントを確認済み)。このパターンは本 Issue #927 が対象とする `silent-no-op` (#365) とは独立した if-elif 分岐であり、スコープ外。post-hoc ログスキャンがログ内の初期警告文字列にのみマッチし、後続の recovery 成功メッセージを考慮していないことが原因と推測される。

#### merge
- 特記事項なし。CI green・review approved・conflict なしで squash merge 完了。

#### verify
- Pre-merge rubric AC 3件とも PASS (bats 39件全て実行し PASS を確認)。post-merge の opportunistic AC 1件は次回 clean review 完了時の自動観測待ちのため未チェックのまま `phase/verify` を維持。

### Improvement Proposals
- `scripts/detect-wrapper-anomaly.sh` の `review-completion-false-negative` (#547) パターンを、`post-fallback-review-summary.sh` による recovery 成功 (recheck で `matches_expected:true` に復帰) を考慮するよう補正する: `mid-run-api-error` パターンが既に採用している「Tier 1 reconciler (`reconcile-phase-state.sh --check-completion`) を再実行して `matches_expected:true` なら anomaly を抑止する」という手法を、`review-completion-false-negative` パターンにも同様に適用できると見込まれる。#916 (merge phase MERGED live check) および #927 (review phase Review 投稿 live check、本 Issue) に続く、同系統3件目の false positive 修正候補。実害は informational-only ログの事実誤認に限られるため優先度は中程度。
