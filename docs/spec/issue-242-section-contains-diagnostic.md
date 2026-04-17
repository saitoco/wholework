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
