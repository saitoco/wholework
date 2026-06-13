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

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- `/issue` が AC #3 の壊れた verify command (`file_not_contains "..." ""`) を自動修正したことで、verify フェーズで FAIL が発生せず一発成功。`/audit drift` 生成時の AC 雛形に verify command の妥当性チェックを組み込む価値が見える（→ 改善提案）。
- `section_contains` の追加は `verify-patterns.md §5` の指針通り。雛形が `grep` のみだった点は audit の Issue 生成テンプレートで改善余地あり。

#### spec
- Size=XS のため spec フェーズはスキップ。Spec ファイル本体は `/auto` Step 4b の Issue Retrospective 転記で作成された。

#### code
- 1 commit (679252d) で完結。fixup/amend なし。実装は environment-adaptation.md の Layer 3 表に 1 行追加するのみで、watchdog log では 660s+ 経過しているが silent-no-op false-positive ではなく正常完了。`detect-wrapper-anomaly.sh` の reconcile-success gate (#592 で実装) が機能していることを確認。

#### review
- patch route のため review フェーズなし（XS の通常動作）。

#### merge
- patch route の直接コミット。マージ衝突なし。

#### verify
- Pre-merge 4 件、Post-merge 1 件すべて PASS。Post-merge AC は Claude が `/audit drift` の検出ロジックを再実行することで PASS 判定。
- 一時的に別 Issue (#581) の spec が dirty として現れた (origin 側で先に commit されていた)。`git pull` で fast-forward 解消。`check-verify-dirty.sh` は実行時点では clean を返したため Step 1 で見落としではない。

### Improvement Proposals

- **`/audit drift` の Issue 生成テンプレートに verify command 妥当性チェックを追加**: 本 Issue では AC #3 が `file_not_contains "..." ""` という壊れたコマンドで生成され、`/issue` フェーズで自動修正された。`/audit drift` の Issue 生成時に、生成した verify command が `verify-executor.md` の許容パターンに合致するかを生成直後にチェックすることで、`/issue` フェーズに過剰な負担をかけずに済む。
- **`/audit drift` の表行追加検証パターンを雛形化**: テーブル行追加系の AC では `grep` + `section_contains` の組み合わせが推奨される（`verify-patterns.md §5`）。`/audit drift` のテンプレートにこのペアを最初から組み込むことで、`/issue` での修正が不要になる。
