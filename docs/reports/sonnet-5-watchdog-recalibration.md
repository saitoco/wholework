# Sonnet 5 Watchdog Recalibration: `/code` / `/review` Wall-Clock Measurement

**Report date**: 2026-07-05
**Author**: Automated analysis session (Issue #903)
**Scope**: Measure real `/code` and `/review` phase wall-clock durations under Sonnet 5 (n≥3 each), judge whether `WATCHDOG_TIMEOUT_CODE_DEFAULT` (3600) / `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` (2000) in `scripts/watchdog-defaults.sh` need recalibration, and record the prompt-slimming candidate assessment.
**Depends on**: #878 (`docs/reports/sonnet-5-tokenizer-impact.md`) — established that Sonnet 5's tokenizer maps the same content to ~1.3-1.4× more tokens (raw total-token ratio, p95=1.413), which is the mechanism plausibly narrowing existing wall-clock timeout margins.

## Background

#878 measured *token* ratios via short, single-turn, tool-disabled `claude -p` calls with a pinned model ID (`claude-sonnet-4-6` / `claude-sonnet-5`) — a design well-suited to isolating tokenizer effects but not representative of a full `/code` or `/review` skill invocation's wall-clock time (worktree lifecycle, multi-step tool use, test runs, verify-executor, PR creation, etc.).

**Feasibility check — direct fresh invocation**: Spinning up 3+ dedicated, throwaway `/code` and `/review` invocations purely for wall-clock measurement was considered and rejected: each `/code` run creates a real worktree/branch/commit and each `/review` run posts real PR comments and drives CI, so intentionally manufacturing N idle "for the reading" runs is expensive and produces side effects unrelated to any real Issue. Instead, this report reuses **production wall-clock data already recorded via GitHub's Issue/PR timeline** (`labeled` events for `phase/*` transitions, `gh pr view --json comments` for the automated review-summary comment) for real Issues processed after Sonnet 5's 2026-06-30 launch. This is the log-based approach `#877` (`docs/reports/verify-sonnet-5-remeasurement.md`) used when direct invocation wasn't practical, applied here for the same reason.

**Model-pinning caveat**: `run-code.sh` / `run-review.sh` invoke `--model sonnet` / `ANTHROPIC_MODEL=sonnet` (the CLI alias), not a date-pinned model ID. Unlike #878's explicit pinning, this report cannot directly confirm the alias resolved to Sonnet 5 for every sampled run — it infers this from the run being dated on or after the 2026-06-30 Sonnet 5 launch date, when the `sonnet` alias would be expected to already point at the newest Sonnet release. Treat the results below as representative of "current production `/code`/`/review` wall-clock" rather than a hermetically Sonnet-5-only measurement.

## A. Measurement Method

### Code phase (`/code`)

Duration = timestamp of the `phase/code` label application → timestamp of the next `phase/*` label application (`phase/review` for pr route, `phase/verify` for patch route, which skips review). Each skill sets its *own* phase label at its *own* start (`gh-label-transition.sh` in `/code` Step 4), so this span cleanly brackets one full `/code` invocation (worktree entry through push/PR creation) with no other skill's work included, *provided* the run was not internally retried by the auto-retry-on-fail mechanism (`docs/tech.md` § "code-side auto-retry"). One sample (Issue #882) was excluded because its `events.jsonl` showed two internal silent-no-op retries stacked within the label span, making the raw span not comparable to a single watchdog window; its first (clean, un-retried) invocation, from `events.jsonl`, was used instead where available — see Notes.

Fetched via:
```bash
gh api "repos/saitoco/wholework/issues/<N>/timeline" --paginate \
  --jq '.[] | select(.event=="labeled" and (.label.name|startswith("phase/"))) | "\(.created_at) \(.label.name)"'
```

### Review phase (`/review`)

Duration proxy = PR `createdAt` → timestamp of the automated "Review Response Summary" comment `/review` posts near the end of its run (`gh pr view --json comments,createdAt`). This span overlaps some of `/code`'s own tail (Step 12 retrospective commit + push + worktree exit, which happen after PR creation but are still attributed to `/code`), so it is not a hermetically pure review-only span. It was cross-checked against the one case with a clean `events.jsonl` `phase_start`/`phase_complete` pair for `review` (Issue #882 / PR #889: true span 1160s vs. this proxy's 1120s, a 3.6% difference) — close enough to treat the proxy as a reasonable direct approximation rather than a loose upper bound.

## B. Results

### Code phase samples (n=10)

| Issue | `phase/code` → next label | Duration (s) | % of current timeout (3600s) |
|---|---|---|---|
| #875 | code → review | 822 | 22.8% |
| #861 | code → review | 859 | 23.9% |
| #860 (1st cycle) | code → verify (patch) | 1055 | 29.3% |
| #860 (2nd cycle) | code → review | 922 | 25.6% |
| #897 | code → review | 1097 | 30.5% |
| #853 | code → review | 1240 | 34.4% |
| #857 | code → review | 1331 | 37.0% |
| #893 | code → review | 1539 | 42.8% |
| #906 | code → review | 2375 | 66.0% |
| #902 | code → verify (patch) | 3376 | 93.8% |

Summary: median **1168.5s** (32.5%), **p95 2925.5s (81.3%)**, max **3376s (93.8%)**.

### Review phase samples (n=9)

