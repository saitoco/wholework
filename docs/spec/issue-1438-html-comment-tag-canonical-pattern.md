# Issue #1438: spec: HTMLコメントタグ抽出のcanonical pattern参照をSkill Development Constraint Checklistに追加

## Issue Retrospective

### Acceptance Criteria の修正

`/triage` の AC audit コメント (saito, MEMBER) で、Pre-merge AC #1 の verify command `file_contains "skills/spec/skill-dev-constraints.md" "verify-classifier.md"` が常時 PASS するパターンであると指摘された。

- **原因**: 検索文字列 `"verify-classifier.md"` は、本 Issue が実装する新規チェックリスト行を待たず、既存の Constraint checklist 行 (`Patch route CI verify | ... | #112`, `skills/spec/skill-dev-constraints.md:67`) に main ブランチ上で既に存在していた。実装前から常に PASS してしまうため、AC として無効。
- **修正**: 検索文字列を、新規追加行が実装後にのみ含むはずの `"閉じタグ"` に変更した (`skill-dev-constraints.md` に既存の同一文字列がないことを事前に grep で確認済み)。コメントの修復案どおり、実装後にのみ真になる、より具体的な文字列への置き換え。
- AC #2 (rubric) は変更なし — 既に `modules/verify-classifier.md` § Tag Extraction Rule への参照内容を要求する具体的な文言になっており、AC #1 の修正後の `file_contains` チェックが同じファイルへの補完的なメカニカル安全網として機能する。

### Post-merge セクション追加

Issue 本文に `### Post-merge` セクションが存在しなかったため「なし」で追加した (post-merge 条件なし、pre-merge のみの構成)。

### その他

- ambiguity 検出: 該当なし (Size XS、要件は明確)。
- steering docs (product.md / tech.md) との整合性チェック: Forbidden Expressions 抵触なし、用語 (「verify command」) は既に正しく使用されている。
- Background の事実主張 (`modules/verify-classifier.md` § Tag Extraction Rule の記載内容、#1271 実装の乖離) はコードベース照合により裏付け確認済み。

### Consumed Comments

- saito / MEMBER / first-class / Pre-merge AC #1 の verify command が常時 PASS するパターンである旨の triage AC audit 指摘 / https://github.com/saitoco/wholework/issues/1438#issuecomment-5380795218

## Consumed Comments
No new comments since last phase.
