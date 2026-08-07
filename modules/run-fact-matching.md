# run-fact-matching

SSoT for the run-fact AC reconciliation mechanism: detecting pending `phase/verify`
post-merge acceptance conditions that a completed `/auto` run has already satisfied.

## Purpose

`/auto`'s existing Event-based observation scan (`modules/observation-trigger.md`) only
matches Issues by **event name** (`verify-type: observation event=<name>`), so it never
reaches `manual`-tagged post-merge AC — the majority (measured 244 of 414) of the
conditions stuck in `phase/verify`. This module defines the complementary mechanism: after
a run completes, structure **what actually happened** (route / Size / phase outcomes / PR
state / anomaly events) as data, and reconcile that data against every pending post-merge
AC's condition text — `manual`, `observation`, `opportunistic`, and `auto` alike — to
detect conditions the run has already satisfied.

The three scripts below split the deterministic parts (fact collection, candidate
enumeration and pre-filtering, tier gating and L0 writes) from the one part that cannot be
made deterministic (matching free-text condition prose against structured facts), so the
non-deterministic part is confined to a single LLM rubric-judgment step that this module's
Processing Steps drive.

## Input

- `AUTO_SESSION_ID` — the current `/auto` session id (held by the calling `/auto` run;
  passed through to `collect-run-facts.sh --session`)
- `AUTONOMY_TIER` — resolved by the caller per `modules/detect-config-markers.md`
  (`autonomy` key in `.wholework.yml`, default `L1`); consumed by
  `apply-run-fact-match.sh`'s tier gate

## Fact JSON Fields (matching-relevant)

Full field definitions live in `scripts/collect-run-facts.sh`'s header comment (SSoT for the
JSON shape). Fields most relevant to Step 3's rubric judgment:

- Top-level `mode`: `batch` | `single` | `unknown` — whether `/auto` was invoked with
  `--batch`, not how many Issues the run actually processed. Resolved from session metadata
  declared by `/auto` first, with an event-based fallback second; `unknown` only when the
  session has no events at all. See `collect-run-facts.sh`'s header comment for the full
  resolution ladder. **Caveat**: the XL sub-issue fan-out path is not `--batch` and therefore
  declares `single` even though it processes multiple Issues (`skills/auto/SKILL.md` Step 1).
  For sessions with no `mode` declaration (e.g. a session started before this field existed),
  the event-based fallback cannot distinguish an XL fan-out from a `--batch` run (`sub_start`
  is emitted by `run-auto-sub.sh` on both paths) — treat a `mode`-dependent condition as
  `ambiguous` rather than trusting `mode` alone when the session predates this field.
- Per-issue `route`: `pr` | `patch` | `operate` | `unknown`. `operate` distinguishes the
  diff-less operate route (`docs/tech.md` § operate route) from a regular patch-route commit
  — both emit `code-patch` phase events, so `route` is the only fact-JSON signal that tells
  them apart. **Caveat**: when `collect-run-facts.sh` is invoked with `--no-github` (used by
  most hermetic bats execution; the operate-route tests instead run without `--no-github`
  against a `gh` mock), the operate-route marker probe is skipped and `route` stays `patch`
  even for an operate-route run.
- Per-issue `recovery_tiers`: sorted unique array of recovery tiers (`1`/`2`/`3`) seen for the
  issue, or `[]` if no recovery event fired. `anomalies.recovery` keeps its existing
  count-only semantics unchanged (additive, backward-compatible).

This same fact JSON (top-level `mode`, per-issue `route` and `recovery_tiers`) is also consumed by
`scripts/opportunistic-search.sh`'s `when=<axis>:<value>` condition check gate, which matches
observation AC dispatch against a single run's context rather than reconciling post-merge AC after
the fact — see `modules/observation-trigger.md` § Condition Check Gate (`when=`).

## fact_tokens Vocabulary and Matching Rule

