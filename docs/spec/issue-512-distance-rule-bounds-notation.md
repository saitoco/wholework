# Issue #512: spec: 距離ルール記述に下限・上限を明示する表記規約を追加

## Issue Retrospective

### 曖昧点の自動解決

#### 1. grep 交替構文の分割（高優先度）

**解決内容**: 元の AC1 verify command `grep "以上かつ.*以内\\|lower.*bound\\|下限" modules/verify-patterns.md` を 2 つの独立した grep コマンドに分割。

**理由**: `\|` はGNU grep の BRE 拡張であり、macOS の BSD grep では動作しない。verify-patterns.md §1「複数キーワードを同一行で grep 検索するとマルチライン時に FAIL する」パターンと同様のリスクがある。分割により OS 依存をなくし、各チェック点も明確化される。

**採用**: `grep "以上かつ" "modules/verify-patterns.md"` + `grep "下限" "modules/verify-patterns.md"`

#### 2. 条件付きファイルチェックへの `--when` 追加（中優先度）

**解決内容**: `file_contains "docs/spec-writing-guide.md" "下限"` に `--when="test -f docs/spec-writing-guide.md"` を追加。

**理由**: `docs/spec-writing-guide.md` は現時点で存在しないため、`--when` なしでは verify 実行時に必ず FAIL となる。AC テキストには「ファイルが存在する場合」と明記されており、これを verify command に反映するのが最小リスクの選択。ファイルが将来作成された場合は自動的に有効になる。

**採用**: `file_contains "docs/spec-writing-guide.md" "下限" --when="test -f docs/spec-writing-guide.md"`

### 受入条件の変更理由

- AC1（旧）: `grep "以上かつ.*以内\\|lower.*bound\\|下限"` → 交替構文を 2 つの独立した grep に分割
- AC2（旧）: `file_contains "docs/spec-writing-guide.md" "下限"` → `--when` 修飾子を追加して条件付きに変更
- Post-merge: 変更なし（manual 分類は適切）
