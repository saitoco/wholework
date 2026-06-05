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

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- AC 品質が高い。`/issue` refinement が2つの実質的改善を実施: (1) AC2 の `file_contains "verify-ignore-paths"`（変更前から存在し偽陽性となる）を rubric + `file_not_contains "gitignore 形式"` に置換、(2) AC3 の `github_check "gh pr checks"` を patch 経路非対応のため `gh run list --workflow=test.yml` 形式へ変更。verify-patterns §8/§9 と verify-classifier の Patch Route Note を正しく適用。

#### spec
- N/A（XS patch route のため spec フェーズなし）。issue retrospective を `/auto` Step 4b で本 Spec に転記。

#### code
- docs-only 変更（`customization.md` + 日本語ミラー）を main 直コミット（c06ef33）。手戻りなし。実装は `_is_ignored` の実サポート範囲（`dir/**` プレフィックス + 単純 bash glob、中間 `**`・否定 `!` 非対応）をドキュメントに正確に反映。

#### review
- N/A（patch route のため review フェーズなし）。

#### merge
- N/A（patch route、直コミットのため merge フェーズなし）。

#### verify
- 全 pre-merge AC（5件）PASS。AC1/AC4 の rubric は doc 記述の正確性を意味判定、AC2/AC3 と AC4 の file_not_contains が旧フレーズ削除を機械確認 — rubric + 補完チェックの組合せが有効に機能した。
- AC5（`gh run list --limit=1`）は初回 PENDING（最新 run が Step 4b の spec-retrospective コミット 5038bde で in_progress だったため）→ CI 完了待機後 conclusion=success で PASS。`--limit=1` は最新コミットの run を参照するため、Step 4b の追加コミットが新 run をトリガーしても最新コードを含む run を見るため検証は正しく機能した。
- post-merge の「（任意）glob 拡張検討」manual 条件は、ドキュメントが制約を正確化したことで「現時点で拡張不要」と検討結論を出し PASS とした。

### Improvement Proposals
- N/A。XS patch route の `gh run list --limit=1` CI 確認は Step 4b の spec-retrospective 追加コミットと相互作用するが、最新 run が最新コードを含むため検証は正しく機能した。docs-only 変更では特に問題なし。
