# observation-trigger

Design specification for the observation AC trigger mechanism.

## Purpose

`verify-type: observation event=<name>` ACs are not verified during a normal `/verify` run **until the specified event has fired**. Once the event has fired (a detection comment has been posted on the Issue), the condition is evaluated during the next normal `/verify` run per `skills/verify/SKILL.md` Step 8c — it is no longer SKIPPED at that point.
This module documents the trigger interface: who calls the trigger, with what arguments, and what the output contract is.

The actual dispatch is handled by `scripts/opportunistic-search.sh --event <name>`, which:
1. Fetches Issues in `phase/verify` (closed)
2. Finds unchecked ACs tagged `verify-type: observation event=<name>`
3. Returns a JSON array of matched Issues and conditions for the caller to act on

## Trigger Interface

### Caller → `opportunistic-search.sh --event`

Each emitter calls the following command when its event fires:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh" --event <event-name>
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `--event <event-name>` | Required. The event name from the table in `modules/verify-classifier.md § observation Type` |
| `--dry-run` | Optional. Skip API calls; return empty array (for testing) |
| `--context-file <path>` | Optional. Gates matches carrying a `keyword=` AC attribute against this file's content. See § Condition Check Gate below |

**Output (stdout):** JSON array

```json
[
  { "number": 123, "condition": "condition text with HTML comments stripped" },
  { "number": 456, "condition": "another condition" }
]
```

Empty array `[]` when no matching ACs are found.

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Success (including empty result) |
| `1` | Argument error or unknown event with no fallback skill name |

### Emitter Responsibilities

Each emitter is responsible for:

1. **Calling `opportunistic-search.sh --event <name>`** after the triggering action completes
2. **Processing the returned JSON array** — for each entry, run `/verify <number>` or post a comment
3. **Handling errors** — if `opportunistic-search.sh` exits non-zero or returns invalid JSON, log a warning and continue (do not abort the emitting skill)

### Emitter Lookup Table

