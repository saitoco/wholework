# observation-trigger

Design specification for the observation AC trigger mechanism.

## Purpose

`verify-type: observation event=<name>` ACs are not verified during a normal `/verify` run.
Instead, they are re-evaluated automatically when the specified event fires.
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

## `scripts/observation-trigger.sh` (実装済み #656; stdout output added in #897)

A dedicated dispatch script (`scripts/observation-trigger.sh`) encapsulates the
processing contract above, making emitter integration a one-liner:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/observation-trigger.sh" --event <event-name>
```

The script calls `opportunistic-search.sh --event <name>`, and for each matched Issue
posts a comment recommending the user re-run `/verify <N>` (comment-posting side effect;
unconditional regardless of caller context). It also prints the matched Issue numbers
(newline-separated, one per line; empty output when no matches) to stdout, so that
callers with a dispatch mechanism can act on the result directly instead of relying on
the human reading the comment.

**Dispatch responsibility split (since #897):** `observation-trigger.sh` itself never
dispatches `/verify` — it only posts the comment and prints the matched numbers. Whether
those numbers are turned into an actual `/verify` dispatch is the calling emitter's
responsibility:

- **LLM-session emitters** (`/auto`, `/review`) capture stdout and, when `AUTONOMY_TIER`
  is `L2`/`L3` (via `modules/detect-config-markers.md`), dispatch
  `Skill(skill="wholework:verify", args="$N")` for each matched number (excluding the
  Issue the current phase just processed). At `L1`, dispatch is skipped and the posted
  comment remains the only signal (advisory-only, matching the `L1` semantics in
  `modules/autonomy-tier.md`).
- **`scripts/claude-watchdog.sh`** (shell-only context, no `Skill` tool available) does
  not capture or act on stdout — its existing comment-posting-only fallback is
  unaffected by this change.

## Notes

- `opportunistic-search.sh` is the single source of truth for event-name validation (`KNOWN_EVENTS` list)
- Adding a new event requires: (1) adding to `KNOWN_EVENTS` in `opportunistic-search.sh`, (2) adding a row to the emitter table in `modules/verify-classifier.md`, (3) wiring the emitter call in the relevant skill or script
- The `fix-cycle` event is defined but has no emitter yet — see child Issue under #650
