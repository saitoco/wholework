# Issue #37: settings: Fix permission patterns for plugin absolute paths

## Issue Retrospective

### Ambiguity Resolution

- **パスパターン形式**: 相対パスが絶対パスにマッチしないことが permission-log.txt 分析で確定。`${CLAUDE_PLUGIN_ROOT}` 展開後のパスにマッチするパターンが必要。
- **ワイルドカード対応**: Claude Code の permissions.allow がグロブパターン（`*/scripts/xxx.sh *`）をサポートするかは未調査。Spec フェーズで検証する。

### Key Decisions

- #34 は settings.json の構造・hook 設定として完了済み。本 Issue はパスパターンの修正に特化。
- `settings.local.json` に蓄積した `~/.claude/scripts/` 形式のエントリも原因の一部である可能性があるため、併せて調査する。

## Issue Refinement Retrospective

### Changes from Initial Issue

- **Triage 実行**: Type=Bug, Priority=high, Size=XS, Value=3 を設定
- Bug に分類: 期待動作（確認プロンプトなし）と実際の動作（プロンプト多発）が異なるため
- Priority=high: 全スキル実行に影響し、DX を大幅に低下させているため

### Ambiguity Auto-Resolution

- `file_not_contains "Bash(scripts/"` パターンはワイルドカード形式（`Bash(*/scripts/`）にマッチしないため false positive なし
- 具体的なパターン形式は Investigation Notes で Spec に委任済み

## Issue Refinement Retrospective (2)

### Ambiguity Auto-Resolution

1. **パターン形式（ワイルドカード採用）**
   - `settings.json` 既存の `"Bash(~/.claude/scripts/*.sh *)"` パターンによりワイルドカードが機能することをコードから確認。
   - 26 個のスクリプトを個別列挙するより `Bash(/Users/saito/src/wholework/scripts/*.sh *)` 一行で全カバーできるため、ワイルドカードを採用と自動解決。

2. **settings.local.json のスコープ外判断**
   - 現 `settings.json` に `~/.claude/scripts/` の絶対パス・チルダパターンが既存のため対応済み。本 Issue の範囲外と自動解決。

### Acceptance Criteria の変更

- 旧: `grep "scripts/get-issue-size.sh"` / `grep "scripts/run-code.sh"` — ワイルドカードパターン採用時は individual スクリプト名が settings.json に出現しないため false negative になる問題があった
- 新: `file_contains ".claude/settings.json" "Bash(/Users/saito/src/wholework/scripts/*.sh *)"` — ワイルドカードエントリの存在を直接検証する形に統一

### Purpose の明確化

Issue 背景を整理し、「相対パスが問題」ではなく「ワイルドカードパターンが存在しない」ことが本質的な原因であることを明記した。
