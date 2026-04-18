---
type: project
ssot_for:
  - versioning-policy
  - release-bump-rules
  - pre-1.0-policy
---

English | [日本語](ja/versioning.md)

# Versioning Policy

This document is the SSoT for Wholework's versioning rules. Claude Code sessions should consult this before bumping `.claude-plugin/plugin.json` or tagging a release.

## Current State

- **Pre-1.0 phase.** Wholework is in active development and distributed to selected collaborators for feedback.
- **1.0.0 is reserved** for the point when the public API is declared frozen and marketing/outreach begins.
- No marketing activities until 1.0.0.

## Bump Level Rules

| Change type | Bump | Notes |
|-------------|------|-------|
| New skill, new sub-command, new flag (safe default), new file (e.g., `SECURITY.md`), new section in README/docs, new verify command type | **minor** (e.g., 0.1.0 → 0.2.0) | Additive — existing users install without modification |
| Bug fix, behavior fix that restores documented intent, typo fix, emoji-only cosmetic change | **patch** (e.g., 0.1.0 → 0.1.1) | No new capability introduced |
| Rename skill, remove sub-command, change required argument signature, change semantic of existing command, rename `phase/*` or `triaged` labels, rename `.wholework.yml` keys, move output file locations (`docs/spec/` → elsewhere), remove/change verify command types | **minor** pre-1.0 / **major** post-1.0 | Breaking — record under `### Breaking Changes` in release notes |

**Decision shortcut**: "Does an existing user need to change anything to install the new version?"
- No → patch (if fix) or minor additive
- Yes → breaking (minor pre-1.0 / major post-1.0)

## Pre-1.0 Relaxation

SemVer permits breaking changes in minor bumps during 0.x. Wholework follows this convention:

- 0.x → 0.(x+1) can include breaking changes
- **Always note breaking changes explicitly** in the release notes / tag message so the pre-1.0 → 1.0 transition has a clean audit trail

## Judging Bump Level from Closed Issues

When preparing a release, review the set of closed Issues since the last tag. Claude Code can discover and classify these automatically.

### Discovery Procedure

1. **Find the previous tag**:
   ```sh
   git describe --tags --abbrev=0
   ```

2. **List commits since that tag** (to extract `closes #N` references):
   ```sh
   git log <prev-tag>..HEAD --pretty=format:'%H %s'
   ```
   Parse `closes #N`, `fixes #N`, `(closes #N)` patterns from commit messages.

3. **List Issues closed after the tag date** (catches Issues closed outside commit messages):
   ```sh
   TAG_DATE=$(git log -1 --format=%aI <prev-tag>)
   gh issue list --state closed --search "closed:>${TAG_DATE}" --json number,title,closedAt,labels --limit 200
   ```

4. **Merge the two sources, de-duplicate**, and retrieve each Issue body for classification:
   ```sh
   gh issue view <N> --json title,body,labels
   ```

### Classification Procedure

For each discovered Issue:

1. Read the Issue title + body + `closing commit message`
2. Classify per the "Bump Level Rules" table above (Added / Changed / Fixed / Breaking)
3. Aggregate with highest-wins rule:
   - Any Breaking Issue → release is breaking (minor pre-1.0 / major post-1.0)
   - Any Additive Issue → minor
   - Only Fixes → patch

### Exclusions

Skip from the count:
- Issues closed as `not planned` or merged into another Issue (no code impact)
- Parent tracker Issues (`phase/verify` placeholder) where all work is in sub-issues (count sub-issues instead)
- Refactors/cleanup with no user-visible change → patch

### Ambiguity Handling

If any Issue cannot be classified unambiguously, Claude Code must:
1. Surface that Issue with a proposed classification and rationale
2. Ask the user to confirm before applying
3. Only proceed to tag/bump after confirmation

### Example Invocation

User: "Next release level?" or "Prepare v{next} release notes"

Claude Code response flow:
1. Run discovery commands above
2. Present a table: `| # | Title | Category | Rationale |`
3. Propose bump level with one-sentence justification
4. Ask for confirmation before running the Release Procedure below

## Known Precedents and Exceptions

| Version | Date | Actual content | Should have been | Note |
|---------|------|---------------|------------------|------|
| 0.1.1 | 2026-04-16 | Additive (SECURITY.md, Issue templates, README sections) | 0.2.0 | Judgment error; documented here for audit trail |

**Rule when correction needed**: skip the would-be next number rather than retag. Example: since 0.1.1 was really 0.2.0-equivalent, next release goes to **0.2.0** (not 0.1.2), leaving 0.1.2 as a skipped slot.

## Release Procedure

1. Determine bump level (table above or ask Claude Code with the closed Issue list)
2. Update `.claude-plugin/plugin.json` `"version"` field
3. Commit with message `chore: bump version to vX.Y.Z`
4. Push to main
5. Create annotated tag:
   ```sh
   git tag -a vX.Y.Z -m "vX.Y.Z: <summary>

   - <change 1>
   - <change 2>"
   git push origin vX.Y.Z
   ```
6. (Optional) `gh release create vX.Y.Z --notes-file ...` for a GitHub Release with richer notes

## 1.0.0 Criteria

Tag 1.0.0 **only when all of the following are true**:

- Public API (skills, sub-commands, flags, labels, config schema, file layout) is declared frozen for backward compatibility
- A consolidated CHANGELOG or release notes covering the 0.x → 1.0 journey is prepared
- Marketing / outreach readiness is in place (website, announcement plan, adoption funnel)
- Installation and upgrade path from 0.x is documented

Until these conditions are met, keep minor-bumping as 0.x — high minor numbers (0.10, 0.15, 0.20 …) are normal and healthy for projects in this phase.

If the 0.x minor number reaches a point that feels aesthetically awkward at 1.0-launch time, it is acceptable to **skip to a larger major** (e.g., 0.15 → 2.0) following precedents like React (0.14 → 15) or Node.js (0.12 → 4).

## When to Consult vs Auto-decide

- **Claude Code may auto-decide bump level** when the set of closed Issues unambiguously maps to a single category (all fixes → patch, all additive → minor)
- **Claude Code must surface uncertainty** when any Issue's category is ambiguous, asking the user before tagging
- **User decision always wins** over table interpretation
