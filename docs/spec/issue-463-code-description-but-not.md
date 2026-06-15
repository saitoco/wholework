# Issue #463: code: Clarify Description to Prevent Skill Selection Confusion

## Overview

`run-code.sh` が `claude -p "/code N"` で `wholework:code` を起動する場面で、Claude のスキル選択が `claude-md-management:revise-claude-md` に誤 dispatch される事例が発生。`wholework:code` の frontmatter `description` フィールドに、CLAUDE.md 更新・session 振り返り・memory management を行わないことを明示する but-not 記述を追加し、スキル選択の区別を明確化する。

（#520 で headless 経路の guard text 対策は完了済み。本 Issue は description レベルの defense-in-depth を担う。）

## Reproduction Steps

1. `run-code.sh N` で `/code N` を起動する
2. Claude のスキル選択が `wholework:code` ではなく `claude-md-management:revise-claude-md` に dispatch される
3. コミットなしで exit 0 が返り、後段 phase（/review 等）が進めない anomaly が発生する

## Root Cause

`wholework:code` の description に「CLAUDE.md 更新・session 振り返り・memory management を行わない」旨の but-not 表現がなく、`claude-md-management:revise-claude-md` との選択判断が曖昧になっている。description に but-not 記述を追加することで、Claude のスキル選択ロジックが両者を明確に区別できるようにする。

## Changed Files

- `skills/code/SKILL.md`: frontmatter `description` フィールドの末尾に、CLAUDE.md 更新・session 振り返り・memory management を行わないことを示す but-not 表現を追加

## Implementation Steps

1. `skills/code/SKILL.md` frontmatter の `description` フィールドを更新する。既存の記述末尾に、CLAUDE.md 更新・session 振り返り・memory management を行わないことを示す but-not 表現を追加する（→ AC1）

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md の frontmatter description field に、CLAUDE.md 更新・session 振り返り・memory management を行わないことを示す but-not 表現が追加されており、wholework:code と claude-md-management:revise-claude-md のスキル選択上の区別が明確になっている" --> `wholework:code` の description に but-not 記述が追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) の全ジョブが pass する

### Post-merge

なし

## Notes

- `claude-md-management:revise-claude-md` は外部 plugin のためスコープ外
- #520 の headless 経路 guard text 対策（CLOSED）と本 Issue は補完関係にある
- SKILL.md frontmatter の `description` フィールドは Claude Code のスキル選択ロジックが参照するメタデータ

## Code Retrospective

### Deviations from Design
- Spec file title contained a deprecated term (旧称: Dispatch) that is now forbidden. The implementation step fixed this by renaming the title from "Prevent Skill Dispatch Confusion" to "Prevent Skill Selection Confusion". This fix was discovered during the forbidden expressions check and was not in the original implementation plan.

### Design Gaps/Ambiguities
- None

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Added "Does not update CLAUDE.md, run session retrospectives, or manage memory." to the `description` field in `skills/code/SKILL.md` frontmatter; this is the minimal but-not clause that disambiguates from `claude-md-management:revise-claude-md`
- Fixed Spec file title to remove the deprecated term ("旧称: Dispatch" → "Selection"); this was discovered during the forbidden expressions check and is a required change to pass CI
- Patch route was used (XS size) with direct commit to main

### Deferred Items
- `claude-md-management:revise-claude-md` description update is out of scope (external plugin)
- CI verification (test.yml pass) will be confirmed after push to main

### Notes for Next Phase
- The only file changed is `skills/code/SKILL.md` (one line in frontmatter) plus the Spec title fix — review scope is very small
- The rubric AC1 was PASS (verified by grader); AC2 (CI) is UNCERTAIN until CI runs after push
