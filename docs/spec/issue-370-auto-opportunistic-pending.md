# Issue #370: auto: Make Completion State Explicit When Opportunistic Conditions Remain

## Overview

`/auto` の patch-route XS において、pre-merge 受入条件がすべて PASS した後も `verify-type: opportunistic` の post-merge 条件が unchecked のまま残る場合がある。このとき `skills/auto/SKILL.md` Step 5 の完了判定ロジックに当該状態の扱いが明示されていない。

Issue #365 verify iter 2 でこのパターンが確認された: Issue が `phase/verify` に遷移したにもかかわらず、Step 5 の完了バナーに「opportunistic 条件 pending」の旨が表示されなかった。

本 Issue では、Step 5 に `phase/verify` ラベルの残存確認ステップを追加し、残存している場合は通常の完了バナーの代わりに「partial success — opportunistic pending」バナーを出力するよう記述を追加する。

## Changed Files

- `skills/auto/SKILL.md`: Step 5 に opportunistic pending 状態の検知と partial success バナー出力を追加

## Implementation Steps

1. `skills/auto/SKILL.md` Step 5 の "If all phases succeeded, output the completion banner:" 段落を以下の構造に置き換える (→ 受入条件 1, 2):

   **置き換え前:**
   ```
   If all phases succeeded, output the completion banner:
   ```
   /auto #N complete
   TITLE
   URL
   ```
   Followed by a result table (one row per phase with status).
   ```

   **置き換え後:**
   ```
   If all phases succeeded:

   1. **Check for opportunistic pending state**: Run `gh issue view $NUMBER --json labels --jq '.labels[].name'`

   2. **If output contains `phase/verify` (opportunistic pending)**: output the partial success — opportunistic pending banner:
      ```
      /auto #N partial success — opportunistic pending
      TITLE
      URL
      ```
      Followed by a result table (one row per phase with status). Post-merge opportunistic conditions remain unchecked; run `/verify $NUMBER` after confirming them manually.

   3. **If output does not contain `phase/verify`**: output the completion banner:
      ```
      /auto #N complete
      TITLE
      URL
      ```
      Followed by a result table (one row per phase with status).
   ```

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/auto/SKILL.md" "### Step 5" "opportunistic" --> `skills/auto/SKILL.md` Step 5 に opportunistic pending 状態への言及が含まれている
- <!-- verify: section_contains "skills/auto/SKILL.md" "### Step 5" "partial success" --> `skills/auto/SKILL.md` Step 5 に partial success 状態の明示が含まれている

### Post-merge

- 当該パターンで `/auto` を実行し、Step 5 完了バナーに opportunistic pending の状態が表示されることを確認 <!-- verify-type: opportunistic -->

## Notes

### Auto-resolved ambiguity points (from Issue body)

| # | 曖昧ポイント | 採用 | 理由 |
|---|------------|------|------|
| 1 | verify command の OR パターン | `section_contains` 2 つに分割 | ripgrep は ERE を使用するため `\|` がリテラル解釈されるリスクがある。`section_contains` で Step 5 スコープに限定することで誤検知も防げる |
| 2 | opportunistic pending 状態の検知方法 | verify 後に `gh issue view` でラベル確認 | ラベル確認は最もシンプルかつ確実。`phase/verify` が verify 後も残っている = opportunistic pending |
| 3 | post-merge 条件の verify-type | opportunistic | `/auto` を実行して確認する性質のため機械的な verify command は不適切 |
