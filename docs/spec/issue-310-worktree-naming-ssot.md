# Issue #310: watchdog-reconcile: run-code.sh と SKILL.md のworktree命名規則の不整合を解消

## Overview

`skills/code/SKILL.md` / `scripts/run-code.sh` / `scripts/watchdog-reconcile.sh` の3系統に分かれていた worktree 命名を `code/issue-{N}` に統一し、`skills/code/SKILL.md` Step 2 を命名規則の SSoT として明記する。`_find_code_worktree` の 2段階探索（primary `code+issue-{N}` + fallback `issue-{N}-*`）は workaround のため単一パターンに簡素化する。

背景: #308 (Stage 2 リカバリ) 実装時に workaround として追加された `_find_code_worktree` を恒久的な SSoT 化に置き換えるフォローアップ。`run-code.sh` の stale cleanup は既に `code+issue-{N}` 形式のため変更なし。

## Changed Files

- `skills/code/SKILL.md`: Step 2 "Worktree naming convention (by route)" の記述を patch/pr 両ルートとも `code/issue-$NUMBER` に統一し、当該サブセクションを worktree 命名規則の SSoT として明記する（EnterWorktree による `/` → `+` 変換で worktree dir は `code+issue-$NUMBER`、ブランチは `worktree-code+issue-$NUMBER` になる旨を注記）
- `scripts/watchdog-reconcile.sh`: `_find_code_worktree` の 2段階探索を単一パターン `$worktree_base/code+issue-${ISSUE_NUMBER}` のみに簡素化（fallback glob `issue-${ISSUE_NUMBER}-*` を削除）。`_reconcile_code_pr` Stage 1 は `gh pr list --head "issue-${ISSUE_NUMBER}-*"` と `--head "code+issue-${ISSUE_NUMBER}"` の2段階判定を廃止し、実ブランチ名 `worktree-code+issue-${ISSUE_NUMBER}` に対する単一判定に差し替える。bash 3.2+ 互換を維持
- `scripts/run-code.sh`: 変更なし（WORKTREE_PATH / WORKTREE_BRANCH は既に新 SSoT と整合。grep 検証済み: 91-92行目のみ該当）
- `tests/watchdog-reconcile.bats`: 変更なし（既存 Stage 2 テストは `code+issue-55` ベースで新 SSoT と整合。Stage 1 テストは mock が pattern に依存せず固定値を返すため影響なし。grep 検証済み: fallback `issue-N-*` 固有テストは存在しない）
- `tests/run-code.bats`: 変更なし（`worktree-code+issue-123` 1箇所のみで新 SSoT と整合。grep 検証済み）

## Implementation Steps

1. `skills/code/SKILL.md` Step 2 "Worktree naming convention (by route)" の箇条書きを以下に置き換え、SSoT マーカーを追記する（→ pre-merge verification 1, 2）:
   - patch/pr 両ルートとも `code/issue-$NUMBER` に統一
   - EnterWorktree による変換結果（worktree dir `code+issue-$NUMBER`、ブランチ `worktree-code+issue-$NUMBER`）を注記
   - 「本セクションは worktree 命名規則の SSoT である」旨を明示
2. `scripts/watchdog-reconcile.sh` `_find_code_worktree` (97-118行目) を単一パターン探索に書き換え、`issue-${ISSUE_NUMBER}-*` glob ループを削除する（after 1。→ pre-merge verification 3）
3. `scripts/watchdog-reconcile.sh` `_reconcile_code_pr` Stage 1 (121-134行目) の `gh pr list --head` パターンを実ブランチ名 `worktree-code+issue-${ISSUE_NUMBER}` 単一判定に差し替える。冗長な 2段階判定を除去する（after 2。→ pre-merge verification 3）

## Verification

### Pre-merge
- <!-- verify: section_contains "skills/code/SKILL.md" "Step 2: Worktree Entry" "code/issue-" --> `skills/code/SKILL.md` Step 2 に `code/issue-{N}` 命名規則が SSoT として記載されている
- <!-- verify: rubric "skills/code/SKILL.md Step 2 Worktree Entry defines a single unified worktree naming convention code/issue-N for BOTH patch and pr routes. The old patch/issue-N (patch route) and issue-N-<short-description> (pr route) naming conventions are no longer present anywhere in skills/code/SKILL.md." --> `skills/code/SKILL.md` から旧命名（`patch/issue-N`、`issue-N-<short-description>`）が除去されている
- <!-- verify: rubric "scripts/watchdog-reconcile.sh の _find_code_worktree は単一パターン code+issue-{N} のみを探索しており、issue-{N}-* フォールバック（glob 探索）は削除されている。_reconcile_code_pr Stage 1 の gh pr list --head pattern も新 SSoT 由来の実ブランチ名（worktree-code+issue-{N} 系）と整合している。" --> `watchdog-reconcile.sh` の worktree/branch 探索ロジックが新 SSoT `code+issue-{N}` 単一パターンに簡素化され、Stage 1 も整合している
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 既存 bats テスト（`tests/watchdog-reconcile.bats`、`tests/run-code.bats` 含む）が通過している

