# l0-surfaces

SSoT for Wholework's L0 (GitHub state) surface inventory and comment consumption policy.

## Purpose

Define the exhaustive set of L0 surfaces that Wholework skills read and write, so that:
- The autonomy tier matrix (#704) can look up "is this an L0 write?" per surface without per-call judgment.
- Skills treat Issue / PR comments as first-class input equivalent to prompts, consumed at the start of each phase.
- L0 write operations across skills become auditable from a single reference.

## Input

None. Loaded by skills at phase start via "Read and follow" pattern.

Parameters accepted by the Comment Consumption Procedure:
- `ISSUE_NUMBER` — the Issue number being processed
- `COMMENT_SCOPE` — `issue` (Issue comments only) or `issue+pr` (Issue + PR comments)
- `PHASE_NAME` — the current phase name (e.g., `spec`, `code`, `verify`)

## L0 Surface SSoT

The table below is **exhaustive** for Wholework's current scope. Add a row here whenever a skill begins reading or writing a new GitHub state surface.

| L0 surface | Operations | Primary callers | Mutation kind | Consumed by skills |
|------------|-----------|-----------------|---------------|-------------------|
| Issue title | edit | `/issue`, `/triage` | mutable | yes |
| Issue body | edit | `/issue`, `/spec`, `/verify` | mutable | yes |
| Issue state (OPEN/CLOSED) | close, reopen | `/verify`, `/auto` | mutable | yes |
| Labels (`phase/*`, `audit/*`, ...) | add, remove | `gh-label-transition.sh` | mutable | yes |
| Issue comments | append + read | `gh-issue-comment.sh` (write); all skills (read — introduced here) | append-only | yes (introduced in #705) |
| PR comments | append + read | `/review` (write); `/code`, `/review` (read) | append-only | yes (introduced in #705) |
| Project v2 fields (Size, Priority, ...) | update | `project-field-update.md` | mutable | yes |
| PR body, review state | view | `/review`, `/merge` | read-mostly | yes |
| Sub-issue graph | view (`subIssues` GraphQL) | `get-sub-issue-graph.sh` | read-only | yes |
| `closes #N` magic | parse | `gh-extract-issue-from-pr.sh` | derived | yes |

Note: bare-namespace label exceptions (e.g., `triaged`) are documented in a separate Issue (#R2).

## Trust Boundary

When consuming comments, classify each by the comment author's `author.association` field.
The actual GitHub API field returned by `gh issue view --json comments` is `authorAssociation`
(a top-level field per comment, not nested under `author`); conceptually this represents the
author's association level — `author.association` in this document refers to that value.

| `authorAssociation` | Trust tier | Handling |
|---------------------|-----------|----------|
| `OWNER` | first-class | Inject as prompt-equivalent input |
| `MEMBER` | first-class | Inject as prompt-equivalent input |
| `COLLABORATOR` | first-class | Inject as prompt-equivalent input |
| `CONTRIBUTOR` | external | Inject with "external input" marker |
| `NONE` | external | Inject with "external input" marker |
| actor `login` ends with `[bot]` | bot | Skip (see exception below) |

Bot exception: skip bot comments by default, but consume them when their body
contains `<!-- wholework-event:` (i.e., any comment whose body includes a marker
beginning with that prefix — comments that Wholework itself wrote and that carry structured data).

Detection: use `authorAssociation` for the trust tier check; use `author.login` suffix `[bot]`
for the bot check. The `gh issue view --json comments` response returns `author` with `login`
and `authorAssociation` at the comment top level.

## Machine-Readable Event Marker

Wholework embeds structured metadata in Issue/PR comments using HTML comment markers.
The machine-readable marker is invisible in rendered Markdown; human-readable body follows as normal Markdown.

Format:
```
<!-- wholework-event: type=<event-type> phase=<phase> issue=<N> -->
<human-readable body in normal Markdown>
```

Example:
```
<!-- wholework-event: type=verify-fail phase=verify issue=42 -->
FAIL detected on AC 2: the expected string was not found in the output.
```

This marker namespace (`wholework-event:`) is consistent with existing HTML comment markers
in the codebase (`<!-- verify-type: ... -->`, `<!-- verify: ... -->`).

When consuming comments (see Processing Steps), a comment containing `<!-- wholework-event:`
in its body from a bot actor is treated as a Wholework-authored structured comment and consumed (bot exception above).

## Processing Steps

### Comment Consumption Procedure

Input: `ISSUE_NUMBER`, `COMMENT_SCOPE`, `PHASE_NAME`.

**Step 1 — Determine the cutoff timestamp (fallback ladder):**

Primary: fetch the timestamp of the most recent `phase/*` label assignment from the Issue timeline:
```
gh api "repos/{owner}/{repo}/issues/$ISSUE_NUMBER/timeline" --paginate \
  --jq '[.[] | select(.event=="labeled" and (.label.name|startswith("phase/"))) | .created_at] | last'
```
(`{owner}` and `{repo}` are expanded automatically by `gh`.)

Fallback A: if the timeline is empty or the command fails, read the latest `phase_start` event
`ts` for this Issue from `.tmp/auto-events.jsonl`.

Fallback B: if neither source is available, set cutoff to empty (consume all comments as
best-effort) and note "cutoff undetermined" in the Consumed Comments record.

**Step 2 — Fetch comments:**

```
gh issue view "$ISSUE_NUMBER" --json comments \
  --jq ".comments[] | select(.createdAt > \"$CUTOFF\")"
```
If CUTOFF is empty, omit the `select` filter (fetch all comments).

ISO 8601 UTC strings are lexicographically comparable, so `date` conversion is not needed.

If `COMMENT_SCOPE=issue+pr`: also fetch PR comments with `gh pr view <PR_NUMBER> --json comments`
for the PR associated with this Issue.

**Step 3 — Classify by trust boundary:**

For each comment, read `authorAssociation` and `author.login` and apply the Trust Boundary table above.

**Step 4 — Inject into current phase context:**

- first-class comments: inject as prompt-equivalent context for the current phase
- external comments: inject with an "external input" prefix marker
- bot comments: skip (unless the bot exception applies)

**Step 5 — Record in Consumed Comments:**

Append a `## Consumed Comments` section to the Spec (or retrospective) with one entry per
consumed comment:
- login / authorAssociation / trust tier / one-line intent summary / comment URL

If no comments were consumed: write "No new comments since last phase."

**Step 6 — Emit event (best-effort, only when `AUTO_EVENTS_LOG` is set):**

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"
EMIT_ISSUE_NUMBER=$ISSUE_NUMBER emit_event "comments_consumed" \
  "phase=$PHASE_NAME" \
  "count=$N" \
  "authors=$AUTHORS" \
  "trust_breakdown=OWNER:$OWNER_N,MEMBER:$MEMBER_N,COLLABORATOR:$COLLAB_N,CONTRIBUTOR:$CONTRIB_N,NONE:$NONE_N"
```

Skip this step entirely when `AUTO_EVENTS_LOG` is not set (normal in-session execution).
The `trust_breakdown` uses `KEY:n` flat format (not JSON) to avoid quoting issues with
`emit_event()`'s value sanitization.

## Output

- Comments injected as context for the calling skill's current phase
- `## Consumed Comments` section recorded in the Spec or retrospective
- `comments_consumed` event emitted to `AUTO_EVENTS_LOG` when available (best-effort)
