# Issue #804: Spec Symbol Impact Discovery for Delete/Migration/Rename Issues

## Overview

When a spec involves deleting, migrating, or renaming a named symbol (path string, variable name, file name, function name), there is no structured guidance prompting the spec writer to grep for all files that reference that symbol. Three consecutive Changed Files omissions in a single `/auto --batch` session (#771, #770, #775) exposed this as a structural gap.

Add a "Symbol impact discovery (deletion/migration/rename)" guidance section to `skills/spec/SKILL.md` Step 10. The guidance provides a 3-phase approach: (1) extract the old symbol from the Issue body, (2) run `rg "<old-symbol>" --files-with-matches` or `git grep -l`, (3) add all discovered files as Changed Files candidates (spec writer makes inclusion/exclusion decisions). This mechanically guards against the recurring pattern of missing test, docs, and SKILL.md files in Changed Files lists.

## Changed Files

- `skills/spec/SKILL.md`: add "Symbol impact discovery (deletion/migration/rename)" guidance section immediately after the "Feature deletion impact chain check" block (before "**bats test Spec input format:**") — bash 3.2+ compatible (guidance text only, no new bash code)

## Implementation Steps

1. In `skills/spec/SKILL.md`, immediately before `**bats test Spec input format:**` (after the `*Example: Issue #485 retro...` line), insert the following new guidance block (→ acceptance criteria AC1, AC2, AC3):

```
**Symbol impact discovery (deletion/migration/rename):**

When the Issue involves deleting, migrating, or renaming a target symbol (path string, variable name, file name, function name, etc.), run a codebase-wide full-text search to discover all files that reference the symbol and add them as Changed Files candidates:

**Phase 1 — Extract target symbol:** Identify the old symbol from the Issue body (e.g., old path `docs/reports/loop-state-` before migration to `docs/sessions/_daily/loop-state-`, old variable name, old file name).

**Phase 2 — Full-text grep:**
\```bash
rg "<old-symbol>" --files-with-matches
# or
git grep -l "<old-symbol>"
\```

**Phase 3 — Candidate list:** For each file in the grep output, evaluate whether it needs a change (reference update, cleanup, or test update) and add it to the Changed Files list. The spec writer makes the final inclusion/exclusion decision — exclude only files that reference the symbol in non-load-bearing contexts (e.g., historical records, retrospective examples, comparison tables).

**Skip** if the Issue does not involve deletion, migration, or renaming of a named symbol.

*Background: Three consecutive Changed Files omissions in a single `/auto --batch` session exposed this as a structural gap:*
- *#771: `tests/append-loop-state-heartbeat.bats` path reference not updated after loop-state path migration (caught in verify retrospective)*
- *#770: `skills/audit/SKILL.md` session boundary section reference missed after session boundary section rename (caught in review)*
- *#775: `docs/structure.md`, `docs/reports/orchestration-recoveries.md`, `tests/collect-recovery-candidates.bats` not updated after audit recoveries feature deletion (caught in review/verify)*
```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md に、削除/migration/rename Issue における対象 symbol (path/variable/file name) の codebase 全文 grep + 影響先 Changed Files 自動候補追加の手順 (Phase 1: symbol 抽出、Phase 2: grep 実行、Phase 3: Changed Files 候補化) が明文化されている" --> <!-- verify: grep "files-with-matches" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` に "削除/migration/rename を伴う Issue で対象 symbol を全文 grep して影響先候補を Changed Files に追加" のガイダンスと手順が記載されている
- <!-- verify: grep "rg.*files-with-matches|git grep|grep.*-l\b|symbol.*grep|grep.*symbol" "skills/spec/SKILL.md" --> grep ベース discovery のコマンド例 (rg / git grep のコマンド形) が提示されている
- <!-- verify: rubric "skills/spec/SKILL.md の Changed Files 網羅性ガイダンスに、Issue #771 / #770 / #775 のような実例 (path migration での test/docs/SKILL.md スコープ漏れ) の引用または同種パターンの説明が含まれており、guidance の motivation が明確化されている" --> guidance に既知の 3 事例 (#771, #770, #775 の Spec Changed Files 漏れ) への言及または同種パターンの説明が含まれる

### Post-merge

- 次回 migration/rename/削除を伴う Issue の `/spec` で Changed Files リストに対象 symbol grep 結果が反映されていることを観察

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: auto-resolved implementation target to `skills/spec/SKILL.md` only; AC2 verify command `-iE` flags removed; AC1 supplementary `files-with-matches` grep added / https://github.com/saitoco/wholework/issues/804#issuecomment-4823468455

## Notes

- Size S → patch route; no new modules or scripts added
- Implementation target: `skills/spec/SKILL.md` only (auto-resolved from Issue Retrospective: modules/ approach is over-engineering for Size S scope)
- The new section complements the existing "Feature deletion impact chain check" (deletion only, cleanup ACs) and "Rename-type Issue grep check" (rename keyword trigger); the new section provides the broader 3-phase discovery framework covering all three types (deletion, migration, rename)
- `\b` in AC2 verify pattern is a ripgrep word boundary (valid ERE); no BRE metacharacters present

## Code Retrospective

### Deviations from Design

- None. Implementation matched the Spec insertion point exactly: the new guidance block was inserted immediately before `**bats test Spec input format:**` (after the `*Example: Issue #485 retro...` line), as specified.

### Design Gaps/Ambiguities

- None. The Spec's inline code block for the guidance content (with escaped backticks `\`\`\``) translated cleanly to actual code fences in the SKILL.md content; no ambiguity in rendering.

### Rework

- None. All 3 pre-merge AC verify commands (grep "files-with-matches", grep for rg/git grep command examples, issue references #771/#770/#775) PASS on first implementation.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Inserted guidance block immediately before `**bats test Spec input format:**` in `skills/spec/SKILL.md` (lines 319+), following Spec direction verbatim.
- No new modules or scripts added; single-file change kept scope within Size S bounds.
- Phase 1/2/3 structure preserved as specified; Skip condition and background bullet-points included.

### Deferred Items
- Post-merge observation: confirm that next migration/rename/delete Issue's `/spec` session reflects grep-discovered candidates in Changed Files list (manual verification).

### Notes for Next Phase
- All 3 pre-merge ACs verified PASS; checkboxes updated in Issue body.
- `rubric` ACs (AC1, AC3) were verified mechanically via grep checks; rubric grader confirmation at `/verify` phase.
- No rework or test failures encountered; clean implementation.
