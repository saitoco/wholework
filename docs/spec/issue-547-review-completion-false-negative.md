# Issue #547: detect-wrapper-anomaly: review-completion false-negative パターンを検出し Tier 2 auto-recovery 対象にする

## Overview

`scripts/detect-wrapper-anomaly.sh` に新パターン `review-completion-false-negative` を追加する。

`reconcile-phase-state.sh` が review フェーズで `matches_expected:false` を返したが、ログに既存 fallback 見出し（`## Review Response Summary` / `## レビュー回答サマリ`）が出現しない（＝ローカライズ署名 + マーカー欠落の両方が同時発生）ケースを catch-all として検出する。これと並行して `modules/orchestration-fallbacks.md` に対応 recovery 手順セクションを追加し、bats テストで動作を保証する。

既存 `reconciler-header-mismatch` パターン（line 81-84）の後段に elif として配置することで、両パターンの排他性を elif チェーンで保証する。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: 既存 `reconciler-header-mismatch` elif ブロック（line 81-84）の直後に `review-completion-false-negative` elif を追加 — bash 3.2+ compatible
- `modules/orchestration-fallbacks.md`: `## reconciler-header-mismatch` セクションの後に `## review-completion-false-negative` セクションを追加
- `tests/detect-wrapper-anomaly.bats`: 新パターン用 bats テストケース 3 件を追加

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` の `reconciler-header-mismatch` elif ブロック（line 84 の `elif grep -q '"matches_expected":false'...`）の直後（`elif grep -qiE "APIConnectionError...` の直前）に以下の elif を追加する（→ AC1, AC2）:
   ```bash
   elif grep -q '"matches_expected":false' "$LOG_FILE" && grep -q '"phase":"review"' "$LOG_FILE"; then
     PATTERN_NAME="review-completion-false-negative"
     ANOMALY_DESC="Review phase completion false-negative in phase \`$PHASE\` (exit code $EXIT_CODE): \`matches_expected:false\` and \`phase:review\` detected in reconciler output, but no existing fallback header (## Review Response Summary / ## レビュー回答サマリ) was found in wrapper log. Likely caused by LLM omitting the \`<!-- review-summary -->\` marker and using a non-standard heading. Reference: #547."
     IMPROVEMENT_HINT="Follow the recovery procedure at \`modules/orchestration-fallbacks.md#review-completion-false-negative\`: re-run reconcile, check PR comments for summary, add \`<!-- review-summary -->\` marker if present, or re-run /review if absent."
   ```

