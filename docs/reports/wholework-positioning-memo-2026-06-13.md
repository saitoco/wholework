English | [日本語](../ja/reports/wholework-positioning-memo-2026-06-13.md)

# Wholework Positioning Memo — 2026-06-13

**Report date**: 2026-06-13
**Author**: User dialogue session (Fable 5 launch/suspension → /auto session-performance analysis → Nuxt→Next preparation)
**Status**: Strategy memo — not a finalized specification; preserves judgment and frozen-item context
**Related reports**:
- `docs/reports/claude-fable-5-impact-strategy.md` (Fable 5 impact analysis)
- `docs/reports/auto-session-performance-2026-06-13.md` (14-issue continuous-run empirical data)
- `docs/reports/workflow-adapter-spike.md` (dynamic-workflow adoption decision)

## 1. Purpose and Scope

This memo preserves the **strategic positioning and frozen-item context** of Wholework as derived from the 2026-06-13 user dialogue. It collects the judgment logic, spectrum framings, and boundary declarations that would otherwise be scattered or lost across Issues and Specs.

In scope:
- Anchor use case where Wholework delivers the most value
- Problem-shape spectrum (Stripe-class fleet / Wholework mid-scale / interactive single-task)
- Five typical migration patterns and their classification
- Complementarity with Managed Agents + Outcomes
- Explicit out-of-scope declarations
- Derived Issue index (#583–#591)
- Icebox candidates with re-evaluation triggers
- Self-revision discipline

Out of scope:
- Implementation specifics of individual issues (delegated to each Issue)
- Benchmark numbers (see `auto-session-performance-2026-06-13.md`)
- Fable 5 migration strategy (see `claude-fable-5-impact-strategy.md`)

## 2. Anchor Use Case — mid-scale modernization

The work band where Wholework delivers the **clearest value**:

| Axis | Range |
|---|---|
| Budget | Up to $10,000 per project |
| Duration | Days to two weeks (10 days is the standard target) |
| Scale | 50–100 PRs per project |
| Concurrency | 5–10 concurrent (local + subscription-auth practical ceiling) |
| Project types | Framework migration, major-version upgrades, test-coverage backfill, library upgrades, CMS migrations (hybrid) |

Concrete examples (the user's actual work domain — large corporate / EC sites):

1. **Nuxt.js → Next.js full replacement** (Pattern B fan-out + foundation phase)
2. **Astro +1 version upgrade** (Pattern A sequential, single L-sized issue)
3. **Rails major +2 + Ruby +1** (Pattern A serial, phase-split)
4. **API test-coverage backfill** (Pattern B pure fan-out)
5. **Contentful → Sanity CMS migration** (Pattern C hybrid: code + data fleet)

Anchor numbers: $10K × 10 days × 5 projects/year × 1 developer = **$50K/year/developer**. An agency running 4–6 projects per year sees $200–300K of budget volume — a commercially meaningful size band.

## 3. Problem-Shape Spectrum

Three distinct problem shapes, each best served by different tooling:

| Shape | Scale | Tool |
|---|---|---|
| **Stripe-class fleet** | 50M LOC in a day / 100+ concurrent / homogeneous transforms / unbounded budget | API-direct fleet infrastructure (built in-house, or Anthropic Managed Agents Outcomes) |
| **Wholework mid-scale** | 50–100 PRs in 10 days / 5–10 concurrent / heterogeneous / governance required / $10K | **Wholework** |
| **Interactive single-task** | 1–5 files / hours / interactive IDE support | Claude Code interactive session, Cursor, etc. |

A hammer is not deficient for not being a saw — these are specializations, not failures.

Over-investing in the Stripe-class direction would break Wholework's moat: subscription-auth ownership disappears, dependence on Anthropic hosting grows, and Wholework becomes a degraded Managed Agents.

### Wholework's moat (governance + verification harness)

The 2026-06-13 `/auto` 14-issue continuous run empirically demonstrated:

- **Self-diagnose / self-repair loop** — problem in `/auto` → retrospective → improvement issue → implemented and closed in the same session, end-to-end **within 10 hours**
- **GitHub-native artifacts** — Issues/PRs/Labels/review threads as the records of work (where teams already live)
- **Subscription / OAuth auth** — `claude -p` runs on the user's subscription (no fleet infrastructure)
- **Incremental adoption** — `/review` only, or `/verify` only, are valid adoption paths
- **Human gates as first-class** — PR review, AC confirmation, retrospectives all incorporate human judgment

The line-by-line alignment between Anthropic's Fable 5 deployment guidance ("give it a memory surface / run a verification harness / state boundaries explicitly") and Wholework's design philosophy is not a coincidence.

## 4. Five Migration Pattern Classification

| Pattern | Characteristic | Examples | Required tools |
|---|---|---|---|
| **A. Sequential upgrade** | Order-dependent, code-only, breaking-change chains | Astro +1, Rails major +N, Ruby +N | Existing Wholework (serial issues + CI verification) |
| **B. Fan-out migration** | Homogeneous transforms parallelizable at page/endpoint level, code-only | Nuxt→Next, API test coverage | XL parallel execution + #589 concurrency cap + #590 progress + #591 bulk creation |
| **C. Hybrid migration** | Code change + external data-fleet job + long-tail observation | CMS migration (Contentful→Sanity, record migration) | Wholework handles code; external script handles data fleet; AC of "script completed + verification passed" captures the result |

Pattern C is where Wholework doesn't complete the work alone. **Wholework acts as the migration project conductor**: it does the code itself, delegates fleet operations to external scripts, and tracks long-tail observation via observation ACs.

## 5. Complementarity with Managed Agents + Outcomes

Anthropic's **Managed Agents + Outcomes** (rubric-grading loop) converges conceptually with parts of Wholework, but the boundary is clear:

| Dimension | Wholework | Managed Agents + Outcomes |
|---|---|---|
| Unit | Issue / PR (many) | Outcome / Session (one) |
| Duration | Days to two weeks | Hours to a day |
| Audit trail | GitHub Issue/PR/Label/retro (durable, public) | Session log (Anthropic-hosted) |
| Auth | Subscription / OAuth | API key |
| Iteration | Human gate + retrospective accumulating per issue | Autonomous rubric grading + revise loop |
| Fit | Heterogeneous, staged, governance-required | Homogeneous, fleet-shaped, single-goal |

These are not competitors — they are **optimized for different time scales and different work shapes**. Pattern C (hybrid CMS migration) is where they can actually coexist: Wholework handles Sanity schema design and frontend rewrites; a Managed Agents Outcome runs the data migration in bulk.

## 6. Explicit Out-of-Scope (Non-Goals)

The following are deliberately **not** Wholework's growth direction:

1. **Fleet-class 100+ concurrent execution** — Managed Agents Outcomes territory; would break the subscription-auth moat
2. **Interactive single-task UI support** — Claude Code interactive sessions / Cursor, etc.
3. **Full CI/CD pipeline replacement** — Wholework uses CI as `/verify` input, does not host its own workflow runner
4. **Monorepo cross-package orchestration** — delegated to package managers (pnpm workspace, etc.)
5. **Mobile app store submission flows** — Wholework is GitHub-centric, delegate to Fastlane and similar external tooling

These are candidates for addition to `docs/product.md § Non-Goals`; this memo declares them in advance.

## 7. Derived Issue Index (filed in the 2026-06-13 session)

### Fable 5 impact-analysis series (#555–#563, #565, #575, #576, #579–#582)

Details in `docs/reports/claude-fable-5-impact-strategy.md` and the individual Issues. All CLOSED in this session.

### `/auto` session-performance analysis series (#583–#588)

| # | Content | Status |
|---|---|---|
| #583 | Introduce `verify-type: observation` classification | OPEN, retro/verify |
| #584 | Systematize triage's AC verify-command audit | OPEN, retro/verify |
| #585 | Phase-specific watchdog timeouts | OPEN, retro/verify |
| #586 | `/code` Tier 0 recovery (auto-fix for test failures) | OPEN, retro/verify |
| #587 | Opus 4.8 parent-session perf spike | OPEN, retro/verify |
| #588 | audit-stats retention metrics (blocked by #583) | OPEN, retro/verify |

### Nuxt→Next pre-launch prerequisites (#589–#591)

| # | Content | Where it takes effect |
|---|---|---|
| #589 | XL sub-issue concurrency cap (`auto-max-concurrent`) | Every run (parallelism safety net) |
| #590 | `/audit progress <XL>` progress snapshot | Throughout the 10-day operation |
| #591 | XL sub-issue bulk creation (YAML → bulk create) | Day one (saves 4–8 hours of typing) |

## 8. Icebox Candidates (frozen, with re-evaluation triggers)

The following improvement candidates were deliberately not filed as active Issues. They will be filed as **Icebox status** Issues in the GitHub Project and managed via re-evaluation triggers:

| Candidate | Freeze rationale | Re-evaluation trigger |
|---|---|---|
| **Migration template set** (`framework-migration.md`, etc.) | Better to build from experience after the first Nuxt→Next run; pre-emptive templates risk misalignment with the field | After Nuxt→Next completion |
| **Full auto-decomposition** (LLM analyzes codebase → YAML auto-generation) | Large implementation; measure whether #591's manual YAML minimum suffices through actual execution | After #591 lands + 1 project's operation |
| **Cost measurement mechanism** | $10K/10 days has post-hoc verification headroom; cost > value | When a budget-tight project appears |
| **Adaptive throttling** (dynamic concurrency adjustment) | Take real data from #589's fixed cap first | After #589 + 1 XL run |
| **External-job primitive** (data-fleet adapter) | Required for Pattern C (CMS migration), unneeded for Pattern A/B | When the Contentful→Sanity project starts |
| **`/auto` child-phase in-session migration** (spawn-and-block → async) | Depends on #587 measurement; re-evaluate after Fable 5 resumes | After #587 conclusion + after Fable 5 resumes |
| **Formal anchor-case addition to `docs/product.md`** | Carries more weight with one project's worth of empirical data behind it | After Nuxt→Next completion |

Conventions for filing Icebox Issues:
- Set Project Status to `Icebox` explicitly (avoid the automatic `Backlog` transition)
- Apply the `retro/verify` label
- Body must include at least three sections: "Freeze rationale", "Re-evaluation trigger", "Origin (link to this memo)"
- Quarterly review (visualize Icebox dwell-time >90 days via `/audit stats` — an application of #588's retention metric)

## 9. Redefining Benchmark Metrics

The Stripe-class "LOC/day" metric does not apply to Wholework's work shape. Wholework's own metrics:

| Metric | Description | 2026-06-13 measured |
|---|---|---|
| **Auditable PRs / day** | Completed PRs that were monitored / verified | ~1.3 PR/h (14 issues / 11h) |
| **Self-improvement-loop closure time** | Problem emergence → improvement issue → consumption | Under 10 hours (#557 → #569) |
| **Triage repair rate** | Fraction where triage caught a verify-command defect | 3/14 = 21% |
| **Autonomous completion rate** | Wrapper completion without parent-session manual intervention | 13/14 = 93% |
| **Observation AC dwell time** | phase/verify dwell-time median (to be visualized in #588) | TBD |

These are the **moat metrics** — what Wholework optimizes for, in its own terms.

## 10. Self-Revision Discipline

This memo will be revised at **milestones**:

- After Nuxt→Next completion: empirical validation of the anchor numbers + Icebox re-evaluation + Pattern B evidence addition
- Quarterly: review Icebox items with >90 days dwell time
- After Fable 5 resumes: in conjunction with removal of the Suspension Notice in `docs/reports/claude-fable-5-impact-strategy.md`, update this memo's boundaries
- On Anthropic new-product release: re-verify boundary declarations against Managed Agents and others

When revising, keep a dated filename (`wholework-positioning-memo-2026-XX-XX.md`). Maintain a diff-readable form so that the logic of past judgments is not lost.

## 11. Derived Next Actions

After committing this memo, execute the following in order:

1. **File 7 Icebox Issues** (the candidates in §8, with links back to this memo as reference)
2. **Add 3 auto-memory entries** (anchor case / problem shape / Icebox index)
3. **Plan Icebox dwell-time visualization in `/audit stats`** to be added as a comment on #588 retention metric

After this commit, the strategic logic of the user dialogue session is redundantly preserved across three persistence channels (report / Issues / memory).

---

*This is a strategy memo. It does not override Steering Documents (`docs/product.md`, etc.) on items where those are SSoT. Confirmed strategy graduates from this memo to a Steering Document; this memo functions as the "pre-graduation judgment-logic storage."*
