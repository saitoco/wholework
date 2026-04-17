# Issue #242: verify-executor: section_contains で見出しが見つからない場合の診断メッセージを出力

## Issue Retrospective

### Auto-Resolved Ambiguity Points (non-interactive mode)

- **診断メッセージの言語: 英語を選択**
  - 理由: `verify-executor.md` は全文英語で書かれているため、追加する診断メッセージ仕様も英語が一貫している。元の受入条件 `file_contains "modules/verify-executor.md" "見出しが見つからない"` は日本語文字列を検索するが、実装後の英語モジュールに対して FAIL になる。`grep "no heading matched|heading not found|no matching heading"` に変更した。
  - 他の候補: 日本語 (Issue の診断例が日本語のため)

- **候補見出し件数の上限: 最大3件を明記**
  - 理由: 上限が未定義だと実装者がファイル全見出しを列挙する可能性があり、UNCERTAIN の Details 列が冗長になる。最大3件 + `...` は過多出力を防ぐ慣行として妥当。
  - 他の候補: 制限なし、最大5件

### 受入条件の変更点

1. **Pre-merge / Post-merge セクション分割を追加** — 既存の受入条件はすべてファイルベースで pre-merge に分類。
2. **AC1 の verify command を修正**: `file_contains "modules/verify-executor.md" "見出しが見つからない"` → `grep "no heading matched|heading not found|no matching heading" "modules/verify-executor.md"`
   - 日本語固定文字列から英語 regex 検索に変更 (verify-patterns.md guideline: 英語文書には grep 推奨)
3. **AC2 の verify command を修正**: `grep "heading not found\|見出し.*なし\|not found.*heading"` → `grep "[Cc]andidate heading"` に変更
   - 元のパターンは `\|` (BRE エスケープ) を使っているが ripgrep では `|` が正しい構文。候補見出しリストの仕様確認に絞って明確化。
4. **Purpose 節に英語診断例と最大件数を追記** — 実装者への仕様伝達を明確化。
5. **Related Issues セクションを追加** — `Related to #241`

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue Retrospective が ambiguity resolution を丁寧にドキュメント化しており、実装者への仕様伝達が明確だった。
- AC1 の verify command (`grep "no heading matched|..."`) は小文字パターンだが、実装は大文字 `No heading matched` を採用したため、grep が技術的に不一致になった。verify 実行時は AI 判定で PASS としたが、verify command の精度としては惜しい点。

#### design
- Spec なし（patch route）。Issue 本文と Issue Retrospective のみで設計を記録。小規模な変更として妥当。

#### code
- 単一クリーンコミット `70f1dd5`。fixup/amend パターンなし。パッチルートの直 commit として適切。

#### review
- パッチルート（PR なし）のため review なし。verify-executor.md 単独の軽微な仕様追加であり、レビュー省略は妥当。

#### merge
- main への直接コミット（パッチルート）。競合なし。

#### verify
- AC1 の grep パターン `no heading matched`（小文字）と実装の `No heading matched`（大文字 N）の不一致を検出。AI 判定で PASS としたが、verify command の作成ガイドラインとして「仕様文字列の大文字小文字は `[Nn]o` のようにブラケット表記でカバーする」か「`-i` フラグ相当の考慮を加える」ことを検討できる。

### Improvement Proposals
- verify command で docs/spec の仕様文字列を検索する場合、大文字小文字の揺れに対応するため `[Nn]o heading matched` のようなブラケット正規表現パターン、または verify-executor.md に「grep コマンドはデフォルト大文字小文字区別あり。実装テキストの正確なケースと一致させること」という注記を追加することを検討する。これにより verify command の精度が向上し、AI 判定への依存を減らせる。
