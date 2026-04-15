# Issue #190: verify: CI が in_progress の場合を PENDING 扱いに変更

## Overview

`/verify` 実行時、CI ジョブが `in_progress`（実行中）の状態の場合、現在は UNCERTAIN として処理されて Issue が reopen される。
CI 実行中は一時的な状態であり実装上の問題ではないため、新ステータス **PENDING** として識別し、`phase/verify` ラベルを付与するだけで reopen しないフローに変更する。

**自動解決済み曖昧性（Issue body より）:**
- FAIL + PENDING 共存時: FAIL 優先（既存の FAIL ブランチと同様）
- PENDING の表示形式: ⏳ PENDING（既存の ✅ PASS / ❌ FAIL / ⚠️ UNCERTAIN / ⏭️ SKIPPED と統一）
- `queued` はスコープ外（`in_progress` のみ対象）

## Changed Files

- `modules/verify-executor.md`: `github_check` 翻訳テーブルに `in_progress` → PENDING 検出を追加；Step 6 分類・CI Reference Fallback・Output Format に PENDING を追加
- `skills/verify/SKILL.md`: Step 7/8 の出力テーブルに PENDING 行追加；Step 9 に PENDING ブランチ追加、再実行メッセージ追加

## Implementation Steps

1. `modules/verify-executor.md` の `github_check` 翻訳テーブル行を更新: `gh_command` 実行後、出力に `in_progress` が含まれる場合 → **PENDING**（detail: "CI job is in_progress; re-verify after CI completes"）を返す。`in_progress` が含まれない場合は従来通り `expected_value` 照合 (→ 受入条件1)

2. `modules/verify-executor.md` の以下を更新 (→ 受入条件2):
   - Step 6 結果分類リストに追加: `**PENDING**: CI job is in_progress; temporary execution state, re-verify after CI completes`
   - CI Reference Fallback セクションの "Related job is **incomplete** (PENDING, etc.) → **UNCERTAIN**" を分割: `status: IN_PROGRESS → **PENDING**`、その他 incomplete (QUEUED 等) → **UNCERTAIN**
   - Output Format の Summary に `- PENDING: N items` を追加

3. `skills/verify/SKILL.md` Step 7（Issue コメント形式）と Step 8（ターミナル出力形式）の出力テーブルに PENDING 行を追加 (→ 受入条件4の一部):
   - Step 7: `| Condition N | PENDING | CI is in_progress; re-run after CI completes |`
   - Step 8: `| Condition N | ⏳ PENDING | CI is in_progress; re-run after CI completes |`

4. `skills/verify/SKILL.md` Step 9 に PENDING ブランチを追加 (→ 受入条件3, 4):
   - CLOSED パス・OPEN パスの両方に「**PENDING のみ（FAIL なし、PENDING ≥1）**」ブランチを追加（UNCERTAIN-only ブランチの直前に挿入）
   - 処理: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" verify`（reopen なし）
   - ユーザー通知（日本語）: "CI が実行中のため一部の条件が PENDING です。CI 完了後に `/verify $NUMBER` を再実行してください。"（"再実行" を含む）

## Verification

### Pre-merge

- <!-- verify: grep "in_progress" "modules/verify-executor.md" --> `modules/verify-executor.md` の `github_check` 処理に CI ジョブの `in_progress` 検出が追加される
- <!-- verify: section_contains "modules/verify-executor.md" "## Processing Steps" "**PENDING**" --> `modules/verify-executor.md` の結果分類に PENDING が新しいステータスとして追加される
- <!-- verify: section_contains "skills/verify/SKILL.md" "### Step 9: Apply Verification Results" "PENDING" --> `skills/verify/SKILL.md` の Step 9 に PENDING ブランチが追加される（reopen なし、`phase/verify` ラベル付与）
- <!-- verify: grep "再実行" "skills/verify/SKILL.md" --> `skills/verify/SKILL.md` のユーザー出力に CI 完了後の再実行を促すメッセージが含まれる

### Post-merge

- `/verify` 実行時に CI が `in_progress` の場合、PENDING として処理され Issue が reopen されないことを確認
- PENDING が含まれる場合、`phase/verify` ラベルが付与されることを確認

## Notes

- PENDING + UNCERTAIN 共存時（FAIL なし）は PENDING ブランチで処理（PENDING≥1 が優先）
- `github_check` の `in_progress` 検出はテキスト出力に "in_progress" が含まれる場合に適用（`gh pr checks`・`gh run list` の非JSON出力に対応）
- CI Reference Fallback（`command` ヒント用）の PENDING 対応も同時に実施（`statusCheckRollup` の `IN_PROGRESS` 検出）

## Code Retrospective

### Deviations from Design
- Edit ツールで絶対パス（`/Users/saito/src/wholework/...`）を使用してしまいメインリポジトリに変更を加えてしまった。ワークツリー内では CWD 相対パスを使用すべきだった。`cp` コマンドでファイルをワークツリーにコピーし、メインリポジトリの変更を `git checkout --` で revert することで対処した。実装内容自体はすべて Spec 通り。

### Design Gaps/Ambiguities
- N/A

### Rework
- Edit ツールの絶対パス使用によりメインリポジトリに変更が入った。ワークツリーへのコピーとメインリポジトリ revert でリカバリした（1サイクル）。
