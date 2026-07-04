# /verify Interactive Friction Re-measurement: Sonnet 4.6 vs Sonnet 5

**Report date**: 2026-07-05
**Author**: Automated analysis session (Issue #877)
**Scope**: Re-measure `/verify` interactive-mode friction under Claude Sonnet 5 (released 2026-06-30) against the Sonnet 4.6 baseline, and judge whether Issue #485's design can be simplified further
**Depends on**: #876 (Sonnet 5 impact analysis, `docs/reports/claude-sonnet-5-impact-strategy.md` §4.5)

## Background

Issue #877's body describes #485 as "design work in progress." That is out of date: **#485 closed on 2026-05-26** with all 6 acceptance conditions met (fork abolition, parent-context execution, `AskUserQuestion`-based manual AC confirmation, checkbox flip, `phase/done` transition, removal of `scripts/run-verify.sh`). This report's actual question is therefore not "should #485's in-flight design shrink" but **"does #485's already-shipped design continue to hold up under Sonnet 5, and does Sonnet 5's higher agentic accuracy further reduce whatever friction remains?"**

Because `scripts/run-verify.sh` was removed by #485, `/verify` now runs entirely in-session (parent context) with no external wrapper. This has a direct consequence for this report: **there is no instrumentation that records `/verify` wall-clock time or `AskUserQuestion` turn counts** (`docs/sessions/*/events.jsonl` `phase_start`/`phase_complete` events cover `spec`/`code`/`review`/`merge` only, not `verify` — confirmed by grep against `scripts/emit-event.sh` and session event logs). All four metrics below are therefore necessarily **proxy metrics** derived from GitHub Issue timeline and comment artifacts, not direct measurements of the interactive experience itself. This limitation is material to the judgment in §3 and is not a data-quality accident — it reflects a real instrumentation gap that predates this Issue.

## A. Measurement Scenario

**Cohort construction**: Sonnet 5's `claude-sonnet-5` model ID is resolved by the bare `sonnet` alias used throughout `run-*.sh` and skill frontmatter (confirmed zero matches for a pinned pre-Sonnet-5 model ID via `grep -rn "claude-sonnet-4" scripts/ skills/*/SKILL.md`). Therefore any `/verify` run completed before 2026-06-30 used Sonnet 4.6, and any run completed after used Sonnet 5. Issues whose first verify comment landed *on* 2026-06-30 itself were excluded from both cohorts (exact release hour is unknown, so same-day comments are ambiguous per the Spec's guidance).

From `gh issue list --state closed` (2026-06-20 – 2026-07-04 window) filtered to issues carrying a `## Acceptance Test Results` comment, 5 issues were sampled per cohort, spread across a mix of Task types (auto/docs/scripts/hooks/code+review):

- **Sonnet 4.6 cohort** (comment posted 2026-06-29 or earlier): #848, #850, #859, #865, #869
- **Sonnet 5 cohort** (comment posted 2026-07-01 or later): #875, #880, #882, #885, #887

**Metric derivation** (all from `gh api .../timeline` and `gh issue view --json comments`):

1. **Wall clock (proxy)**: time between the first `phase/verify` `labeled` timeline event and the first `## Acceptance Test Results` comment's `createdAt`.
2. **User intervention count (proxy)**: number of bullet items under "Items Requiring User Verification" in that same comment.
3. **Reopen → fix → re-verify cycle rate**: count of `reopened` timeline events for the issue ÷ cohort size.
4. **Verify command pass rate / false-positive rate**: PASS/FAIL/UNCERTAIN tally across the "Auto Verification" table rows with a definitive result (PENDING/SKIPPED observation rows excluded as not-yet-executed); false positive = a FAIL followed by a PASS on re-verify with no intervening fix commit.

**Known proxy limitations** (apply to all four metrics):

- Metric 1 measures the gap between a label event and a comment post — largely mechanical/session-scheduling time, not the interactive back-and-forth (`AskUserQuestion` turns) that #485 targeted. It is included because the Issue's AC requires a wall-clock comparison, but it should not be read as "how long a human waited on confirmation dialogs."
- Metric 2 counts *post-merge observation bullets* left in the comment for future automatic pickup, not the number of `AskUserQuestion` prompts a user answered during the `/verify` run itself (that count is not persisted anywhere).
- Metric 3 and 4 are the most direct proxies available, but sample sizes (n=5 per cohort) are small, and a single outlier can dominate metric 1.

## B. Results

