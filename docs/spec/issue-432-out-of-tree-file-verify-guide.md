# Issue #432: verify-patterns: プロジェクト外ファイルを参照する verify command のガイダンスを整備

## Overview

`grep` / `file_contains` で `~/.claude/settings.json` などプロジェクトルート外のパスを参照すると、Claude Code のセキュリティサンドボックスによりアクセスが拒否され UNCERTAIN になる。この挙動と推奨代替 (`command "python3 -c ..."` 形式) を `modules/verify-patterns.md` の新セクション §20 として明記する。実装アプローチは Approach A (ガイドライン追加のみ) を採用。Approach B (専用コマンド追加) / C (自動フォールバック) は別 Issue 対応。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: Approach A 自動選択、AC の正式化、旧称: verify hint → "verify command" 用語更新 / https://github.com/saitoco/wholework/issues/432#issuecomment-4824715925

## Changed Files

- `modules/verify-patterns.md`: 末尾に §20 "Out-of-Tree File References — Use `command python3` Instead of `grep`/`file_contains`" セクションを追加

## Implementation Steps

1. `modules/verify-patterns.md` の `## Output` セクションの直前 (§19 の末尾の後) に §20 を追加する (→ 受入条件 1, 2, 3)

   追加するセクションの構成:
   - セクション見出し: `### 20. Out-of-Tree File References — Use command python3 Instead of grep/file_contains`
   - **背景**: `grep`/`file_contains` のパス引数にプロジェクトルート外 (out-of-tree) のパス (例: `~/.claude/settings.json`) を指定すると、Claude Code の Grep ツールのセキュリティ制限によりアクセスが拒否され UNCERTAIN になる
   - **NG/OK 早見表** (テーブル形式):

     | やりたいこと | NG | OK |
     |---|---|---|
     | `~/.claude/settings.json` に特定キーワードがあるか | `grep "key" "~/.claude/settings.json"` | `command "python3 -c \"import json,os; ...\"` |

   - **推奨パターン**: `command "python3 -c \"import json,os; data=json.load(open(os.path.expanduser('~/.claude/settings.json'))); assert 'keyword' in str(data)\"`
   - **セキュリティ境界の維持**: `grep`/`file_contains` の out-of-tree 拒否はデフォルト deny として維持され、`command python3` は利用者が意図的に out-of-tree アクセスを宣言する明示的な opt-in 経路として機能する

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-patterns.md に、プロジェクトルート外のパス (out-of-tree、例: ~/.claude/settings.json) を grep または file_contains で参照した場合の挙動 (アクセス拒否または UNCERTAIN) と、推奨代替として command python3 形式が NG/OK 早見表で追加されている" --> `modules/verify-patterns.md` にプロジェクト外パス参照のガイダンスが追加されている
- <!-- verify: grep "out-of-tree" "modules/verify-patterns.md" --> `out-of-tree` キーワードが `modules/verify-patterns.md` に含まれている (rubric supplementary)
- <!-- verify: grep "settings\\.json" "modules/verify-patterns.md" --> `~/.claude/settings.json` を例とした NG/OK パターンが含まれている

### Post-merge

なし

## Notes

- Issue 体との実装コンフリクト: なし (modules/verify-patterns.md に out-of-tree 関連の既存記述は存在しない。grep "out-of-tree" "modules/verify-patterns.md" で確認済み)
- 推奨パターン中の Python3 コードは、`json.load` + `os.path.expanduser` の組み合わせが CLI ツール依存なしで安全に動作するため採用
- `command` verify タイプは full モードでのみ実行されるため、`/review` (safe モード) では UNCERTAIN になる点を §20 に明記する

## Code Retrospective

### Deviations from Design
- None. §20 was added exactly as specified (section heading, background, NG/OK table, recommended pattern, security boundary note, verify mode note).

### Design Gaps/Ambiguities
- Spec's NG/OK table used Japanese column header ("やりたいこと") but verify-patterns.md uses English throughout; adapted to English ("Goal") for consistency with the surrounding document style.

### Rework
- `## Consumed Comments` contained a quoted deprecated term that triggered CI forbidden expression scan; fixed by adding `旧称:` prefix to the quoted comment text.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Approach A (guideline-only) implemented: §20 added to `modules/verify-patterns.md` as a standalone section before `## Output`.
- English column headers used in the NG/OK table to match the surrounding document style (Spec used Japanese "やりたいこと" but the module is English-only).
- The `command python3` pattern is positioned as explicit opt-in (not a fallback), preserving the deny-by-default security boundary.

### Deferred Items
- Approach B (`external_file_contains` command): out of scope, separate Issue required.
- Approach C (auto-fallback in verify-executor): out of scope, separate Issue required.

### Notes for Next Phase
- No post-merge ACs; `/verify` can close the Issue immediately after confirming pre-merge checkboxes (already updated to [x]).
- The rubric AC verifies semantic content of §20 — should PASS in full mode; in safe mode (`/review`) it still runs as `always_allow`.
- All 3 pre-merge verify commands confirmed PASS during `/code` execution.
