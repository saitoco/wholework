# Issue #359: /verify Step 13 skill-infra classification early gate

## Overview

`/verify` Step 13 currently classifies all improvement proposals (skill-infra vs. code improvement) unconditionally, regardless of `HAS_SKILL_PROPOSALS`. When `HAS_SKILL_PROPOSALS=false`, Issue creation for skill-infra proposals is gated — but the classification step itself, duplicate check, freshness check, and skip-count log still execute. This wastes processing and adds noise (e.g., "Detected N skill infrastructure improvement proposals, but skipping...") in non-skill-dev projects.

This change adds an early gate immediately before the classification step in Step 13: when `HAS_SKILL_PROPOSALS=false`, all proposals are routed directly to the code improvement handler without classifying, running skill-infra duplicate/freshness checks, or emitting skip-count log. The gate sits before the classification step, not just at Issue creation.

## Changed Files

- `skills/verify/SKILL.md`: Step 13 — add early `HAS_SKILL_PROPOSALS=false` gate before "classify each improvement proposal", routing all proposals to code improvement handler; remove the `HAS_SKILL_PROPOSALS=false` skip branch from the skill-infra Issue creation rule

## Implementation Steps

1. In `skills/verify/SKILL.md` Step 13, replace the line `**If improvement proposals exist**: classify each improvement proposal by the following criteria.` with:
   ```
   **If improvement proposals exist**:

   **Early gate — if `HAS_SKILL_PROPOSALS=false`**: skip classification. Treat all proposals as Code improvements and proceed directly to the Code improvement handler (duplicate check → freshness check → create Issues). No skill-infra classification, no skip-count log.

   **If `HAS_SKILL_PROPOSALS=true`**: classify each improvement proposal by the following criteria.
   ```
   Then replace the Skill infrastructure Issue creation rule `only create Issue if \`HAS_SKILL_PROPOSALS=true\`. If \`false\`, skip Issue creation and output the count of skipped proposals to terminal (e.g., "Detected N skill infrastructure improvement proposals, but skipping Issue creation because \`skill-proposals\` marker is disabled.")` with `create Issue (reached only when \`HAS_SKILL_PROPOSALS=true\`)`.

## Verification

### Pre-merge

- <!-- verify: rubric "skills/verify/SKILL.md Step 13 early-gates the skill-infrastructure-vs-code classification block when HAS_SKILL_PROPOSALS is false: before the 'classify each improvement proposal' step, a gate routes all proposals directly to the code-improvement handler so that no skill-infra classification, duplicate check, freshness check, or skip-count log runs for skill-infra proposals. The gate sits before the classification step, not just at the Issue creation step." --> `/verify` Step 13 で `HAS_SKILL_PROPOSALS=false` のとき分類ロジック全体が早期 gate され、全 proposal が Code improvement として扱われる

### Post-merge

- 非 skill-dev プロジェクト（`.wholework.yml` に `skill-proposals: true` を置かない、または未設定の状態）で改善提案を含む Spec を対象に `/verify` を実行した際、terminal 出力に `Detected N skill infrastructure improvement proposals` や `Skill infrastructure improvement` 等の skill-infra 分類関連メッセージが一切現れず、かつ `retro/verify` ラベル付きの新規 Issue のうち skill-infra 由来（`/verify` 等の skill 自身への改善提案）の Issue が 0 件であることを手動確認 <!-- verify-type: manual -->

## Notes

- `HAS_SKILL_PROPOSALS` is already fetched in Step 4 via `detect-config-markers.md`; no additional fetch needed at the gate
- The duplicate check and freshness check for Code improvements still run normally when `HAS_SKILL_PROPOSALS=false` (all proposals are treated as Code improvements and go through those checks)
- Parent issue: #294 (Core/Domain 分離 Phase 3)
