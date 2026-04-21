# Issue #296: spec: Spec のサブセクション見出しレベルを実装ステップに明記する慣習を追加

## Issue Retrospective

### 判断根拠

- **曖昧点の自動解決**: 3 点すべてをモデル判断で auto-resolve（詳細は body `Auto-Resolved Ambiguity Points` セクション）。AskUserQuestion は使わず。
  - 対象ファイル範囲 → `skills/spec/SKILL.md` のみ（`modules/spec-template.md` は存在しないため AC から削除）
  - 見出しレベルの対象 → ターゲット実装ファイル側（Spec 自身の階層ではなく、Implementation Steps が追加を記述するサブセクションの見出しレベル）
  - ガイダンス強度 → SHOULD レベル（既存 SHOULD 制約表への追加）

### 受入条件の変更理由

- **削除**: `modules/spec-template.md` を参照する AC2 を削除。該当ファイルが存在しないため（Glob 0 件）、条件が vacuous に成立してしまい実質的な検証にならなかった。
- **`grep "h3\|h4\|見出しレベル\|heading level"` → `rubric` + `file_contains "heading level"`**: 元の `grep` パターンは既存の `headings` 記述（例: 行 236 "section headings"）にマッチしてしまい、追加されたかどうかの検証にならない（false positive リスク）。意味論的な追加確認は `rubric` で、具体的な追加文字列の存在確認は `file_contains "heading level"`（現在 0 件）で二重に担保する。
- **Post-merge 追加**: 実際に次回 `/spec` 実行時に慣習が遵守されているかを観察する opportunistic check を追加。`/verify` で条件が観察可能なら自動チェック、そうでなければ skip される。

### Triage 結果

- Type: Feature
- Size: XS（`skills/spec/SKILL.md` への doc-only 追加、1 ファイル）
- Value: 2（Impact=0, Alignment=1 / Level 1）
- Priority: 未指定（body に優先度シグナルなし）
