# Claude Opus 5 Impact Analysis & Strategy for Wholework

**Report date**: 2026-07-29
**Author**: Automated analysis session
**Model launched**: Claude Opus 5 (`claude-opus-5`) — 2026-07-24 ([announcement](https://www.anthropic.com/news/claude-opus-5))
**Scope**: Opus-routed components only — 7 locations across the phase-specific model/effort matrix (`docs/tech.md`, `ssot_for: model-effort-matrix`). Unlike the Sonnet 5 report (`#876`), which analyzed a **default-parent** candidate touching every phase, this report's scope is narrower by construction: Opus is never the default parent in Wholework, so the blast radius is limited to the components that explicitly route to the `opus` alias.
**Status**: Factual correction + deferral record — see "Candidate Issues" (§8) for the two already-filed child Issues this report enumerates

**Companion**: builds on `docs/reports/claude-sonnet-5-impact-strategy.md` and `docs/reports/claude-fable-5-impact-strategy.md`

## 1. Executive Summary

Claude Opus 5 launched 2026-07-24 at the same price as Opus 4.8 ($5/$25 per MTok), with 1M context as both the default and maximum window, 128K max output, and SOTA results on Frontier-Bench v0.1 and GDPval-AA — at CursorBench 3.2 `max` effort it lands within 0.5% of Fable 5's peak score at half the cost. It is now the default model behind Claude Max and the strongest model available on Claude Pro. Its effort ladder gained a fifth rung (`low`/`medium`/`high`/`xhigh`/`max`, default `high`), and Anthropic's guidance is that the two lowest rungs, `low` and `medium`, are stronger than their names suggest. Prompt caching now activates from a 512-token minimum prompt, half of Opus 4.8's 1024-token floor. Rate limits sit in a pool separate from the unified Opus 4.x pool. Opus 5 carries its own cyber classifier (~85% lower trigger frequency than Fable 5's; flagged requests fall back to Opus 4.8) — source-code vulnerability discovery is permitted, while binary-based scanning, penetration testing, and exploit generation are blocked. Fable 5's biology-classifier fallback target also moved from Opus 4.8 to Opus 5 (its cyber-classifier fallback target is unchanged, still Opus 4.8).

Unlike the Sonnet 5 report, this is not a default-parent evaluation: Wholework's `sonnet` alias is the pipeline's default parent, and Opus is reached only through explicit `model: opus` sub-agent frontmatter or the `run-spec.sh --opus` flag. But because Wholework's alias pin policy (`docs/tech.md` § Alias pin policy) has the bare `opus` CLI alias auto-resolve to "the current Opus" rather than a pinned version string, **Opus 5 has already been live across all 7 Opus-routed components since 2026-07-24** — three weeks before this report was written — with zero corresponding "Opus 5" text anywhere in the repository (confirmed via `grep`) until this Issue. This is not a new risk: the alias pin policy explicitly named this exact failure mode as an accepted trade-off ("future model generations will likewise be auto-adopted as default parent via the alias before a dedicated measurement Issue lands"), and it is the same reactive-recalibration pattern already exercised twice — the Fable 5 → Sonnet 4.6 transition (`#628`) and the Sonnet 4.6 → Sonnet 5 transition (`#877`/`#878`/`#903`). This report is the third data point for that pattern, and the first one triggered by an *Opus* generation change rather than a *Sonnet*-alias one.

This report's conclusion: Wholework's `docs/tech.md` matrix notes are corrected to reflect Opus 5 as the resolved target of the `opus` alias and its own effort-calibration guidance (§ below); the Sonnet 5 → Opus 5 default-parent question is evaluated and explicitly **deferred**, not adopted (§4.1); and two scoped follow-up Issues already exist to carry the remaining Opus-5-driven work — sub-agent `effort:` frontmatter decoupling (`#1063`) and `run-spec.sh --opus`'s own effort recalibration (`#1064`).

## 3. Key Claude Opus 5 changes (relevant to Wholework)

### 3.1 Pricing and context

| Model | Price (input/output per MTok) | Context | Max output |
|---|---|---|---|
| Opus 5 | $5 / $25 | 1M (default and max) | 128K |
| Opus 4.8 (reference) | $5 / $25 | — | — |
| Sonnet 5 standard, from 2026-09-01 (reference) | $3 / $15 | — | — |

Opus 5 is priced identically to Opus 4.8 — this is a pure capability upgrade at the existing Opus price point, not a new cost tier. Relative to Sonnet 5, Opus 5 remains 1.7× (standard pricing) to 2.5× (Sonnet 5's introductory pricing through 2026-08-31) more expensive; see §4.1 for how this factors into the default-parent deferral.

### 3.2 Effort ladder recalibration

Opus 5's effort ladder keeps the same five rungs as Opus 4.8 (`low`/`medium`/`high`/`xhigh`/`max`, default `high`), but Anthropic's calibration guidance changed materially: coding/agentic tasks should start at `xhigh` and other tasks at `high`, then sweep *downward* from there, because `low`/`medium` are reported to be stronger than their tier names suggest — the opposite emphasis from Opus 4.8's guidance, which recommended `xhigh` as the default for most coding/agentic work and warned that `max` risked diminishing returns (overthinking). `max` itself is now framed as reserved for extremely difficult, latency-insensitive tasks only. This directly obsoletes the existing "Opus 4.8 effort calibration" note in `docs/tech.md`'s matrix section (§ Implementation Steps 2 below).

### 3.3 Prompt cache minimum prompt: 1024 → 512 tokens

Opus 5 halves the minimum prompt length required for cache activation, from Opus 4.8's 1024 tokens to 512. This is favorable for any Opus-routed component whose typical prompt sits between 512 and 1024 tokens — such invocations become cache-eligible under Opus 5 where they were not under Opus 4.8. Recorded as a watch item (§ Implementation Steps 4) rather than acted on, since Wholework does not currently track per-component prompt-token sizes against this threshold.

### 3.4 Rate limits: separate pool from Opus 4.x

Opus 5's rate limit is a distinct pool from the unified Opus 4.x limit, rather than sharing headroom with Opus 4.7/4.8 traffic. This changes the parallel-capacity picture for `/auto --batch` runs that fan out multiple L/XL Issues' Opus sub-agents (`issue-scope`/`issue-risk`/`issue-precedent`, `review-bug`/`review-spec`) concurrently — headroom is now governed by Opus 5's own pool rather than a shared Opus 4.x ceiling. Recorded as a watch item (§ Implementation Steps 4); no `WHOLEWORK_MAX_RECOVERY_SUBAGENTS`-style cap change is made in this report, since no concrete throttling incident has been observed yet.

### 3.5 Cyber classifier

Opus 5 ships its own cyber classifier, triggering roughly 85% less frequently than Fable 5's Mythos-tier classifier; flagged requests fall back to Opus 4.8. Source-code vulnerability discovery is explicitly permitted, while binary-based scanning, penetration testing, and exploit generation are blocked. This is directly relevant to `agents/review-bug.md`, an Opus-routed sub-agent whose job is source-level bug/security detection — squarely inside the permitted category, so actual operational risk is low, but the existing Fable-5-only note in that agent file is now factually incomplete (Opus 5 itself, not just Fable 5, can hit a classifier and reroute) and is generalized in this report's scope (§ Implementation Steps 5).

### 3.6 Fable 5 biology-routing target change

Requests blocked by Fable 5's biology classifier now route to Opus 5 rather than Opus 4.8 (Fable 5's cyber-classifier routing target is unchanged — still Opus 4.8). This is a narrow correction to the existing Fable 5 paragraph in `docs/tech.md` (§ Implementation Steps 3) and does not affect any Wholework component directly, since no Wholework skill or sub-agent currently runs on Fable 5 in production (`docs/tech.md` § Fable 5 paragraph: opt-in only).

## 4. Impact analysis (concrete)

### 4.1 Default parent switch (Sonnet 5 → Opus 5): evaluated and deferred

| Factor | Sonnet 5 (current default parent) | Opus 5 | Verdict |
|---|---|---|---|
| Cost at standard pricing | $3/$15 | $5/$25 (~1.7×) | Unfavorable to Opus 5 |
| Cost vs. Sonnet 5 introductory (through 2026-08-31) | $2/$10 | $5/$25 (~2.5×) | Unfavorable to Opus 5 |
| Time since default-parent confirmation | `#914` landed ~4 weeks before this report | — | Too recent to re-open |
| Evidence of Sonnet 5 quality shortfall | None — `#921`/`#922`/`#923` (code/review, spec, issue effort recalibrations) all resolved **maintain**, no gap found | — | No basis for a swap |
| Measurement chain cost to justify a swap | `#877`/`#878`-equivalent re-measurement (tokenizer/watchdog, `/verify` friction) would need to run again for Opus 5 | Not yet run | Not justified without a quality signal first |
| Claude Max default model | Sonnet 5 remains Wholework's pipeline default | Opus 5 is now Claude Max's own default | Recorded as a future re-evaluation trigger, not actioned |

**Verdict: defer.** The default-parent question is evaluated, not adopted. Three reasons converge: (a) the Sonnet 5 default-parent decision (`#914`) is roughly four weeks old — too recent to re-open without new evidence; (b) all three Sonnet-5-era effort recalibrations (`#921` code/review, `#922` spec, `#923` issue) independently concluded `maintain` with no design-reasoning gaps found in production samples, meaning there is no quality signal motivating a more expensive model; (c) Opus 5's 1.7–2.5× cost premium over Sonnet 5 is exactly the kind of gap that justified running the `#877`/`#878` measurement chain before the Sonnet 4.6 → Sonnet 5 swap — and no comparable measurement has been run for a Sonnet 5 → Opus 5 swap, nor is one justified without (b) changing. The one fact this table does *not* neutralize is that Claude Max's own default model is now Opus 5 — recorded as a re-evaluation trigger (§ Implementation Steps 4), not as grounds for a swap today.

### 4.2 Opus-routed component inventory and impact scope

Per the Issue Background, the alias pin policy's auto-resolve behavior means Opus 5 is already the effective model behind all 7 of the following as of 2026-07-24 — this section is a factual inventory, not a proposed change:

| Component | Phase | Trigger |
|---|---|---|
| `run-spec.sh --opus` (effort `xhigh`) | spec | `/auto` auto-passes `--opus` for L-size Issues |
| `agents/issue-scope.md` | issue (L/XL) | `/issue` Step 12a parallel investigation |
| `agents/issue-risk.md` | issue (L/XL) | `/issue` Step 12a parallel investigation |
| `agents/issue-precedent.md` | issue (L/XL) | `/issue` Step 12a parallel investigation |
| `agents/review-bug.md` | review | `/review` full mode |
| `agents/review-spec.md` | review | `/review` full mode |
| `agents/frontend-visual-review.md` | verify | `visual_diff` verify commands |

The default-parent path (`run-issue.sh`/`run-code.sh`/`run-review.sh`/`run-merge.sh`/`/auto`/`/verify`/`/triage`/`/audit`/`/doc`) resolves `sonnet`, not `opus`, and is entirely unaffected by this report.

### 4.3 API breaking changes: absorbed by the CLI, not Wholework-relevant

Opus 5 introduces two API-level breaking changes — extended thinking defaults to ON, and combining `thinking: disabled` with `xhigh`/`max` effort now returns a 400. Both are absorbed transparently by the `claude -p` CLI that all `run-*.sh` wrappers invoke; Wholework issues no raw Messages API calls that would need to handle either case directly. What *does* reach Wholework is the effort-calibration guidance shift (§3.2) and the routing/classifier behavior shift (§3.5/§3.6), both addressed in this report's `docs/tech.md` edits.

### 4.4 Deferred implementation work: `#1063` and `#1064`

Two implementation items fall out of this report's analysis but are explicitly out of scope for this Issue, carried by already-filed child Issues:

- **`#1063`** (sub-agent `effort:` frontmatter introduction): today, `agents/review-bug.md`/`review-spec.md`/`issue-scope.md`/`issue-risk.md`/`issue-precedent.md`/`frontend-visual-review.md` inherit effort from their parent orchestrator session rather than setting their own `effort:` frontmatter (confirmed via the Claude Code CLI changelog, also noted in `docs/tech.md`'s `#921` entry). Decoupling sub-agent effort from the parent session is a prerequisite for applying §3.2's Opus-5-specific effort guidance (start `xhigh` for coding/agentic, `high` otherwise, sweep down) at the sub-agent level rather than only at `run-spec.sh`'s own invocation.
- **`#1064`** (`run-spec.sh --opus` effort recalibration): the existing `xhigh` default (set in `#217`) was calibrated against Opus 4.8's guidance ("`xhigh` is the recommended default"). Opus 5's guidance is structurally different (§3.2) — start at `xhigh` for coding/agentic work specifically, which `run-spec.sh --opus` *is*, so `xhigh` may still be correct, but the rationale it was chosen for no longer matches Opus 5's actual guidance and needs its own re-evaluation pass rather than being carried forward unexamined.

## 5. Strategic recommendations

### 5.1 Correct the factual record without touching the matrix table body (P1)

This Issue's own scope: publish this report and update `docs/tech.md`'s note paragraphs (effort calibration, alias resolution, Fable 5 cost/routing, default-parent deferral, watch items) and `agents/review-bug.md`'s cyber-classifier note. Do not touch the matrix table's Model/Effort columns — no component's actual model/effort assignment changes in this Issue; only the descriptive text catches up to what has already been true since 2026-07-24.

### 5.2 Let `#1063` and `#1064` carry the implementation work (P2)

Both are already filed and blocked-by this Issue's parent (`#1062`). Do not pre-empt them here — §4.4 documents why they are separate, appropriately-scoped Issues rather than folded into this factual-correction pass.

### 5.3 Re-evaluate the default-parent deferral only on a concrete trigger, not on a calendar (P2)

Per §4.1, the deferral is not time-boxed. Re-open the Sonnet 5 → Opus 5 default-parent question only if (a) a future Sonnet 5 effort or capability re-evaluation surfaces a genuine quality gap, or (b) Claude Max's Opus-5-as-default status is judged to carry independent weight for Wholework's own default-parent choice — neither condition holds today.

### 5.4 Treat the watch items as monitoring, not action items (P3)

§3.3 (512-token cache floor) and §3.4 (separate rate-limit pool) are recorded in `docs/tech.md` as things to watch, not things to change. Neither has a concrete incident or measured headroom problem behind it yet; acting on either without evidence would repeat the same "adopt before measuring" pattern the alias pin policy already accepts as its known trade-off.

## 6. Impact summary table

| Area | Risk/Opportunity | Priority | Est. Size |
|---|---|---|---|
| `docs/tech.md` factual corrections (effort calibration, alias target, Fable 5 note, cyber classifier) | Closes documentation drift already live since 2026-07-24 | high | M |
| Default parent swap (Sonnet 5 → Opus 5) | Evaluated, deferred — no cost/quality basis today | — (deferred, not filed) | — |
| `#1063` sub-agent effort frontmatter | Decouples sub-agent effort from parent session; prerequisite for applying Opus 5 effort guidance per sub-agent | medium | M |
| `#1064` `run-spec.sh --opus` effort recalibration | Existing `xhigh` default's rationale is stale (Opus 4.8-era guidance); needs its own re-evaluation | medium | M |
| Prompt cache 512-token floor | Favorable for prompts in the 512–1024 token range; monitoring only | low | — |
| Rate limit pool separation | Changes `/auto --batch` Opus sub-agent parallel headroom; monitoring only | low | — |

## 7. Migration checklist

- [x] Publish `docs/reports/claude-opus-5-impact-strategy.md` (this report)
- [x] Update `docs/tech.md`'s effort calibration note for Opus 5 guidance, preserving the Opus 4.8 note for `#922`'s citation
- [x] Fix `docs/tech.md`'s alias-resolution text (Opus 4.8 → Opus 5)
- [x] Update `docs/tech.md`'s Fable 5 paragraph (cost basis, biology routing target)
- [x] Record the default-parent deferral judgment and re-evaluation trigger in `docs/tech.md`
- [x] Record the two Opus 5 watch items (prompt cache floor, rate limit pool) in `docs/tech.md`
- [x] Generalize `agents/review-bug.md`'s cyber classifier note beyond Fable 5
- [ ] Confirm `#1063`/`#1064` remain correctly scoped as this report's own deferred implementation items (both already filed and blocked-by `#1062`)

## 8. Candidate Issues (execution plan)

Both candidate Issues below were already filed at Issue-triage time as `blocked-by` children of this Issue (`#1062`), consistent with the Sonnet 5 report's own C-series precedent.

| # | Title (Japanese) | Priority | Est. Size | Phase impact |
|---|---|---|---|---|
| #1063 | agents: Opus sub-agent に effort frontmatter を導入し親セッション継承から分離する | medium | M | issue, review, verify |
| #1064 | spec: run-spec.sh --opus の effort を Opus 5 指針で再校正する | medium | M | spec |

### Ordering rationale

- **#1063** is the prerequisite: without per-sub-agent `effort:` frontmatter, no Opus-routed sub-agent can apply §3.2's Opus-5-specific effort guidance independently of its parent orchestrator's own effort setting.
- **#1064** can proceed independently of `#1063` — `run-spec.sh --opus` sets its own `--effort` flag directly rather than inheriting from a sub-agent frontmatter, so its recalibration is not blocked by `#1063`'s completion. Both are listed at the same Priority/Size because neither is more urgent than the other; they address different components of the same Opus-5-guidance-adoption gap.
- No C1-equivalent default-parent-swap Issue is filed from this report (contrast with the Sonnet 5 report's `C1`) — §4.1 deferred that question outright rather than sequencing it behind a measurement gate.

## 9. Non-goals

- No default-parent swap (Sonnet 5 → Opus 5) — evaluated and explicitly deferred in §4.1; no Issue filed for it.
- No sub-agent `effort:` frontmatter implementation in this Issue — delegated to `#1063`.
- No `run-spec.sh --opus` effort value change in this Issue — delegated to `#1064`.
- No prompt-side response to Opus 5's behavioral shifts (verbosity-driven output growth, task-scope expansion, over-verification) — out of scope per the parent Issue body; candidates are not even enumerated here since no concrete instance has been observed yet (contrast with `#1063`/`#1064`, which are enumerated because they were already identified and filed).
- No `WATCHDOG_TIMEOUT_SPEC_DEFAULT`-style watchdog recalibration for Opus 5 — handled via a comment on the existing `#939` (that Issue's own default is still undecided, so an Opus 5 addendum belongs there, not in a new Issue).
- No action on the two watch items (§3.3 prompt cache floor, §3.4 rate limit pool) — monitoring only, per §5.4.

## 10. References

- [Introducing Claude Opus 5 (Anthropic, 2026-07-24)](https://www.anthropic.com/news/claude-opus-5)
- [Claude Opus 5 System Card](https://www.anthropic.com/claude-opus-5-system-card)
- `docs/reports/claude-sonnet-5-impact-strategy.md` (companion; default-parent evaluation precedent this report's §4.1 methodology follows)
- `docs/reports/claude-fable-5-impact-strategy.md` (companion; Mythos-tier cyber/biology classifier precedent)
- `docs/tech.md` § Phase-specific model and effort matrix (`ssot_for: model-effort-matrix`, update target for this report's `docs/tech.md` edits)
- Prior reactive-recalibration precedents: `#628` (Fable 5 → Sonnet 4.6), `#903` (Sonnet 5 watchdog recalibration)
- Issue #1062 (this Issue), #1063 (sub-agent effort frontmatter), #1064 (`run-spec.sh --opus` effort recalibration)

---

*This report enumerates `#1063` and `#1064` in §8 — both were already filed as `blocked-by` children of `#1062` at Issue-triage time, not newly proposed here.*
