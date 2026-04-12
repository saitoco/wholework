# Issue #122: Project-Local Domain File Loading

## Overview

Add a project-local Domain file loading mechanism to spec/code/review skills. Users place `.md` files in `.wholework/domains/{skill}/` and the skill automatically discovers and reads them at startup via Glob scan. This enables domain-specific behavior customization without modifying wholework itself.

Design decisions (from Issue #122):
- **Path convention**: `.wholework/domains/{skill}/{file}.md`
- **Detection**: Directory scan (Glob at skill start)
- **Target skills**: spec / code / review
- **No capability linkage**: File presence alone triggers loading
- **User-global path**: Out of scope (future extension)

## Changed Files

- `modules/domain-loader.md`: new shared module for project-local domain file discovery and loading
- `skills/spec/SKILL.md`: add domain loading instruction (within Step 5, after steering document references)
- `skills/code/SKILL.md`: add domain loading instruction (after setup steps, before main processing)
- `skills/review/SKILL.md`: add domain loading instruction (after review mode detection, before review execution)
- `docs/environment-adaptation.md`: update Layer 3 (Extraction Patterns table, Domain Files table, description)
- `docs/structure.md`: add `.wholework/` directory convention to Directory Layout, add `domain-loader.md` to Modules list

## Implementation Steps

1. Create `modules/domain-loader.md` (→ acceptance criteria A, B, C)

   New shared module following the standard 4-section structure (Purpose/Input/Processing Steps/Output):

   **Purpose**: Discover and load project-local Domain files from `.wholework/domains/{skill}/`.

   **Input**: `SKILL_NAME` (one of: `spec`, `code`, `review`) — passed by the calling skill.

   **Processing Steps**:
   1. Glob for `.wholework/domains/{SKILL_NAME}/*.md`
   2. If no files found: output nothing and return (silent skip)
   3. For each discovered file (alphabetical order): Read the file. The content becomes part of the skill's execution context, influencing subsequent steps.
   4. Output a summary line: "Loaded N project-local domain file(s) from .wholework/domains/{SKILL_NAME}/"

   **Output**: Domain file contents loaded into the skill's context. Summary line for traceability.

2. Add domain loading to `skills/spec/SKILL.md` (after Step 5) (→ acceptance criteria D)

   Insert within Step 5 (Reference Steering Documents) as an additional sub-section:

   ```markdown
   **Project-local Domain files (if present):**

   Read `${CLAUDE_PLUGIN_ROOT}/modules/domain-loader.md` and follow the "Processing Steps" section with `SKILL_NAME=spec`. Domain file content supplements steering documents as additional context for codebase investigation and design.
   ```

   Position: at the end of Step 5, after the steering document reading instructions. No step renumbering needed.

3. Add domain loading to `skills/code/SKILL.md` (→ acceptance criteria E)

   Insert at the appropriate position after setup steps (Worktree Entry, Spec loading) as an additional sub-section within the step that loads context:

   ```markdown
   **Project-local Domain files (if present):**

   Read `${CLAUDE_PLUGIN_ROOT}/modules/domain-loader.md` and follow the "Processing Steps" section with `SKILL_NAME=code`. Domain file content provides additional implementation guidelines and constraints.
   ```

   No step renumbering needed.

4. Add domain loading to `skills/review/SKILL.md` (→ acceptance criteria F)

   Insert after Step 3 (Review Mode Detection) as an additional sub-section:

   ```markdown
   **Project-local Domain files (if present):**

   Read `${CLAUDE_PLUGIN_ROOT}/modules/domain-loader.md` and follow the "Processing Steps" section with `SKILL_NAME=review`. Domain file content provides additional review perspectives and domain-specific checks.
   ```

   No step renumbering needed.

5. Update `docs/environment-adaptation.md` Layer 3 (→ acceptance criteria A, B, C)

   5a. Add "Directory scan" row to the Extraction Patterns table:

   | Pattern | Condition Check | Example |
   |---------|----------------|---------|
   | Directory scan | `.wholework/domains/{skill}/` Glob | Project-local domain files (loaded when files exist) |

   5b. Add project-local entry to the Domain Files table. Add a row with:
   - File: `.wholework/domains/{skill}/*.md`
   - Skill: `/spec`, `/code`, `/review`
   - Load Condition: directory scan (files exist in `.wholework/domains/{skill}/`)
   - Domain: project-local (user-defined)

   5c. Add descriptive paragraph about project-local Domain files after the Domain Files table, explaining the directory scan mechanism and the `.wholework/domains/` convention.

6. Update `docs/structure.md` (→ acceptance criteria G)

   6a. Add `.wholework/` to the Directory Layout tree:

   ```
   ├── .wholework/          # Project-local Wholework configuration (user-managed, not tracked in wholework repo)
   │   ├── adapters/        # Verification adapter overrides
   │   └── domains/         # Project-local Domain files
   │       ├── spec/        # Domain files for /spec
   │       ├── code/        # Domain files for /code
   │       └── review/      # Domain files for /review
   ```

   6b. Add `modules/domain-loader.md` to the Modules list:
   - `modules/domain-loader.md` — project-local domain file discovery and loading

7. Run syntax validation (→ acceptance criteria H)

   ```bash
   python3 scripts/validate-skill-syntax.py skills/
   ```

## Alternatives Considered

**Inline domain loading in each SKILL.md (no shared module)**: Each SKILL.md would directly contain the Glob + Read logic. Rejected because: violates DRY principle, three copies of the same logic would drift over time, and the shared module pattern is established in the codebase.

**Capability-linked loading**: Only load domain files when a matching `HAS_{NAME}_CAPABILITY` is true. Rejected in Issue #122 refinement because: requires double configuration (file + .wholework.yml), contradicts "just drop a file" UX goal, and capability declarations serve a different purpose (adapter/verify command routing).

**User-global resolution (~/.wholework/domains/)**: Add a 2-layer resolution (project-local → user-global) similar to adapter-resolver. Deferred as future extension because: the primary use case is project-specific domain logic, not cross-project shared logic. Can be added to `domain-loader.md` later without breaking changes.

## Verification

### Pre-merge

- <!-- verify: section_contains "docs/environment-adaptation.md" "## Layer 3" ".wholework/domains" --> Layer 3 section documents `.wholework/domains/{skill}/` loading specification
- <!-- verify: section_contains "docs/environment-adaptation.md" "### Extraction Patterns" ".wholework" --> Extraction Patterns table includes directory scan pattern
- <!-- verify: section_contains "docs/environment-adaptation.md" "### Domain Files" "project-local" --> Domain Files table includes project-local entries
- <!-- verify: file_contains "docs/structure.md" ".wholework/" --> structure.md documents `.wholework/` directory convention
- <!-- verify: grep "[Dd]omain" "skills/spec/SKILL.md" --> /spec SKILL.md has project-local Domain file loading step
- <!-- verify: grep "[Dd]omain" "skills/code/SKILL.md" --> /code SKILL.md has project-local Domain file loading step
- <!-- verify: grep "[Dd]omain" "skills/review/SKILL.md" --> /review SKILL.md has project-local Domain file loading step
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> All SKILL.md files pass syntax validation

### Post-merge

- Create a test domain file at `.wholework/domains/spec/test.md`, run `/spec`, and confirm the domain file content influences spec execution (verify-type: opportunistic)

## Notes

- **No step renumbering**: Domain loading is added as sub-sections within existing steps, not as new top-level steps. This avoids cascading renumbering of step references across the codebase.
- **Silent skip on no files**: When `.wholework/domains/{skill}/` does not exist or is empty, the module returns silently without warnings. This matches the existing pattern where steering documents are silently skipped when absent.
- **Auto-resolved ambiguity**: Loading order is alphabetical (Glob output order). No priority mechanism. If ordering matters, users can prefix filenames (e.g., `01-base.md`, `02-api.md`).
- **`docs/ja/environment-adaptation.md`**: Japanese mirror file exists but is generated by `/doc translate ja` and is not an implementation target.

## Issue Retrospective

### Ambiguity Resolution

5 ambiguity points detected; 2 resolved via user confirmation, 3 auto-resolved:

**User-confirmed:**
1. **Path convention**: `.wholework/domains/{skill}/` selected. Symmetric with `.wholework/adapters/`. `.wholework/phases/` rejected due to concept collision with phase labels.
2. **Detection mechanism**: Directory scan selected. Prioritizes "just drop a file" UX. Capability linkage rejected because it requires double configuration.

**Auto-resolved:**
3. Loading timing: Glob scan at skill start
4. Target skills: spec/code/review
5. File format: Markdown

### Key Decisions

- Needs Refinement fully resolved: path convention and loading timing both decided.
- Capability linkage not required: dynamic capabilities (#121) and domain file loading operate independently.

## Spec Retrospective

### Minor observations
- The "no step renumbering" approach (adding domain loading as sub-sections within existing steps) keeps the change footprint small but means the domain loading instruction is embedded within a step with a different primary purpose. If domain loading becomes more complex in the future, extracting it to a dedicated step would be cleaner.

### Judgment rationale
- Chose shared module (`domain-loader.md`) over inline implementation to follow the established shared module pattern and avoid DRY violations.
- Positioned domain loading within existing setup/context steps rather than as new top-level steps to avoid cascading renumbering of 15+ step references.

### Uncertainty resolution
- Nothing to note. The Glob + Read mechanism is well-understood and has no external dependencies.

## Code Retrospective

### Deviations from Design
- N/A. Implementation followed the Spec's 7 steps exactly as designed.

### Design Gaps/Ambiguities
- The module count in `docs/structure.md` (24 files) needed updating to 25 after adding `domain-loader.md`. This was not listed in the Spec's changed files or implementation steps but was caught by the documentation consistency check.

### Rework
- N/A. No rework was needed.

## Review Retrospective

### Spec vs. implementation divergence patterns
- 構造的な乖離なし。実装は Spec の Implementation Steps 1〜7 をそのまま忠実に反映。Code Retrospective に記録された module count 更新 (24→25) も期待通り反映済みで、Spec の "Changed Files" リストから漏れていた点は Code 段階で適切に検知・補正された。

### Recurring issues
- Nothing to note. Review で検出した3件はすべて CONSIDER レベルで、かつ観点も独立（tree 配置／入力バリデーション／優先順位）しており、workflow 改善に繋がる反復パターンは見られない。

### Acceptance criteria verification difficulty
- 8件の Pre-merge 条件すべてが静的検証（`section_contains` / `file_contains` / `grep` / `command`）で PASS 判定可能な設計になっており、UNCERTAIN は発生しなかった。`command "python3 scripts/validate-skill-syntax.py skills/"` は safe モードでは UNCERTAIN になるが、CI 参照フォールバックで PASS を確定できた。verify コマンドの精度は良好。
- 改善提案: `modules/domain-loader.md` の新規追加に対する検証条件が明示的に含まれていなかった（Layer 3 テーブルや structure.md の Modules list 経由で間接的にカバー）。新規モジュール追加時の acceptance criteria テンプレートに「当該モジュールファイルが存在すること」のチェックを含めると、より直接的な検証になる。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件 8 件すべてが静的検証系コマンド（`section_contains` / `file_contains` / `grep` / `command`）に落とし込まれており、verify で UNCERTAIN 発生なく全件 PASS 判定できた。条件粒度と verify コマンドのマッピングは適切。

#### design
- 設計は Implementation Steps 1〜7 で段階分解されており、verify 時の条件とほぼ 1 対 1 で対応していた。ただし、新規追加モジュール `modules/domain-loader.md` 自体の存在確認条件が Issue 側になく、Layer 3 テーブルや structure.md の Modules list 経由での間接カバーに留まっている点は review 段階でも指摘済み。

#### code
- 実装は Spec 通り忠実に反映。Code Retrospective にあった module count (24→25) 更新も verify 時点では整合が取れており、追加後 regression なし。

#### review
- Review で検出した 3 件は CONSIDER レベルで、FAIL に繋がる致命的な見落としはなかった。verify 全件 PASS で結果的に review の判断も妥当だった。

#### merge
- Squash merge（PR #128 → main: commit `ae95231`）は正常完了。conflict 解決痕跡なし。

#### verify
- 全 8 件 Pre-merge 条件が PASS。FAIL / UNCERTAIN ともにゼロ。verify コマンドの翻訳・実行フローに不整合なし。Post-merge opportunistic 1 件はユーザー検証項目として適切にガイドを提示。

### Improvement Proposals
- N/A
