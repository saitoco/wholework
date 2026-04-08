# Issue #35: issue: Add triage auto-chain to new issue creation flow

## Issue Retrospective

### Ambiguity Resolution

- **挿入位置**: Step 7（ラベル付与）の直後・Step 8（Scope 評価）の前を推奨し、ユーザーが承認。Scope 評価が Size に依存するため、この位置が論理的に正しい。
- **triage 開始ポイント**: Step 2（タイトル正規化）から開始。Step 6 での正規化と二重になるが、冪等操作のため問題なし。既存フローとの一貫性を優先するユーザー判断。
- **Lightweight Analysis**: 新規 Issue には stale check が無意味だが、triage 処理全体の一貫性のためそのまま実行する方針で自動解決。

### Key Decisions

- 既存精査フローの Step 2 と完全に同じ記述パターン（`triaged` ラベル確認 → triage/SKILL.md の Single Execution Step 2 から実行）を新規作成フローにも適用する

### Verify Hint Corrections (Refinement)

- **`section_contains ... "Step 2"` の偽陽性修正**: New Issue Creation セクションには既存の "Step 2: Reference Steering Documents" があり、変更なしでも PASS になる問題を検出。`"Single Execution"` に変更し、triage SKILL.md の実行セクション参照を正確に検証するよう修正。
- **`grep "triaged"` の偽陽性修正**: 既存精査フロー（Existing Issue Refinement）に "triaged" が既に存在するため、ファイル全体の grep では常に PASS になる問題を検出。`section_contains ... "## New Issue Creation" "triaged"` に変更し、New Issue Creation セクション内での参照に限定。

### Triage Results

- Type: Feature, Priority: medium, Size: XS, Value: 1
- 挿入位置（Step 7 後）の決定をレトロスペクティブから Auto-Resolved Ambiguity Points セクションに移動して明示化。
