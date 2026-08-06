# Issue #562: Spec-as-memory Enhancement (Retrospective Discipline and /code・/spec Guidance)

## Overview

Strengthen the Spec-as-memory pattern by:
1. Adding guidance to read existing retrospective sections before implementation (`skills/code/SKILL.md` Step 5) and before design (`skills/spec/SKILL.md` Step 6)
2. Adding explicit retrospective writing discipline to `skills/spec/SKILL.md` Step 13 and `skills/code/SKILL.md` Step 12

The writing discipline follows Fable 5 memory-surface guidance: one learning per entry, record corrections and confirmed approaches, avoid duplicating git history, update/delete entries found to be incorrect.

## Changed Files

- `skills/code/SKILL.md`: Step 5 — add retrospective reading guidance; Step 12 — add writing discipline rules
- `skills/spec/SKILL.md`: Step 6 — add retrospective reading guidance; Step 13 — add writing discipline rules

## Implementation Steps

1. `skills/code/SKILL.md` Step 5 (Load Spec): After the existing "Phase Handoff read" block, add a **Read existing retrospective sections** paragraph instructing `/code` to read any retrospective sections present in the Spec (e.g., `## spec retrospective`, `## code retrospective`) before starting implementation (→ AC#1)

2. `skills/spec/SKILL.md` Step 6 (Codebase Investigation): At the very start of Step 6, before `Read ${CLAUDE_PLUGIN_ROOT}/modules/measurement-scope.md`, add a **Read existing retrospective sections** paragraph instructing `/spec` to read any retrospective sections already present in the Spec file for this Issue before proceeding with codebase investigation (→ AC#2)

3. `skills/spec/SKILL.md` Step 13 (Spec Retrospective): Before the existing retrospective template block, add a **Retrospective writing discipline** paragraph with the 5 rules: one entry per learning; record both corrections and confirmed approaches; link related entries; do not duplicate what the repository or git history already records; update or delete entries found to be incorrect (→ AC#3)

4. `skills/code/SKILL.md` Step 12 (Code Retrospective): Before the existing retrospective template block, add the same **Retrospective writing discipline** paragraph as Step 3 (→ AC#4)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md Step 5 (Load Spec) includes guidance to read existing retrospective sections in the Spec (such as ## Code Retrospective or ## Spec Retrospective) before starting implementation" --> <!-- verify: section_contains "skills/code/SKILL.md" "Step 5" "retrospective" --> `skills/code/SKILL.md` の Step 5 (Load Spec) またはそれに準じる位置に、実装開始前に Spec 内の既存 retrospective セクションを参照する誘導が追加されている
- <!-- verify: rubric "skills/spec/SKILL.md Step 6 (Codebase Investigation) or equivalent early step includes guidance to read existing retrospective sections in the Spec file from prior phases before designing the implementation plan" --> <!-- verify: section_contains "skills/spec/SKILL.md" "Step 6" "retrospective" --> `skills/spec/SKILL.md` の早期ステップ（コードベース調査等）に、設計前に既存フェーズの retrospective を参照する誘導が追加されている
- <!-- verify: rubric "skills/spec/SKILL.md Step 13 (Spec Retrospective) explicitly states retrospective writing guidelines: one learning per entry, record both corrections and confirmed approaches, avoid duplicating what the repository or git history already records, and update or delete entries found to be incorrect" --> `skills/spec/SKILL.md` Step 13 に retrospective 記述規律（1 エントリ 1 学び、訂正も確認済みアプローチも記録、git history 重複排除、誤り修正）が明示されている
- <!-- verify: rubric "skills/code/SKILL.md Step 12 (Code Retrospective) explicitly states retrospective writing guidelines: one learning per entry, record both corrections and confirmed approaches, avoid duplicating what the repository or git history already records, and update or delete entries found to be incorrect" --> `skills/code/SKILL.md` Step 12 に retrospective 記述規律（1 エントリ 1 学び、訂正も確認済みアプローチも記録、git history 重複排除、誤り修正）が明示されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> 既存 bats テストが CI で PASS している

### Post-merge

- 実 `/auto` で Spec retrospective が後続フェーズに参照され、重複/矛盾記述が減っていること（観測） <!-- verify-type: manual -->

## Notes

- No bats test changes required — changes are SKILL.md text additions only
- No docs/ translation sync required — changed files are under `skills/`, not `docs/`
- No doc update (README.md, workflow.md) required — no new skills or phases added; internal step-level behavior change only
- Auto-resolved ambiguity points from Issue body are carried over verbatim (see Issue body § Auto-Resolved Ambiguity Points)
- Step 13 and Step 12 note: the writing discipline rules should be placed as a named block (e.g., `**Retrospective writing discipline:**`) before the template block so they are clearly visible as authoring guidelines, not part of the template itself

## Code Retrospective

### Deviations from Design
- None — implementation followed the 4-step plan exactly

### Design Gaps/Ambiguities
- The Spec called for "linking related entries" as a discipline rule; this was included in both Step 12 and Step 13 additions, but the Issue AC rubric did not check for it. It is present in the implementation and adds value beyond the minimum rubric requirement.

### Rework
- None

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 4 件が rubric + section_contains のペア構成で、意味的検証と構造的安全網の両立ができていた。UNCERTAIN 0 件

#### design
- 4-step 計画と実装の乖離なし。記述規律に Issue AC の最低要件を超える「関連エントリのリンク」規則が含まれ、価値を追加した

#### code
- 手戻りなし。patch ルートで spec→code が単一チェーンで完了

#### review
- patch ルートのため review フェーズなし

#### merge
- patch ルートのため merge フェーズなし

#### verify
- pre-merge 5/5 PASS。post-merge 観測条件（実 /auto での retrospective 参照効果）は適用直後のため SKIP — 直後の #563 が最初の観測機会

### Improvement Proposals
- N/A

### 追記 (2026-08-06, observation 評価時)

post-merge observation 条件が `/auto --batch 1197 1162 1133 1102` (session `74631-1786005349`) の observation scan で dispatch され、**UNCERTAIN** と判定された。条件が 2 つの節に分かれており、前半のみ成立したため。

#### 前半「後続フェーズに参照される」— 成立 (実測 3 件)

1. **跨り Issue の Spec-as-memory が回帰を防いだ (#1133)**: `docs/spec/issue-1133-*.md:65` が「前身 Issue #687 の Spec Notes が記録する通り」として `grep -c ... || _failed=0` イディオムの維持を指示し、Code Retrospective (`:83`) が「per Spec Notes' explicit instruction not to regress the Issue #687 fix」と遵守を明記。#687 の Spec Notes → #1133 の Spec Notes → code 遵守 → retrospective 確認、の連鎖が完結している
2. **retrospective 記述規律の遵守 (#1162)**: `docs/spec/issue-1162-*.md:120` が単発学びを「1 エントリ 1 学び」形式 + Tier 判断付きで記録 (本 Issue の受入条件 3/4 が求めた規律)
3. **Phase Handoff の消費 (#1102)**: `### Deferred Items` 2 件を verify フェーズがそのまま引き継ぎ、AC5 は CI 確認で解決、manual AC は SKIP と判断

#### 後半「重複/矛盾記述が減っている」— 判定不能

比較基準が記録されておらず増減を確定できない。加えて同バッチ内に反例がある — #1102 の Spec で、GitHub timeline と矛盾する `phase/ready` 不在の主張が `## Notes` > `### Auto-Resolve Log` と `## Phase Handoff` > `### Notes for Next Phase` の 2 箇所に重複して書き込まれていた (verify で訂正注記を追記済み、同型の齟齬は #1112 で追跡中)。

#### AC 設計上の所見

「減っている」という比較節は測定可能なベースラインを伴わないため、PASS にも FAIL にも倒せず observation AC として恒久的に UNCERTAIN に留まる構造になっている。「後続フェーズが Spec retrospective を参照した形跡が Spec 内に残っている」のような**単一実行で判定可能な条件**への再型付けが妥当。observation AC の判別可能性という論点は #1118 が扱っており、単発観測のため新規起票はしない。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Added "retrospective reading guidance" to Step 5 of `/code` (after Phase Handoff read block) and Step 6 of `/spec` (before measurement-scope.md line) — these are the first natural points where the Spec is loaded, making the guidance immediately actionable.
- Used `**Retrospective writing discipline:**` named block (as specified in Spec Notes) before each template block in Step 12 and Step 13, so the rules are visually distinct from the template itself.
- Writing discipline includes 5 rules: one-entry-per-learning, record corrections AND confirmed approaches, link related entries, no-git-history-duplication, update/delete stale entries.

### Deferred Items
- Behavioral observation of whether `/auto` actually reduces duplicate/conflicting retrospective entries is a post-merge manual verification item (AC post-merge, verify-type: manual).
- No follow-up Issues created — the implementation is complete and self-contained.

### Notes for Next Phase
- All 5 pre-merge ACs verified PASS (section_contains, rubric ×4, github_check CI).
- Changes are purely additive text insertions in two SKILL.md files — no logic, no scripts, no tests modified. Low regression risk.
- The `link related entries` discipline rule is present in both additions even though the rubric did not check for it — verify should confirm the full discipline list matches the AC intent.

## Consumed Comments
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/562#issuecomment-4695351782
- saito / MEMBER / first-class / observation event `auto-run` detected. Run `/verify 562` to verify the condition / https://github.com/saitoco/wholework/issues/562#issuecomment-4756911079
- saito / MEMBER / first-class / observation event `auto-run` detected. Run `/verify 562` to verify the condition / https://github.com/saitoco/wholework/issues/562#issuecomment-4768309468
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/562#issuecomment-5195217035
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/562#issuecomment-5202635269