| Emitter | Where called | Event fired |
|---------|-------------|-------------|
| `/review` skill | Opportunistic Verification step (after Step completion) | `pr-review-full` or `pr-review-light` depending on `REVIEW_DEPTH` |
| `/auto` skill | Post-completion event scan (after Completion Report) | `auto-run` |
| `scripts/claude-watchdog.sh` | Watchdog kill handler (`_auto_emit_watchdog_kill`) | `watchdog-kill` |
| `/verify` skill | FAIL → reopen → fix-cycle detection | `fix-cycle` (implemented in #656) |

## Output Processing Contract

After calling `opportunistic-search.sh --event <name>`, the emitter receives a JSON array.
The standard processing contract is:

```
for each entry in result:
  if entry.number is in phase/verify (closed) AND condition is still unchecked:
    dispatch /verify <entry.number>  (or post a shell comment if /verify is unavailable)
  else:
    skip silently
```

In shell contexts where `/verify` cannot be spawned (e.g., inside `claude-watchdog.sh`):
- Post a comment to the Issue noting the event was observed
- Recommend the user re-run `/verify <number>` to update the checkbox

## `scripts/observation-trigger.sh` (実装済み #656; stdout output added in #897; idempotency guard added in #1099)

A dedicated dispatch script (`scripts/observation-trigger.sh`) encapsulates the
processing contract above, making emitter integration a one-liner:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/observation-trigger.sh" --event <event-name>
```

The script calls `opportunistic-search.sh --event <name>`, and for each matched Issue
posts a comment recommending the user re-run `/verify <N>` (comment-posting side effect,
subject to an idempotency guard: if a `type=observation-trigger` marker for the same
`event=<name>` was already posted to that Issue within the last 24 hours, the comment is
skipped). It also prints the matched Issue numbers (newline-separated, one per line;
empty output when no matches) to stdout — skipped Issues are included in this list just
like posted ones, so callers with a dispatch mechanism can act on the result directly
instead of relying on the human reading the comment.

### Idempotency guard marker format

Each posted comment carries a machine-readable marker following
`modules/l0-surfaces.md` § "Machine-Readable Event Marker" base fields (`type`/`phase`/`issue`),
with `event` appended as an additional attribute (the same pattern used by
`type=verify-fail`'s `deferral=true reason=...`):

```
<!-- wholework-event: type=observation-trigger phase=observation-trigger issue=<N> event=<name> -->
```

`phase=observation-trigger` is a fixed literal rather than a workflow phase name
(`spec`/`code`/`review`/`merge`/`verify`): the script is invoked from multiple distinct
phases (`/auto`, `/review`, `/verify`'s fix-cycle, `scripts/claude-watchdog.sh`) with no
`--phase` argument and no reliable way to know the caller's actual phase, so the script
uses its own identifier instead. All existing `wholework-event` marker consumers match on
the `type=` prefix, not on `phase=` values, so this choice does not affect existing
consumption logic. Before posting, the script checks for the latest such marker on the
target Issue and skips the comment if its `createdAt` is less than 86400 seconds (24
hours) old.

**Concurrency limitation**: the guard's check-then-post is not atomic — it reads existing
markers via `gh issue view`, then later posts a comment if none is found. If two
invocations for the same `event`/Issue run truly concurrently, both can pass the marker
check before either posts, so duplicate comments are still possible under that pattern.
The guard fixes the sequential re-run case (the one observed in the reference incident,
session `25766-1785288928`); it does not provide full mutual exclusion across concurrent
callers.

**Who invokes `/verify` (since #897):** `observation-trigger.sh` itself never
invokes `/verify` — it only posts the comment and prints the matched numbers. Whether
those numbers are turned into an actual `/verify` call is the calling emitter's
responsibility:

- **LLM-session emitters** (`/auto`, `/review`) capture stdout and, when `AUTONOMY_TIER`
  is `L2`/`L3` (via `modules/detect-config-markers.md`), dispatch
  `Skill(skill="wholework:verify", args="$N")` for each matched number (excluding the
  Issue the current phase just processed). At `L1`, dispatch is skipped and the posted
  comment remains the only signal (advisory-only, matching the `L1` semantics in
  `modules/autonomy-tier.md`).
  - **`/auto` dispatch cap (#952)**: `/auto`'s single-issue and batch Event-based observation
    scan steps additionally cap active dispatch to the first `OBSERVATION_DISPATCH_THRESHOLD`
    matched numbers per run (`observation-dispatch-threshold` in `.wholework.yml`, default `5`;
    see `modules/detect-config-markers.md`). `observation-trigger.sh`'s stdout is already
    ascending-sorted by Issue number (`sort -un`), so the cap naturally prioritizes the
    longest-waiting Issue first. Numbers beyond the cap are not lost: the notification comment
    above is posted to every matched Issue regardless of the cap (subject to the idempotency
    guard described above — see "Idempotency guard marker format"), and because
    `opportunistic-search.sh` re-scans all unchecked `event=auto-run` observation ACs on every
    invocation with no already-notified state, deferred Issues are re-matched (and re-attempted,
    cap permitting) on the next `auto-run` event — a stateless, rolling form of deferred coverage.
    `/review`'s Event-based observation scan (`event=pr-review-full`/`pr-review-light`) is not
    capped: it is a structurally separate emitter/event population with no `--batch`-style volume
    multiplier and no evidence of the same fan-out pattern.
- **`scripts/claude-watchdog.sh`** (shell-only context, no `Skill` tool available) does
  not capture or act on stdout — its existing comment-posting-only fallback is
  unaffected by this change.

## Condition Check Gate (`keyword=`)

Problem: an `event=<name>` fires for *any* completion of the triggering action, regardless of
whether the specific Issue's condition actually applies. Issue #794 observed `event=pr-review-full`
fire 8 times over a week, 7 of which resolved SKIP because the reviewed Spec had no `enum`
definition — each SKIP still cost a full `/verify` dispatch round-trip.

The gate adds an optional `keyword=<text>` attribute to the observation AC tag:

```
<!-- verify-type: observation event=pr-review-full keyword=enum -->
```

When the emitter also passes `--context-file <path>` (e.g., the Spec file for the review that
just completed), `opportunistic-search.sh`/`observation-trigger.sh` only include Issues whose
matched AC line carries a `keyword=` value found in that file's content (case-insensitive
substring match via `grep -qi`). ACs without `keyword=`, or invocations without
`--context-file`, match unconditionally — the existing behavior is preserved.

**Arguments table addition (both scripts):**

| Argument | Description |
|----------|-------------|
| `--context-file <path>` | Optional. Path to a file whose content is checked against each matched AC's `keyword=` value. If the path does not exist, the gate is disabled (falls back to unconditional match) and a warning is printed to stderr. `observation-trigger.sh` forwards this argument as-is to `opportunistic-search.sh`. |

**Matching specification:**

- Extraction: `keyword=<value>` is read from the AC line via `grep -oE 'keyword=[^ >]+'` (stops at the next space or `-->`).
- Comparison: case-insensitive substring match of `<value>` against `--context-file`'s full content (`grep -qi -- "$KEYWORD" "$CONTEXT_FILE"`).
- Gate disabled (unconditional match) when: no `keyword=` attribute on the AC line, no `--context-file` given, or the given path does not exist.
- No semantic/LLM judgment is performed here — this is a lightweight pre-filter; the actual acceptance decision still belongs to `/verify`.

This is a lighter-weight alternative to adding a new fine-grained event name for every condition
pattern (see the `KNOWN_EVENTS` addition steps below) — it reuses the existing grep-based
event-matching mechanism instead of growing the event namespace combinatorially.

## Condition Check Gate (`config=`)

Problem: an `event=<name>` fires for any completion of the triggering action, even when the
Issue's observation condition depends on a specific project-local `.wholework.yml` setting.
If that setting is not enabled in the target repository, the condition is principled
unobservable, yet the notification comment still accumulates on every dispatch. Issue #1026
observed this with #797's `always-pr` observation: `always-pr` is unset in this repository, so
the condition can never resolve, but notification comments piled up past 30 and all 4 `/verify`
re-runs resolved SKIPPED.

The gate adds an optional `config=<key>` attribute to the observation AC tag:

```
<!-- verify-type: observation event=auto-run config=always-pr -->
```

`opportunistic-search.sh` resolves `<key>` against the current repository's `.wholework.yml` via
`scripts/get-config-value.sh` and only includes Issues whose matched AC line carries a `config=`
value that resolves to `"true"` (case-insensitive). ACs without `config=` match unconditionally —
the existing behavior is preserved. Unlike `keyword=`, this gate needs no `--context-file`
argument: `.wholework.yml` is read directly from the working directory, so no new CLI argument is
added to either script.

**Matching specification:**

- Extraction: `config=<key>` is read from the AC line via `grep -oE 'config=[^ >]+'` (stops at the next space or `-->`).
- Resolution: `<key>`'s value is resolved via `"${SCRIPT_DIR}/get-config-value.sh" "$CONFIG_KEY" "false"`, then lowercased.
- Comparison: the resolved value must equal `"true"` exactly; any other value (including the `"false"` fallback) excludes the Issue from match results.
- Gate disabled (unconditional match) when: no `config=` attribute is present on the AC line.
- Scope: `<key>` must be a flat kebab-case key or a single-level nested key in block format (e.g. `capabilities.workflow`), matching `get-config-value.sh`'s own constraint — inline hash format and keys with two or more dots are not supported. The comparison is boolean-only (`true`/`false`); enum-valued keys (e.g. `auto-stop-at`) are out of scope. Both are candidates for a `config=key:value` extension if a future Issue needs them.

## Notes

- `opportunistic-search.sh` is the single source of truth for event-name validation (`KNOWN_EVENTS` list)
- Adding a new event requires: (1) adding to `KNOWN_EVENTS` in `opportunistic-search.sh`, (2) adding a row to the emitter table in `modules/verify-classifier.md`, (3) wiring the emitter call in the relevant skill or script
- The `fix-cycle` event is defined but has no emitter yet — see child Issue under #650
