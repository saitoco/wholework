# Issue #601: audit/drift: environment-adaptation.md Layer 3 表に skills/review/workflow-guidance.md が未掲載

## Issue Retrospective

### 自動解決した曖昧点

1. **AC #3 の verify コマンド修正**
   - **問題**: 元の `<!-- verify: file_not_contains "skills/review/workflow-guidance.md" "" -->` は空文字列を引数とする無効なコマンド。`file_not_contains` は全ファイルに対して常に FAIL するか、動作が未定義になる。
   - **解決**: `file_contains "skills/review/workflow-guidance.md" "capability: workflow"` に置換。frontmatter の `load_when.capability: workflow` が保持されていることを正方向で検証する形に変更。
   - **判断根拠**: 「ファイルを変更しない」という制約はスコープ定義であり、検証の対象としては「変更前の正しい状態が維持されているか」を確認する方が適切。

2. **section_contains の追加**
   - **追加理由**: `verify-patterns.md §5` の「テーブル行追加の検証には `grep` + `section_contains` の組み合わせを推奨」に従い、`### Domain Files (exhaustive)` セクション内に行が挿入されていることを確認する verify コマンドを追加。
   - **判断根拠**: `grep` のみでは環境適応ドキュメントの別箇所に偶発的にマッチする可能性があるため、セクションスコープを限定する `section_contains` で精度を向上。

3. **Post-merge AC への verify-type: manual 付与**
   - **判断根拠**: `/audit drift` は Claude Code スキルの対話的実行を必要とするため、`command` ヒントや `github_check` では自動検証不可。`verify-classifier.md` の分類基準（"Does not match auto or opportunistic" → manual）に従い `manual` を付与。

### Triage 結果

- Type: Task
- Size: XS（ドキュメント 1 行追加のみ）
- Value: 2（Impact=0、Alignment=+2; ドキュメント正確性確保は Vision に適合）
