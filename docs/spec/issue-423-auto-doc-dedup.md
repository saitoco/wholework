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

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue 起票と同時に Spec も作成済み。Acceptance Criteria は `file_not_contains` / `section_contains` / `file_contains` の組合せで pre-merge verify 可能な構成が取られており、曖昧さなし。workflow.md 回帰確認条件（条件6）を明示的に追加しており、削除方向の変更が誤って SSoT を壊さないことを担保している点が適切。

#### design
- 実装方針は明確（tech.md の運用仕様段落を参照リンク1行に置換、設計判断は残す）。docs/ja/tech.md も同時更新しており、翻訳対称性を維持した。

#### code
- 実装はコミット1本（`61d0d8c`）で完結。2ファイル変更のみの最小変更。fixup/amend なし、コードレトロスペクティブ課題なし。

#### review
- PR なし（patch route）のためレビューコメントなし。XS サイズの機械的変更であり、verify コマンドによる自動確認で代替。

#### merge
- patch route で直接 main コミット。コンフリクトなし。Signed-off-by あり。

#### verify
- 全6条件 PASS。`file_not_contains` 2件・`section_contains` 2件・`file_contains` 2件がすべて期待通りに機能。Post-merge に manual 条件が1件残存（次回 `/auto` 運用仕様変更時の実地確認）。

### Improvement Proposals
- N/A
