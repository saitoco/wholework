# Issue #915: review: run-review.sh が MUST 修正 push 後に Review Response Summary 未投稿で silent no-op を返すパターンが継続発生する

## Consumed Comments

No new comments since last phase.

## Overview

`run-review.sh` は既に exit 0 + `reconcile-phase-state.sh review <issue> --pr <PR> --check-completion` の `matches_expected:false` (diagnosis: "Review Response Summary not found in PR #N comments") を検出して `EXIT_CODE=1` を返す仕組みを持つ (#394/#528 で導入済み)。しかし検出後のリカバリは `modules/orchestration-fallbacks.md` の `review-completion-false-negative` エントリが記述する手動手順 ("PR コメントを確認し、無ければ /review を再実行する") に依存しており、`run-review.sh` 自体や `apply-fallback.sh` に自動化されたフォールバック投稿の仕組みがない。この結果、同一パターンの failure が batch session `5169-1783172364` (2026-07-04〜05) 内で PR #901 (Issue #893) と PR #907 (Issue #906) の 2 回連続で発生し、いずれも親 `/auto` セッションが手動で Response Summary コメントを投稿する ad-hoc 対応を行った。

本 Spec は `run-review.sh` 自体に、silent no-op 検出直後に決定論的なフォールバック投稿を試みる仕組みを追加する。新規スクリプト `scripts/post-fallback-review-summary.sh` は、Step 11 (Post Review Results) が既に完了していた証跡 (`gh pr view --json reviews` に "Acceptance Criteria Verification Results" 見出しを含む Review が存在すること) を確認できた場合のみ、`<!-- review-summary -->` マーカー付きの簡易 Response Summary をフォールバック投稿する。この証跡確認ガードにより、review が実質的に進行していなかったケースでの誤った "recovered" 報告を防ぐ (PR #901・#907 の両実インシデントで、この証跡パターンが共通して観測されたことを確認済み)。

## Reproduction Steps

1. Size M/L の Issue の PR に対して `/auto` (または `/review`) を実行し、Review Claude が Step 10 (Multi-perspective Code Review) → Step 11 (Post Review Results) まで完了する。
2. MUST issue が検出された場合は Step 12 で修正コミットを作成・push する (PR #907 のように SHOULD のみで fix なしの場合もある)。
3. push 後、Claude セッションが Step 13 (Acceptance Criteria Consistency Check) / Step 14 (Post Response Summary) に到達せず exit 0 で silent に終了する。
4. `run-review.sh` が `reconcile-phase-state.sh review <issue> --pr <PR> --check-completion` を実行し、`matches_expected:false` (diagnosis: "Review Response Summary not found in PR #N comments") を検出して `EXIT_CODE=1` で終了する。
5. `/auto` 側の Tier 2 (`detect-wrapper-anomaly.sh` → `review-completion-false-negative` パターン) が一致し、`modules/orchestration-fallbacks.md` のカタログ手順 (PR コメント確認 → 無ければ `/review` 再実行) を LLM が読むが、実際には親セッションが手動で summary コメントを投稿する ad-hoc 対応となった。

実際に PR #901 (Issue #893) と PR #907 (Issue #906) で 2 回連続発生した (batch session `5169-1783172364`, 2026-07-04〜05)。両 PR とも `gh pr view --json reviews` で "## Acceptance Criteria Verification Results" を本文に含む Review が既に投稿されていることを確認済み (Step 11 は完了していた)。

## Root Cause

`skills/review/SKILL.md` の Step 12 (Issue Resolution and Fixes) → Step 13 (Acceptance Criteria Consistency Check) → Step 14 (Post Response Summary) の間には、Step 14 の実行を構造的に保証する仕組みがない。Autonomous 実行下で、修正コミット push 後に LLM が「重要な作業は完了した」と判断し Step 14 (体裁を整える最終ステップ) を実行せず早期終了するリスクが構造的に残っている。

`run-review.sh` は exit 0 + `matches_expected:false` の検出自体は既に正しく機能している (#394/#528) が、検出後のリカバリ手段が `modules/orchestration-fallbacks.md` の `review-completion-false-negative` エントリが記述する手動手順のみであり、`apply-fallback.sh` にも `run-review.sh` にも自動化されたフォールバック投稿ロジックが実装されていない。このため、Tier 2 (LLM が catalog を読んで手動適用) の段階で LLM が catalog の推奨手順 (`/review` 再実行) ではなく ad-hoc に summary コメントを直接投稿する、という一貫しない挙動が 2 回連続で発生した。

## Changed Files

- `scripts/post-fallback-review-summary.sh`: 新規 — PR 番号を受け取り、`gh pr view --json reviews` で "Acceptance Criteria Verification Results" を含む Review の存在を確認できた場合のみ `<!-- review-summary -->` マーカー付きの簡易 Response Summary を `gh pr comment` で投稿するフォールバックスクリプト。証跡が確認できない場合は投稿せず exit 1 — bash 3.2+ compatible
- `scripts/run-review.sh`: 変更 — 既存の exit 0 + `matches_expected:false` 分岐 (L178 付近、`elif echo "$_reconcile_out" | grep -q '"matches_expected":false'` ブランチ) 内で、既存の warning 出力後に `post-fallback-review-summary.sh` を呼び出し、成功時は completion を再チェックして `matches_expected:true` なら `EXIT_CODE=0` に復帰、それ以外は既存どおり `EXIT_CODE=1` を維持する — bash 3.2+ compatible
- `tests/post-fallback-review-summary.bats`: 新規 — 新規スクリプトの単体テスト (証跡なし時は投稿しない、証跡あり時はマーカー付きで投稿する、`gh pr comment` 失敗時は exit 1 を返す)
- `tests/run-review.bats`: 変更 — `setup()` に `post-fallback-review-summary.sh` のデフォルト mock (exit 1) を追加 (既存の "results in exit 1" テストの回帰防止)、フォールバック成功で `EXIT_CODE=0` に復帰するケースとフォールバック失敗時に `EXIT_CODE=1` を維持するケースの新規テストを追加
- `modules/orchestration-fallbacks.md`: 変更 — `review-completion-false-negative` エントリの Fallback Steps に、`run-review.sh` が自動フォールバック投稿を既に試行済みであることを明記する一文を追加
- `docs/structure.md`: 変更 — Scripts セクション (Process management) に `post-fallback-review-summary.sh` のエントリを追加し、Directory Layout の `scripts/` ファイル数を63→64、`tests/` ファイル数を94→95 に更新
- `docs/ja/structure.md`: 変更 — 上記の日本語ミラー同期 (`docs/translation-workflow.md` Sync Procedure 準拠)

## Implementation Steps

1. `scripts/post-fallback-review-summary.sh` を新規作成する (→ acceptance criteria 1):
   - 引数: PR 番号 (`${1:?Usage: post-fallback-review-summary.sh <pr-number>}`)
   - ガード: `gh pr view "$PR_NUMBER" --json reviews --jq '.reviews[].body'` の出力に "Acceptance Criteria Verification Results" が含まれるか確認する。含まれない場合は stderr にメッセージを出力して exit 1 (投稿しない)
   - ガード通過時: `<!-- review-summary -->` マーカーを先頭行に置き、`## Review Response Summary` 見出し、これが自動生成されたフォールバックである旨、マージ前に CI 状態と修正内容を手動確認するよう推奨する旨を含む本文を組み立てる
   - `gh pr comment "$PR_NUMBER" --body "$BODY"` で投稿する。成功時 exit 0、失敗時は stderr にメッセージを出力して exit 1

2. `scripts/run-review.sh` の既存の `elif echo "$_reconcile_out" | grep -q '"matches_expected":false'` ブランチ (exit 0 + silent no-op 検出時) を修正する (after 1) (→ acceptance criteria 1):
   - 既存の `echo "Warning: ..." >&2` の後に `"$SCRIPT_DIR/post-fallback-review-summary.sh" "$PR_NUMBER"` を呼び出す
   - 呼び出しが成功した場合、`"$SCRIPT_DIR/reconcile-phase-state.sh" review "$_REVIEW_ISSUE" --pr "$PR_NUMBER" --check-completion` を再実行し、出力に `"matches_expected":true` が含まれれば recovery メッセージを出力して `EXIT_CODE=0` に復帰する
   - フォールバックスクリプトが失敗した場合、または再チェックが依然 `matches_expected:false` の場合は、既存どおり `EXIT_CODE=1` を維持する (変更なし)

3. `tests/post-fallback-review-summary.bats` を新規作成する (after 1) (→ acceptance criteria 2):
   - "no AC Verification Results review: exits 1 without posting" — `gh` mock が reviews のない状態を返すケースで `gh pr comment` が呼ばれないことを検証
   - "AC Verification Results review exists: posts marker comment" — `gh` mock が該当 Review を返すケースで `<!-- review-summary -->` を含む本文が `gh pr comment` に渡されることを検証
   - "gh pr comment failure propagates as exit 1" — `gh pr comment` が失敗するケースで exit 1 になることを検証

4. `tests/run-review.bats` を修正する (after 2, 3) (→ acceptance criteria 2):
   - `setup()` の `$MOCK_DIR` に `post-fallback-review-summary.sh` のデフォルト mock (exit 1) を追加する — 既存の "reconcile: exit 0 + matches_expected:false results in exit 1" テストが回帰なく PASS することを確認する
   - 新規テスト "reconcile: fallback post succeeds and recheck confirms matches_expected:true results in exit 0" を追加する。`reconcile-phase-state.sh` mock をステートフルにし (フォールバック投稿前は false、投稿後は true を返す)、`post-fallback-review-summary.sh` mock が成功する前提で `$status -eq 0` を検証する
   - 新規テスト "reconcile: fallback post itself fails keeps exit 1" を追加する。`post-fallback-review-summary.sh` mock が exit 1 を返す前提で `$status -eq 1` を検証する

5. ドキュメントを同期する (Implementation Step 1-4 と並行, → SHOULD):
   - `modules/orchestration-fallbacks.md` の `review-completion-false-negative` エントリの Fallback Steps に、`run-review.sh` が exit 0 + `matches_expected:false` 検出時に `post-fallback-review-summary.sh` による自動フォールバック投稿を既に試行済みであり、本エントリの手動手順は自動フォールバックも失敗した場合にのみ必要になる旨を追記する
   - `docs/structure.md` の Scripts セクション (Process management) に `post-fallback-review-summary.sh` のエントリを追加し、Directory Layout の `scripts/` ファイル数コメントを63→64、`tests/` ファイル数コメントを94→95 に更新する
   - `docs/ja/structure.md` に上記の日本語ミラーを同期する (`docs/translation-workflow.md` Sync Procedure 準拠)

## Verification

### Pre-merge

- <!-- verify: rubric "run-review.sh または skills/review/SKILL.md に、修正コミットpush後のReview Response Summary投稿が保証される仕組み (structural step 順序 / fallback 投稿 / recovery entry いずれか) が実装されている" --> `run-review.sh` に silent no-op 検出後のフォールバック Response Summary 投稿の仕組みが実装されている
- <!-- verify: rubric "run-review 関連の bats に、修正コミット push 完了後に Response Summary が投稿されず silent no-op で exit するケースの検知/フォローアップテストが含まれる" --> `tests/run-review.bats` / `tests/post-fallback-review-summary.bats` に silent no-op 検知・フォールバック投稿のテストが含まれる

### Post-merge

- 次回 `/auto` セッション実行時、修正コミットのある PR で Response Summary の欠落が発生しない (または wrapper が確実に補完する) ことを観察 <!-- verify-type: opportunistic -->

## Notes

- **Option A vs Option B の採否**: Issue 本文は Option A (SKILL.md step 順序強制 + 完了マーカー必須化) を推奨としているが、Option A の「SKILL.md 側の記述強化」はプロンプトレベルの指示に留まり、LLM の early-stop を構造的に防ぐ保証にはならない (今回の2件のインシデントも、既存の SKILL.md Step 14 の指示自体は明確だったにもかかわらず発生した)。一方 `run-review.sh` の reconcile ベースの exit 0 + `matches_expected:false` 検出は既に structurally 実装済み (#394/#528) であり、真に欠けていたのは「検出後の決定論的なリカバリ」だった。そのため本 Spec は Option B (wrapper 側でのフォールバック投稿) を採用し、Issue 本文の AC rubric が許容する3つのアプローチ (structural step順序 / fallback投稿 / recovery entry) のうち fallback投稿 + recovery entry 更新の組み合わせで対応する。
- **ガード条件の根拠**: 実インシデント PR #901・#907 の両方で `gh pr view --json reviews` を実際に確認したところ、いずれも "## Acceptance Criteria Verification Results" を本文に含む Review が既に投稿されていた (Step 11 完了の証跡)。一方 PR #907 は修正コミットが存在しない (SHOULD のみで fix なし) ため、「修正コミットの有無」をガード条件にすると #907 のケースを捕捉できない。そのため「Step 11 の Review 投稿」をガード条件として採用した。
- **スコープ外の関連発見 (対応は別 Issue を推奨、本 Spec の Changed Files には含めない)**: `scripts/detect-wrapper-anomaly.sh` の `reconciler-header-mismatch` パターン (L85) は `grep -q "Review Summary"` を検索条件としているが、実際の `reconcile-phase-state.sh` の diagnosis 文言は "Review Response Summary not found" であり、"Review" と "Summary" の間に "Response" が入るため `"Review Summary"` という連続文字列とは一致しない。この結果、review phase の completion mismatch は常に `review-completion-false-negative` パターンに分類され、`reconciler-header-mismatch` パターンは実質的に到達不能になっている (pattern misattribution)。本 Issue の Purpose (Response Summary 投稿の保証) には直接影響しないため本 Spec の Changed Files には含めないが、パターン名の誤帰属を修正する価値はあるため、別 Issue での対応を推奨する。
- **既存の安全網との関係**: `/merge` skill は `gh-pr-merge-status.sh` の `mergeable` 状態のみを見て merge 可否を判断しており、Issue 本文の Acceptance Criteria チェックボックス状態を独立に再検証しない。そのため本 Spec のフォールバック投稿によって `matches_expected:true` に復帰したとしても、実際に AC が検証されていない PR が merge されるリスクは理論上残る。ただし `/verify` が post-merge で Acceptance Criteria を独立に再検証し FAIL 時に Issue を reopen する設計になっているため、最終的な正しさは `/verify` フェーズで担保される (`docs/product.md` Vision の "verifies that the delivered artifact matches the acceptance criteria after merge" という設計方針どおり)。
- **重複投稿の可能性**: `run-review.sh` がリトライされ、2 回目の実行で LLM が正常に Step 14 まで到達して本来の Response Summary を投稿した場合、1 回目のフォールバック投稿と合わせて PR に `<!-- review-summary -->` マーカー付きコメントが 2 件残る可能性がある。`reconcile-phase-state.sh` はマーカーの存在有無のみを見るため機能的な問題はないが、コメント欄が冗長になる cosmetic な tradeoff として許容する (dedup ロジックは本 Issue のスコープ外)。
- **allowed-tools への影響なし**: `post-fallback-review-summary.sh` は `run-review.sh` (bash サブプロセス) から呼び出されるため、`skills/review/SKILL.md` の `allowed-tools` frontmatter への追加は不要 (既存の `apply-fallback.sh` 等、wrapper script 間の内部呼び出しと同じパターン)。
- **Issue body vs 実装の整合性確認**: Issue Background に記載の「reconcile: matches_expected:false ... → wrapper exit 1」は `scripts/run-review.sh` の現行実装 (L178-181) と一致していることを確認済み。コンフリクトなし。
- **Verify command sync 確認**: 本 Spec の `## Verification > Pre-merge` は Issue 本文 `## Acceptance Criteria > Pre-merge` の2項目と verify コマンドを含め完全に一致 (件数一致: Issue側2件 / Spec側2件)。Post-merge も Issue本文の1件と一致。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Implementation Steps 1〜5 をそのままの順序・内容で実装した (deviation なし)
- `post-fallback-review-summary.sh` のガード条件は Spec 記載どおり "Acceptance Criteria Verification Results" を含む既存 Review の有無とし、修正コミットの有無はガードに使わなかった (#907 が修正コミットなしのケースだったため)
- `tests/run-review.bats` の再チェック用 `reconcile-phase-state.sh` mock は呼び出し回数に応じて出力を切り替えるステートフルな実装 (1回目 false、2回目以降 true) にして、フォールバック投稿前後の状態遷移を検証した

### Deferred Items
- `scripts/detect-wrapper-anomaly.sh` の `reconciler-header-mismatch` パターンの誤帰属修正 (Spec Notes に記載、別 Issue 推奨。本 Issue のスコープ外)
- フォールバック投稿と本来の Step 14 投稿が両方成功した場合の重複コメント dedup ロジック (Spec Notes に記載、cosmetic tradeoff として許容)

### Notes for Next Phase
- Review phase (`/review` on PR #920) で本 PR 自体をレビューする際、`scripts/run-review.sh` の変更が review skill 自身の completion 検出ロジックに影響するため、review 実行時に silent no-op が発生した場合は今回追加したフォールバックが作動することを期待した挙動として扱う
- Behavioral Change Detection (Step 9) により `scripts/run-review.sh` の変更が `tests/run-auto-sub.bats` からも参照されていることを検出し、`bats tests/` フルスイート (1084 tests) を実行して回帰なしを確認済み

## Code Retrospective

### Deviations from Design
- N/A (Spec の Implementation Steps 1〜5 をそのまま実装)

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