| Metric | Sonnet 4.6 (n=5) | Sonnet 5 (n=5) | Delta |
|---|---|---|---|
| Wall clock — median (label → first ATR comment) | 163s (2.7 min) | 156s (2.6 min) | ~flat |
| Wall clock — mean | 499s (8.3 min; #859 outlier at 32 min) | 169s (2.8 min) | mean skewed by one outlier; median is the more reliable read and shows no difference |
| User intervention count — mean per issue | 0.6 (3 items / 5 issues) | 0.2 (1 item / 5 issues) | −67% (small-n; see limitation above) |
| Reopen → fix → re-verify cycle rate | 20% (1/5 — #848) | 0% (0/5) | −20pp (see note below) |
| Verify command pass rate | 100% (20/20 rows PASS, 0 FAIL) | 100% (20/20 rows PASS, 0 FAIL) | No difference |
| Verify command false-positive rate | Undetermined (0 FAIL rows to evaluate) | Undetermined (0 FAIL rows to evaluate) | Not measurable from this sample |

**Per-issue detail**:

| Issue | Cohort | Wall clock | Intervention items | Reopened | Verify rows (PASS/total) |
|---|---|---|---|---|---|
| #848 | 4.6 | 184s | 0 | 1 (see note) | 3/3 (+1 pending) |
| #850 | 4.6 | 163s | 0 | 0 | 3/3 (+1 pending) |
| #859 | 4.6 | 1922s | 1 | 0 | 4/4 |
| #865 | 4.6 | 125s | 1 | 0 | 4/4 |
| #869 | 4.6 | 103s | 1 | 0 | 6/6 |
| #875 | 5 | 299s | 0 | 0 | 9/9 (+2 skipped) |
| #880 | 5 | 156s | 0 | 0 | 3/3 |
| #882 | 5 | 91s | 0 | 0 | 2/2 |
| #885 | 5 | 137s | 1 | 0 | 4/4 |
| #887 | 5 | 164s | 0 | 0 | 2/2 |

**Note on #848's reopen**: the reopen was not caused by a `/verify` command false positive — the closed issue's `## Recurrence after merge — different silent failure path` comment shows it was reopened after an *unrelated, genuinely new* regression was found via a subsequent `auto-run` observation event, then fixed and re-verified PASS. This is the reopen→fix→re-verify mechanism (built by #485) working as designed, not evidence of interactive-mode friction from a bad verify command.

## C. Judgment

**NO-GO** — continue with #485's current (already-shipped) design; no simplification is issued from this re-measurement.

**Rationale**:

1. Two of the four metrics (wall clock, verify-command pass rate) show no measurable difference between cohorts. The wall-clock proxy's apparent Sonnet-5 improvement disappears once the single #859 outlier is excluded from the mean (median is nearly identical: 2.7 min vs 2.6 min).
2. The two metrics with an apparent direction of improvement (intervention count, reopen rate) are drawn from n=5 samples with 1–3 total events — too small to attribute confidently to a model change rather than issue-to-issue variance in this repository's current activity. The one reopen in the Sonnet 4.6 cohort was independently confirmed to be unrelated to `/verify` command accuracy (see note above), which further weakens the reopen-rate delta as an "improvement" signal.
3. Most importantly: **none of the four measurable proxies actually capture the friction #485 was built to address** (the `AskUserQuestion`-driven "re-verify ceremony" — `[[project_verify_interactive_pain]]`). That count is not persisted to any GitHub artifact or session log, so this report cannot confirm or deny whether Sonnet 5's self-verification behavior reduces the number of confirmation round-trips a user experiences during a live `/verify` run.
4. Per the Issue's own judgment criteria (§B): "実測で改善確認できず → #485 現行設計で続行" (no measurable improvement confirmed → continue with #485's current design) is the correct bucket. This is a data-availability NO-GO, not a "Sonnet 5 underperforms" finding — the report found no evidence either for or against a friction reduction on the dimension that actually matters.

**Consequence for the Sonnet 4.6 → Sonnet 5 default-parent decision** (`docs/reports/claude-sonnet-5-impact-strategy.md` §4.1, §4.5): this Issue's scope is limited to the `/verify` friction re-measurement; it does not block or clear the broader default-parent swap on its own (that also depends on #878's tokenizer/context-budget measurement). The NO-GO recorded here means the `/verify`-specific risk row in the impact-strategy decision matrix remains "Unknown" rather than resolving to "Favorable" — a follow-up Issue (§D) proposes closing that gap with direct instrumentation.

## D. Follow-up

Since the judgment is NO-GO and the root cause is a genuine measurement gap (not a rejected design), **Issue #902** was filed to add direct `/verify` session instrumentation (an `AskUserQuestion` turn-count event and a `phase_start`/`phase_complete` pair for the `verify` phase, mirroring the existing `spec`/`code`/`review`/`merge` events) so that a future re-measurement can evaluate the actual interactive-friction dimension instead of these GitHub-artifact proxies. #485 is not reopened — it already met all of its own acceptance conditions and continues unchanged.

## Notes

- Sample selection favored recent, verified issues (2026-06-20–2026-07-04) with a mix of Task types to avoid a single skill area dominating either cohort.
- `docs/reports/` is excluded from the `docs/ja/` translation mirror per `docs/translation-workflow.md` § Exclusions — no `ja/` counterpart is required for this file.
- Related: `docs/reports/claude-sonnet-5-impact-strategy.md` §4.1 (decision matrix), §4.5 (delegated scope to this Issue); `docs/reports/claude-fable-5-impact-strategy.md` §4.3 (de-prescription audit precedent, not applicable here since no de-prescription is being proposed).
