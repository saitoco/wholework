# Issue #487: `/issue` スキル — 削除系 Issue の自動スコープ列挙

## Overview

`/issue` スキルの Pre-investigation ステップ（新規 Issue Step 5・既存 Issue Step 7）に、削除系 Issue（「削除」「撤去」「remove」「delete」「clean up」キーワードを含む）を検出した際に `grep -rl 'pattern' .` を実行して全対象ファイルを `## Scope` セクションに列挙する静的ガイドラインを追加する。

実装アプローチは案3（静的ガイドライン追加のみ）。`ambiguity-detector` や `verify-executor` 等の共有モジュール変更は不要。

## Changed Files

- `skills/issue/SKILL.md`: New Issue Creation Step 5 および Existing Issue Refinement Step 7 の冒頭（"Priority sort:" の前）に削除系 Issue 事前スキャンブロックを追加 — bash 3.2+ 非依存（Markdown テキスト追加のみ）

## Implementation Steps

1. `skills/issue/SKILL.md` の New Issue Creation **Step 5** (`### Step 5: Clarification Questions`)内、`**Priority sort:**` の直前に以下のブロックを追加する（→ AC1, AC2）:

   ```
   **Deletion-type issue pre-scan (削除系 Issue の事前スキャン):**

   Before processing ambiguity points, check if the Issue body or purpose contains deletion-type keywords (「削除」「撤去」「remove」「delete」「clean up」). If detected:
   1. Extract the target keyword or pattern from the Issue content
   2. Run `grep -rl 'pattern' .` from the repository root to enumerate all files containing the pattern
   3. Add a `## Scope` section to the Issue body listing all enumerated files (create if absent, supplement with newly found files if already present)
   ```

2. `skills/issue/SKILL.md` の Existing Issue Refinement **Step 7** (`### Step 7: Clarification Questions`)内、`**Priority sort:**` の直前に同じブロックを追加する（→ AC1, AC2）

## Verification

### Pre-merge

- <!-- verify: rubric "skills/issue/SKILL.md Pre-investigation steps (Step 5 for new issues and Step 7 for existing issues) include an instruction to detect deletion-type Issues containing keywords like 削除/撤去/remove/delete and run grep -rl to enumerate target files, then add them to the Issue body as a Scope section" --> `/issue` Skill の Pre-investigation ステップに削除系 Issue 検出時の grep 全ファイル列挙と Scope 追記の指示が追加される
- <!-- verify: grep "削除系" "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` に削除系 Issue に関する記述が存在する

### Post-merge

- 削除系 Issue を `/issue` で起票し、対象ファイルが grep により自動列挙されて Issue 本文の Scope セクションに反映されることを確認する <!-- verify-type: opportunistic -->

## Notes

- SPEC_DEPTH=light（Size=S）のため、実装ステップ数・検証項目数は軽量化
- 案3の弱点（LLM が grep をスキップする可能性）は Issue 本文でも言及済み。案1/2はモジュール変更が必要で Size=S スコープに対して過剰
- 検出テキストに「削除系」を含めること：`grep "削除系" "skills/issue/SKILL.md"` AC が機械的に検証するため
- SKILL.md 本文に半角 `!` を使わないこと（forbidden expression）
- `docs/*.md` 変更なし → `docs/ja/` 翻訳同期不要
- `docs/structure.md` の Key Files テーブルは既存ファイルへの追記のみのため更新不要

## Code Retrospective

### Deviations from Design

- Spec のブロック見出しは「Deletion-type issue pre-scan (削除系 Issue の事前スキャン):」（英語先頭）だったが、実装では「削除系 Issue の事前スキャン (Deletion-type issue pre-scan):」（日本語先頭）を採用した。`grep "削除系"` の AC が先頭テキストに依存しないため機能上の差異はないが、SKILL.md の日本語優先慣例に合わせて変更した。

### Design Gaps/Ambiguities

- 特になし。Spec は挿入位置（`**Priority sort:**` の直前）を明確に指定しており、実装はそのまま適用できた。

### Rework

- 特になし。1回のEditで実装完了。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 静的ガイドライン（Markdown テキスト追加のみ）で実装。モジュール変更・スクリプト追加なし。
- 見出し語順を日本語先頭に変更（Spec の英語先頭例からの意図的な逸脱）。
- forbidden expression（半角 `!`）なし、validate-skill-syntax PASS 確認済み。

### Deferred Items
- 案1/2（自動 grep 実行）は Size=S スコープ外として未実装のまま。LLM が grep をスキップするリスクは Issue 本文に記録済み。

### Notes for Next Phase
- verify コマンド（rubric, grep）は /code 段階で全 PASS 済み。/verify では再確認のみ。
- 変更ファイルは `skills/issue/SKILL.md` 1 ファイルのみ。