### Post-merge
- `/auto {issue-number}` を pr route で実行し、worktree dir `.claude/worktrees/code+issue-{N}` とブランチ `worktree-code+issue-{N}` が作成され、/code → /review → /merge → /verify が正常完走することを手動確認

## Notes

- **EnterWorktree の命名変換挙動**: `name: "code/issue-N"` を渡すと `/` → `+` 変換で worktree dir `code+issue-N`、`worktree-` prefix 付与でブランチ `worktree-code+issue-N` が作られる（`docs/spec/issue-129-watchdog-hang-avoidance.md` で EnterWorktree 出力 "branch worktree-spec+issue-129" により確認済み）。
- **`gh pr list --head` 挙動**: 現行コード `--head "code+issue-${ISSUE_NUMBER}"` は実ブランチ名 `worktree-code+issue-${ISSUE_NUMBER}` と prefix 不一致により無マッチが懸念される。Step 3 では実ブランチ名ベース（例: `--head "worktree-code+issue-${ISSUE_NUMBER}"`）に揃えることで、Stage 1 の PR 存在判定を実運用と整合させる。
- **Auto-Resolve Log（Issue 側で確定済み）**: SSoT 配置先は `skills/code/SKILL.md` Step 2（AC rubric 「どちらか一方に SSoT が明記」と整合）。`_find_code_worktree` の 2段階探索は単一パターンに簡素化（workaround 除去、wholework の no-backwards-compat-shims 方針と整合）。
- **"No change needed" pre-verification 結果**: `scripts/run-code.sh` / `tests/run-code.bats` / `tests/watchdog-reconcile.bats` の無変更判断は grep で実検証済み（Step 6 codebase investigation 時）。

## Code Retrospective

### Deviations from Design

- `tests/watchdog-reconcile.bats` に変更なしの予定だったが、mock コメント（`# gh pr list --head "issue-N-*" ...`）が旧パターンを参照していたため、新 SSoT パターン（`worktree-code+issue-N`）に更新した。Spec の "変更なし（grep 検証済み）" は実行パスに影響するコードに限定した判断であり、コメント更新は追加スコープとして受容。

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## review retrospective

### Spec vs. Implementation Divergence Patterns

- Spec と実装の乖離なし。`tests/watchdog-reconcile.bats` のコメント更新（実行パス非影響）は Code Retrospective で既に記録済み。

### Recurring Issues

- 特記事項なし。

### Acceptance Criteria Verification Difficulty

- 4条件すべて自動検証可能。`github_check` 条件は CI SUCCESS により PASS。UNCERTAIN ゼロ、verify コマンドの精度は高い。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue の受入条件は明確で曖昧さなし（4条件すべて自動検証可能）。SSoT 配置先と 2段階探索廃止のトレードオフも Issue 本文で明示済み。

#### design
- Spec の設計は実装と整合。"変更なし" 判断は実行パスの grep に限定したものであり、コメント行への影響は設計スコープ外とした判断は妥当。Code Retrospective でキャプチャ済み。

#### code
- `tests/watchdog-reconcile.bats` の mock コメントが旧パターン参照だったため追加修正が発生（Code Retrospective 記録済み）。実行パス非影響のため品質リスクは低い。パターン変更時はコメント行も grep チェック対象に含めると将来の "no change needed" 誤判定を防げる。

#### review
- Review Retrospective によれば Spec との乖離なし、verify コマンド精度も高い評価。bats コメント修正は review 時に検出・承認された。

#### merge
- PR #321 経由でクリーンにマージ。CI（Run bats tests・Forbidden Expressions・Validate skill syntax・macOS shell compatibility）全 pass。

#### verify
- 4条件すべて PASS。Post-merge manual 条件（`/auto` フルフロー確認）が残るため `phase/verify` に移行。verify コマンドは全条件で適切に機能した。

### Improvement Proposals
- N/A
