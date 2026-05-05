# Issue #423: docs: /auto の詳細記述が tech.md と workflow.md で重複している

## Issue Retrospective

### 判断根拠

- **起票背景**: `/doc sync --deep` (2026-05-05 実行) で検出された Drift D5 を Issue 化したもの
- **SSoT 階層化方針**: tech.md frontmatter (`ssot_for: [tech-stack, ...]`) に対して `/auto` の運用仕様は本来 workflow.md (`ssot_for: workflow-phases, label-transitions`) のスコープ。`workflow-phases` カテゴリに該当する運用仕様は workflow.md を SSoT として一本化する
- **保留する記述**: tech.md の「設計判断」観点（fork context, two-tier orchestration, `reconcile-phase-state.sh` との関係性, `WHOLEWORK_MAX_RECOVERY_SUBAGENTS` 等）は tech-stack/architecture-decisions の SSoT として残す

### 自動解決した曖昧ポイント

なし。要件は `/doc sync --deep` の検出結果から明確に導出できた。

### Acceptance Criteria の補足

- `verify: file_not_contains` で削除確認、`verify: section_contains` で参照リンク追加確認、`verify: file_contains` で設計判断記述の維持確認の組合せで pre-merge verify 可能な構成
- workflow.md 側は変更不要だが、回帰確認として `section_contains "## Orchestration" "--batch"` を追加し、誤って削除しないことを担保

### Triage 結果

- Type: Task（ドキュメント整理）
- Size: XS（tech.md 単一ファイル、~30 行以下の修正）
- Priority: 未設定（緊急度なし、技術的負債解消）
- Value: 2（Impact=0, Alignment=1, raw=1, Level 1 normalization）
- Duplicate candidates: なし
- Stale check: 起票直後のため対象外
- Dependency check: blocked-by なし
