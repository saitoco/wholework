# Issue #399: verify: 未関連ファイルの dirty 検知時に判定/誘導を追加

## Overview

`/verify` Step 1 に未関連ファイルの dirty 検知ロジックを追加する。`docs/spec/issue-N-*.md` パターン（N が対象 Issue 番号と異なる）のみが dirty な場合は interactive で stash 提案、non-interactive では自動 stash して継続する。

## Implementation Steps

1. `skills/verify/SKILL.md` の `## Error Handling in Non-Interactive Mode` テーブルの Step 1 行を更新
   - 旧: `Same (hard-error: uncommitted changes cannot be auto-resolved)`
   - 新: unrelated spec files → auto-stash, related/other files → hard-error
2. `skills/verify/SKILL.md` の `### Step 1: Check Working Directory Safety` を更新
   - clean → continue の順序に変更
   - dirty 検出時に `git status --short` でファイルリスト取得
   - unrelated 判定: `docs/spec/issue-N-*.md`（N ≠ $NUMBER）
   - all unrelated → interactive: stash-and-continue/abort 選択提示; non-interactive: 自動 stash
   - other dirty → VERIFY_FAILED 出力して hard-error abort

## Code Retrospective

### Deviations from Design

- N/A（Spec なし、Issue 本文から直接実装）

### Design Gaps/Ambiguities

- Spec が存在しなかったため Issue 本文の Auto-Resolved Ambiguity Points セクションを設計根拠として利用した。判定スコープ（`docs/spec/issue-N-*.md` のみ）と interactive/non-interactive 分岐はその記述に忠実に実装した。

### Rework

- N/A
