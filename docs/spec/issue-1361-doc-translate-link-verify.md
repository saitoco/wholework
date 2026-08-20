# Issue #1361: doc: /doc translate に生成後の相対リンク機械検証ステップを追加

Size XS のため `/spec` は実行されていない (`phase/ready` 前提の Spec 作成をスキップし、`/code --patch` が直接実行された)。本ファイルは `/code` フェーズが Issue コメントに投稿した Implementation Complete レポートを、`/verify` の Phase Handoff / Consumed Comments 記録先として転記したものである。

## Code Retrospective

### 実装内容

- `skills/doc/translate-phase.md` — Step 5 (Review Generated Translations) に機械的な相対リンク検証サブセクションを追加。生成された各翻訳ファイルから Markdown 相対リンクを抽出し、要約/承認プロンプトの提示前に解決先ファイルがディスク上に存在することを確認する
- Commit: `09898ccd` feat: Add mechanical relative link verification to /doc translate Step 5 (closes #1361)

### AC Audit Fixes (triage コメント由来)

2026-08-15 saito (MEMBER) の triage AC audit コメントに基づき、Pre-merge verify command 2件を修正:
- `grep "relative link" "skills/doc/translate-phase.md"` → `grep "Broken relative link" "skills/doc/translate-phase.md"` (元の文字列は実装前から20行目に既存しており、機能実装の有無に関わらず常時 PASS していた)
- `section_contains "skills/doc/translate-phase.md" "### Step 5" "exist"` → `section_contains "skills/doc/translate-phase.md" "Step 5" "exist"` (見出し引数の先頭 `###` が `section_contains` の比較 (`#` とスペースを除去した見出しテキストとの比較) を妨げ、恒久的 UNCERTAIN の原因になっていた)
- 両修正コマンドは Issue AC チェックボックスをチェックする前に手動で PASS を確認済み

### Deviations from Design

- N/A — Issue 本文が示した実装内容をそのまま実施した。手戻りは発生していない。

### Tests

- `bats --jobs 18 tests/` — PASS (1887/1887, 2 skip)
- `python3 scripts/validate-skill-syntax.py skills/` — PASS (0 error, 0 warning)
- `bash scripts/check-forbidden-expressions.sh skills/doc/translate-phase.md` — PASS (0 violations)

## Consumed Comments

No new comments since last phase.
