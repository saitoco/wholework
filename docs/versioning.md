---
type: project
ssot_for:
  - versioning-policy
  - release-bump-rules
  - pre-1.0-policy
---

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

When preparing a release, review the set of closed Issues since the last tag. For each Issue, classify:

1. Read the Issue title + closing commit + body
2. Classify per the table above
3. Aggregate: the highest classification wins
   - If any issue is breaking → treat the release as breaking (minor pre-1.0)
   - Else if any issue is additive → minor
   - Else (all fixes only) → patch

**Ask Claude Code**: "Since v{prev}, here are the closed Issues: #N, #M, ... What bump level?" — the AI should apply this table and return a single bump level with rationale per Issue.

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
