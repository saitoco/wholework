# Sonnet 5 Effort Recalibration: `run-issue.sh`

**Report date**: 2026-07-05
**Issue**: #923 (C4, `docs/reports/claude-sonnet-5-impact-strategy.md` §8)
**Scope**: Re-evaluate whether `run-issue.sh` (issue phase) effort can drop from `high` to `medium` under Sonnet 5's widened effort curve, framed by the impact report as the lowest-priority of the four C-series recalibration candidates.
**Depends on**: `docs/reports/claude-sonnet-5-impact-strategy.md` §3.3/§4.2 (candidate framing); `docs/reports/sonnet-effort-recalibration.md` (#229, 2026-04-18, Sonnet 4.6 baseline evaluation of `run-issue.sh` and four sibling scripts); `docs/reports/sonnet-5-effort-recalibration-code-review.md` (#921, C2) and `docs/reports/sonnet-5-effort-recalibration-spec.md` (#922, C3) — sibling reports and methodology precedent.

## Background

C1 (#914, default parent swap to Sonnet 5) landed, making phase-specific effort re-evaluation actionable. The impact strategy report §4.2 frames the issue phase's workload as "scope analysis rather than implementation," judging the recalibration risk as low and ranking `run-issue.sh` as the lowest-priority `medium` candidate among the four (`run-code.sh`/`run-review.sh` in #921, `run-spec.sh` in #922, `run-issue.sh` here).

No quantitative A/B benchmarking harness exists for isolating effort-level impact on a single task in production. Per the Issue's Auto-Resolved Ambiguity Points, this report follows the `#921`/`#922` precedent: combine (a) a structural re-derivation of `run-issue.sh`'s actual execution path, (b) a check of whether the sub-agent effort inheritance rationale documented in `docs/tech.md`'s matrix row still applies under that execution path, and (c) a production-sample check of recent Issue-phase-attributable Code Retrospective gaps.

## Evaluation Method

1. **Re-derive `run-issue.sh`'s execution path.** Identify every caller, confirm the invocation mode (interactive vs. non-interactive) and the Issue-number argument shape, and determine which of `skills/issue/SKILL.md`'s two flows ("New Issue Creation" vs. "Existing Issue Refinement") actually executes.
2. **Verify the sub-agent effort inheritance rationale the current matrix row's Rationale text relies on.** The row cites "L/XL scope analysis and sub-issue splitting require thorough orchestration" — confirm whether the L/XL sub-agent fan-out step this describes is actually reachable given the execution path from step 1.
3. **Structural comparison with `run-code.sh` (#921) / `run-spec.sh` (#922).** Determine whether `run-issue.sh`'s non-sub-agent workload is a single continuous reasoning chain of comparable structural class, and assess its downstream blast radius relative to the two already-evaluated scripts.
4. **Production-sample check.** Survey `docs/spec/*.md` Code Retrospective "Design Gaps/Ambiguities" entries for Issues coded after Sonnet 5 became the default parent (#914), filtered for gaps attributable to issue-phase artifact quality specifically (as opposed to environment/runtime specifics already excluded by `#921`/`#922`'s same check).

## Analysis 1 — Execution path re-derivation

`run-issue.sh` has exactly one caller in the codebase: `skills/auto/SKILL.md`, invoked for Issues lacking `phase/*` labels. `scripts/run-issue.sh` always constructs its prompt as `"${SKILL_BODY}\n\nARGUMENTS: ${ISSUE_NUMBER} --non-interactive"` (confirmed by reading the script body) — every invocation is non-interactive. The script also validates `$ISSUE_NUMBER` as numeric at entry (`[[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]`), and `skills/issue/SKILL.md`'s own mode-detection rule ("If ARGUMENTS is a number, refine an existing issue; if a string, create a new one") means `run-issue.sh` always executes the "Existing Issue Refinement" flow — "New Issue Creation" is unreachable via this entry point.

**Verdict of this check**: `run-issue.sh` is a single, fixed execution path — always non-interactive, always "Existing Issue Refinement" — not a two-mode script whose effort might need to vary by invocation shape.

## Analysis 2 — Does the matrix row's sub-agent rationale actually apply?

"Existing Issue Refinement" is a 14-step flow (fetch → triage auto-chain → label transition → steering-doc reference → background fact-check → ambiguity detection → AC classification/verify-command assignment → confirmation questions → issue body update → title drift check → blocked-by detection → **Scope Assessment (Step 12)** → issue retrospective → opportunistic verification). Step 12 is the only step that spawns sub-agents: for L/XL Issues, Step 12a fan-outs `issue-scope`/`issue-risk`/`issue-precedent` (all `model: opus`, confirmed via grep to have no `effort:` set — inheriting from the orchestrator, the same pattern `#921` confirmed for `review-bug`/`review-spec`).

However, Step 12's body opens with an unconditional non-interactive-mode skip clause that precedes any Issue-size branching: "(non-interactive mode: skip this entire step — sub-issue splitting is a High-Stakes Decision... then proceed to Step 13.)" Since Analysis 1 established that `run-issue.sh` always runs non-interactively, Step 12 — and the Step 12a Opus sub-agent fan-out inside it — **never actually executes** when invoked via `run-issue.sh`, regardless of Issue size. The three sub-agents only run when a human runs `/issue N` interactively in their own session, which is a different execution context than the one this Issue's `--effort` evaluation governs.

**Finding**: both `#229`'s original rationale ("L/XL requires `high` to preserve sub-agent accuracy") and the current matrix row's own Rationale text ("L/XL scope analysis and sub-issue splitting require thorough orchestration") describe a code path `run-issue.sh` never actually reaches. This is the same class of finding as `#921`'s discovery about `run-review.sh`'s "mechanical" framing — in both cases, the documented rationale did not accurately describe the target script's actual runtime behavior. Per the Issue's Auto-Resolved Ambiguity Points, this report does not rewrite the matrix row's Rationale cell itself — the corrected rationale is recorded only as a prose note (see `docs/tech.md` § Phase-specific model and effort matrix), consistent with the note-only pattern `#921`/`#922` established.

## Analysis 3 — Structural comparison and downstream blast radius

Excluding the unreachable Step 12a, `run-issue.sh`'s effective workload is a single-agent, 13-effective-step reasoning chain with no sub-agent fan-out — the same structural class `#921` used to justify `high` for `run-code.sh` (14 steps) and `#922` used for `run-spec.sh` (19 steps).

The impact report §4.2's "scope analysis rather than implementation" framing understates the actual work this chain performs: Step 6 (ambiguity detection and auto-resolution), Step 7 (acceptance-criteria classification and verify-command assignment), Step 5 (background fact-checking), and Step 10 (title drift detection) are all substantive judgment work of the same kind as spec authoring — determining what the Issue is actually asking for and how to mechanically verify it — not passive scope description.

The issue phase's artifacts (title, body, acceptance criteria, verify commands, Size/Priority/Type/Value) are also the most upstream artifacts in the entire pipeline. Errors here propagate through **every** downstream phase (spec, code, review, merge, and verify, which directly executes the assigned verify commands) — a longer propagation chain than either `run-code.sh` (#921) or `run-spec.sh` (#922, counted at three downstream phases: code+review+merge). This is a stronger downstream-blast-radius argument than the impact report §4.2/§8's "lowest-priority candidate of the four" framing suggests on its own: recalibration *urgency* (priority) and *blast-radius cost if the verdict is wrong* (propagation scope) are different axes, and this report's finding concerns the latter, not the former.

## Analysis 4 — Production-sample check (Issues coded under Sonnet-5-as-default, #915+)

Surveyed `docs/spec/*.md` Code Retrospective "Design Gaps/Ambiguities" sections across all Issues coded since #914 landed for which a Spec exists at report time (#915, #916, #917, #918, #921, #922, #927, #930, #932 — nine Issues; the same population `#922`'s Analysis 4 used, extended with the three Issues coded since):

| Issue | Design Gaps/Ambiguities — issue-phase-attributable? |
|---|---|
| #915, #916, #918, #927, #932 | N/A — no entry recorded |
| #917 | An interaction between recovery guidance and a security classifier, surfaced only by running the bats test — an environment/runtime-specific finding, not attributable to issue-phase artifact quality |
| #921 | A procedural note about resuming an interrupted `/code` run — not attributable to issue-phase content |
| #930 | A macOS `/tmp` → `/private/tmp` symlink test-comparison mismatch — an environment-specific finding, not attributable to issue-phase content |

**Reading**: none of the nine samples show a gap attributable to issue-phase artifact quality (a misclassified acceptance criterion, a verify command that turns out unverifiable and traces back to `/issue`, or a Size/Priority misjudgment surfacing as spec/code-time rework). This is net-neutral in the same sense `#922`'s Analysis 4 was: it does not prove `high` is necessary, but it also shows no over-provisioning signal (no recorded complaint that this phase is receiving more reasoning effort than its workload needs) — consistent with, but not proof of, `high` continuing to perform adequately.

## Recommendations

| Script | Current | Verdict | Rationale |
|--------|---------|---------|-----------|
| `run-issue.sh` | `high` | **Maintain** | `run-issue.sh` is invoked only by `/auto` for Issues lacking `phase/*` labels and always runs non-interactively (Analysis 1), so it always executes the "Existing Issue Refinement" flow — a single-agent 14-step reasoning chain whose only sub-agent fan-out (Step 12's L/XL Opus sub-agents) is unconditionally skipped in non-interactive mode regardless of Issue size (Analysis 2). Both `#229`'s original rationale and this matrix row's own Rationale text describe a code path that is never actually reached — an inaccuracy in the same vein as `#921`'s finding about `run-review.sh`. The corrected rationale is that Existing Issue Refinement performs substantive judgment work producing the pipeline's most upstream artifact, whose errors have the longest blast radius in the C-series (propagating through spec, code, review, merge, and verify — Analysis 3). A production-sample check across nine Issues coded under Sonnet 5 found no issue-phase-attributable design gaps (net-neutral, Analysis 4). |

No changes are made to `run-issue.sh`, the `docs/tech.md`/`docs/ja/tech.md` matrix table cells, or `tests/run-issue.bats` — this Issue records the verdict as a prose note (see `docs/tech.md` § Phase-specific model and effort matrix), consistent with the "maintain" precedent set by `#921`/`#922`.

## Notes

- **Out of scope**: `run-code.sh`/`run-review.sh` (#921, C2) and `run-spec.sh` (#922, C3) are separate impact-report §8 candidates, already resolved independently. `--effort=` flag exposure for per-Issue-size conditional tiering (C5) is a separate, larger Icebox candidate (§5.5) — not this Issue's two-way judgment. Rewriting the matrix row's Rationale cell itself, and the similarly-inaccurate "L/XL parallel sub-agent investigation" framing in the Architecture Decisions fork-justification table's `issue` row (`docs/tech.md` § Architecture Decisions), are both deliberately out of scope per the Issue's Auto-Resolved Ambiguity Points (note-only pattern); a future Issue can revisit either if needed.
- **bats**: no update needed — the verdict is "maintain" (no `run-issue.sh` value change), and `tests/run-issue.bats` currently has no assertion on the `--effort` value (grep-confirmed).
- **Translation mirror**: per `docs/translation-workflow.md` § Exclusions, `docs/reports/` is excluded from `docs/ja/` sync (same precedent as `#229`, `#903`, `#921`, `#922`) — no `docs/ja/reports/` mirror is created for this file. The `docs/tech.md` note this report supports *is* mirrored to `docs/ja/tech.md` (in scope for this Issue).
- Related: `docs/reports/sonnet-effort-recalibration.md` (#229, Sonnet 4.6 baseline, includes `run-issue.sh`); `docs/reports/sonnet-5-effort-recalibration-code-review.md` (#921, C2) and `docs/reports/sonnet-5-effort-recalibration-spec.md` (#922, C3) — sibling reports and methodology precedent; `docs/reports/claude-sonnet-5-impact-strategy.md` (§4.2/§8, candidate framing); Issue #914 (C1, default parent swap prerequisite).
