# Ultrareview Spike Report: `/review --ultra` Option Evaluation

**Report date**: 2026-04-18
**Author**: Automated spike session (Issue #223)
**Scope**: Evaluate `/ultrareview` (Claude Opus 4.7) as a `--ultra` depth mode for Wholework `/review`
**Status**: Concluded — see Recommendation

---

## Overview

Claude Opus 4.7 introduced `/ultrareview`, a built-in Claude Code command that runs a deep, multi-agent code review in a remote cloud sandbox. This spike evaluates whether Wholework `/review` should expose this capability as a new `--ultra` mode, replacing or augmenting the existing `--full` (3-agent parallel: review-spec/Opus + review-bug×2/Opus with 2-stage verification).

Reference: `docs/reports/claude-opus-4-7-optimization-strategy.md` §2.3, §5.3 #9.

**Research method**: Official documentation fetched via WebFetch from:
- `https://www.anthropic.com/news/claude-opus-4-7`
- `https://code.claude.com/docs/en/commands`
- `https://code.claude.com/docs/en/ultrareview`

---

## Comparison

### `/ultrareview` (built-in command) vs Wholework `/review --full`

| Axis | `/review --full` (Wholework) | `/ultrareview` (built-in) |
|------|------------------------------|---------------------------|
| **Architecture** | 3 Opus agents in parallel (review-spec + review-bug×2) + 2-stage bug verification sub-agents | Fleet of reviewer agents in remote cloud sandbox; each finding independently verified |
| **Duration** | 3–8 min (local, parallel Opus) | 5–10 min (remote background task) |
| **Cost** | Counted toward plan usage (~$1–3 per typical PR at Opus 4.7 pricing) | 3 free runs (one-time, Pro/Max); then $5–20 per review billed as extra usage |
| **Coverage** | Spec deviation + documentation consistency + HIGH SIGNAL bugs + security issues | Bug-focused ("find bugs in your branch or PR") |
| **False-positive reduction** | 2-stage verification via dedicated verification sub-agents | Independent reproduction and verification by the fleet |
| **Invocation** | Automated via `run-review.sh` / `/auto` pipeline | User-invoked only (`/ultrareview`); Claude cannot trigger it automatically |
| **Auth requirement** | Standard Claude Code (API key or subscription) | Claude.ai subscription required; unavailable with API key only, Bedrock, Vertex AI, Foundry |
| **Local resource use** | Uses local Claude Code session resources | Runs entirely remotely; terminal stays free |
| **Configuration** | `--light` / `--full`, `review-bug: false` in `.wholework.yml`, SKIP_REVIEW_BUG | None (PR number only) |
| **Automation compatibility** | Fully automatable (`claude -p` compatible) | Manual-only; requires user confirmation dialog; background task |

### Quality

Official Anthropic documentation characterizes `/ultrareview` as offering:
- "Higher signal: every reported finding is independently reproduced and verified"
- "Broader coverage: many reviewer agents explore the change in parallel"

Wholework `/review --full` already implements:
- Parallel multi-agent detection (3 Opus agents)
- 2-stage verification (review-bug → verification sub-agents) for false-positive filtering

The architectural gap between Wholework's `--full` and `/ultrareview` is therefore narrower than it would be for a simpler single-pass reviewer. The primary unknown is whether the `/ultrareview` fleet size and cloud sandbox isolation produces materially more bug detections on Wholework-style PRs (Markdown/Shell/YAML changes). No benchmark data is available from official documentation; direct comparison would require running both on the same PRs.

### Cost

- Wholework `/review --full`: ~$1–3 per typical PR (3 Opus 4.7 agents; counts against plan usage)
- `/ultrareview`: $5–20 per review as extra usage after free runs (10–20x cost increase)

The cost differential is significant for automated pipelines where reviews run on every PR.

---

## Recommendation

**非採用 (Do not adopt as `--ultra` mode)**

### Primary reason: Automation incompatibility

`/ultrareview` is explicitly user-invoked only — Anthropic documentation states "The command runs only when you invoke it with `/ultrareview`; Claude does not start an ultrareview on its own." This is a fundamental incompatibility with Wholework's `/auto` pipeline, which chains spec→code→review→merge non-interactively via `run-review.sh`. Adding `--ultra` as an automated mode is not technically feasible under the current `/ultrareview` interface.

### Supporting reasons

1. **Cost**: $5–20 per review (extra usage) vs ~$1–3 for `--full`. At 10–20x cost, the quality uplift would need to be substantial and measurable to justify for routine CI/auto runs.

2. **No programmatic API**: `/ultrareview` exposes no flags, configuration, or hooks. Wholework would have no way to pass context (Spec path, steering docs, Issue acceptance criteria) to the remote review fleet — which is exactly the context that makes Wholework's `--full` mode project-aware rather than generic.

3. **Auth restriction**: Wholework supports API-key-only users (e.g., Bedrock, Vertex AI). `/ultrareview` is unavailable in these configurations, making `--ultra` a partial-availability feature that would require conditional logic and user-facing error messages.

4. **Overlapping architecture**: Wholework `--full` already uses parallel Opus agents with independent verification. The architectural advantage of `/ultrareview` is not a novelty for Wholework users — the gap is incremental (fleet size, cloud isolation) rather than categorical.

5. **Spec/context integration**: Wholework's review quality comes from cross-referencing the PR against the Spec, steering documents, and Issue acceptance criteria. `/ultrareview` has no mechanism to inject this project context, making it unsuitable as a drop-in replacement for Wholework's context-aware review.

### Alternative (zero implementation cost)

If users want pre-merge confidence beyond `--full`, Wholework's completion report can mention `/ultrareview` as an optional manual step:

> "For additional pre-merge confidence, run `/ultrareview <PR-number>` in your Claude Code session (Pro/Max, 3 free runs then extra usage)."

This surfaces the feature without any integration work and preserves full automation for `--full`.

### Conditions for re-evaluation

Re-evaluate if:
- Anthropic exposes a programmatic API or CLI flag to trigger `/ultrareview` non-interactively (enabling `/auto` integration)
- Benchmark data shows `/ultrareview` catching substantially more Wholework-relevant bugs than `--full` on Markdown/Shell/YAML PRs
- Cost drops to within 2–3x of `--full` mode

---

## Appendix: Research Notes

**Information confidence**: All `/ultrareview` details sourced from official Anthropic documentation (2026-04-18). The documentation does not disclose the specific model, fleet size, or internal implementation details of the cloud sandbox. The cost range ($5–20) and "5–10 minutes" duration are stated directly in the official docs.

**Tokenizer note**: This spike predates any end-to-end benchmark of Wholework under Opus 4.7 new tokenizer (1.0–1.35× token increase per §2.1 of the optimization strategy). The `--full` cost estimate above may increase by up to 35% under the new tokenizer; this does not change the recommendation.
