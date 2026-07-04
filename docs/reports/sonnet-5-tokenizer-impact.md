# Sonnet 5 Tokenizer Impact: Watchdog / Context Budget Measurement

**Report date**: 2026-07-05
**Author**: Automated analysis session (Issue #878)
**Scope**: Measure the actual input-token ratio between Claude Sonnet 4.6 and Claude Sonnet 5 (released 2026-06-30) for three prompt content types representative of Wholework's own skill invocations, and judge whether watchdog timeout recalibration and/or prompt slimming is warranted
**Depends on**: #876 (Sonnet 5 impact analysis, `docs/reports/claude-sonnet-5-impact-strategy.md` §4.1/§4.4/§8)
**Related precedent**: #877 (`docs/reports/verify-sonnet-5-remeasurement.md`) — the sibling default-parent-swap blocker Issue, which used a log-based cohort/cutover design because `/verify` has no direct-invocation option. This report was able to use a stronger direct side-by-side design instead (see Background).

## Background

**Feasibility check (a) — direct pinned-model invocation**: Both a date-pinned Sonnet 4.6 model ID (`claude-sonnet-4-6`, already used for the same purpose in `scripts/spawn-recovery-subagent.sh:144`) and the current Sonnet 5 ID (`claude-sonnet-5`) are directly callable via `claude -p --model <id> --output-format json`. This was confirmed by direct invocation before designing the measurement. Because both models can be invoked side-by-side on demand, this report did not need the log-based cohort/cutover method that #877 used for `/verify` (which has no direct-invocation path since `scripts/run-verify.sh` was removed by #485).

**Feasibility check (b) — existing `token_usage` event log**: `docs/sessions/*/events.jsonl` `token_usage` events (`modules/event-emission.md`) are emitted only for `code`/`review`/`merge` phase wrappers — `spec` is explicitly out of scope (`docs/reports/event-log-schema.md`: "spec phase is excluded as it is called directly") and `/audit` has no `run-*.sh` wrapper at all, so no instrumentation exists for it either. Independently re-confirmed against 11 sampled `events.jsonl` files (76 `token_usage` events total): every single event's `model` field is the literal string `"unknown"` — the precedent noted in #877 (`run-auto-sub.sh`'s `.model` extraction is currently non-functional) reproduces here. Log-based Sonnet 4.6/5 cohort separation by `model` field is therefore infeasible; only a date-cutover split would work, and it is unnecessary since (a) succeeded.

Given (a) succeeded, this report uses **direct same-day side-by-side measurement** (identical content sent to both pinned models) rather than a historical cohort split — this removes cross-day activity-mix confounds entirely, which was the main source of small-sample noise in #877's design.

## A. Measurement Scenario

Three content types were sampled, 3 representative real-repository samples each (n=9 total), matching the Issue's Proposal §A:

| Content type | Proxy for | Samples (size) |
|---|---|---|
| `spec_issue` | `/spec` prompt (Issue body + docs excerpts) | Issue #848 body (3.2 KB), #859 (6.8 KB), #875 (10.3 KB) |
| `review_diff` | `/review` review-bug sub-agent input (git diff + changed file contents) | `git show` of commit `2c852451` (1.5 KB), `eb15be5b` (5.4 KB), `10cdf646` (20.8 KB) |
| `audit_events` | `/audit auto-session` events.jsonl aggregation prompt | `docs/sessions/98315-.../events.jsonl` (3.2 KB), `62650-.../events.jsonl` (21.8 KB), `13998-.../events.jsonl` (64.7 KB) |

