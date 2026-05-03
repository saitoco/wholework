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

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue 本文の verify command を section_contains 2 つに分割する形で設計した点は適切。ripgrep の ERE/BRE 曖昧性を事前に排除し、Step 5 スコープに限定することで誤検知リスクも低減。
- 受入条件の自動解決（3 点）が Issue フェーズで記録されており、設計判断の根拠が明確に追跡可能。

#### design
- Spec の実装手順（Step 5 の置き換え前/後コード）が実際の実装と一致。設計偏差なし。
- patch route XS のため Spec は最小限の構成で十分だった。

#### code
- commit 3ee3208 の 1 コミットで実装完了。fixup/amend パターンなし。
- commit 7f447e4 でコード回顧録を追加（プロセス通り）。
- コード回顧録はすべて N/A — 実装はシンプルなテキスト追加で、リワークなし。

#### review
- patch route XS のため review フェーズなし（/review 未実行）。

#### merge
- patch route による直接 main コミット。コンフリクトなし、マージプロセス上の問題なし。

#### verify
- pre-merge 2 条件ともに PASS。verify command の設計（section_contains）が意図通り機能。
- post-merge 条件は verify-type: opportunistic（/auto 実行での手動確認）。Issue は phase/verify に遷移し、ユーザーによる opportunistic 確認を待つ状態。
- FAIL なし。verify command の不整合なし。

### Improvement Proposals
- N/A
