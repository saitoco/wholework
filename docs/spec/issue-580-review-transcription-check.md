# Issue #580: Review skill-dev: Add transcription divergence detection perspective

## Overview

Add a "Transcription Divergence Check" section to `skills/review/skill-dev-recheck.md` so the `/review` skill detects when aspirational expressions in spike reports or design documents (e.g., "N-vote adversarial verify") are transcribed unchanged into Domain files or SKILL.md despite the actual implementation being simpler (e.g., 1 refutation agent per finding).

Background: In Issue #575 review retrospective, the workflow-adapter spike (#565 `docs/reports/workflow-adapter-spike.md`) aspirational expressions were preserved unchanged in `skills/review/workflow-guidance.md` even though the actual implementation was 1-vote. This is a "transcription divergence" pattern where spike-stage aspirational ideas are kept verbatim when the spec is materialized into implementation files.

Adding this detection perspective to `skill-dev-recheck.md` enables future reviews to flag similar divergences early.

## Changed Files

- `skills/review/skill-dev-recheck.md`: add "## Transcription Divergence Check" section after "## Retrospective Guard"
- `skills/review/SKILL.md`: add conditional reference to the new section in Step 10.2 between step 2.5 and step 3

## Implementation Steps

1. Add "## Transcription Divergence Check" section to `skills/review/skill-dev-recheck.md`, immediately after the "## Retrospective Guard" section. The section content should include:
   - Trigger condition: any changed Domain file or SKILL.md references a spike report
   - Steps: (1) identify spike references in changed files, (2) read spike chapter and extract aspirational expressions, (3) grep implementation files, (4) compare expressed vs. actual behavior
   - Aspirational expression examples: "N-vote", "adversarial verify", loop counts, "ループ until dry", "最大 N 件", parallelism counts
   - Output: SHOULD-level finding when transcription divergence is detected
   (→ AC1, AC2)

2. Add a conditional reference to the new section in `skills/review/SKILL.md` Step 10.2, inserting between the current step 2.5 ("Get steering doc paths") and step 3 ("Launch agents in parallel") as step 2.6:
   `If scripts/validate-skill-syntax.py exists, read ${CLAUDE_PLUGIN_ROOT}/skills/review/skill-dev-recheck.md and follow "Transcription Divergence Check". Record any findings for inclusion in the review results.`
   (after Step 1)

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/review/skill-dev-recheck.md" "transcription" --> review phase の transcription divergence チェック観点が `skill-dev-recheck.md` に追加されている
- <!-- verify: grep "spike|aspirational|N-vote" "skills/review/skill-dev-recheck.md" --> spike からの転記乖離を検出する具体例が記載されている

### Post-merge

- 次回 spike レポート（`docs/reports/*-spike.md`）を参照する実装 Issue の review phase で、transcription check が機能することを確認 <!-- verify-type: opportunistic -->

## Notes

- Section named "## Transcription Divergence Check" (no step number prefix) to match the "## Retrospective Guard" naming style for cross-step concerns
- The check is SHOULD-level: aspirational-vs-implementation divergence is a documentation quality issue, not a correctness bug
- SKILL.md reference step numbered 2.6 to fit between existing steps 2.5 and 3 in Step 10.2 — the existing 2.5 numbering is already non-sequential (historical), so 2.6 is consistent
- No docs/ files need updating (changed files are under `skills/`, not `docs/`)
- No bats test changes needed (modifying markdown files, not scripts)

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- None

### Rework
- None

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| spec | patch | SUCCESS | — |
| code | patch | SUCCESS (after silent-no-op detection) | detect-wrapper-anomaly が初回 code 実行を silent-no-op として検出。run-auto-sub.sh の Tier 2 リトライで 2 回目に成功（commit c81aa61） |
| verify | - | SUCCESS | pre-merge 2/2 PASS |

### Orchestration Anomalies
- code phase の 1 回目実行で wrapper exit 0 だがコミットなし（silent no-op、#365 pattern）。`detect-wrapper-anomaly.sh` が検出し、改善提案として "Re-run run-code.sh 580" を出力。`run-auto-sub.sh` がこの提案を読みリトライ実行、2 回目で正常コミット（c81aa61）。Tier 2 fallback-catalog（#315）+ wrapper-anomaly-detector（#313）が連携して機能した実例

### Improvement Proposals
- N/A（既存の Tier 2 recovery が機能した。silent no-op の根本原因（claude の応答内容と実 commit の乖離）の追跡は #365 で継続中）

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- retro/verify 起票時点で AC（file_contains + grep）が完備、triage 補正不要

#### spec
- skill-dev-recheck.md への追記設計が単純で曖昧点 0

#### code
- 1 回目 silent no-op → wrapper-anomaly-detector + Tier 2 リトライで 2 回目成功。**自動リカバリの実地動作の好例**。手戻りは Tier 2 内部で完結し、親セッションへの手動介入不要

#### verify
- pre-merge 2/2 PASS。post-merge opportunistic は spike 参照型実装 Issue の review 実行が観測機会で SKIP

### Improvement Proposals
- N/A（silent no-op recovery が機能した。recovery log には orchestration-recoveries.md 経由で記録される）

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Added `## Transcription Divergence Check` section to `skill-dev-recheck.md` immediately after `## Retrospective Guard`, matching the existing naming style (no step number prefix, consistent with other cross-step concerns)
- Added step 2.6 in `SKILL.md` Step 10.2 between step 2.5 and step 3, gated on `scripts/validate-skill-syntax.py` existence to preserve the skill-dev-only conditional loading pattern
- Section uses SHOULD severity for divergence findings, consistent with the documentation quality classification (not a correctness bug)

### Deferred Items
- None — scope is narrow (markdown-only change) and fully implemented

### Notes for Next Phase
- Both Pre-merge ACs verified PASS: `file_contains "transcription"` and `grep "spike|aspirational|N-vote"` both match
- Changed files: `skills/review/skill-dev-recheck.md` and `skills/review/SKILL.md` only; no docs/ updates needed per Spec Notes
- validate-skill-syntax.py passed on all 10 skills; bats 700 tests all passed
