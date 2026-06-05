# Issue #533: customization: verify-ignore-paths の glob サポート範囲を実装に合わせて正確化

> XS patch route で実装（spec フェーズなし）。本 Spec は `/auto` Step 4b により issue retrospective を転記したもの。

## Issue Retrospective

### 自動解決した曖昧ポイント

#### 1. AC3: `gh pr checks` → `gh run list` に変更（verify-classifier §Patch Route CI Verification Note 適用）

- **選択肢A（採用）**: `github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"`
- **選択肢B（却下）**: `github_check "gh pr checks" "Run bats tests"`
- **理由**: Size=XS はパッチ経路（直接 main コミット）のため PR が存在しない。`verify-classifier.md` の「Patch Route CI Verification Note」に従い `gh run list` 形式に変更。`expected_value` も job 名から `"success"` に修正（`gh run list` は run レベルの conclusion を出力するため job 名は使用不可）。

#### 2. AC2 verify command 強化（偽陽性リスクの排除）

- **選択肢A（採用）**: `rubric` による意味的確認 + `file_not_contains "docs/ja/guide/customization.md" "gitignore 形式"` による旧フレーズ削除確認
- **選択肢B（却下）**: 元の `file_contains "docs/ja/guide/customization.md" "verify-ignore-paths"`
- **理由**: `verify-ignore-paths` は変更前から日本語ミラーファイルに存在する文字列。このままでは変更なしでも PASS する偽陽性となる。`verify-patterns.md` §8（ポリシー変更パターン）に従い、旧テキスト削除確認を追加。

#### 3. AC1 rubric への補完チェック追加（§8 + §9 適用）

- **採用**: `file_not_contains "docs/guide/customization.md" "gitignore format"` および `file_not_contains "docs/guide/customization.md" "gitignore-style"` を追加
- **理由**: `verify-patterns.md` §8（ポリシー変更パターン）により、旧テキスト削除確認を mechanical check で追加。§9（rubric + 補完チェック）に従い、rubric の意味的確認に加えて旧テキストの機械的削除確認を行う。YAML コメント（行50: "gitignore-style glob list"）とテーブル（行95: "gitignore format"）の両方を対象とした。

### 主要ポリシー判断

- **スコープ**: YAML コメントとテーブルの両方を更新対象とした（背景セクションで "gitignore format" / "gitignore-style glob list" の両方が問題として明示されていたため）。
- **日本語ミラー**: rubric + file_not_contains の組み合わせで確認することにより、翻訳品質と旧フレーズ削除の両方を保証する。
- **サブ Issue 分割**: 非インタラクティブモードのためスキップ。Size=XS かつ単一ファイル修正であり分割不要と判断。
