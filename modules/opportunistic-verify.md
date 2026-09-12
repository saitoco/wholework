# opportunistic-verify

Shared module for running opportunistic verification of verification-pending Issues at skill completion.

## Purpose

At each skill execution completion, extract `verify-type: opportunistic` conditions from Issues with the `phase/verify` label that are relevant to the current skill, and automatically check them via AI retrospective. This creates a structure where normal workflow operations become the throughput rate for consuming the verification backlog.

## Input

Information provided by the calling skill:

- **Skill name**: Hardcoded by the calling skill in its SKILL.md (e.g., `/spec`, `/review`, `/verify`, `/issue`, `/code`)
- **Calling Issue/PR number**: The Issue (or the Issue resolved from a PR) that the calling skill is currently processing. Taken from the calling skill's own context (`/spec`/`/code`/`/issue`/`/verify` use their own `$NUMBER`; `/review` uses the Issue number it already resolved from its PR) — used by Step 3 for session pointer resolution

## Processing Steps

Skills that Read this file should execute opportunistic verification following the steps below.

### 1. Fetch Verification-Pending Issues and Extract Conditions

First check for the existence of `${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh` using a `-x` test. If the script does not exist (or is not executable), output "Warning: ${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh not found. Skipping opportunistic verification." and skip all subsequent processing.

If the script exists, resolve `--facts` and `--context-file` before calling it:

**Resolve `--facts` (run-fact token relevance ordering — reorders the opportunistic-mode candidate set by run-fact relevance without requiring AC-side attributes; matched candidates are prioritized, but unmatched candidates are never dropped solely for lacking a token match):**

- **Ordering, not exclusion**: a candidate whose condition text does not contain any `--facts` token is still included in `opportunistic-search.sh`'s output — it is placed after token-matched candidates, never dropped for the mismatch alone (Issue #1285).
- **Separate safety valve**: `opportunistic-search.sh` additionally caps the reordered set at a fixed candidate-count limit (`FACTS_CANDIDATE_LIMIT`, applied only when `--facts` is given and valid). This is a population-size safeguard unrelated to token matching, and it prints a non-silent `Note: truncated ...` warning to stderr when it actually drops candidates — token mismatch by itself never triggers this warning.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-run-facts.sh --session-from-issue <calling skill's own Issue/PR number>
```

Session id resolution is handled internally by `collect-run-facts.sh --session-from-issue` (issue-scoped pointer file, evaluated before the `.tmp/auto-session-current` fallback — see this script's own header comment for the full resolution-order SSoT). This is a best-effort improvement over the prior form, not an absolute guarantee: the issue-scoped pointer lookup itself no-ops when `AUTO_EVENTS_LOG` is already set but `AUTO_SESSION_ID` is not (see `scripts/collect-run-facts.sh`'s inline note at its `--session-from-issue` branch), in which case resolution falls through to `.tmp/auto-session-current` and, under concurrent `/auto` sessions, may attribute facts to a different session's run. This is tolerated here because facts only reorder opportunistic-mode candidates (never exclude them) — a wrong attribution degrades ordering quality, it does not corrupt Issue state.

- **If the command exits 0 with JSON on stdout**: capture that stdout, and write it to `.tmp/facts-<calling Issue number>.json` with the Write tool (same convention as `--context-file` below), then pass `--facts .tmp/facts-<calling Issue number>.json` to `opportunistic-search.sh` below.
- **If the command exits non-zero** (session id unresolved — standalone run outside `/auto`, or otherwise unavailable): omit `--facts` — `opportunistic-search.sh` falls back to its existing unfiltered, backward-compatible behavior.

**Resolve `--context-file` (`keyword=` gate — otherwise unreachable, since `opportunistic-search.sh`'s `keyword=` gate only activates when `--context-file` is supplied):**

Write `.tmp/context-<calling skill's own Issue/PR number>.md` with the Write tool, containing the current Issue's body plus, if a Spec exists at `$SPEC_PATH/issue-<calling Issue number>-*.md`, that Spec's `## Changed Files` section — this is the text the `keyword=` gate matches against.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh <skill-name> --context-file .tmp/context-<calling Issue number>.md [--facts .tmp/facts-<calling Issue number>.json]
```

- The script fetches closed Issues with the `phase/verify` label and filters by `verify-type: opportunistic` tag, skill name, and unchecked conditions; when `--context-file` is given, the `keyword=` gate additionally excludes non-matching candidates; when `--facts` is given, matched candidates are reordered ahead of unmatched ones (never excluded for the mismatch alone) and the reordered set is capped at `FACTS_CANDIDATE_LIMIT`
- Output is JSON: `[{"number": N, "condition": "condition text"}]` (empty: `[]`)
- **If output is `[]`**: Output "Opportunistic verification: 0 conditions found, skipping" and exit

### 2. Cross-Reference with Current Execution Results (AI Retrospective)

For each extracted condition, first check whether it is observable within this execution's own scope, then judge by PASS/FAIL/SKIP criteria.

**Observation scope check (before PASS/FAIL judgment)**: a condition is in scope only when its truth value is fully determined by what this skill execution itself performed or observed. Conditions that require repository-wide aggregation (e.g., "no stale worktrees accumulate repository-wide", "N occurrences across the repository") or state spanning multiple sessions are out of scope for a single execution — judge these **SKIP**, not PASS/FAIL, regardless of how this execution's own local work went.

For in-scope conditions, reflect on this skill's execution memory (output results, operations performed, observed facts) and judge:

- **PASS**: Confirmed during this execution that the condition is met. This execution's own local success (e.g., this session created and removed its own worktree) is not by itself evidence that a broader or repository-wide condition holds — do not read a partial, local success as PASS for the condition as a whole.
- **FAIL**: Confirmed during this execution that the condition is not met
- **SKIP**: Insufficient information for judgment (not the specific pattern of input, out of this execution's observable scope per the check above, etc.)

No additional log retention mechanism is needed. The AI retrospects on its memory of skill execution to make judgments.

### 3. Persist Judgment Results (Event Emission)

Before emitting events for a candidate Issue's conditions, fetch that Issue's body once: `gh issue view <N> --json body -q .body`. Neither Step 1 (`opportunistic-search.sh`'s output is only `[{"number": N, "condition": "condition text"}]`, no body) nor Step 2 (pure AI retrospective over execution memory) provides it — this fetch is required for `ac_index` below.

Within Step 2's judgment loop, immediately after each condition's PASS/FAIL/SKIP result is determined — and before moving on to the next condition — emit one event per condition (do not aggregate — see `modules/event-emission.md`'s `opportunistic_verify_result` entry for the rationale):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-skill-event.sh" <calling skill's own Issue/PR number> opportunistic_verify_result \
  --emit-issue <candidate Issue number N this condition belongs to> \
  "skill=<calling skill name (e.g., /spec)>" \
  "result=<PASS|FAIL|SKIP>" \
  "ac_index=<1-based index>"
```

