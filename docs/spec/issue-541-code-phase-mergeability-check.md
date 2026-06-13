# Issue #541: code phase mergeability conflict pre-detection

## Overview

PR route の code phase 完了時、並行セッションによる base branch 先行マージで mergeability 衝突が発生した場合、現状は merge phase まで未検出。`scripts/run-code.sh` の既存 reconcile check ブロック（lines 171-182 付近）後段に pr route 限定の mergeability 事前検査を追加し、`scripts/gh-pr-merge-status.sh` を再利用して `reason: conflicts` の場合のみ warn を stderr 出力する（EXIT_CODE は変更しない）。`modules/orchestration-fallbacks.md` に `## code-base-conflict` セクションを追加して recovery 手順を文書化する。

## Changed Files

- `scripts/run-code.sh`: add mergeability check block after existing reconcile check — bash 3.2+ compatible
- `modules/orchestration-fallbacks.md`: add `## code-base-conflict` section before "Operational Notes"
- `tests/run-code-mergeability.bats`: new test file for mergeability check behavior

## Implementation Steps

1. **`scripts/run-code.sh` mergeability check 追加** (→ AC1, AC2, AC3): 既存 reconcile check ブロック（lines 171-182 付近）の閉じ `fi` の直後に、`[[ "$ROUTE_FLAG" == "--pr" && $EXIT_CODE -eq 0 ]]` を条件とする mergeability check ブロックを追加。ブロック直上に `# See modules/orchestration-fallbacks.md#code-base-conflict` ポインターコメントを付与。ブロック内: `_PR_NUM=$(echo "$_reconcile_out" | jq -r '.actual.pr_number // empty' 2>/dev/null || true)` で PR 番号を取得し、空またはシェル数値正規表現不一致の場合は skip。PR 番号が有効な場合 `"$SCRIPT_DIR/gh-pr-merge-status.sh" "$_PR_NUM" 2>/dev/null || true` を呼出し、出力に `"reason":"conflicts"` が含まれる場合のみ以下 4 行を stderr 出力:
   ```
   Warning: code phase completed but PR #${_PR_NUM} has conflicts with base.
   This is likely due to a concurrent merge on the base branch during code phase.
   PR diff (merge-base based) shows only this Issue's changes correctly -- do not mistake this for contamination.
   Recommended: resolve conflicts before /merge. See modules/orchestration-fallbacks.md#code-base-conflict for the recovery procedure.
   ```
   EXIT_CODE は変更しない（warn-only, completion 判定から独立）。

2. **`modules/orchestration-fallbacks.md` セクション追加** (→ AC4, AC5, AC6): ファイル末尾の `## Operational Notes` の直前に `## code-base-conflict` セクションを英語で追加。既存エントリ（`## ff-only-merge-fallback` 等）と同じ構造（Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale）で記述。Fallback Steps に6ステップを含む: (1) `git fetch origin main`, (2) `git checkout worktree-code+issue-<N>`, (3) `git merge-tree --write-tree origin/main HEAD` で衝突ファイル確認, (4) directly orthogonal changes（引数追加等独立した変更）の場合は `git merge origin/main` で解消 → push, (5) functionally overlapping の場合は親セッションへ escalation, (6) 解消後 `/merge <PR>` を実行。Rationale に Issue #541 と `scripts/run-code.sh` の参照を含める。

3. **`tests/run-code-mergeability.bats` 新規作成** (→ AC8): `run-code.bats` の `setup()` をベースに同等のモック環境を構築（MOCK_DIR, WHOLEWORK_SCRIPT_DIR, claude mock, claude-watchdog.sh, handle-permission-mode-failure.sh, phase-banner.sh, watchdog-defaults.sh, guard-prefix.sh, git, gh, get-config-value.sh, reconcile-phase-state.sh, skills/code/SKILL.md を含む）。reconcile-phase-state.sh mock は `{"matches_expected":true,"phase":"code-pr","actual":{"pr_state":"OPEN","pr_number":123},"schema_version":"v1","diagnosis":"test"}` を出力（pr_number 含む）。`gh-pr-merge-status.sh` mock を MOCK_DIR に追加。2 テストケース: (a) `@test "mergeability: pr route with conflicts warns on stderr"` — gh-pr-merge-status mock が `{"mergeable": false, "reason": "conflicts", "ci_status": "unknown", "review_status": "unknown"}` を返す場合、stderr（`$output` または `$stderr`）に "conflicts with base" が含まれることを確認; (b) `@test "mergeability: pr route without conflicts outputs no warn"` — gh-pr-merge-status mock が `{"mergeable": true, "reason": "clean", "ci_status": "success", "review_status": "approved"}` を返す場合、stderr に warn が含まれないことを確認。

## Verification

### Pre-merge

