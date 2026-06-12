# Issue #563: 並列 spawn 説明の世代非依存化 + cyber-classifier fallback 監視メモ

## Overview

2 つの軽微な補強:

1. `skills/issue/SKILL.md` Step 11a と `skills/review/SKILL.md` Step 10.2 の並列 spawn 根拠文 `(Opus 4.7 may otherwise serialize the spawns)` が世代依存で陳腐化しているため、世代非依存の表現へ更新する。single-message-spawn 指示自体は維持する。

2. Fable 5 の cyber classifier が `agents/review-bug.md` の security 系クエリを Opus 4.8 へ自動 fallback しうること（CLI 経由では透過）を監視メモとして `agents/review-bug.md` 冒頭と `docs/tech.md` の Fable 5 記述に追加する。

## Changed Files

- `skills/issue/SKILL.md`: Step 11a の spawn 根拠文を世代非依存の表現へ変更
- `skills/review/SKILL.md`: Step 10.2 の spawn 根拠文を世代非依存の表現へ変更
- `agents/review-bug.md`: 冒頭に cyber-classifier fallback 監視メモを追加
- `docs/tech.md`: Fable 5 セクションに cyber-classifier fallback 監視メモを追加
- `docs/ja/tech.md`: docs/tech.md の変更に対応する翻訳同期

## Implementation Steps

1. `skills/issue/SKILL.md` Step 11a（line 382）を編集: `(Opus 4.7 may otherwise serialize the spawns)` → `(single-message fan-out prevents serialization regardless of model generation)` (→ AC1, AC2)

2. `skills/review/SKILL.md` Step 10.2（line 366）を編集: 同じ置換を適用 (→ AC3, AC4)

3. `agents/review-bug.md` に冒頭注記を追加: `# Review: Bug/Logic Error Detection` 見出しの直後（`## Purpose` の前）に以下を追加 (→ AC5):
   ```
   > **Note (Fable 5):** When running on Fable 5, security-related queries (shell injection, secrets, LLM-to-Shell risks) may be automatically routed to Opus 4.8 via the cyber classifier (transparent via CLI). Do not evaluate security coverage assuming Fable 5 execution.
   ```

4. `docs/tech.md` line 95 の Fable 5 段落末尾（`§3.3 and §5.2 for adoption guidance.` の後）に以下の文を追加 (→ AC6):
   `When running on Fable 5, security-related queries in review phases may be automatically routed to Opus 4.8 via the cyber classifier (transparent via CLI) — do not assume Fable 5 handles security analysis directly.`

5. `docs/ja/tech.md` line 93 の Fable 5 段落末尾に対応する日本語翻訳を追加（Step 4 と同期） (→ translation sync)

## Verification

### Pre-merge

- <!-- verify: file_not_contains "skills/issue/SKILL.md" "Opus 4.7 may otherwise serialize" --> Step 11a の spawn 指示から旧モデル依存根拠が除去されている
- <!-- verify: grep "single message" "skills/issue/SKILL.md" --> Step 11a の single-message spawn 指示が維持されている
- <!-- verify: file_not_contains "skills/review/SKILL.md" "Opus 4.7 may otherwise serialize" --> Step 10 の spawn 指示から旧モデル依存根拠が除去されている
- <!-- verify: grep "single message" "skills/review/SKILL.md" --> Step 10 の single-message spawn 指示が維持されている
- <!-- verify: grep "cyber" "agents/review-bug.md" --> cyber-classifier fallback の監視メモが agents/review-bug.md に追加されている
- <!-- verify: grep "cyber" "docs/tech.md" --> cyber-classifier fallback の監視メモが docs/tech.md に追加されている

### Post-merge

- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> 既存 bats テストが CI で green
- （該当時）Fable 5 採用後、security 観点で Opus 4.8 fallback が発生しても運用上の問題がないこと（観測）

## Notes

- `skills/issue/SKILL.md` と `skills/review/SKILL.md` の spawn 根拠文は同一パターンであり、同じ置換で対応できる
- `agents/review-bug.md` の冒頭注記は、エージェントファイルの冒頭（`## Purpose` の前）に blockquote 形式で追加する。`grep "cyber"` でマッチするよう "cyber classifier" という表記を必ず含める
- `docs/tech.md` の変更は `docs/ja/tech.md` の翻訳同期が必要（translation-workflow.md の規定による）
- `docs/reports/` は翻訳同期の除外対象なので `docs/reports/claude-fable-5-impact-strategy.md` は変更不要
- `skills/issue/SKILL.md` の新しい表現: `(single-message fan-out prevents serialization regardless of model generation)`

## Code Retrospective

### Deviations from Design

- N/A（全ステップを Spec 通り実施。ライン番号は実際の値と一致した）

### Design Gaps/Ambiguities

- Step 11 で commit prefix を `feat:` にしてしまった（Type=Task のため正しくは `chore:`）。実装コミットをStep 8 で早期に作成したため、Step 11 の Type 取得ステップを踏まずに prefix を決定したことが原因。push 前であり CLAUDE.md のルールに従い amend はしないが、次回は Type 取得を実施してから commit を行う。

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `agents/review-bug.md` への追記は `## Purpose` の前（見出し直後）に blockquote 形式で配置し、`grep "cyber"` でマッチする表現を確保した
- `docs/tech.md` への追記は Fable 5 段落末尾（既存文の続き）として追加し、文書構造を変えなかった
- `docs/ja/tech.md` の翻訳同期は translation-workflow.md の規定に従い同じコミットで実施した

### Deferred Items
- commit prefix の `feat:` → `chore:` 修正は push 前だが CLAUDE.md のルールに従い amend しないまま進行（実害なし）

### Notes for Next Phase
- Pre-merge verify 6件すべて PASS 済み
- Post-merge verify は CI green 確認（`github_check` / manual）のみ残る
- bats 697件 PASS、スキル構文検証・禁止表現チェックいずれも PASS
