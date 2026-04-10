# Issue #77: verify: section_contains/file_contains の OR パターン分割ガイドラインを追記

## Issue Retrospective

### 曖昧性解決の判断根拠

| 曖昧性 | 解決方法 | 根拠 |
|--------|---------|------|
| AC2 false positive | 自動解決 → 削除 | `grep "section_contains"` は既存ファイル内 (lines 29-31) で既に PASS。AC1 で十分カバー |
| `file_contains` スコープ拡張 | 自動解決 → 含める | 同じ fixed-string matching (line 31 で言及済み)。根本原因が共通のため両方カバーが自然 |
| 配置箇所 | 自動解決 → Section 1 | "False Positive Patterns and How to Avoid Them" は同種エントリの配置場所として適切 |

### 主要なポリシー判断

- `section_contains` のみから `file_contains` も含むスコープに拡張（タイトルも合わせて更新）
- false positive する AC2 を削除し、AC1 の grep パターンに `file_contains` を追加

### 受け入れ条件の変更理由

- 旧 AC2 `grep "section_contains"` が実装前から PASS する false positive のため削除
- AC1 の grep パターンに `file_contains` の OR 条件を追加（スコープ拡張対応）
- Pre-merge / Post-merge セクション構造を適用

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue 本文内で 3 つの曖昧性（AC2 false positive、`file_contains` スコープ、配置箇所）が自動解決されており、/spec 実行なしで Spec として機能した
- AC1 の grep パターンを `file_contains` も含む OR パターンに拡張したことで、実装内容を正確に検証できた

#### design
- N/A（設計フェーズなし。シンプルな 1 行追記タスク）

#### code
- commit `d02bfc4` で直接実装。fixup/amend なし
- パッチルート（直コミット）で完結しており、PR レビューなし

#### review
- パッチルートのため PR レビューなし。コードの変更は `modules/verify-patterns.md` への 1 エントリ追加のみ

#### merge
- クリーンな直コミット。コンフリクトなし

#### verify
- grep verify コマンドが正確に機能。36 行目にマッチ（PASS）
- 既にチェック済みの条件だったが、再検証でも同じ PASS 結果（idempotent）

### Improvement Proposals
- N/A
