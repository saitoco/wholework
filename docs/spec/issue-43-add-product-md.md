# Issue #43: docs: Migrate steering document product.md

## Overview

Wholework has `docs/tech.md` as a Steering Document but no `docs/product.md`. Skills like `/issue` and `/spec` are designed to reference `docs/product.md` for Vision alignment, Non-Goals checks, and terminology consistency, but currently skip this step because the file is absent.

Port `docs/product.md` from the claude-config repository to Wholework, rewriting it for the public Skills project context. Remove all claude-config-specific content (personal config repo assumptions, direct references to "claude-config") and rewrite with Wholework as the subject.

## Changed Files

- `docs/product.md`: new file — Wholework Steering Document (Vision, Non-Goals, Target Users, Competitors, Future Direction, Terms)
- `docs/structure.md`: add `product.md` entry to the Directory Layout `docs/` section

## Implementation Steps

1. Create `docs/product.md` with frontmatter (`type: steering`, `ssot_for: [vision, non-goals, terminology]`) and the following sections, porting from `~/src/claude-config/docs/product.md` and rewriting with Wholework as the subject throughout:
   - `## Vision` — rewrite as a public Skills distribution project (remove personal config repo framing)
   - `## Target Users` — generalize to "developers who use Claude Code regularly" (remove "individual repository owner" framing)
   - `## Non-Goals` — remove "personal config repository" item; keep project-relevant constraints
   - `## Required Dependencies` — retain as-is (already Wholework-centric)
   - `## Future Direction` — remove "Skills repository split/distribution" item (already realized); update remaining items with Wholework as subject
   - `## Competitors / Alternatives` — retain tables as-is; update differentiation summary subject from "claude-config" to "Wholework"
   - `## Terms` — translate from Japanese to English; retain structure (public terms + internal terms tables)
   - Language: English throughout (per CLAUDE.md documentation convention)
   - Remove all occurrences of "claude-config" and "個人用設定リポジトリ" (→ acceptance criteria 10, 11)
   (→ acceptance criteria 1–11)

2. Update `docs/structure.md` Directory Layout section: add `│   ├── product.md       # Project vision, non-goals, terminology (steering)` line after `tech.md` entry
   (→ acceptance criteria: documentation consistency)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/product.md" --> `docs/product.md` is created
- <!-- verify: grep "type: steering" "docs/product.md" --> frontmatter contains `type: steering`
- <!-- verify: grep "ssot_for" "docs/product.md" --> frontmatter contains `ssot_for`
- <!-- verify: section_contains "docs/product.md" "## Vision" "Skills" --> Vision section is rewritten for Wholework as a public Skills project
- <!-- verify: grep "## Non-Goals" "docs/product.md" --> Non-Goals section exists
- <!-- verify: grep "## Terms" "docs/product.md" --> Terms section exists
- <!-- verify: grep "## Target Users" "docs/product.md" --> Target Users section exists
- <!-- verify: grep "## Competitors" "docs/product.md" --> Competitors / Alternatives section exists
- <!-- verify: grep "## Future Direction" "docs/product.md" --> Future Direction section exists
- <!-- verify: file_not_contains "docs/product.md" "個人用設定リポジトリ" --> claude-config-specific "個人用設定リポジトリ" text is removed
- <!-- verify: file_not_contains "docs/product.md" "claude-config" --> direct references to claude-config are removed

### Post-merge

- When running `/issue`, `docs/product.md` is referenced and Vision alignment check works

## Notes

- Competitors section data is ported as-is from claude-config; only the differentiation summary subject changes from "claude-config" to "Wholework"
- Future Direction: "Skills repository split/distribution" item should be removed or marked as completed (already realized as the current public repo distribution)
- Target Users: remove "リポジトリオーナー個人" (individual repo owner) framing; generalize to developers using Claude Code regularly
- `docs/structure.md` currently lists only `tech.md` with `(steering)` annotation; `product.md` should be added consistently