| Issue / PR | Duration (s) | % of current timeout (2000s) |
|---|---|---|
| #861 / PR872 | 575 | 28.8% |
| #857 / PR874 | 682 | 34.1% |
| #897 / PR905 | 690 | 34.5% |
| #853 / PR873 | 755 | 37.8% |
| #875 / PR879 | 1004 | 50.2% |
| #882 / PR889 (validation sample, clean `events.jsonl` span 1160s) | 1120 | 56.0% |
| #893 / PR901 | 1379 | 69.0% |
| #860 (2nd cycle) / PR884 | 1604 | 80.2% |
| #906 / PR907 | 2003 | **100.2%** |

Summary: median **1004s** (50.2%), **p95 1843.4s (92.2%)**, max **2003s (100.2%)** — the max sample already meets/slightly exceeds the current `WATCHDOG_TIMEOUT_REVIEW_DEFAULT`.

## C. Judgment

Per the Issue's decision criterion: recalibrate when measured wall-clock is **≥80%** of the current timeout (margin <20%); otherwise leave as-is.

- **Code**: p95 (81.3%) and max (93.8%) both exceed the 80% threshold. **Recalibrate.**
- **Review**: p95 (92.2%) and max (100.2%, i.e. a real sample already at/over the current timeout) both clearly exceed the 80% threshold. **Recalibrate.**

Applying a **1.3×** proportional increase (the conservative end of #878's measured 1.3-1.4× tokenizer ratio range, deliberately less aggressive than the 2× precedent in #628 per the Issue's own guidance, to avoid over-inflating timeouts and delaying true-stall detection — Icebox #596):

| Constant | Old | New (×1.3) | New p95 margin | New max margin |
|---|---|---|---|---|
| `WATCHDOG_TIMEOUT_CODE_DEFAULT` | 3600 | **4680** | 2925.5/4680 = 62.5% used (37.5% margin) | 3376/4680 = 72.1% used (27.9% margin) |
| `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` | 2000 | **2600** | 1843.4/2600 = 70.9% used (29.1% margin) | 2003/2600 = 77.0% used (23.0% margin) |

Both constants land back under the 80%-usage / 20%-margin target after the 1.3× adjustment. Implemented in `scripts/watchdog-defaults.sh` and the corresponding `tests/watchdog-defaults.bats` assertion (this Issue).

## D. Prompt Slimming Candidates

### 1. `/audit auto-session` events.jsonl aggregation

Investigation found this is **two distinct code paths**, not one:

- The `/audit auto-session <id>` display subcommand (`skills/audit/SKILL.md` § auto-session Subcommand) generates its `## Metrics` section via `scripts/get-auto-session-report.sh`, a mechanical bash/jq script. The LLM never ingests the raw `events.jsonl` content in this path — it only reads the script's already-aggregated Markdown output. **No slimming needed here**; #878's `audit_events` proxy scenario (raw `events.jsonl` samples up to 64.7KB) does not correspond to a real token cost in this specific display path.
- `/auto`'s own L3 auto-retrospective **"Notable judgment"** step (`skills/auto/SKILL.md`, batch/XL routes) *does* inject the full session-filtered `events.jsonl` content directly into LLM context, for a decision that is entirely mechanical (recovery fired? verify FAIL? commit count ≥3? watchdog kill?). **This is a real, addressable candidate.** Recommendation: replace the raw event-stream injection with a small jq-computed summary (event-type counts + boolean flags) sized independent of session length, since none of the four notable-judgment criteria require reading individual event bodies. Filing this as a follow-up Issue is out of scope for #903 (investigate-and-decide only); the finding is recorded here for that follow-up.

### 2. L/XL parallel investigation sub-agent input (`/issue` Step 12a, `/review` full mode)

`issue-scope` / `issue-risk` / `issue-precedent` (`/issue` Step 12a) and `review-spec` / `review-bug` (`/review` full mode) each receive the full diff and full changed-file contents, not excerpts. **Decision: no slimming.** Scope/risk/precedent assessment and bug detection genuinely depend on complete context — truncating to hunks or summaries risks false negatives (a missed scope boundary or an undetected bug), which is a materially more expensive failure mode than the token savings from excerpting. This applies uniformly across both call sites; no case-by-case difference was found. Revisit only if a future cost audit shows these specific paths dominating budget in practice.

## Notes

- **#882 code-phase exclusion**: `events.jsonl` shows `code-pr` for Issue #882 fired two internal `code_retry_fire` events (silent-no-op auto-retry, `docs/tech.md` § "code-side auto-retry") within the `phase/code`→`phase/review` label span, so the raw ~3902s span is three stacked invocation attempts, not one continuous watchdog window — not comparable to the other single-pass samples. Excluded from the code-phase table above.
- **`docs/reports/` translation-mirror exclusion**: per `docs/translation-workflow.md` § Exclusions (same precedent as #877, #876, #878), this report has no `docs/ja/` counterpart.
- Related: `docs/reports/sonnet-5-tokenizer-impact.md` (#878, tokenizer ratio measurement this report's recalibration decision is based on); `docs/reports/verify-sonnet-5-remeasurement.md` (#877, sibling log-based-cohort precedent); `scripts/watchdog-defaults.sh` (updated constants); `tests/watchdog-defaults.bats` (updated assertion); Issue #628 (Fable 5 → Sonnet 4.6 precedent); Issue #903 (this Issue); Icebox #596 (timeout-inflation vs. stuck-detection-latency tradeoff).
