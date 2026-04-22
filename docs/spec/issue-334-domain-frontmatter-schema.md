# Issue #334: Domain File Frontmatter Schema Definition and 9-File Retroactive Application (Phase 2 Sub 2A)

## Overview

Phase 2 (#293) foundation work. Define a frontmatter-driven Domain file registration schema (`type: domain`, `skill:`, `load_when:`) and apply it retroactively to the existing 9 bundled Domain files. Establishes machine-readable load condition declarations as a prerequisite for Phase 2B domain-loader extension.

## Changed Files

- `docs/environment-adaptation.md`: Add `### Domain File Frontmatter Schema` subsection to Layer 3; add `load_when` column to Domain Files table — bash 3.2+ compatible (no shell commands involved)
- `docs/ja/environment-adaptation.md`: Translation sync for Layer 3 schema and table changes
- `skills/spec/figma-design-phase.md`: add frontmatter (`type: domain`, `skill: spec`)
- `skills/spec/codebase-search.md`: add frontmatter (`type: domain`, `skill: spec`, `load_when: spec_depth: full`)
- `skills/spec/external-spec.md`: add frontmatter (`type: domain`, `skill: spec`)
- `skills/review/external-review-phase.md`: add frontmatter (`type: domain`, `skill: review`, `load_when: marker: [copilot-review, claude-code-review, coderabbit-review]`)
- `skills/review/skill-dev-recheck.md`: add frontmatter (`type: domain`, `skill: review`, `load_when: file_exists_any: [scripts/validate-skill-syntax.py]`)
- `skills/issue/spec-test-guidelines.md`: add frontmatter (`type: domain`, `skill: issue`, `load_when: file_exists_any: [scripts/validate-skill-syntax.py]`)
- `skills/issue/mcp-call-guidelines.md`: add frontmatter (`type: domain`, `skill: issue`, `load_when: capability: mcp`)
- `skills/verify/browser-verify-phase.md`: add frontmatter (`type: domain`, `skill: verify`, `load_when: capability: browser`)
- `skills/doc/translate-phase.md`: add frontmatter (`type: domain`, `skill: doc`, `load_when: arg_starts_with: translate`)

## Implementation Steps

1. Add `### Domain File Frontmatter Schema` subsection to `docs/environment-adaptation.md` Layer 3, inserted between `### Extraction Patterns` and `### Domain Files (exhaustive)`. Include: the schema YAML block (`type: domain`, `skill:`, `load_when:` with 5 typed keys from issue body), AND evaluation for multiple keys, and "unspecified keys are ignored" note. (→ acceptance criteria 1)

2. Add `load_when` column to the Domain Files table in `docs/environment-adaptation.md` Layer 3 (after step 1). Per-file values:
   - `figma-design-phase.md`: _(none — runtime-detected via ToolSearch inside file body)_
   - `codebase-search.md`: `spec_depth: full`
   - `external-spec.md`: _(none — conditional inside file body)_
   - `external-review-phase.md`: `marker: [copilot-review, claude-code-review, coderabbit-review]`
   - `skill-dev-recheck.md`: `file_exists_any: [scripts/validate-skill-syntax.py]`
   - `spec-test-guidelines.md`: `file_exists_any: [scripts/validate-skill-syntax.py]`
   - `mcp-call-guidelines.md`: `capability: mcp`
   - `browser-verify-phase.md`: `capability: browser`
   - `translate-phase.md`: `arg_starts_with: translate`
   (→ acceptance criteria 11)

3. Insert YAML frontmatter at the top of each of the 9 bundled Domain files (after step 1). Place the `---` block before all existing content. Frontmatter per file as specified in Changed Files section. (→ acceptance criteria 2–10)

4. Sync `docs/ja/environment-adaptation.md` Layer 3 section: translate and reflect the schema subsection and updated Domain Files table from steps 1–2. (after steps 1, 2)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/environment-adaptation.md documents the YAML frontmatter schema (type: domain, skill, load_when with typed keys file_exists_any, marker, capability, arg_starts_with, spec_depth) for Domain file registration" --> frontmatter スキーマが `docs/environment-adaptation.md` に記載されている
- <!-- verify: section_contains "docs/environment-adaptation.md" "### Domain File Frontmatter Schema" "type: domain" --> schema セクションに `type: domain` が含まれている
- <!-- verify: file_contains "skills/spec/figma-design-phase.md" "type: domain" --> `figma-design-phase.md` に frontmatter が追加されている
- <!-- verify: file_contains "skills/spec/codebase-search.md" "type: domain" --> `codebase-search.md` に frontmatter が追加されている
- <!-- verify: file_contains "skills/spec/external-spec.md" "type: domain" --> `external-spec.md` に frontmatter が追加されている
- <!-- verify: file_contains "skills/review/external-review-phase.md" "type: domain" --> `external-review-phase.md` に frontmatter が追加されている
- <!-- verify: file_contains "skills/review/skill-dev-recheck.md" "type: domain" --> `skill-dev-recheck.md` に frontmatter が追加されている
- <!-- verify: file_contains "skills/issue/spec-test-guidelines.md" "type: domain" --> `spec-test-guidelines.md` に frontmatter が追加されている
- <!-- verify: file_contains "skills/issue/mcp-call-guidelines.md" "type: domain" --> `mcp-call-guidelines.md` に frontmatter が追加されている
- <!-- verify: file_contains "skills/verify/browser-verify-phase.md" "type: domain" --> `browser-verify-phase.md` に frontmatter が追加されている
- <!-- verify: file_contains "skills/doc/translate-phase.md" "type: domain" --> `translate-phase.md` に frontmatter が追加されている
- <!-- verify: rubric "The Domain Files table in docs/environment-adaptation.md Layer 3 reflects the load_when values declared in each bundled Domain file's frontmatter" --> environment-adaptation.md の Domain Files 表が frontmatter 宣言と整合している
- <!-- verify: section_contains "docs/environment-adaptation.md" "### Domain Files" "spec_depth: full" --> Domain Files 表に `spec_depth: full` が記載されている

### Post-merge

- 新 frontmatter を記述した Domain file を wholework 本体で `/spec` `/review` `/issue` `/verify` `/doc` から読ませて、従来通り読み込めることを手動確認 <!-- verify-type: opportunistic -->

## Notes

**Auto-resolved decisions (non-interactive mode):**

1. **Runtime-detected Domain files (`figma-design-phase.md`, `external-spec.md`)**: These files perform detection at runtime inside the file body (Figma MCP via ToolSearch; external spec dependency via contextual judgment). No static `load_when` key exists in the schema for runtime-detected conditions. Resolution: Omit `load_when` from frontmatter; include only `type: domain` and `skill: spec`.

2. **`mcp-call-guidelines.md` load condition**: Loaded when `MCP_TOOLS` is non-empty (sourced from `capabilities.mcp` list in `.wholework.yml`). The schema's `capability: {name}` targets boolean `capabilities.{name}: true`, but `capabilities.mcp` is a list type. Resolution: Use `capability: mcp` treating it as "list is non-empty". This is a semantic extension; the distinction from boolean `true` is noted here and may be refined in a follow-up issue.

3. **`external-review-phase.md` OR marker condition**: Loaded when any of three markers is true. The schema shows `marker: {yaml_key}` (singular), but OR evaluation requires multiple values. Resolution: Use list notation `marker: [copilot-review, claude-code-review, coderabbit-review]` for OR evaluation, consistent with `file_exists_any` list semantics.

**Verification count note**: Pre-merge verification items (13) exceeds SPEC_DEPTH=light limit (5) due to 9 individual `file_contains` checks from Issue body plus 2 supplementary `section_contains` checks (added per verify-patterns.md §9 for `rubric` conditions with known target files). Verbatim Issue body items are preserved; 2 supplementary items are added and will sync to Issue body.

**Scope boundary**: This issue adds frontmatter as metadata only. `modules/domain-loader.md` and SKILL.md conditional Read instructions are unchanged. Parsing and routing by domain-loader based on this frontmatter is Phase 2B scope (#293 sub-issue 2B).
