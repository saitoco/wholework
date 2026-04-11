# Issue #118: spec-test-guidelinesにpost-merge条件のverify command付与推奨を追加

## Issue Retrospective

### Ambiguity Resolution

1. **verify command の `\|` パターン修正**: 元の verify command が BRE スタイル `\|` を使用していたが、verify システムの grep は ripgrep ベースのため `|` に修正。また複雑な OR パターンをシンプルな個別条件に分割
2. **Pre-merge / Post-merge セクション追加**: 全条件がファイル内容チェック（pre-merge auto-verified）のため、Pre-merge セクションのみで構成

### Key Decisions

- `grep "module"` は現在 spec-test-guidelines.md に存在しないキーワードのため、新規追加セクションの存在確認として十分と判断
- Related Issues に #112 を追加（レトロスペクティブの発生元）

### Nothing else to note

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue Retrospective のみ存在（Spec フェーズは省略されたパッチルート）。Verify command のパターン修正（BRE → ripgrep）と Pre-merge セクション構成は適切な意思決定だった

#### design
- パッチルートのため設計フェーズなし

#### code
- 実装コミット1件（`9e37180`）でクリーンに完了。fixup/amend パターンなし。Issue retrospective も別コミット（`f03d9e9`）として適切に分離されている

#### review
- パッチルートのためPRレビューなし。小規模な文書追加として適切な判断

#### merge
- mainへの直接コミット（パッチルート）。コンフリクトなし

#### verify
- 全2条件が即時PASS。`grep "module"` と `grep "file_contains|section_contains"` というシンプルな条件が実装内容と正確に対応しており、verify commandの品質が高かった

### Improvement Proposals
- N/A