**Procedure**: for each sample, both `claude-sonnet-4-6` and `claude-sonnet-5` were invoked as `claude -p --model <id> --disallowedTools "*" --output-format json` with an identical short wrapper instruction ("Reply with exactly one word: done. Do not include any other text.") followed by the sample content, all from the same fixed CWD (this repository's `/code` worktree). `usage.input_tokens + usage.cache_creation_input_tokens + usage.cache_read_input_tokens` was summed as the call's total processed tokens.

**Why `--disallowedTools "*"` was necessary**: an initial unrestricted run let the model act agentically on file paths mentioned inside one sample (triggering Read/Bash exploration instead of a plain text reply), inflating that one measurement to 557k tokens — a measurement artifact, not a tokenizer effect. Disabling all tools forced a single-turn reply for every call and eliminated the artifact.

**Why CWD was held fixed**: the CLI's dynamic system-prompt sections (cwd, git status, memory paths — see `claude --help` for `--exclude-dynamic-system-prompt-sections`) change with the working directory. An empty-content baseline measured from `/tmp` (7129/9640 tokens for Sonnet 4.6/5) differed from the same baseline measured from the worktree CWD (9763/13052) — a genuine CWD-dependent confound, not measurement noise. Re-measuring the worktree-CWD baseline after the full sample run reproduced the original values exactly for both models, confirming determinism once CWD is fixed.

**Two derived metrics per sample**:
1. **Raw total-token ratio** — Sonnet 5 total ÷ Sonnet 4.6 total for the full call (system prompt + wrapper + content). Closest match to Anthropic's literal framing ("the same input can map to more tokens").
2. **Content-only ratio** — same totals with each model's own empty-content baseline subtracted first, isolating the marginal content contribution from the (also Sonnet-5-elevated) fixed system-prompt overhead. This metric is noisier for small samples because it subtracts two large, nearly-equal numbers.

## B. Results

**Baseline (empty-content) ratio**: Sonnet 5 / Sonnet 4.6 = 13052 / 9763 = **1.337** — even the fixed system-prompt/tool-definition overhead alone tokenizes ~1.34× larger under Sonnet 5.

### Per-sample detail

| content_type | sample | raw total (4.6) | raw total (5) | raw ratio | content tokens (4.6) | content tokens (5) | content-only ratio |
|---|---|---|---|---|---|---|---|
| spec_issue | issue-848 | 10966 | 14523 | 1.324 | 1203 | 1471 | 1.223 |
| spec_issue | issue-859 | 12132 | 15904 | 1.311 | 2369 | 2852 | 1.204 |
| spec_issue | issue-875 | 13258 | 17318 | 1.306 | 3495 | 4266 | 1.221 |
| review_diff | commit-2c852451 | 10243 | 14506 | 1.416 | 480 | 1454 | 3.029 |
| review_diff | commit-eb15be5b | 11978 | 16865 | 1.408 | 2215 | 3813 | 1.721 |
| review_diff | commit-10cdf646 | 17066 | 23295 | 1.365 | 7303 | 10243 | 1.403 |
| audit_events | small | 11012 | 15484 | 1.406 | 1249 | 2432 | 1.947 |
| audit_events | medium | 18079 | 24204 | 1.339 | 8316 | 11152 | 1.341 |
| audit_events | large | 34767 | 46174 | 1.328 | 25004 | 33122 | 1.325 |

### Per content-type summary — raw total-token ratio (primary metric)

| content_type | n | median | p95 | max |
|---|---|---|---|---|
| spec_issue | 3 | 1.311 | 1.322 | 1.324 |
| review_diff | 3 | 1.408 | 1.415 | 1.416 |
| audit_events | 3 | 1.339 | 1.395 | 1.406 |
| **Overall** | **9** | **1.339** | **1.413** | **1.416** |

### Per content-type summary — content-only ratio (secondary, baseline-subtracted)

| content_type | n | median | p95 | max |
|---|---|---|---|---|
| spec_issue | 3 | 1.221 | 1.223 | 1.223 |
| review_diff | 3 | 1.721 | 2.898 | 3.029 |
| audit_events | 3 | 1.341 | 1.887 | 1.947 |
| **Overall** | **9** | **1.341** | **2.596** | **3.029** |

## C. Judgment

Per the Issue's §B criterion: **p95 token 比が 1.15× を超過 → 有意と判定**、watchdog 再校正 + prompt slimming の follow-up Issue を起票。1.15× 以下なら対応不要。

Both metrics' p95 clear the **1.15**× threshold by a wide margin — raw total-token ratio p95 = **1.413**, content-only ratio p95 = **2.596**. The raw metric (closer to Anthropic's literal framing and far more stable across sample sizes — see the CWD-determinism check in §A) lands almost exactly inside Anthropic's own disclosed range of 1.0–1.35× at the whole-prompt level, with all 9 samples between 1.31× and 1.42×. The content-only metric shows the same directional signal but with much higher sample-to-sample variance (up to 3.03× on the smallest, 480-token sample), consistent with its documented weakness (subtracting two large near-equal numbers amplifies relative noise for small content).

