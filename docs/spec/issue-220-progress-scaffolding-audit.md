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
