# Issue #352: verify — Warn on All-Checked, No-Implementation Pattern

## Overview

`/verify` 実行時に、全受け入れ条件がチェック済み (`[x]`) にもかかわらず実装コミット・マージ済み PR が存在しないパターン（false-ready state）を検出し、警告を出力する機能を追加する。警告後はフローを継続する（中断しない）。

実装は `skills/verify/SKILL.md` の Step 1 末尾に **pre-check** サブセクションとして追加する。

Issue の Auto-Resolved Ambiguity Points に従い:
- 判定方法: `gh pr list --search "closes #$NUMBER" --state merged` (Step 2 と同方式) + `git log --grep="#$NUMBER"`
- トリガー閾値: 受け入れ条件が**すべて** `[x]` の状態
- 警告後フロー: verify フローを継続（中断しない）

## Changed Files

- `skills/verify/SKILL.md`: Step 1 のフェーズバナー表示行の直後（`### Step 2` の直前）に `pre-check: all-checked, no-implementation pattern` サブセクションを追加

## Implementation Steps

1. `skills/verify/SKILL.md` の Step 1 内、フェーズバナー表示行（`Read ${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` の行）の直後に以下のサブセクションを挿入する（`### Step 2` の直前）:

   ```
   **pre-check: all-checked, no-implementation pattern**

   After the banner, detect the false-ready state: all acceptance conditions are pre-checked (`[x]`) but no implementation commit or merged PR exists for this issue. If detected, output a warning and continue (do not abort).

   1. Fetch Issue body: `gh issue view "$NUMBER" --json body`
   2. Count total checkboxes and checked (`[x]`) items in the Acceptance Criteria section
   3. If all conditions are checked:
      - Check for merged PR: `gh pr list --search "closes #$NUMBER" --state merged --json number --jq 'length'`
      - Check for direct commits: `git log --oneline --grep="#$NUMBER" -20`
      - If no implementation commit or merged PR is found (both return 0 results), output the following warning and continue:
        ```
        Warning: All acceptance conditions are pre-checked but no implementation commit or PR was found for issue #$NUMBER. This may be a false-ready state.
        ```
   4. Continue with normal verify flow
   ```

## Verification

### Pre-merge

- <!-- verify: grep "no.*implementation\|commit.*missing\|pre-check" "skills/verify/SKILL.md" --> `skills/verify/SKILL.md` に「チェックボックス事前チェック済み・実装コミット未存在」パターンの警告ロジックが記述されている
- <!-- verify: section_contains "skills/verify/SKILL.md" "### Step 1" "pre-check" --> Step 1 またはその周辺に pre-check 警告に関する記述が追加されている

### Post-merge

- `/verify 352` を再実行して Issue がクローズされることを確認する

## Notes

- SKILL.md は LLM 実行ファイルのため bats テストは不要
- pre-check は Step 1 に含まれるため `section_contains "### Step 1" "pre-check"` で検証可能
- 実装テキスト中の "pre-check"（小文字）が `grep "pre-check"` にマッチし、"no implementation commit or merged PR" が `grep "no.*implementation"` にマッチすることを確認済み
- `git log --grep="#$NUMBER"` はパッチルート（PR なし）でのコミット確認に対応するため両方チェックする