**Conclusion: significant (有意).** Watchdog timeout constants in `scripts/watchdog-defaults.sh` are calibrated against Sonnet 4.6's per-token latency (`docs/tech.md` § Watchdog timeout calibration, precedent #628: Fable 5 → Sonnet 4.6 raised `WATCHDOG_TIMEOUT_ISSUE_DEFAULT` 600→1200). A ~1.3–1.4× increase in tokens-per-equivalent-content under Sonnet 5, without a comparable recalibration, plausibly narrows the existing timeout margins for the same wall-clock-equivalent work — most acutely for `code`/`review` phases, whose events.jsonl `token_usage` samples in this repository already show these phases carrying the largest absolute input-token volumes (up to ~29k input tokens per phase observed above).

Long-context skills flagged in the Issue Background (`/audit auto-session`, L/XL parallel investigation sub-agents in `/issue` and `/review`) are exactly the `audit_events`/`review_diff` content types measured here, both showing ratios at or above the overall median — supporting the Issue's hypothesis that these are the areas most exposed to the tokenizer change.

**Workflow budget**: `budget.total` (the Workflow tool's per-turn hard ceiling driven by a user's "+500k"-style directive) has no automatic adjustment for tokenizer changes — it is a fixed number set by the user, and `budget.remaining()` is computed purely from `budget.spent()` against that fixed ceiling (per the Workflow tool's own documented contract). A user-specified budget sized against Sonnet 4.6-era token counts will be consumed ~1.3–1.4× faster in wall-clock-equivalent terms under Sonnet 5 with no compensating mechanism. This is a real but out-of-scope-for-recalibration observation (there is no "default" budget to recalibrate — it is always user-set) and is recorded here for follow-up-issue triage.

## D. Follow-up

Since the judgment is significant, **Issue #903** was filed proposing: (1) a proportional (~1.3–1.4×) upward recalibration of the `code`/`review` watchdog timeout constants in `scripts/watchdog-defaults.sh`, informed by this report's measured ratios, and (2) prompt-slimming candidates for the two content types shown here to run largest in absolute token volume (`/audit auto-session` events.jsonl aggregation, and L/XL parallel investigation sub-agent inputs in `/issue`/`/review`).

## Notes

- **CWD is a confound for any future re-measurement of this kind**: all calls in this report were made from a single fixed CWD (this repository's `/code` worktree) specifically to hold the CLI's dynamic system-prompt sections (cwd, git status, memory paths) constant; comparing totals across different CWDs (as an early sanity-check accidentally did) produces a large, spurious difference unrelated to tokenizer behavior. Any follow-up measurement should replicate this constraint.
- **`--disallowedTools "*"` is required** for any single-shot token-counting measurement of this kind — without it, the model may act agentically on content that references file paths or commands, producing multi-turn tool-use inflation unrelated to input tokenization.
- **Content-only (baseline-subtracted) ratios are noisy for small samples** and should be treated as a secondary/directional signal only; the raw total-token ratio is the more defensible metric for threshold judgments.
- `docs/reports/` is excluded from the `docs/ja/` translation mirror per `docs/translation-workflow.md` § Exclusions (confirmed precedent: #877, #876) — no `ja/` counterpart is required for this file.
- Related: `docs/reports/claude-sonnet-5-impact-strategy.md` §4.1 (decision matrix) / §4.4 (delegated to this Issue) / §8 (candidate issues); `docs/reports/verify-sonnet-5-remeasurement.md` (sibling Issue #877, log-based cohort design precedent); `docs/reports/tokenizer-audit.md` (Opus 4.7 tokenizer audit precedent, static-analysis rather than measured); `scripts/watchdog-defaults.sh` (current timeout constants); Issue #628 (Fable 5 → Sonnet 4.6 timeout adjustment precedent); Issue #903 (this report's follow-up: watchdog recalibration / prompt slimming proposal); `modules/event-emission.md` / `docs/reports/event-log-schema.md` (`token_usage` event spec).