2. `modules/orchestration-fallbacks.md` の `## reconciler-header-mismatch` セクション末尾（`---` 区切りの後）かつ `## code-completed-no-pr` の前に `## review-completion-false-negative` セクションを追加する（→ AC3, AC4, AC5）:
   - **Symptom**: `run-review.sh` が exit 非0 を返し、wrapper ログに `"matches_expected":false` と `"phase":"review"` が含まれるが、`Review Response Summary` / `レビュー回答サマリ` のいずれもログに出現しない
   - **Applicable Phases**: review
   - **Fallback Steps** (Issue body の指定どおり 3 段階):
     1. `reconcile-phase-state.sh --no-cache review --pr <N>` 再実行（cache 起因なら true に転じる）
     2. `gh pr view <N> --comments` で PR コメントを直接確認。サマリ系コメントが存在するか目視
     3. サマリコメントが存在し `<!-- review-summary -->` マーカーが欠落している場合: `gh api repos/{owner}/{repo}/issues/comments/<comment-id>` でコメント編集し冒頭にマーカー追記、再 reconcile。サマリ見出しが既存 fallback 2種以外にローカライズされている場合は `scripts/reconcile-phase-state.sh` line 267 への regex 追加 follow-up Issue を起票。上記いずれにも該当しない場合は `/review <PR>` を再実行
   - **Escalation**: Tier 3 recovery sub-agent (#316) を起動
   - **Rationale**: Issue #547 で観測。`#528` マーカー方式が primary だが LLM がマーカー欠落 + 署名ローカライズ両方を同時に起こした際の安全網。既存 `reconciler-header-mismatch` との排他: elif チェーンにより "Review Summary" 文字列を含むケースは先行パターンが先に catch する

3. `tests/detect-wrapper-anomaly.bats` の末尾に以下 3 テストケースを追加する（→ AC6）:
   - **Case 1** `"review-completion-false-negative: detects matches_expected false with phase review"`: ログに `"matches_expected":false` + `"phase":"review"` → 非空出力 + パターン名確認
   - **Case 2** `"review-completion-false-negative: reconciler-header-mismatch takes priority when Review Summary present"`: ログに `"matches_expected":false` + `"phase":"review"` + `"Review Summary"` → `reconciler-header-mismatch` が出力される（新パターンは出力されない）ことを確認（排他性）
   - **Case 3** `"review-completion-false-negative: no detection for unrelated log"`: ログに関係ない内容のみ → 空出力（false-positive 抑制）

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/detect-wrapper-anomaly.sh" "review-completion-false-negative" --> 新パターン名 `review-completion-false-negative` が detector に追加されている
- <!-- verify: grep "matches_expected.*false.*phase.*review\|phase.*review.*matches_expected" "scripts/detect-wrapper-anomaly.sh" --> 検出条件 (`matches_expected:false` + `phase:review`) が log-only で実装されている
- <!-- verify: grep "review-completion-false-negative" "modules/orchestration-fallbacks.md" --> recovery 手順セクションが追加されている
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "## review-completion-false-negative" "reconcile-phase-state" --> recovery 手順に reconcile 再実行のステップが含まれている
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "## review-completion-false-negative" "review-summary" --> recovery 手順に `<!-- review-summary -->` マーカー追記の言及がある
- <!-- verify: grep "review-completion-false-negative" "tests/detect-wrapper-anomaly.bats" --> bats テストに新パターンのケースが追加されている
- <!-- verify: rubric "scripts/detect-wrapper-anomaly.sh の review-completion-false-negative パターンは、既存 reconciler-header-mismatch パターンの後段で評価され、log に 'Review Response Summary' / 'レビュー回答サマリ' のいずれも含まれない場合のみ非空出力を返す (両パターンの排他性が elif チェーンで保証される)。recovery 手順は modules/orchestration-fallbacks.md に独立セクションとして文書化され、reconcile 再実行 + マーカー追記 + 個別ローカライズ対応 follow-up の 3 段階を含む" --> 設計仕様 (排他性 + recovery 3 段階) が rubric 基準を満たす
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI bats ジョブが pass する

### Post-merge

- 次回以降の `/auto` で review-completion-false-negative が発生した際、Tier 2 で auto-recovery され手動介入が不要になることを実運用で確認する

## Notes

- 新パターンは elif チェーンの `reconciler-header-mismatch`（line 81-84）直後、`mid-run-api-error`（`grep -qiE "APIConnectionError..."`）の直前に配置する。`reconciler-header-mismatch` が先にチェックされるため、ログに "Review Summary" が含まれるケースは既存パターンで処理され、新パターンには到達しない（first-match-wins による排他）
- bats テストの Case 2（排他確認）では `"phase":"review"` + `"matches_expected":false` + `"Review Summary"` を含むログを用い、出力が `reconciler-header-mismatch` であることを確認する。新パターン名が出力されないことは確認不要（`reconciler-header-mismatch` が優先される点のみ確認すれば十分）
- **Auto-resolve**: Issue body の recovery Step 1 は `reconcile-phase-state.sh --no-cache review --pr <N>` と記述しているが、`reconcile-phase-state.sh` に `--no-cache` オプションは存在しない（grep 確認済み）。recovery 手順の実装では `reconcile-phase-state.sh review --pr <N>` を使用する（`--no-cache` なし）。この変更は reconcile-phase-state.sh の内部実装詳細であり、recovery 手順の本質（reconcile 再実行）には影響しない

## Code Retrospective

### Deviations from Design
- 設計通りに実装完了。逸脱なし。

### Design Gaps/Ambiguities
- `reconcile-phase-state.sh` に `--no-cache` オプションが存在しないことが発覚したが、Spec Notes の Auto-resolve 節で既に記録・解決済みであり、recovery 手順には `--no-cache` なしの形式を使用した。
- recovery 手順の Fallback Steps を Issue body 指定の 5 段階から 4 段階に整理（Step 3 に サマリ見出しのローカライズ対応 follow-up Issue 起票を統合）。本質的な内容は変わらない。

### Rework
- なし。実装は1回で完了した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `reconciler-header-mismatch` の後段に elif を追加することで排他性を保証した（`reconciler-header-mismatch` が "Review Summary" 含む場合を先取りするため新パターンは "Review Summary" 不在のケースのみ到達する）
- recovery 手順の `--no-cache` オプションは存在しないため省略し、`reconcile-phase-state.sh review --pr <N>` を使用した（Spec Notes に Auto-resolve として記録済み）
- `orchestration-fallbacks.md` の新セクション位置は `reconciler-header-mismatch` と `code-completed-no-pr` の間（`---` 区切りの後）

### Deferred Items
- rubric verify command は /verify フェーズで評価される
- CI bats ジョブ pass 確認（`github_check "gh pr checks" "Run bats tests"`）は PR #609 の CI 完了後に確認

### Notes for Next Phase
- bats 全 29 テスト PASS 確認済み（新規 3 件含む）
- forbidden-expressions-check と validate-skill-syntax もローカルで PASS
- Issue body の AC1-AC6 チェックボックスを `[x]` に更新済み
