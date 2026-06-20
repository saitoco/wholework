# Issue #728: spec: add output-structure criteria guideline for observation-type post-merge AC

## Overview

`/spec` の Step 10 (Create Spec) の `verify-type tag check` セクションに、`observation event` 型 AC 記述ガイドラインを追加する。

背景: `<!-- verify-type: observation event=* -->` 形式で AC を定義する場合、観測対象イベントのみ記述して期待される出力構造 criteria が暗黙になると、`/verify` 段階での FAIL/PASS 判定がブレる。#702 で実際に発生した問題 (iteration 1 でイベントは fire したが内容が tautological → FAIL → iteration 2 再修正)。

解決方針: observation event AC を書く際、(a) 観測対象イベント と (b) 期待される出力構造 criteria の分離記述を義務付ける。実装者はシチュエーションに応じて Option A (2部構成) か Option B (rubric verify command 付与) を選択する。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: Auto-Resolve Log (実装先 SKILL.md 確定・両アプローチ guideline 化) + AC 変更内容を記載 / https://github.com/saitoco/wholework/issues/728#issuecomment-4759763623

## Changed Files

- `skills/spec/SKILL.md`: `**verify-type tag check:**` セクション (Step 10 内) に `observation`-tagged 条件向けガイドライン bullet を追加 — bash 3.2+ compat 非該当 (Markdown のみ)

## Implementation Steps

1. `skills/spec/SKILL.md` の `**verify-type tag check:**` セクション (line 420-425 付近) で、既存の `manual`-tagged 条件の bullet の後に `observation`-tagged 条件向け bullet を追加する (→ AC1, AC2)

   追加する内容 (日本語出力は Skill guideline として適切):
   ```
   - `observation`-tagged conditions — when writing an observation event AC, explicitly separate (a) the observed event and (b) expected output structure criteria. Choose one of:
     - **Option A (2-part structure)**: add indented sub-bullets after the AC line:
       ```
       - [ ] {observed event}<!-- verify-type: observation event={event-name} -->
         - Expected output structure:
           - {criteria 1}
           - {criteria 2}
       ```
     - **Option B (rubric verify command)**: attach a rubric verify command to the same AC line:
       ```
       - [ ] {observed event}<!-- verify-type: observation event={event-name} --> <!-- verify: rubric "{output quality criteria}" -->
       ```
   ```

## Verification

### Pre-merge

- <!-- verify: grep "observation event" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` に observation event AC の品質 criteria 記述ガイドラインが追加されている
- <!-- verify: rubric "skills/spec/SKILL.md の Step 10 で observation event AC 生成時に出力構造 criteria の分離記述または rubric verify command 付与が明示されている" --> <!-- verify: section_contains "skills/spec/SKILL.md" "### Step 10" "observation event" --> guideline 文書化基準を満たす

### Post-merge

なし

## Notes

- 実装先は `skills/spec/SKILL.md` 直接記述 (Auto-resolve: domain file への分離は capability-gated 専用ロジック向け; 本 Issue の observation AC ガイドラインは一般ルールに該当するため SKILL.md 直接記述が標準パターン)
- 両アプローチ (Option A: 2部構成 / Option B: rubric) を guideline として並記 (Auto-resolve: 提案に「または」と並記されており、least-risk 解法として両方を guideline 化)
- `verify-type tag check` セクションへの挿入位置: `manual`-tagged 条件 bullet の直後
- `section_contains "skills/spec/SKILL.md" "### Step 10" "observation event"` が通過するよう、追加テキストに `observation event` という文字列を含めること
