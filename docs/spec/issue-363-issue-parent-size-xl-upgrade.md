# Issue #363: /issue Step 9/11: Add parent Size XL upgrade step on sub-issue split

## Overview

`skills/issue/SKILL.md` に sub-issue 分割を実行した際の parent Size XL 昇格ステップが欠落している。

現状は「分割不要の場合に Size XL → L へ降格する」方向のみ Step 9 の preamble に記述されており、「分割実行時に parent Size を XL へ昇格する」方向が存在しない。初期 triage で M/L と見積もった Issue を分割した場合、parent Size が誤ったまま残り、`/auto {parent}` が pr ルートとして誤実行されるリスクがある（実害: #294, #295 で手動昇格が必要になった）。

Step 9（新規 Issue flow）と Step 11/Step 11c（既存 Issue refinement flow）の両方に、分割実行時の parent Size XL 昇格ステップを追加し、降格と昇格の両方向を対称的に提示する。

## Changed Files

- `skills/issue/SKILL.md`:
  - Step 9: 「**Changing Size when split is executed:**」ブロックを追加（「**Changing Size when no split is needed:**」と対称配置）、Procedure に手順 9（parent Size → XL 昇格、`project-field-update.md` 参照）を追加
  - Step 11c: 「procedures 2–8」を「procedures 2–9」に更新し、手順 9（parent Size → XL 昇格）を追加
  - Step 11 フッター: 昇格・降格の両方向を対称的に記述するよう更新

## Implementation Steps

1. **Step 9 への昇格追加（→ 検証項目 1, 3, 5, 6）**: 「**Changing Size when no split is needed:**」ブロック直後に「**Changing Size when split is executed:**」ブロックを追加。内容: 「Read `${CLAUDE_PLUGIN_ROOT}/modules/project-field-update.md` and update parent Size → XL (steps 1→2→3→4). Use label fallback (step 5) only if GraphQL fails. When GitHub Projects is not configured, step 1 returns empty `projectsV2.nodes` and automatically falls through to step 5.」。次に Procedure の手順 8 直後に手順 9 を追加: 「Upgrade parent Size → XL: read `${CLAUDE_PLUGIN_ROOT}/modules/project-field-update.md` and update parent Size → XL (steps 1→2→3→4). Use label fallback (step 5) only if GraphQL fails.」

2. **Step 11c と Step 11 フッターへの昇格追加（→ 検証項目 2, 4, 6）**: Step 11c の「Run the standard sub-issue creation flow (New Issue Creation Step 9, procedures 2–8):」を「procedures 2–9」に変更し、手順リスト末尾に手順 9（前述と同文）を追加。Step 11 フッター「(For non-L/XL or fallback: run standard split assessment. Size XL → L change applies when no split is needed.)」を「(For non-L/XL or fallback: run standard split assessment. Size → XL upgrade applies when split is executed; Size XL → L downgrade applies when no split is needed.)」に更新。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/issue/SKILL.md Step 9 (Scope Assessment for new issue creation flow) contains a procedure step that upgrades the parent Issue's Size to XL when sub-issue split is executed. The step references modules/project-field-update.md for the Size update mechanism" --> Step 9 (新規 Issue flow) に parent Size XL 昇格ステップが追加されている
- <!-- verify: rubric "skills/issue/SKILL.md Step 11 / Step 11c (existing issue refinement flow, including Step 11c sub-issue creation after approval) contains a procedure step that upgrades the parent Issue's Size to XL when sub-issue split is executed. The step references modules/project-field-update.md for the Size update mechanism" --> Step 11 / Step 11c (既存 Issue flow) に parent Size XL 昇格ステップが追加されている
- <!-- verify: section_contains "skills/issue/SKILL.md" "### Step 9: Scope Assessment (sub-issue splitting)" "XL" --> Step 9 セクション内に XL の記述がある
- <!-- verify: section_contains "skills/issue/SKILL.md" "### Step 11: Scope Assessment (sub-issue splitting)" "XL" --> Step 11 セクション内に XL の記述がある
- <!-- verify: file_contains "skills/issue/SKILL.md" "project-field-update.md" --> Size 更新手順として project-field-update.md が参照されている
- <!-- verify: rubric "The XL downgrade description (Size XL → L when no split needed) and XL upgrade description (Size → XL when split executed) are symmetrically presented so readers can see both directions" --> XL への昇格と L への降格の両方向が対称的に記述されている

### Post-merge

- 新規 M/L Issue に対して `/issue` で sub-issue 分割を実行し、parent Size が XL に自動更新されることを手動確認

## Notes

検証項目 3（section_contains Step 9 "XL"）、4（section_contains Step 11 "XL"）、5（file_contains "project-field-update.md"）は実装前の既存コードですでに通過条件を満たしている。rubric 条件（項目 1, 2, 6）の充足が本 Issue の実質的な要件であり、実装ステップ 1, 2 で対応する。