- <!-- verify: grep "gh-pr-merge-status\|mergeable" "scripts/run-code.sh" --> `scripts/run-code.sh` に mergeability check ロジックが追加されている
- <!-- verify: grep "ROUTE_FLAG.*--pr\|pr route" "scripts/run-code.sh" --> mergeability check は pr route のときのみ実行されることが明示されている
- <!-- verify: grep "conflicts with base\|concurrent merge" "scripts/run-code.sh" --> 衝突検出時の warn メッセージが追加されている
- <!-- verify: grep "code-base-conflict" "modules/orchestration-fallbacks.md" --> recovery 手順セクションが追加されている
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "## code-base-conflict" "git merge-tree" --> recovery 手順に `git merge-tree` による衝突確認ステップが含まれる
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "## code-base-conflict" "directly" --> recovery 手順に直交変更 vs 機能重複の判断ステップが含まれる
- <!-- verify: rubric "scripts/run-code.sh は既存 silent no-op check (line 171-182 付近) の後段に mergeability check を pr route 限定で追加し、scripts/gh-pr-merge-status.sh を再利用して mergeable=false, reason=conflicts のとき warn を stderr に出力するが EXIT_CODE は変更しない (completion 判定と独立)。modules/orchestration-fallbacks.md は code-base-conflict セクションで recovery 手順 (fetch → checkout → merge-tree → 直交判定 → 解消 → /merge) を文書化" --> 実装方針 (run-code.sh 独立 check + warn-only + recovery 手順) が rubric 基準を満たす
- <!-- verify: command "bats tests/run-code-mergeability.bats" --> mergeability check の bats テストが pass (新規ファイル、または既存テストに統合)
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI green

### Post-merge

- 次回以降の `/auto` で base 先行マージが発生した際、code phase 終了時に warn が出力され merge phase へ進む前に解消フローを起動できることを確認 <!-- verify-type: opportunistic -->

## Notes

- **verify item 数**: Issue body pre-merge AC が 9 件のため Spec も 9 件（SPEC_DEPTH=light の上限 5 件を超えるが、verbatim copy ルールが優先）
- **`_reconcile_out` 変数の可用性**: mergeability check は `EXIT_CODE -eq 0` のみ実行されるため、reconcile ブロック（`EXIT_CODE -eq 143 || EXIT_CODE -eq 0` で実行）が必ず先行し `_reconcile_out` は定義済み
- **既存 `run-code.bats` への影響なし**: reconcile mock が `pr_number` を含まない場合 `jq` が空を返し `gh-pr-merge-status.sh` は呼ばれない。既存テストは修正不要
- **`docs/structure.md` の `tests/` ファイル数**: 現在 59 files（under `tests/`）。`run-code-mergeability.bats` 追加で 60 files となるが SPEC_DEPTH=light のため docs/structure.md 更新は省略（コメントのみ）
- **bats の stderr キャプチャ**: `run` コマンド後は `$output` に stdout+stderr が混在する場合と bats バージョンにより `$stderr` に分離される場合がある。テスト内では `run bash "$SCRIPT" 123 --pr` 後に `[[ "$output" == *"conflicts with base"* ]]` のように確認（bats は通常 stdout+stderr を `$output` に統合するため）

## Code Retrospective

### Deviations from Design
- grep パターンを `"reason":"conflicts"` （スペースなし）から `"reason"[[:space:]]*:[[:space:]]*"conflicts"` （スペース許容）に変更。`gh-pr-merge-status.sh` が出力する JSON は `"reason": "conflicts"` とコロン後にスペースがあり、Spec のパターンでは一致しなかった。テスト実行後に発見し修正コミットを追加した。

### Design Gaps/Ambiguities
- Spec Notes の bats stderr キャプチャ補足は正確だった。`run bash "$SCRIPT"` では stdout+stderr が `$output` に統合されるため `$output` チェックで正しく検出できる。

### Rework
- `scripts/run-code.sh` の grep パターン修正のため実装コミット後に追加コミット（fix:）が発生した。Spec 実装ステップには JSON スペース有無の明示がなく、grep パターンの柔軟性確保が見落とされていた。

## review retrospective

### Spec vs. Implementation Divergence Patterns
- verify commands が `\|` 記法（traditional grep の alternation）を使用しているが、verify-executor は ripgrep を使用するため `\|` はリテラルマッチとなる。今回は条件が全て PASS だったため機能的影響はないが、verify command 品質として `|` 記法への統一を検討すべき。
- Spec の実装ステップは `mergeable: false, reason: conflicts` の両条件チェックと記述しているが、実装は `reason: conflicts` のみチェック。意味的には等価だが、今後 Spec 記述と実装の整合性を高めるため、このような省略は Spec Notes に明記することを推奨。

### Recurring Issues
- Nothing to note.

### Acceptance Criteria Verification Difficulty
- `command` verify コマンド（bats テスト）は safe mode では実行不可。CI reference fallback（"Run bats tests" SUCCESS）で代替した。これは /review での想定動作であり問題なし。
- `github_check` の verify command notation（`\|`）は仕様書のminor inconsistency。次回 Issue 作成時に verify-executor の注記（ripgrep alternation は `|`）を参照して記述することを推奨。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- REVIEW_DEPTH=light（明示的 `--light` フラグ）で軽量統合レビューを実行した
- MUST/SHOULD 件数 0 → Step 12 修正なし、Step 13 policy change なし
- CI green 確認（github_check PASS）→ AC9 のチェックボックスを `[x]` に更新した

### Deferred Items
- verify commands の `\|` 記法を `|` に修正すること（Spec quality issue、CONSIDER レベル）
- Spec の `mergeable: false` 条件明示（現実装は `reason: conflicts` のみ、意味的等価だが verbatim からの乖離）

### Notes for Next Phase
- 全受け入れ条件 PASS（9/9）、CI 全件 SUCCESS → `/merge 613` で問題なくマージ可能
- post-merge AC あり（opportunistic verify-type）: `/auto` 実行時の base 先行マージ発生で自動確認される
- CONSIDER 指摘 1 件（scripts/run-code.sh:189）は機能影響なし、マージブロックにならない