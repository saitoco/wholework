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
     `docs/spec/issue-1157-run-fact-ac-match.md` § Uncertainty).
   - The condition text asserts something did **not** happen, and the corresponding signal
     is not one of the five `anomalies` keys (`recovery` / `watchdog_kill` /
     `manual_intervention` / `concurrent_commit_detected` / `code_retry_fire`) — there is no
     general-purpose "nothing happened" fact to check absence-claims against.
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
