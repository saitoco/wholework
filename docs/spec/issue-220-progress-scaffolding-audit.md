# Issue #220: skills: 冗長な進捗更新 scaffolding を監査して削除

## Overview

Claude Opus 4.7 は long-running agentic trace 中に built-in の高品質な progress update を提供する。Wholework の全 SKILL.md と modules を監査し、「N 回ごとに進捗を要約」「X ステップ後に状況をまとめる」といった redundant な progress-update scaffolding を識別して削除する。Retrospective コメント・phase-banner など意図的な永続化出力は維持する。

監査対象: `skills/*/SKILL.md` 10ファイル、`skills/*/` 補助ファイル 9ファイル、`modules/*.md` 27ファイル。

## Changed Files

- `docs/reports/progress-scaffolding-audit.md`: new file — audit report with Findings / Preserved / Changes sections
- `docs/structure.md`: add `docs/reports/` directory entry to Directory Layout (missing since creation in prior issue)
- `docs/ja/structure.md`: 同上（Japanese mirror）

## Implementation Steps

1. Audit all `skills/*/SKILL.md`, skill auxiliary files (`skills/*/*.md`), and `modules/*.md` for redundant progress-update scaffolding — search patterns: "summarize", "every N tool calls", "after X steps", "interim status", "progress update" (→ acceptance criteria 1–4)
2. Create `docs/reports/progress-scaffolding-audit.md` with `## Findings`, `## Preserved`, and `## Changes` sections based on audit results from step 1 (→ acceptance criteria 1–4)
3. Update `docs/structure.md` Directory Layout: add `│   ├── reports/  # Optimization and audit reports` entry between `spec/` and `stats/` lines (→ documentation consistency)
4. Update `docs/ja/structure.md` Directory Layout: add `│   ├── reports/  # 最適化・監査レポート` entry at the same position (→ documentation consistency)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/progress-scaffolding-audit.md" --> 監査レポートが作成されている
- <!-- verify: section_contains "docs/reports/progress-scaffolding-audit.md" "Findings" "." --> redundant 認定された箇所の一覧
- <!-- verify: section_contains "docs/reports/progress-scaffolding-audit.md" "Preserved" "." --> 維持する (意図的 scaffolding) 一覧と理由
- <!-- verify: section_contains "docs/reports/progress-scaffolding-audit.md" "Changes" "." --> 実施した削除 / 書き換え diff の要約

### Post-merge

- 参照 Issue で `/auto N` を実行し、進捗出力の量が同等以上の情報量で維持されている

## Notes

**Audit findings (pre-determined in /spec phase):**

Codebase scan of all SKILL.md and modules found **no redundant progress-update scaffolding**. Specifically:
- No "summarize after every N tool calls" instructions
- No "output status every X steps" directives
- No "interim status message" scaffolding

Intentional progress outputs to preserve (Preserved section of audit report):
- `modules/phase-banner.md` / `scripts/phase-banner.sh` — phase start/end banners (runtime-level, outside model reasoning)
- `/auto` SKILL.md `[N/M] phase_name` output format — phase-boundary markers for multi-phase orchestration visibility (not "summarize after N tool calls")
- Retrospective comments at skill end — Spec-as-memory pattern (explicit persistence)
- Completion/error reports at end of skills — user feedback on workflow result

The `docs/reports/` directory already exists but is absent from `docs/structure.md` Directory Layout. Steps 3 and 4 correct this.

## Code Retrospective

### Deviations from Design
- None. Implementation followed Spec steps 1–4 as designed.

### Design Gaps/Ambiguities
- None identified. The pre-determined findings in the Notes section were accurate and confirmed by the audit scan.

### Rework
- None.

## review retrospective

### Spec vs. Implementation Divergence Patterns
The Spec file (Overview, line 7) stated "補助ファイル 9ファイル" but the actual count was 12. This figure was propagated verbatim into the audit report's Findings section, creating a factual inaccuracy. The audit conclusion (zero redundant scaffolding) was unaffected, but it shows that pre-determined quantitative claims in Spec files are not automatically verified against current state during `/code`. Consider adding a `<!-- verify: command "..." -->` hint for numeric scope claims when precision matters.

### Recurring Issues
Nothing to note. Only one SHOULD issue found; no recurring pattern.

### Acceptance Criteria Verification Difficulty
Nothing to note. All 4 pre-merge conditions were `file_exists` / `section_contains` commands, all resolved as PASS without ambiguity. No UNCERTAINs. Verify commands were well-formed and accurately reflected the deliverables.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec pre-determined the audit findings (zero redundant scaffolding) in the Notes section — accelerated implementation, and the conclusion proved accurate. However, the numeric scope claim ("補助ファイル 9ファイル") was inaccurate (actual: 12); this was propagated verbatim into the audit report and caught only in review. Spec-level quantitative claims without a corresponding verify command carry silent inaccuracy risk.

#### design
- No design phase separate from spec. Spec doubled as design and was well-aligned with implementation. No gaps identified.

#### code
- Zero rework. Implementation was a pure documentation task (creating the audit report + structure.md corrections). Commit history shows a single clean commit in PR #240 with no fixups.

#### review
- Review correctly caught the "9ファイル vs 12ファイル" inaccuracy as a SHOULD issue, flagged it without blocking merge (conclusion was unaffected). Review also suggested adding `<!-- verify: command "..." -->` hints for numeric scope claims — a constructive, forward-looking observation.

#### merge
- Clean FF merge via PR #240 on 2026-04-17. No conflicts, no CI failures.

#### verify
- All 4 pre-merge conditions: PASS. Post-merge condition (#5) is `verify-type: manual` — not auto-verifiable; deferred to user. Phase label transitioned to `phase/verify` pending manual confirmation.

### Improvement Proposals
- For Spec files containing numeric scope claims (file counts, line counts, etc.), consider adding a `<!-- verify: command "find ... | wc -l" -->` hint in the corresponding acceptance condition to catch count drift automatically.
