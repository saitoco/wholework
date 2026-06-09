# Issue #513: verify: 間接反映パターンの AC 分類ガイドを verify-patterns に追加

## Issue Retrospective

### 自動解決した曖昧ポイント

以下の3点を非対話モードで自動解決した。

#### 1. AC1 の grep パターン簡略化 (MEDIUM)

- **元のパターン**: `grep "間接反映\\|indirect.*reflect\\|downstream.*script" modules/verify-patterns.md`
- **問題**: `\|` alternation は macOS BSD grep の basic mode で非サポートリスク。また日本語キーワード `間接反映` は English-first 実装では FAIL するリスクがある
- **採用**: `grep "indirect" "modules/verify-patterns.md"` に単純化
- **根拠**: verify-patterns.md は全て英語（English-only ドキュメント）。実装後 "indirect" が必ず含まれる。現時点で "indirect" は未存在（実装前は FAIL、実装後 PASS）
- **不採用候補**: `-E` フラグ付き egrep（verify executor の対応状況が不明）

#### 2. AC2 の verify command 強化 (HIGH)

- **元のパターン**: `file_contains "modules/verify-patterns.md" "command"`
- **問題**: "command" は verify-patterns.md 全体に既存するため trivially PASS（実装なしでも常にPASS）
- **採用**: `rubric "..."` ＋ `file_contains "modules/verify-patterns.md" "indirect"` 補足
- **根拠**: verify-patterns.md §9 の rubric + 補足パターンに従う。file_contains 補足は実装前に "indirect" が未存在であるため機械的安全網として機能する
- **不採用候補**: `section_contains` による節番号指定（実装前に節番号が確定しないため）

#### 3. Background プレースホルダー削除 (LOW)

- **変更**: `（downstream Issue <downstream-issue> の review retrospective で記録）` を削除
- **理由**: 未解決の孤立プレースホルダー。削除後も背景の意図（"rubric grader が UNCERTAIN になるリスク"）は明確に伝わる

### 受入条件の変更理由

| 変更前 | 変更後 | 理由 |
|--------|--------|------|
| `grep "間接反映\\|indirect.*reflect\\|downstream.*script"` | `grep "indirect"` | 単純化・macOS 互換性向上 |
| `file_contains "modules/verify-patterns.md" "command"` | `rubric "..." + file_contains "indirect"` | trivially PASS を回避し意味的チェックを追加 |
