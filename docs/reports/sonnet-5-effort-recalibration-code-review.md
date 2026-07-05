# Sonnet 5 Effort Recalibration: `run-code.sh` / `run-review.sh`

**Report date**: 2026-07-05
**Issue**: #921 (C2, `docs/reports/claude-sonnet-5-impact-strategy.md` §8)
**Scope**: Re-evaluate whether `run-code.sh` (code phase) / `run-review.sh` (review phase) effort can drop from `high` to `medium` under Sonnet 5's widened effort curve.
**Depends on**: `docs/reports/claude-sonnet-5-impact-strategy.md` §3.3/§4.2 (candidate framing); `docs/reports/sonnet-effort-recalibration.md` (#229, 2026-04-18, Sonnet 4.6 baseline evaluation of the same two scripts).

## Background

C1 (#914, default parent swap to Sonnet 5) landed, making phase-specific effort re-evaluation actionable. The impact strategy report §3.3 argues that Sonnet 5 widens the cost/performance curve for `medium` effort, making it competitive with `high` on tasks that do not require deep reasoning. §4.2 flags `run-code.sh` and `run-review.sh` as `medium` candidates worth re-checking, since both currently carry a fixed `effort: high` in `docs/tech.md` § Phase-specific model and effort matrix.

No quantitative A/B benchmarking harness exists for isolating effort-level impact on a single task (running the same Issue twice, once at each effort level, is not practical in production — it would require duplicate worktrees/branches/PRs for no real deliverable). This report instead follows the Issue's Auto-Resolved Ambiguity Points: combine (a) a qualitative re-evaluation of `#229`'s Sonnet-4.6-era conclusions from the Sonnet 5 lens, and (b) a production-sample check in the style of `#903` (`docs/reports/sonnet-5-watchdog-recalibration.md`).

## Evaluation Method

1. **Re-derive #229's rationale and check whether the model swap invalidates it.** `#229` (2026-04-18) evaluated the same two scripts under Sonnet 4.6 and concluded `high` for both. If the reasons behind that verdict are properties of the *workload* rather than the *model generation*, the verdict should not change simply because the parent model swapped to Sonnet 5.
2. **Verify the sub-agent effort inheritance claim `#229` relies on for `run-review.sh`.** Confirmed both via direct grep of agent frontmatter and via the Claude Code CLI changelog, since this claim is load-bearing for the `run-review.sh` verdict.
3. **Spot-check recent production PRs for evidence of continued non-trivial review findings** (supplementary signal only, not a substitute for #1/#2).

## `run-code.sh` Analysis — Verdict: maintain `high`

`skills/code/SKILL.md` runs as a single agent with no sub-agent fan-out (confirmed via grep — no `Task(subagent_type=...)` calls in the skill body). It executes a 14-step reasoning chain in one continuous session: worktree entry → `phase/ready` precondition check → Spec load → uncertainty resolution → steering-document reference → implementation → test execution → verify-command consistency check → commit/PR creation → retrospective write → worktree exit. `#229` grounded its `high` verdict in this structure: shallow reasoning early in the chain (e.g., a misread Spec constraint, an overlooked steering-doc convention) surfaces as rework several steps later, and the cost of that rework outweighs the per-token savings of a lower effort tier.

The Sonnet 5 effort-curve-widening argument (impact report §3.3) is about tasks that do not require deep reasoning — but the impact report's own §4.2 scopes the `run-code.sh` `medium` candidacy to **XS/S patch-route Issues only**, not the full Issue-size range. `run-code.sh`'s `--effort` flag, however, is a single global CLI setting with no per-Issue-size branching (confirmed via grep of `scripts/run-code.sh` — the `--effort` value is fixed at invocation, not conditioned on the Size fetched in Step 0). Lowering it globally to `medium` would apply the discount uniformly to M/L/XL-route implementation work too, where `#229`'s rework-risk argument is unchanged by the model generation swap — the multi-step chain and lack of sub-agent fan-out are structural properties of the skill, not of Sonnet 4.6 specifically.

A conditional effort tier (e.g., `medium` for XS/S, `high` otherwise) would require exposing an `--effort=` flag override path, which is a materially larger change than a two-way "high vs. medium" judgment — already tracked separately as impact report §8 candidate C5 (Icebox, §5.5). This report does not implement conditional tiering; it evaluates only the current global-flag scope.

## `run-review.sh` Analysis — Verdict: maintain `high`

`skills/review/SKILL.md`'s orchestrator spawns `review-spec` and `review-bug` (both `model: opus`, Step 10.2) as parallel sub-agents, plus a second-stage `general-purpose` verification sub-agent for `review-bug` findings (Step 10.3). None of these `Task(...)` calls set an explicit `effort` parameter.

**Sub-agent effort inheritance — verified**:
- Grepped `agents/review-bug.md`, `agents/review-spec.md`, `agents/review-light.md` frontmatter: all three set only `model:`, none set `effort:`.
- Claude Code CLI changelog (v2.1.198) confirms sub-agents inherit the parent session's extended-thinking/effort configuration by default.
- **Additional finding**: the CLI has supported a per-agent `effort:` frontmatter override since v2.1.78 (skill-level support since v2.1.80) — i.e., decoupling `review-bug`/`review-spec`'s effort from the orchestrator's is technically possible today, but **not adopted** in this repo (`scripts/validate-skill-syntax.py`'s `KNOWN_FIELDS` does not include `effort`, though unknown fields are warning-only, not a hard block).

Given no override is set, `#229`'s "sub-agents inherit orchestrator effort" premise holds as a **current policy choice**, not an immutable constraint — but it is still true today, so downgrading the orchestrator to `medium` would silently reduce `review-bug`/`review-spec` (Opus) reasoning depth too.

**Orchestrator's own reasoning depth — impact report premise found inaccurate**: impact report §4.2 frames review orchestration as "mechanical (deep analysis is delegated to sub-agents)". This does not hold up against the actual skill body: `skills/review/SKILL.md`'s Non-Interactive Mode Behavior (Steps 7.2/7.4/7.6) has the orchestrator itself interpret external review feedback (Copilot / Claude Code Review / CodeRabbit comments) and author fix commits via "model judgment" — reasoning work of the same kind `run-code.sh` performs directly, not pure dispatch/aggregation/posting.

Both findings — undecoupled sub-agent inheritance and the orchestrator's own fix-authoring reasoning — support maintaining `high`.

**Follow-up (out of scope for this Issue)**: a future re-evaluation of `run-review.sh`'s effort should first add explicit `effort: high` frontmatter to `agents/review-bug.md` / `agents/review-spec.md`, decoupling their accuracy from the orchestrator's setting before considering an orchestrator-level downgrade. Not implemented here — it exceeds this Issue's AC scope (docs/tech.md recording + run-*.sh/matrix SSoT consistency) and is better judged as its own Issue, consistent with the impact report's §4.3/Non-goals discipline ("any future swap is a separate, individually-judged Issue").

## Production Evidence (supplementary, not a strict A/B)

Per the Issue's Auto-Resolved Ambiguity Points, a strict same-task medium/high dual-run comparison is not required. As a supplementary signal, in the style of `#903`'s production-sample method:

- **Scope**: 15 PRs merged on or after **2026-06-30** (Sonnet 5 launch date) via `gh pr list --state merged --limit 15`; 8 of the 15 spot-checked via `gh pr view --json comments` for review-finding content.
- **Observations**: PR #901 — 1 MUST finding (required a follow-up fix commit). PR #907 — 1 SHOULD finding. PR #905 — an explicit "no MUST issues" pass record. The remaining 5 sampled PRs showed no MUST/SHOULD markers in the extracted comment text.
- **Reading**: this confirms *the presence of a signal*, not a quantitative measurement of effort necessity. It does show that review continues to surface actionable findings post-Sonnet-5, which is inconsistent with a hypothesis that current reasoning depth carries large surplus margin.
- **Cross-reference**: `#903` already captured code/review wall-clock samples from the same period (code: median 1168.5s = 32.5% of the pre-recalibration 3600s timeout; review: median 1004s = 50.2% of the pre-recalibration 2000s timeout) — non-trivial durations consistent with substantive reasoning work actually taking place.

## Recommendations

| Script | Current | Verdict | Rationale |
|--------|---------|---------|-----------|
| `run-code.sh` | `high` | **Maintain** | `--effort` is a global, Issue-size-independent setting; the impact report's `medium` candidacy is scoped to XS/S patch-route only (§4.2), but the flag cannot express that scoping today. `#229`'s rework-risk argument (14-step single-agent reasoning chain, no sub-agent fan-out) is a structural property of the skill, unchanged by the model swap. |
| `run-review.sh` | `high` | **Maintain** | Orchestrator performs real reasoning work beyond dispatch (Steps 7.2/7.4/7.6 fix-commit authoring), contradicting the impact report's "mechanical" framing. `review-bug`/`review-spec` (Opus) inherit effort from the orchestrator and have no `effort:` override set, so a downgrade would silently reduce their reasoning depth too. |

Both verdicts reconfirm `#229` (`docs/reports/sonnet-effort-recalibration.md`, Sonnet 4.6 baseline) from the Sonnet 5 lens: the underlying justification for `high` in both cases is a structural property of the workload (multi-step reasoning chain with no fan-out for `run-code.sh`; sub-agent inheritance ceiling plus first-party fix-authoring reasoning for `run-review.sh`), not something that shifts when the parent model generation changes. No changes are made to `run-code.sh`, `run-review.sh`, or the `docs/tech.md` matrix table itself — this Issue records the verdict as a prose note (see `docs/tech.md` § Phase-specific model and effort matrix).

## Notes

- **Out of scope**: `run-spec.sh` (C3) and `run-issue.sh` (C4) are separate impact-report §8 candidates, evaluated independently. `--effort=` flag exposure for per-Issue-size conditional tiering (C5) is a separate, larger Icebox candidate (§5.5) — not this Issue's two-way judgment. Adding explicit `effort:` frontmatter to `agents/review-bug.md`/`agents/review-spec.md` is recorded above as a follow-up precondition for any *future* `run-review.sh` re-evaluation, not implemented in this Issue's Changed Files.
- **bats**: no update needed — the verdict is "maintain both" (no `run-*.sh` value changes), and neither `tests/run-code.bats` nor `tests/run-review.bats` currently asserts on the `--effort` value (grep-confirmed; both only capture the `--model` flag).
- **Translation mirror**: per `docs/translation-workflow.md` § Exclusions, `docs/reports/` is excluded from `docs/ja/` sync (same precedent as `#229`, `#903`) — no `docs/ja/reports/` mirror is created for this file. The `docs/tech.md` note this report supports *is* mirrored to `docs/ja/tech.md` (in scope for this Issue).
- Related: `docs/reports/sonnet-effort-recalibration.md` (#229, Sonnet 4.6 baseline for the same two scripts); `docs/reports/sonnet-5-watchdog-recalibration.md` (#903, production-sample method precedent and code/review wall-clock cross-reference); `docs/reports/claude-sonnet-5-impact-strategy.md` (§3.3/§4.2/§8, candidate framing); Issue #914 (C1, default parent swap prerequisite).