`fact_tokens` (per-issue array, built by `scripts/collect-run-facts.sh`'s `JQ_PASS2`) is the
pre-filter vocabulary that `scan-pending-ac.sh --facts` and `opportunistic-search.sh --facts`
match against pending AC condition text before this module's Step 3 rubric judgment runs.

**Included token categories:**

- Route: `"<route> route"` (e.g. `"pr route"`, `"patch route"`, `"operate route"`) — omitted
  when route is `unknown`
- Size: `"Size <label>"` (e.g. `"Size S"`, `"Size M"`) — omitted when the Issue's Size could
  not be resolved
- Phase-wrapper script name: the `wrapper_for()`-mapped script for each phase this issue's run
  reached (e.g. `"run-issue.sh"`, `"run-spec.sh"`, `"run-code.sh"`, `"run-review.sh"`,
  `"run-merge.sh"`) — see the "Excluded" list below for what this replaces
- PR number: `"#<N>"`
- Anomaly keys with count ≥ 1: `recovery`, `watchdog_kill`, `manual_intervention`,
  `concurrent_commit_detected`, `code_retry_fire`
- Recovery tier: `"tier <N>"` for each tier (`1`/`2`/`3`) seen in `recovery_tiers`
- Batch mode: `"batch"`, only when the session's top-level `mode` is `batch`

**Deliberately excluded (do not add these back):**

- `"/auto"` — matched 84 of 414 measured pending post-merge AC on its own, making the
  pre-filter a near no-op (`docs/spec/issue-1157-run-fact-ac-match.md` § population)
- `"single"` (the non-batch mode value) — same reason, Issue #1171
- Bare phase names (`issue`, `spec`, `code-pr`, `code-patch`, `review`, `merge`, `verify`) —
  AC condition text almost always mentions the phase name in prose (e.g. "`/verify` を実行した
  とき"), so a bare phase-name token matched nearly every candidate. This was measured most
  starkly on the `opportunistic-search.sh` path, where the skill-name filter already narrows
  candidates to a single phase before the fact-token gate runs: matching that same phase's bare
  name token against the already-narrowed set passes 100% of candidates by construction (13→13,
  session `83694-1786088052`). Removed in Issue #1238; the phase-wrapper script name (e.g.
  `run-issue.sh`) remains as a strictly more specific replacement. `verify` has no
  `wrapper_for()` mapping (`/verify` runs in-session, no `run-verify.sh` wrapper — see
  `docs/tech.md` Fork context table), so a run that only reaches the verify phase contributes no
  token for it at all after this change; this is intentional, not a gap, since the bare `verify`
  token was the token responsible for the 13→13 result above.

**Matching rule** (unchanged by Issue #1238): case-insensitive substring match — a candidate AC
is retained when its condition text contains at least one `fact_tokens` entry as a substring
(both sides lowercased before comparison; see `scripts/scan-pending-ac.sh`'s
`FACT_TOKENS_LOWER` construction and `scripts/opportunistic-search.sh`'s equivalent gate).

**Guidance for AC authors:** because matching is substring-based against this vocabulary, write
post-merge AC condition text in terms of the specific, high-signal facts above (Size, route, PR
number, a named anomaly, a recovery tier) rather than relying on a bare phase name to make a
condition matchable — a bare phase name is no longer part of the vocabulary and will not narrow
the pre-filter. Referencing the phase's wrapper script name (e.g. "`run-code.sh` 実行後") also
works but is a less natural way to write AC prose than referencing the phase's concrete outcome.

## Processing Steps

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/collect-run-facts.sh` (with `--session
   "$AUTO_SESSION_ID"`, and `--issue <N>` for the single-issue route) and save its stdout to
   `.tmp/run-facts-${AUTO_SESSION_ID}.json`.

2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/scan-pending-ac.sh --facts
   .tmp/run-facts-${AUTO_SESSION_ID}.json` to get the candidate AC array. If the array is
   empty, print `Run-fact AC reconciliation: no candidates.` and skip the remaining steps.

3. **Rubric judgment (LLM, one batch judgment covering every candidate):** compare the run
   facts JSON against the candidate AC array and assign each candidate exactly one verdict:
   `satisfied`, `not_satisfied`, or `ambiguous`.

   **`satisfied` is only valid when every sub-condition in the AC's condition text is
   directly readable from a value in the run facts JSON.** A condition text that references
   anything the facts JSON cannot represent must not receive `satisfied`.

   **Fail-safe criteria — return `ambiguous` whenever any of these hold (exhaustive):**
   - The condition text references a fact that has no representation in the run facts JSON.
     Representative case: a condition naming `/review`'s depth (`--full`/`--light`) — the
     facts JSON's `phases` entries carry only a phase name (`review`), never a depth value,
     because `scripts/run-review.sh` sets a fixed `EMIT_PHASE_NAME="review"` regardless of
     depth (see `modules/event-emission.md` Wrapper Coverage Table; confirmed empirically —
     `docs/spec/issue-1157-run-fact-ac-match.md` § Uncertainty). **This no longer applies to
     conditions naming operate route, a specific recovery tier, or batch/single mode** — those
     three axes are now directly readable from `route`, `recovery_tiers`, and top-level `mode`
     respectively (see Fact JSON Fields above), so "no representation in the facts JSON" is not
     a valid `ambiguous` reason for them. Exception: when the facts JSON's `route` is `patch`
     and the condition specifically asserts operate route, still return `ambiguous` if the run
     was collected with `--no-github` (operate detection is skipped in that mode — see the
     `route` caveat above). Step 1 of this module's own Processing Steps never passes
     `--no-github`, so in practice this exception does not apply to run-fact reconciliation —
     `route: patch` is always a direct `not_satisfied` signal for operate-route claims here.
     The exception exists for completeness against direct `collect-run-facts.sh` invocations
     outside this module's pipeline (e.g. ad-hoc debugging), where `--no-github` may be passed.
   - The condition text asserts something did **not** happen, and the corresponding signal
     is not one of the five `anomalies` keys (`recovery` / `watchdog_kill` /
     `manual_intervention` / `concurrent_commit_detected` / `code_retry_fire`) **and not a
     specific recovery tier** — a condition asserting "Tier N recovery did not fire" is
     directly decidable from whether `N` is absent from `recovery_tiers`, so it is not subject
     to this fail-safe branch. Absent a `recovery_tiers`-backed tier claim or one of the five
     `anomalies` keys, there is no general-purpose "nothing happened" fact to check
     absence-claims against.
   - The condition text is a conjunction of multiple sub-conditions and only some of them
     are backed by the facts JSON.
   - Any other case where the judgment is unclear — `ambiguous` is the default when in doubt,
     never `satisfied`.

   `not_satisfied` applies when the facts JSON directly contradicts the condition (e.g. the
   route or phase outcome the condition names did not occur in this run).

4. For each candidate, call:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/apply-run-fact-match.sh --issue <number> --ac <ac_index> \
     --verdict <verdict> --evidence "<one-line fact summary that justified the verdict>"
   ```
   and act on the printed `action=` line: `auto-check` and `advisory` require no further
   action from the caller (the script already performed the checkbox update, the
   audit-trail comment, or the `Recommend:` print). `none` requires no action either.

5. Print a summary line: `Run-fact AC reconciliation: <auto-checked> auto-checked,
   <advisory> advisory, <skipped> not satisfied (candidates: <N>).`

### Why no comment accumulation

`auto-check` checks the AC's checkbox in the same call that posts the audit-trail comment,
so the AC is checked (`- [x]`) by the time `scan-pending-ac.sh` runs on the next `/auto`
completion — it can never become a candidate again. `advisory` never writes to the Issue at
all; it only prints a `Recommend:` line to the terminal. Neither path can repeat the
comment-pileup pattern observed in #1026 (where an unresolvable `config=` gate let the same
notification comment post on every dispatch).

### Marker format

```
<!-- wholework-event: type=run-fact-ac-match phase=run-fact-match issue=<N> ac=<index> verdict=satisfied -->
```

`phase=run-fact-match` is a fixed literal, not a workflow phase name (`spec`/`code`/`review`/
`merge`/`verify`) — the same rationale as `modules/observation-trigger.md`'s
`phase=observation-trigger`: this mechanism runs from `/auto`'s post-completion step, not
from a phase that owns one of the standard phase names, and no existing marker consumer
matches on `phase=` (all match on the `type=` prefix), so this choice does not affect
existing consumption logic.

## Output

- Zero or more Issue checkboxes checked (`action=auto-check`), each with one audit-trail
  comment carrying the `type=run-fact-ac-match` marker
- Zero or more `Recommend: /verify <N> — ...` lines printed to the terminal
  (`action=advisory`) — never written to the Issue
- A summary line reporting the auto-checked / advisory / not-satisfied counts
- `Run-fact AC reconciliation: no candidates.` when step 2 finds no candidates

## Callers (auto-maintained)

| Skill | Path | Notes |
|-------|------|-------|
| auto | `skills/auto/SKILL.md` | Runs after the Event-based observation scan, in both the single-issue and batch routes; best-effort (a script failure prints a warning and `/auto` continues) |
