# Issue #118: spec-test-guidelinesにpost-merge条件のverify command付与推奨を追加

## Issue Retrospective

### Ambiguity Resolution

1. **verify command の `\|` パターン修正**: 元の verify command が BRE スタイル `\|` を使用していたが、verify システムの grep は ripgrep ベースのため `|` に修正。また複雑な OR パターンをシンプルな個別条件に分割
2. **Pre-merge / Post-merge セクション追加**: 全条件がファイル内容チェック（pre-merge auto-verified）のため、Pre-merge セクションのみで構成

### Key Decisions

- `grep "module"` は現在 spec-test-guidelines.md に存在しないキーワードのため、新規追加セクションの存在確認として十分と判断
- Related Issues に #112 を追加（レトロスペクティブの発生元）

### Nothing else to note
