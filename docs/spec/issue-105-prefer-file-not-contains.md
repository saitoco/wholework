# Issue #105: spec: 広範grep command hint より個別 file_not_contains を優先する指針を追加

## Overview

`/review` の safe モードでは `command "test $(grep ...) -eq 0"` 形式の verify hint が UNCERTAIN になる（Issue #94 レビューレトロスペクティブで確認）。一方、同じテキスト除去確認を個別の `file_not_contains` に分解すると safe モードでも PASS/FAIL を確定できる。

`skills/spec/SKILL.md` の Step 10 にある verify command 選択ガイドライン群に、テキスト除去確認は可能な限り個別 `file_not_contains` に分解するという指針を追加する。

## Changed Files

- `skills/spec/SKILL.md`: `verify-type tag check` セクションの後に "Text removal verify command preference" 段落を追加

## Implementation Steps

1. `skills/spec/SKILL.md` の `verify-type tag check` セクション（`opportunistic`-tagged conditions... の行）の直後、`**Spec filename rules:**` の前に以下の段落を挿入する（→ 受け入れ基準1, 2）:

   ```
   **Text removal verify command preference:**

   For verifying text removal (deletion or replacement of specific strings), `file_not_contains` checks are preferred over broad `command "test $(grep ...) -eq 0"` form. `file_not_contains` produces deterministic PASS/FAIL in `/review` safe mode; broad `command` grep form becomes UNCERTAIN. Decompose into per-file `file_not_contains` checks when possible; use `command` only when `file_not_contains` cannot express the condition.
   ```

## Verification

### Pre-merge

- <!-- verify: grep "file_not_contains.*prefer\|file_not_contains.*over.*command\|個別.*file_not_contains" skills/spec/SKILL.md --> `skills/spec/SKILL.md` に `file_not_contains` 優先指針が追記されている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/spec/" --> `validate-skill-syntax.py` が PASS する

### Post-merge

- `/spec` 実行時、テキスト除去を確認する acceptance criteria では `file_not_contains` が優先されるようになる

## Notes

- 追加場所: `verify-type tag check` と `Spec filename rules` の間（既存の verify command ガイドライン群と隣接させる）
- `modules/verify-patterns.md` 行32に count aggregation の `command` hint に関する既存ガイドラインがあるが、テキスト除去（`-eq 0` 形式）に特化した指針はないため、SKILL.md に追加する
- SKILL.md body は English 規約のため、追加テキストは英語で記述する

## Code Retrospective

### Deviations from Design

- コミットプレフィックスに `chore:` の代わりに `feat:` を使用した（Issue Type: Task → `chore:` が正しい）

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A
