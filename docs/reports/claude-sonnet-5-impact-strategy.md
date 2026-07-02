English | [日本語](../ja/reports/claude-sonnet-5-impact-strategy.md)

# Claude Sonnet 5 Impact Analysis & Strategy for Wholework

**Report date**: 2026-07-02
**Author**: Automated analysis session
**Model launched**: Claude Sonnet 5 (`claude-sonnet-5`) — 2026-06-30 ([announcement](https://www.anthropic.com/news/claude-sonnet-5))
**Scope**: Phase-specific model/effort matrix (`docs/tech.md`, `ssot_for: model-effort-matrix`) and the skill/script inventory affected by a potential default-parent change
**Status**: Proposal — see "Candidate Issues" (§8) for an execution plan

**Companion**: builds on `docs/reports/claude-fable-5-impact-strategy.md` and `docs/reports/claude-opus-4-7-optimization-strategy.md`

## 1. Executive Summary

Claude Sonnet 5 is a substantial agentic-performance jump over Sonnet 4.6 — early partner testimony describes it investigating a bug, writing a reproducing test, implementing the fix, and stashing the change to confirm the regression on its own, all in a single pass, and carrying real, previously-unsolved pull requests through to a tested, verified result unattended. At `effort: xhigh` it approaches Opus 4.8 on a meaningful share of tasks, while introductory pricing ($2 input / $10 output per MTok, through 2026-08-31; $3/$15 standard thereafter) sits at roughly 40–60% of Opus 4.8's cost ($5/$25). The `medium` effort tier is reported to substantially widen the cost/performance curve, and Claude Code / Cowork / Chat rate limits have been raised alongside the release. Cyber safeguards are held at the Opus 4.7/4.8 level — materially less restrictive than Fable 5's Mythos-tier classifiers.

Wholework currently pins Sonnet 4.6 as the **default parent model** across the phase-specific matrix (`docs/tech.md` §Phase-specific model and effort matrix, `ssot_for: model-effort-matrix`). Sonnet 5's combination of higher agentic accuracy at a cost still well below Opus makes it the most consequential model-tier development for Wholework's default-model economics since the matrix was last recalibrated — more consequential than Fable 5, whose adoption story is opt-in-only due to $10/$50 pricing and retention constraints (`[[project_sonnet_5_migration]]`).

This report's conclusion: **the default-parent question is real but not yet actionable within this Issue.** Wholework's `/code` skill and phase orchestration already treat effort and model as independently tunable axes (`docs/tech.md` §Effort optimization strategy), so a Sonnet 4.6 → Sonnet 5 swap is a narrow, mechanical change *once* two measurements land — `/verify` interactive-friction re-measurement (#877) and tokenizer-driven watchdog/context-budget impact (#878). This Issue is scoped to Migration path Phase 1 only: publish the impact inventory, add a note-only paragraph to the `docs/tech.md` matrix (no table edits), and enumerate the follow-up Issues (§8) that Phases 2–4 require. The actual default-parent swap, effort recalibration per phase, and any `--effort=` flag exposure are deliberately deferred to those follow-up Issues, consistent with the CI-sensitive Size M minimum policy for matrix-touching changes (`[[feedback_ci_sensitive_size_m]]`).

*A note on scope relative to the Fable 5 report*: §2 of the Fable 5 report ("Does Wholework still have a reason to exist?") is not repeated here. Sonnet 5 sits a tier below Fable 5/Mythos, so the scaffold-dissolution and Managed-Agents-competition pressures already examined there apply transitively and at lower intensity — a more capable *default* model raises the same governance/verification argument, it does not weaken it. See `docs/reports/claude-fable-5-impact-strategy.md` §2 for the full argument.

## 3. Key Claude Sonnet 5 changes (relevant to Wholework)

### 3.1 Pricing

| Model | Price (input/output per MTok) | Relative to Opus 4.8 ($5/$25) |
|---|---|---|
| Sonnet 5 — introductory (through 2026-08-31) | $2 / $10 | ~40% |
| Sonnet 5 — standard (from 2026-09-01) | $3 / $15 | ~60% |
| Opus 4.8 (reference) | $5 / $25 | 100% |
| Fable 5 (reference, opt-in only) | $10 / $50 | 200% |

Sonnet 5's standard price ($3/$15) is in the same band Sonnet 4.6 already occupies in Wholework's cost model (the Fable 5 report's "~3.3× Sonnet 4.6" comparison against Fable 5's $10/$50 backs out to roughly $3/$15 for Sonnet 4.6). In other words, Sonnet 5 does **not** introduce a new cost tier for the default-parent slot — it offers materially higher agentic accuracy *at the price Wholework already pays* for its default model, with an introductory window that is cheaper still.

### 3.2 Tokenizer update

Sonnet 5 ships a tokenizer update in the same family as the Opus 4.7 change: the same input text maps to 1.0×–1.35× more tokens than under the prior tokenizer. This is a **direct input** to `claude-watchdog.sh` no-stdout timeout calibration and to any character-based context-budget heuristics in Wholework. Full measurement is delegated to `#878` (§4.4) — this report only records that the change exists and is in scope for that Issue.

### 3.3 Effort curve widening

Anthropic's guidance is that effort-level tuning on Sonnet 5 spreads the cost/performance curve further than on Sonnet 4.6: `medium` effort delivers meaningfully better cost efficiency for tasks that do not need deep reasoning, while `xhigh` effort approaches Opus 4.8-class performance on a subset of tasks. This directly affects the phase-specific effort column in `docs/tech.md`'s matrix (currently `high` for `run-code.sh`, `run-review.sh`; `max`/`xhigh` for `run-spec.sh`) — recalibration candidates are enumerated in §4.2, but the actual per-phase effort changes are Phase 3 work (§8, C-series), not this Issue.

### 3.4 Rate limits and cyber safeguards

Claude Code / Cowork / Chat rate limits have been raised alongside the Sonnet 5 release, which is a pure operational positive for Wholework's `run-*.sh` orchestration (no action needed). Cyber safeguards are held at the Opus 4.7/4.8 level, not Fable 5's stricter Mythos-tier classifiers — this means Sonnet 5 is less likely than Fable 5 to trigger the cyber-classifier fallback documented in the Fable 5 report §4.6, which is a relevant (favorable) data point for `review-bug`-style security-sensitive queries if Sonnet 5 is ever adopted there.

### 3.5 Fable 5 re-deployment (2026-07-01) — tier separation

Fable 5 was suspended on 2026-06-13 under a government directive and reportedly redeployed on 2026-07-01, one day after Sonnet 5's launch. This report treats the two as separate tracks: **Sonnet 5 is a default-parent candidate** (this report), while **Fable 5 remains opt-in-only** per `docs/tech.md`'s existing Fable 5 paragraph and the Fable 5 report §5.2 — the redeployment does not change Fable 5's cost ($10/$50), retention (30-day), or subscription-gating constraints. The two model tiers should not be conflated when candidate Issues from this report and the Fable 5 report are prioritized against each other.

## 4. Impact analysis (concrete)

### 4.1 Default parent switch: decision matrix

| Factor | Sonnet 4.6 (current default) | Sonnet 5 | Verdict |
|---|---|---|---|
| Cost at standard pricing | ~$3/$15 (baseline) | $3/$15 (from 2026-09-01) | Neutral — same band |
| Cost through 2026-08-31 | ~$3/$15 | $2/$10 (introductory) | Favorable to Sonnet 5 |
| Agentic accuracy (brownfield, multi-step) | Baseline | Reported substantial uplift; approaches Opus 4.8 at `xhigh` | Favorable to Sonnet 5 |
| Tokenizer impact on watchdog/context budget | N/A (current baseline) | 1.0–1.35× — unmeasured for Wholework's actual prompt mix | **Unknown — blocks swap** (#878) |
| `/verify` interactive-mode friction (#485) | Known pain point, confirmed high priority (`[[project_verify_interactive_pain]]`) | Unmeasured whether Sonnet 5's agentic gains reduce re-verify ceremony | **Unknown — blocks swap** (#877) |
| CI-sensitivity of the change itself | — | Matrix-table edit is CI-sensitive, Size M minimum (`[[feedback_ci_sensitive_size_m]]`) | Requires its own PR-route Issue regardless of measurement outcome |

**Reading**: cost and reported accuracy already favor Sonnet 5, but two unknowns (tokenizer-driven watchdog calibration, `/verify` friction delta) are exactly the kind of regression that would not show up until real workloads run against the new tokenizer and model. The matrix swap is therefore correctly sequenced *after* #877 and #878 land, not before — this is the rationale for keeping this Issue analysis-only (`[[project_sonnet_5_migration]]`).

### 4.2 Phase-specific effort recalibration candidates

Per §3.3, `medium` effort now covers more ground and `xhigh` approaches Opus 4.8. Candidates for re-examination once Sonnet 5 is adopted as default (Phase 3, §8):

- `run-code.sh` (currently `high`): candidate for `medium` on XS/S patch-route Issues where the current `high` effort may already be over-provisioned; requires A/B evidence before changing the SSoT.
- `run-review.sh` (currently `high`): review orchestration is mechanical (sub-agents do the deep analysis per `docs/tech.md`'s matrix rationale), making it a plausible `medium` candidate.
- `run-spec.sh` (currently `max` for Sonnet): design-quality-critical phase; §3.3's `xhigh`-approaches-Opus framing suggests `xhigh` may be sufficient without dropping to Opus for L-size specs, but this is a quality-sensitive change requiring careful evaluation, not a default flip.
- `run-issue.sh` (currently `high`): low risk to revisit given issue-phase work is scope analysis rather than implementation; lowest priority of the four.

None of these are implemented in this Issue — they are Phase 3 candidate Issues (§8, C-series) gated behind adoption of Sonnet 5 as default parent (Phase 2).

### 4.3 Sub-agent (Opus alias) continuation judgment

`docs/tech.md`'s matrix currently routes `review-bug`, `review-spec`, `issue-scope`, `issue-risk`, `issue-precedent`, and `frontend-visual-review` to the `opus` alias (auto-resolving to Opus 4.8). Sonnet 5's `xhigh`-approaches-Opus-4.8 framing raises the question of whether some of these sub-agents could move to Sonnet 5.

**Recommendation: keep Opus 4.8 for these sub-agents for now.** The rationale in `docs/tech.md` for each of these routes is *accuracy-criticality* — bug detection, spec-deviation detection, and scope/risk/precedent investigation are exactly the tasks where "approaches Opus 4.8 on a meaningful share of tasks" (i.e., not all tasks) is an unacceptable hedge; a false negative in `review-bug` ships a bug, and a missed precedent in `issue-precedent` degrades acceptance-criteria quality downstream. Sub-agent effort is inherited from the parent and these agents are typically a small fraction of total phase cost, so the cost argument for swapping them is weak relative to the accuracy risk. This judgment should be revisited only if Sonnet 5 `xhigh` benchmarks specifically targeting bug-detection/precedent-retrieval tasks become available (candidate for a future Icebox re-evaluation trigger, not this Issue).

### 4.4 Tokenizer impact — delegated to #878

Sonnet 5's tokenizer maps the same input to 1.0×–1.35× more tokens, in the same family as the Opus 4.7 tokenizer change. Wholework's actual prompt composition (Spec bodies, Issue bodies, git diffs, `auto-events.jsonl` excerpts) determines where in that range real workloads fall, and that determines whether `claude-watchdog.sh`'s no-stdout timeout defaults and any context-budget heuristics need recalibration. This report does not attempt that measurement — it is the complete scope of `#878` ("context-budget: Sonnet 5 tokenizer 変更 (1.0-1.35×) の watchdog/context budget 影響測定"), which blocks the default-parent swap per §4.1.

### 4.5 `/verify` behavioral improvement — delegated to #877

`/verify` interactive mode has confirmed, high-priority user-facing friction from repeated re-verify ceremony (`[[project_verify_interactive_pain]]`, Issue #485). Sonnet 5's higher agentic accuracy and reported self-verification behavior are plausible levers to reduce that friction (fewer false FAILs requiring re-verify, more reliable structured acceptance testing), but this requires re-measurement against real `/verify` runs, not a documentation-only judgment. That re-measurement and any resulting design simplification is the complete scope of `#877` ("verify: Sonnet 5 での /verify interactive 摩擦 (#485) 再測定と設計簡素化判定").

### 4.6 Judgment criteria (draft, aligned with Issue #876 §B)

Carrying forward the Issue body's draft decision matrix:

- **Always Sonnet 5** (once adopted as default): read-heavy, low-risk, high-parallelism phases — `/audit stats`, `/audit auto-session`, `/auto --batch` parent orchestration. These have the lowest blast radius from a model swap and the highest volume, so cost savings compound.
- **Sonnet 5 `xhigh` under evaluation**: implementation-heavy phase (`run-code.sh`), spec phase (`run-spec.sh`) — highest potential quality upside, but also the phases where a regression is costliest (spec errors propagate to all downstream phases per the existing matrix rationale).
- **Opus 4.8 continues**: bug detection (`review-bug`), spec deviation (`review-spec`), scope/risk/precedent investigation (`issue-scope`/`issue-risk`/`issue-precedent`) — per §4.3, agentic precision is critical and "approaches Opus 4.8" is not "matches Opus 4.8."
- **Held for now**: `/verify`, `/merge` — currently Sonnet-sufficient, mechanical; no evidence yet that Sonnet 5 changes this calculus (revisit after #877 lands, since #877 specifically targets `/verify`).

## 5. Strategic recommendations

### 5.1 Publish the impact inventory without touching the matrix table (P1)

This Issue's own scope: ship this report and the `docs/tech.md` note-only paragraph (§ Migration path Phase 1). Do not edit the matrix table itself — the default-parent swap is a distinct, CI-sensitive change (`[[feedback_ci_sensitive_size_m]]`) that belongs in its own PR-route Issue, sequenced after #877/#878.

### 5.2 Sequence the default-parent swap behind #877 and #878 (P1)

File and prioritize the Phase 2 default-parent-swap Issue (§8, C1) so it is ready to execute as soon as both blocking measurements land, but do not pre-empt those measurements. This preserves the pattern already used for Fable 5 adoption (measure-then-decide, not default-then-measure).

### 5.3 Scope Phase 3 effort recalibration as several small Issues (P2)

Per §4.2, recalibrate `run-code.sh`, `run-review.sh`, `run-spec.sh`, `run-issue.sh` effort levels as independent, low-risk patch/S-sized Issues rather than one bundled change — this matches Wholework's existing preference for narrow, individually-revertible SSoT edits and lets each phase's evidence be evaluated on its own merits.

### 5.4 Defer sub-agent model swaps and hold Opus 4.8 for accuracy-critical roles (P2)

Per §4.3, no sub-agent frontmatter changes in this Issue or its immediate follow-ups. Revisit only if Sonnet 5 `xhigh` benchmarks targeting bug-detection/precedent-retrieval accuracy specifically (not general agentic coding benchmarks) become available.

### 5.5 Treat `--effort=` flag exposure as Icebox-eligible, not urgent (P3)

The Size × model × effort three-axis flag exposure (Phase 4) has no urgent driver identified in this report — it is a convenience/control feature, not a correctness or cost-blocking one. Recommend filing it directly as an Icebox candidate (`[[project_icebox_index]]`) rather than a near-term Issue, pending demand signal.

## 6. Impact summary table

| Area | Risk/Opportunity | Priority |
|---|---|---|
| Default parent swap (Sonnet 4.6 → Sonnet 5) | Cost-neutral-to-favorable, accuracy uplift; blocked on #877/#878 | P1 |
| `/verify` re-measurement (#877) | May reduce confirmed high-priority interactive friction | P1 (tracked in #877) |
| Tokenizer/watchdog impact (#878) | Blocks default-parent swap until measured | P1 (tracked in #878) |
| Phase-specific effort recalibration | Cost efficiency once default swap lands | P2 |
| Sub-agent (Opus alias) continuation | No change; accuracy risk if swapped prematurely | P2 (hold) |
| Fable 5 tier separation messaging | Avoid conflating opt-in Fable 5 with default-candidate Sonnet 5 | P2 |
| `--effort=` flag exposure | No urgent driver; Icebox candidate | P3 |

## 7. Migration checklist

- [x] Publish `docs/reports/claude-sonnet-5-impact-strategy.md` (this report)
- [x] Add Sonnet 5 note-only paragraph to `docs/tech.md`'s Phase-specific model/effort matrix section, linking to this report
- [ ] Confirm candidate Issues (§8) are filed or mapped to existing Issues (`#877`/`#878` already exist; C-series to be filed per Phase)
- [ ] (optional) Prepare Phase 2 default-parent-swap Issue draft, held pending #877/#878 completion
- [ ] (optional) Prepare Phase 3 effort-recalibration Issue drafts (one per `run-*.sh` script), held pending Phase 2
- [ ] (optional) File `--effort=` flag exposure as an Icebox candidate per §5.5

## 8. Candidate Issues (execution plan)

All follow the Wholework Standard Format (Background / Purpose / Acceptance Criteria, Pre-merge and Post-merge split where applicable). Matrix-table-touching items are CI-sensitive and Size M minimum (`[[feedback_ci_sensitive_size_m]]`).

| # | Title (Japanese) | Priority | Est. Size | Phase impact |
|---|---|---|---|---|
| #877 | verify: Sonnet 5 での /verify interactive 摩擦 (#485) 再測定と設計簡素化判定 | high | M | verify |
| #878 | context-budget: Sonnet 5 tokenizer 変更 (1.0-1.35×) の watchdog/context budget 影響測定 | high | M | auto, code, spec, watchdog |
| C1 | default parent を Sonnet 4.6 → Sonnet 5 に切替 (#877/#878 完了後、matrix 表本体を更新) | high | M | issue, spec, code, review, merge |
| C2 | run-code.sh / run-review.sh の effort 再校正 (medium 候補の A/B 評価) | medium | S | code, review |
| C3 | run-spec.sh の effort 再校正 (xhigh 候補、Opus fallback との比較評価) | medium | S | spec |
| C4 | run-issue.sh の effort 再校正 (medium 候補、低リスクから着手) | low | S | issue |
| C5 | `--effort=` フラグ露出 (Size × model × effort 3 軸、opt-in) | low | M | all skills |
| C6 | Sonnet 5 xhigh の bug-detection/precedent-retrieval ベンチマーク再評価トリガー登録 (Icebox) | low | XS | review, issue |

### Ordering rationale

- **#877, #878** are already filed and block everything else in this table — both must land before **C1** can execute.
- **C1** is the actual default-parent swap; it is the single highest-leverage change in this table because every other candidate (C2–C4) depends on Sonnet 5 being the default before its effort levels are worth recalibrating.
- **C2, C3, C4** are independent per-phase effort recalibrations, ordered by risk: `run-code.sh`/`run-review.sh` first (mechanical or sub-agent-delegated), `run-spec.sh` next (quality-critical, needs more evidence), `run-issue.sh` last (lowest priority, least urgency).
- **C5** has no urgent driver (§5.5) and can run independently of C1–C4, whenever demand signal appears.
- **C6** is a monitoring/re-evaluation trigger, not an implementation change — lowest cost, lowest priority.

## 9. Non-goals

- No default swap for Fable 5 — Fable 5 remains opt-in-only per its own cost/retention constraints (§3.5); this report does not revisit that conclusion.
- No per-agent frontmatter model swap implementation (`review-bug`, `review-spec`, `issue-scope`, `issue-risk`, `issue-precedent`, `frontend-visual-review`) — §4.3 recommends holding Opus 4.8 for these roles; any future swap is a separate, individually-judged Issue.
- No actual default-parent swap in this Issue — that is Phase 2 (C1, §8), sequenced after `#877`/`#878`.
- No `docs/tech.md` matrix table edits — only the note-only paragraph described in §5.1 and the Implementation Steps.
- No `docs/ja/reports/claude-sonnet-5-impact-strategy.md` translation — `docs/reports/` is excluded from the translation-sync obligation (`docs/translation-workflow.md` § Exclusions); a ja mirror may be created later as a separate, explicit decision if demand emerges.

## 10. References

- [Introducing Claude Sonnet 5 (Anthropic, 2026-06-30)](https://www.anthropic.com/news/claude-sonnet-5)
- [Claude Sonnet 5 System Card](https://www.anthropic.com/claude-sonnet-5-system-card)
- `docs/reports/claude-fable-5-impact-strategy.md` (companion; Mythos-tier analysis and the governance/verification-harness argument this report inherits by reference in §1)
- `docs/reports/claude-opus-4-7-optimization-strategy.md` (companion; prior-model recalibration precedent)
- `docs/tech.md` §Phase-specific model and effort matrix (`ssot_for: model-effort-matrix`, update target for this report's note-only paragraph)
- Issue #876 (this Issue), #877 (`/verify` re-measurement), #878 (tokenizer/context-budget measurement)

---

*This report proposes the Issues in §8. `#877` and `#878` already exist and are blocked-by children of Issue #876. The remaining C-series Issues are expected to be created on the Wholework GitHub repository with the appropriate `phase/*` label and Priority set on the Wholework GitHub Project, sequenced per the "Ordering rationale" above.*
