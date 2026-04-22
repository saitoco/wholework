# Issue #335: domain-loader load_when Evaluation + bats Tests (Phase 2 Sub 2B)

## Overview

Phase 2 (#293) infrastructure work. Extends `modules/domain-loader.md` to evaluate `load_when:` frontmatter conditions when loading bundled Domain files (`skills/{skill}/*.md`). Currently domain-loader only scans project-local files (`.wholework/domains/{SKILL_NAME}/*.md`) with unconditional loading. After this change, the loader also discovers bundled Domain files and applies conditional loading based on their frontmatter.

The 5 typed `load_when:` keys (established in Sub 2A #334): `file_exists_any`, `marker`, `capability`, `arg_starts_with`, `spec_depth`. Multiple keys use AND semantics. Files without `load_when:` are loaded unconditionally for backward compatibility.

## Changed Files

- `modules/domain-loader.md` (20 lines): expand Purpose/Input, add bundled Domain file processing phase, add `load_when` evaluation section, update Output — bash 3.2+ compatible (no shell commands involved)
- `tests/domain-loader.bats` (20 lines, 3 @tests): add 5 @tests for `load_when` evaluation, typed keys, AND semantics, unconditional load, `skill:` array handling
- `docs/structure.md`: update module description line 110 — "project-local domain file discovery and loading" → "bundled and project-local Domain file discovery and conditional loading"
- `docs/environment-adaptation.md`: update Layer 3 "Project-local Domain files" paragraph (line 120) to reflect expanded domain-loader behavior (bundled files + `load_when:` evaluation)
- `docs/ja/structure.md`: translation sync for structure.md change (line 85)
- `docs/ja/environment-adaptation.md`: translation sync for environment-adaptation.md change (line 113)

## Implementation Steps

1. Update `modules/domain-loader.md`: (→ acceptance criteria 1, 2, 3, 4)
   - **Purpose**: update to "Discover and load Domain files for the calling skill from two sources: bundled Domain files (`${CLAUDE_PLUGIN_ROOT}/skills/{SKILL_NAME}/*.md`) with conditional loading, and project-local Domain files (`.wholework/domains/{SKILL_NAME}/*.md`) with unconditional loading."
   - **Input**: add "Context variables available from calling skill: `SPEC_DEPTH`, `ARGUMENTS`; `marker:` and `capability:` conditions are evaluated by reading `.wholework.yml` directly if needed"
   - **Processing Steps**: restructure into two phases:
     - Phase 1 (bundled): Glob `${CLAUDE_PLUGIN_ROOT}/skills/{SKILL_NAME}/*.md`; for each file: Read it; skip if `type: domain` absent from frontmatter; if `skill:` is array, skip if SKILL_NAME not in array; if `load_when:` present, evaluate all typed keys with AND semantics and load only when all evaluate to true; if `load_when:` absent, load unconditionally (backward compatible)
     - Phase 2 (project-local): existing Glob `.wholework/domains/{SKILL_NAME}/*.md` + unconditional Read logic
   - **New `## load_when Evaluation` subsection**: table with 5 typed keys and their evaluation logic:
     - `spec_depth: {level}` → true if SPEC_DEPTH equals level
     - `capability: {name}` → true if `capabilities.{name}: true` in `.wholework.yml`; for `capability: mcp`, true if `capabilities.mcp` list is non-empty
     - `file_exists_any: [path1, path2]` → true if any listed path exists (OR within key; Glob check)
     - `marker: {key}` or `marker: [key1, key2]` → true if any listed key is `true` in `.wholework.yml` (OR within key)
     - `arg_starts_with: {prefix}` → true if ARGUMENTS starts with prefix
     - AND semantics note: all specified keys must evaluate to true; unspecified keys are ignored
   - **`skill:` field note**: when `skill:` is an array (e.g., `skill: [spec, issue]`), match if SKILL_NAME appears in the array
   - **Output**: update summary format to reflect bundled + project-local count

2. Add tests to `tests/domain-loader.bats` (after step 1): (→ acceptance criteria 6)
   - `@test "domain-loader: load_when evaluation is documented"` — `grep -q "load_when"` on domain-loader.md
   - `@test "domain-loader: all typed keys are documented"` — grep for `file_exists_any`, `marker`, `capability`, `arg_starts_with`, `spec_depth`
   - `@test "domain-loader: AND semantics is documented"` — grep for `AND`
   - `@test "domain-loader: unconditional load for files without frontmatter is documented"` — grep for `unconditional`
   - `@test "domain-loader: skill field array handling is documented"` — grep for `array`

3. Update `docs/structure.md` line 110: change "project-local domain file discovery and loading" to "bundled and project-local Domain file discovery and conditional loading" (after step 1) (→ doc sync)

4. Update `docs/environment-adaptation.md` Layer 3 paragraph at line 120 (after step 1): replace the "Project-local Domain files" description to reflect that domain-loader now handles both bundled Domain files (with `load_when:` evaluation) and project-local files (unconditional). Retain the explanation that project-local files are loaded unconditionally when present. (→ doc sync)

5. Translation sync (after steps 3, 4): update `docs/ja/structure.md` (line 85) and `docs/ja/environment-adaptation.md` (line 113) to reflect the English source changes from steps 3-4.

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/domain-loader.md" "load_when" --> domain-loader に load_when 評価ロジックが記載されている
- <!-- verify: rubric "modules/domain-loader.md supports evaluating load_when with typed keys (file_exists_any, marker, capability, arg_starts_with, spec_depth) with AND semantics across multiple keys" --> load_when の定型キー評価（複数キー AND）が loader に実装されている
- <!-- verify: rubric "modules/domain-loader.md retains backward-compatible unconditional load for Domain files without frontmatter" --> frontmatter 無し Domain file の後方互換（無条件 load）が維持されている
- <!-- verify: rubric "modules/domain-loader.md handles skill field as string or array (multi-skill shared Domain)" --> `skill:` の単一値/配列両対応が記載されている
- <!-- verify: file_exists "tests/domain-loader.bats" --> domain-loader の bats テストが存在する
- <!-- verify: rubric "tests/domain-loader.bats adds assertions for frontmatter load_when evaluation and backward-compatible unconditional load" --> 新スキーマに関する回帰テストが追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストが CI で成功する

### Post-merge

- 非 skill-dev プロジェクトで frontmatter 付き skill-dev 向け Domain file が load されないことを手動確認 <!-- verify-type: manual -->

## Notes

**Verification count note**: Pre-merge verification items (7) exceeds SPEC_DEPTH=light limit (5). All 7 are verbatim copies from Issue body acceptance criteria, so they are preserved as-is. Follows Issue #334 precedent.

**Double-loading during transition**: After Sub 2B, bundled Domain files for `/spec` are loaded twice: once by domain-loader (Phase 1) and once by inline "if X then Read Y" logic in spec/SKILL.md. This is a transitional state; Sub 2C/2D/2F/2G will remove the inline logic from SKILL.md files.

**review/SKILL.md ordering**: domain-loader is called in Step 3 of review/SKILL.md, before detect-config-markers runs in Step 7. To avoid this dependency, domain-loader reads `.wholework.yml` directly for `marker:` and `capability:` evaluations rather than relying on already-fetched HAS_* variables. This makes domain-loader self-sufficient.

**doc files without `type: domain`**: `skills/doc/*.md` includes template files (product-template.md, tech-template.md, structure-template.md) without `type: domain` frontmatter. These are skipped by the `type: domain` check in Phase 1, preventing unintended loading.

**`skill:` array handling for current files**: All 9 bundled Domain files use `skill: <string>` (single value). Array form (`skill: [a, b]`) is documented for future shared Domain files.

**`capability: mcp` semantic extension** (from #334 Notes): `capability: mcp` uses list-non-empty semantics instead of boolean `true` check. domain-loader evaluates this by checking `capabilities.mcp` list length, consistent with how detect-config-markers sets `MCP_TOOLS`.
