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

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- スキップ（XS patch ルート）。本 Issue は `modules/verify-patterns.md` への 1 行追加のみで設計レイヤー不要。
- /issue 段階で曖昧点（grep 交替構文と `--when`）が事前解決されており、spec を省略しても実装に支障なし。

#### design
- N/A（XS 規模、設計フェーズなし）

#### code
- 1 コミット (`6bd7e6c`) で完結。fixup/amend なし。
- 実装内容は AC が要求した通りの 1 行追加で、追加範囲・場所ともに verify-patterns.md の既存テーブル末尾近傍（パターン #5 として）に追加。

#### review
- スキップ（patch ルート）。Size XS のため main 直コミットで PR レビュー経路を通らず。
- /issue 段階での AC 明確化により review 不在のリスクは限定的。

#### merge
- N/A（patch route, main 直コミット）

#### verify
- AC3 (`file_contains docs/spec-writing-guide.md`) は `--when` により SKIPPED となるのが正常動作。/issue 段階で AC3 を `- [x]` 事前チェックしているが、verify では SKIPPED 判定となり整合性が取れていない（実害なし — 既に [x] のまま phase/done を阻害しない）。
- post-merge 条件（manual）は次回 /spec 実行時の観察が必要なため、phase/verify に留まる。

### Improvement Proposals
- N/A — verify pattern が機能し、Issue Retrospective 段階での曖昧点解決が有効に作用した好例。skill 改善提案は無し。

