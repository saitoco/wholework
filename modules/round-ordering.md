# round-ordering

Shared module for reordering `/auto --batch --until <query>` Round `ROUND_LIST` so that related
Issues are processed adjacently and high-ROI Issues are processed first.

## Purpose

`resolve-batch-query.sh` returns `ROUND_LIST` in a mechanical order (ascending Issue number).
When related Issues (e.g. two Issues touching the same script/module, or one that blocks the
other's fix) land far apart in that order, per-round processing risks rework, duplicate edits,
or merge conflicts. This module combines three signals — ROI (Value/Size), title prefix
clustering, and semantic relationship judgment — into a single reordering of `ROUND_LIST`.

This module does not replace the existing blocked-by gate (List mode step 4) — see
"Relationship to the blocked-by gate" below.

## Input

- `ROUND_LIST`: space-separated Issue numbers, as recorded by `skills/auto/SKILL.md` Until mode
  step 6, immediately after `resolve-batch-query.sh` resolves the query and before
  `auto-checkpoint.sh write_batch` persists it.

## Processing Steps

### Signal 1 + 2 (mechanical): ROI and title prefix clustering

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/compute-round-order.sh "$ROUND_LIST"` and capture its
   output — one `<number><TAB><size><TAB><value><TAB><roi><TAB><title>` line per Issue, in
   input order. This gives each Issue's `roi` (Value/Size, neutral 1.00 when either is unset)
   and `title`.
2. For each Issue, extract a title prefix: the text before the first `:` in the title, only if
   that `:` occurs within the first 40 characters of the title. Issues with no such `:` have no
   prefix (each becomes its own singleton candidate cluster).
3. Group Issues sharing an identical, non-empty prefix into the same cluster. Issues with no
   prefix, or a prefix unique to them within `ROUND_LIST`, remain singleton clusters at this
   stage.

### Signal 3 (semantic, LLM judgment)

4. For each singleton cluster from step 3, read the Issue body of every other Issue still in
   `ROUND_LIST` (`gh issue view $NUMBER --json body`) and look for:
   - shared file/script/module names mentioned in both bodies (e.g. both reference
     `scripts/foo.sh` or `modules/bar.md`)
   - explicit cross-references (e.g. "See #N", "Related: #N", "depends on #N")
5. When such a relationship is found between a singleton and another Issue (singleton or
   already-clustered), merge the singleton into that Issue's cluster. Judgment is scoped to
   `ROUND_LIST` members only — do not expand the search to Issues outside the current round.

### Combination (`cluster-first`)

6. Once clustering (steps 1–5) is final, order clusters by their **representative value**,
   defined as the maximum `roi` among the cluster's members, in descending order.
7. Within a cluster, order members by their own `roi` in descending order; break ties by
   ascending Issue number (the same tiebreak `resolve-batch-query.sh` itself uses).
8. Flatten the ordered clusters into a single Issue number sequence. This flattened sequence is
   the reordered `ROUND_LIST` — replace the input `ROUND_LIST` with it before it is passed to
   `auto-checkpoint.sh write_batch` and per-round List mode processing.

`cluster-first` means clustering is resolved completely before ROI ordering is applied: cluster
membership is never broken to interleave a higher-roi Issue from a different cluster in between
a cluster's own members. This keeps related Issues adjacent unconditionally, with ROI acting
only as the tiebreaker for cluster *order*, not cluster *membership*.

## Relationship to the blocked-by gate

This reordering step does not replace, weaken, or duplicate the existing blocked-by gate (List
mode step 4 of `skills/auto/SKILL.md`, run per-Issue during round processing). The two operate
at different levels:

- **This module (reordering)**: chooses a *desirable processing order* among Issues that are all
  independently processable this round. It never blocks an Issue from being processed.
- **The blocked-by gate**: enforces a *hard dependency* — an Issue with an open blocker is
  skipped for this round regardless of where reordering placed it in the sequence.

Reordering runs once, before the round's per-Issue loop begins; the blocked-by gate still runs
per-Issue, in the reordered sequence, exactly as it does today. An Issue that reordering placed
early but that the blocked-by gate skips is handled the same way List mode already handles any
blocked-by skip (not added to `PROCESSED`, eligible for re-evaluation next round).

## Confirming real-world effectiveness

To confirm this reordering functions as intended during a real `--until` run:

1. After the run, inspect the actual per-round processing order via
   `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh read_batch "$BATCH_ID"` (while the batch is
   still active) or the session transcript / `docs/sessions/*/events.jsonl` (after completion)
   for the order Issues were dispatched to List mode processing within each round.
2. Separately run `${CLAUDE_PLUGIN_ROOT}/scripts/compute-round-order.sh "$ROUND_LIST"` (using the
   same `ROUND_LIST` the round started with, recoverable from the checkpoint or session record)
   to get each Issue's `roi` and `title`.
3. Cross-reference the two: for Issues with a shared or related title prefix, confirm they
   appear adjacently in the actual processing order from step 1. For the highest-`roi` cluster
   from step 2, confirm its members were processed before lower-`roi` clusters.
4. If either check fails for a given round, treat it as a signal to re-examine this module's
   clustering/combination logic (steps above) rather than assuming the round-to-round variance is
   expected — file a follow-up Issue with the specific `ROUND_LIST`, expected order, and actual
   order observed.

## Output

- `ROUND_LIST` (reordered): the same set of Issue numbers as the input, in cluster-first order.
  No Issue is added or removed — this is a pure reordering.

## Notes

- This module's script dependency (`compute-round-order.sh`) performs only mechanical
  data-gathering and ROI arithmetic (bash 3.2+ compatible, no associative arrays). Clustering and
  ordering decisions are LLM-driven steps in this module, not the script — bash 3.2 (macOS
  default) has no associative arrays, which clustering needs (grouping issue numbers by a
  dynamically-discovered key).
- There is no dedicated Value-reading script (`get-issue-size.sh`/`get-issue-priority.sh` have
  Size/Priority counterparts, but Value's only existing implementation was a write path via
  `gh-graphql.sh`'s batch mutation, read individually inside `/triage`). `compute-round-order.sh`
  defines its own single-round-trip query for title+Size+Value together, following
  `get-issue-size.sh`'s Project-field-first, label-fallback-second priority.

## Callers (auto-maintained)

| Skill | Path | Call site |
|-------|------|-----------|
| auto | `skills/auto/SKILL.md` | Until mode step 6, between recording `ROUND_LIST` and `auto-checkpoint.sh write_batch` |
