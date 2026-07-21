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
| Issue blocked-by relationships | add, remove | `set-blocked-by.sh`, `gh-check-blocking.sh`, `gh-graphql.sh` (`add-blocked-by`, `remove-blocked-by`) | mutable | yes |

Note: label namespace rules and bare-namespace exceptions (e.g., `triaged`) are defined in [`modules/label-conventions.md`](label-conventions.md).

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

**Optional attributes for `type=verify-fail`**: this marker may additionally carry `deferral=true reason="<text>"` appended to the line when `/verify` (Step 11(b)) detects that the FAIL is a documented, intentional deferral rather than an implementation bug (see `skills/verify/SKILL.md` Step 11(b) "Documented deferral detection"). When present, `deferral=true` signals downstream `/verify` runs to skip the tier-gated auto-retry unconditionally. Example:
```
<!-- wholework-event: type=verify-fail phase=verify issue=42 iteration=1 deferral=true reason="pending explicit user authorization for --fable run" -->
```
Consumers matching on the `<!-- wholework-event: type=verify-fail` prefix (see Notes below) are unaffected by this attribute, since it is appended after the existing fields rather than altering them.

**`type=preview-ac-unverified`**: posted by `/review` (Step 8) whenever the Pre-merge section
contains one or more `ac-tier: preview` acceptance conditions — every such `/review` run posts
this marker, not only runs that found an `UNCERTAIN` condition. The `ac=` attribute carries a
comma-separated list of 1-based indices, into the Issue body's full AC enumeration (same
convention as `gh-issue-edit.sh --checkbox`), of the AC that were classified `UNCERTAIN` — i.e.,
`/review` could not actually verify them against the preview URL before the PR merges and the
preview environment disappears — **as of this run**. When no `ac-tier: preview` condition was
`UNCERTAIN` in this run, `ac=` carries the literal sentinel `none` rather than being left empty
(an empty `ac=` value would leave the attribute's boundary with the following token ambiguous).
Example:
```
<!-- wholework-event: type=preview-ac-unverified phase=review issue=42 ac=2,5 -->
Preview-tier AC 2 and 5 could not be verified against the preview URL (UNCERTAIN) before merge.
```
```
<!-- wholework-event: type=preview-ac-unverified phase=review issue=42 ac=none -->
All preview-tier AC were verified against the preview URL before merge.
```
Issue comments are append-only (see the L0 Surface SSoT table above), so a `/review` re-run
after a fix cycle cannot retract or edit an earlier marker — it can only post a new one. Because
of this, consumers must always resolve **only the single comment with the greatest `createdAt`
timestamp among `type=preview-ac-unverified` markers (latest-wins)** and disregard every earlier
marker for this Issue; an earlier marker's `ac=` set is superseded in full, never merged with a
later one. A latest marker carrying `ac=none` means zero preview-tier AC are unverified as of
that run, so the consumer's fallback set is empty. `/verify`'s pre-merge-preview AC skip rule
(`skills/verify/SKILL.md` Step 5) consults this marker, via
`scripts/resolve-preview-ac-fallback.sh`, to decide whether an `ac-tier: preview` condition was
actually verified at `/review` or must fall back to a post-merge check.

When consuming comments (see Processing Steps), a comment containing `<!-- wholework-event:`
in its body from a bot actor is treated as a Wholework-authored structured comment and consumed (bot exception above).

## Processing Steps

### Comment Consumption Procedure

Input: `ISSUE_NUMBER`, `COMMENT_SCOPE`, `PHASE_NAME`.

**Step 1 — Determine the cutoff timestamp (fallback ladder):**

Primary: fetch the timestamp of the most recent `phase/*` label assignment from the Issue timeline:
```
gh api "repos/{owner}/{repo}/issues/$ISSUE_NUMBER/timeline" --paginate \
  --jq '[.[] | select(.event=="labeled" and (.label.name|startswith("phase/"))) | .created_at] | last // empty'
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

**Cross-phase marker exception (defense in depth):** After fetching cutoff-filtered comments,
additionally scan all comments regardless of cutoff for any comment whose body contains
`<!-- wholework-event: type=verify-fail` or `<!-- wholework-event: type=preview-ac-unverified`.
Include any such comments in the consume set even if their `createdAt` is before or equal to
`CUTOFF`. This ensures that marker comments posted before the current phase's cutoff are never
silently dropped — `/verify` FAIL markers can predate a later fix-cycle's cutoff, and
`preview-ac-unverified` markers posted by `/review` always predate `/verify`'s cutoff (the
`phase/verify` label is assigned by `/merge`, not `/review`, so the marker is necessarily older
than the timestamp `/verify`'s Step 1 resolves as cutoff). Deduplicate by comment URL so that
comments already included by the cutoff filter are not injected twice.

```
gh issue view "$ISSUE_NUMBER" --json comments \
  --jq '.comments[] | select(.body | contains("<!-- wholework-event: type=verify-fail") or contains("<!-- wholework-event: type=preview-ac-unverified"))'
```

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

**Bash wrapper fallback (Issue #811):** This step is LLM-driven and may be silently skipped
under context pressure or on fix-cycle paths. Two safety nets ensure the section is written:
- `/spec` and `/code` phases (bash-wrapped via `run-spec.sh` / `run-code.sh`): a pre/post
  `## Consumed Comments` count comparison triggers `append-consumed-comments-section.sh` as a
  post-processor when the LLM did not write the section.
- `/verify` phase (in-session): `SKILL.md` contains an explicit `bash` call to
  `append-consumed-comments-section.sh` after the LLM's comment consumption step, ensuring
  deterministic writeback regardless of prose execution.

**Step 6 — Emit event (handled by bash wrapper in auto mode; LLM skip):**

In `/auto` mode (invoked via `scripts/run-auto-sub.sh`), the bash wrapper calls
`_emit_comments_consumed()` before the `phase_start` emit for each code phase runner.
Placing it before `phase_start` ensures the backfill detection in
`_maybe_emit_phase_complete()` still sees `phase_start` as the last event when
`phase_complete` is absent. **LLM action: skip this step** to avoid duplicate events.

In non-auto interactive mode (`AUTO_EVENTS_LOG` not set): skip this step.

The `trust_breakdown` uses `KEY:n` flat format (not JSON) to avoid quoting issues with
`emit_event()`'s value sanitization. See `scripts/run-auto-sub.sh _emit_comments_consumed()`
for the bash implementation.

## Output

- Comments injected as context for the calling skill's current phase
- `## Consumed Comments` section recorded in the Spec or retrospective
- `comments_consumed` event emitted to `AUTO_EVENTS_LOG` by bash wrapper (best-effort)
