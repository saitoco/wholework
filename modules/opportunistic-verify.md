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

If the script exists:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh <skill-name>
```

- The script fetches closed Issues with the `phase/verify` label and filters by `verify-type: opportunistic` tag, skill name, and unchecked conditions
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

Within Step 2's judgment loop, immediately after each condition's PASS/FAIL/SKIP result is determined — and before moving on to the next condition — emit one event per condition (do not aggregate; see Notes for the reason):

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"
restore_auto_session_pointer <calling skill's own Issue/PR number>
if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
  EMIT_ISSUE_NUMBER=<candidate Issue number N this condition belongs to> emit_event "opportunistic_verify_result" \
    "skill=<calling skill name (e.g., /spec)>" \
    "result=<PASS|FAIL|SKIP>" \
    "ac_index=<1-based index>"
fi
```

- **`AUTO_EVENTS_LOG` guard (required)**: skip the emit when `AUTO_EVENTS_LOG` is unset and `restore_auto_session_pointer` could not restore it either (e.g., a standalone run outside `/auto`) — the same policy as other non-wrapper emitters in `modules/event-emission.md`
- **`ac_index`**: the 1-based position of this condition among the candidate Issue's full checkbox enumeration (pre-merge + post-merge, in order) — the same global-index convention used by `scripts/gh-issue-edit.sh --checkbox` and `scripts/check-pre-merge-ac.sh`. Determine it by counting `^- \[[ xX]\]` lines in the Issue body already fetched in Step 1/2
- **`EMIT_ISSUE_NUMBER` and `restore_auto_session_pointer`'s target differ**: `restore_auto_session_pointer` takes the calling skill's own Issue/PR number (for session pointer resolution), while `EMIT_ISSUE_NUMBER` takes the candidate Issue number N being judged (recorded in the event's `issue` field, meaningful for downstream aggregation)

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