- **`AUTO_EVENTS_LOG` guard**: the script applies this guard internally (skips the emit when the session pointer does not resolve, e.g. a standalone run outside `/auto`) — no `if` is needed at the call site
- **`ac_index`**: the 1-based position of this condition among the candidate Issue's full checkbox enumeration (pre-merge + post-merge, in order) — the same global-index convention used by `scripts/gh-issue-edit.sh --checkbox` and `scripts/check-pre-merge-ac.sh`. Determine it by counting `^- \[[ xX]\]` lines in the Issue body fetched above, excluding lines inside a fenced code block (see `modules/l0-surfaces.md` § AC Enumeration Convention)
- **positional `<issue>` and `--emit-issue` differ**: the positional `<issue>` is the calling skill's own Issue/PR number (used for session pointer resolution), while `--emit-issue` takes the candidate Issue number N being judged (recorded in the event's `issue` field, meaningful for downstream aggregation)

### 4. Update Checkboxes

For Issues with PASS conditions, execute the following:

**Update Issue body:**

1. Get current Issue body with `gh issue view $N --json body -q .body`
2. Rewrite `- [ ]` to `- [x]` for PASS conditions
3. Create directory with `mkdir -p .tmp`, then write updated body to `.tmp/issue-body-$N.md` using the Write tool
4. Update Issue body with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh $N .tmp/issue-body-$N.md`
5. Delete temp file with `rm -f .tmp/issue-body-$N.md`

**Post comment:**

1. Write comment body to `.tmp/issue-comment-$N.md` using the Write tool (template below)
2. Post comment with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $N .tmp/issue-comment-$N.md`
3. Delete temp file with `rm -f .tmp/issue-comment-$N.md`

**Comment template:**
```markdown
## Opportunistic Verification (during /skill-name execution)

| Condition | Result |
|-----------|--------|
| condition text 1 | PASS |
| condition text 2 | SKIP |
```

For FAIL: only report via comment (do not reopen; FAIL reopening is determined during explicit `/verify`)

### 5. All Conditions PASS → Label Transition

After updating checkboxes, confirm whether all post-merge conditions for the Issue (all conditions regardless of `verify-type` tag) are now checked (`- [x]`).

Re-fetch the updated Issue body and check whether any unchecked (`- [ ]`) conditions remain in the post-merge section.

If all conditions are checked:

```bash
gh issue edit $N --remove-label "phase/verify" --add-label "phase/done"
```

## Output

- Terminal output: Opportunistic verification summary (number of target Issues, judgment result for each condition)
- GitHub Issue updates: Checkbox updates for PASS conditions + verification record comment + label transition (only when all conditions PASS)
- `opportunistic_verify_result` event: one per judged condition, emitted when `AUTO_EVENTS_LOG` is set (Step 3)
