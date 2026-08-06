#!/bin/bash
# append-consumed-comments-section.sh - Fallback: append ## Consumed Comments to Spec
# when the LLM phase did not write it (post-processor pattern, Candidate B).
#
# Usage: append-consumed-comments-section.sh <ISSUE_NUMBER> <PHASE_NAME> [--no-push]
#
# --no-push: commit only; skip the push/worktree-merge-push.sh step. The caller is
# responsible for propagating the commit to base via its own Exit path (see
# modules/worktree-lifecycle.md § "Spec file write destination").
#
# Best-effort: always exits 0. Failures are logged to stderr without blocking the caller.
# Bash 3.2+ compatible.

set -uo pipefail

ISSUE_NUMBER="${1:-}"
PHASE_NAME="${2:-}"

if [[ -z "$ISSUE_NUMBER" || -z "$PHASE_NAME" ]]; then
  echo "append-consumed-comments-section.sh: WARNING — skip (missing ISSUE_NUMBER or PHASE_NAME)" >&2
  exit 0
fi

NO_PUSH=false
shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-push)
      NO_PUSH=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
_repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Get spec directory (pass config path explicitly to avoid CWD sensitivity)
SPEC_DIR=$(WHOLEWORK_CONFIG_PATH="$_repo_root/.wholework.yml" \
  "$SCRIPT_DIR/get-config-value.sh" spec-path docs/spec 2>/dev/null || echo "docs/spec")
SPEC_DIR_ABS="$_repo_root/$SPEC_DIR"

# Find spec file
SPEC_FILE=$(ls "$SPEC_DIR_ABS/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1 || true)

if [[ -z "$SPEC_FILE" ]]; then
  echo "append-consumed-comments-section.sh: no spec file for issue #${ISSUE_NUMBER}, skipping" >&2
  exit 0
fi

# Warn on stderr when a jq/gh --jq call fails, distinguishing "jq errored" from
# the "0 new comments" happy path that also yields an empty array.
warn_jq_failed() {
  echo "append-consumed-comments-section.sh: WARNING — jq failed at $1; consumed comments not recorded" >&2
}

# Format a JSON comment array into "## Consumed Comments" entry lines, applying
# trust boundary classification. Trust tiers: OWNER/MEMBER/COLLABORATOR =
# first-class, CONTRIBUTOR/NONE = external. Logins ending with [bot] = bot
# (skip), unless body contains <!-- wholework-event:
format_entries() {
  echo "$1" | jq -r '
    .[] |
    ((.author.login) // "unknown") as $login |
    (.authorAssociation // "NONE") as $assoc |
    (.url // "") as $url |
    (.body // "") as $body |
    (if ($login | test("\\[bot\\]$"))
     then (if ($body | contains("<!-- wholework-event:")) then "first-class" else "bot" end)
     elif ($assoc == "OWNER" or $assoc == "MEMBER" or $assoc == "COLLABORATOR") then "first-class"
     else "external"
     end) as $tier |
    if $tier == "bot" then empty
    else
      ($body | split("\n") | .[0] // "" | .[0:80]) as $summary |
      "- \($login) / \($assoc) / \($tier) / \($summary) / \($url)"
    end
  ' 2>/dev/null
}

# Get cutoff timestamp from GitHub Issue timeline (most recent phase/* label assignment)
CUTOFF=$(gh api "repos/{owner}/{repo}/issues/${ISSUE_NUMBER}/timeline" --paginate \
  --jq '[.[] | select(.event=="labeled" and (.label.name|startswith("phase/"))) | .created_at] | last // empty' \
  2>/dev/null || true)

# Fetch all comments from the Issue
if ! RAW_COMMENTS=$(gh issue view "$ISSUE_NUMBER" --json comments \
  --jq '.comments' 2>/dev/null); then
  warn_jq_failed "RAW_COMMENTS"
  RAW_COMMENTS="[]"
fi

# Filter comments since cutoff
if [[ -n "$CUTOFF" ]]; then
  if ! SINCE_CUTOFF=$(echo "$RAW_COMMENTS" | \
    jq --arg c "$CUTOFF" '[.[] | select(.createdAt > $c)]' 2>/dev/null); then
    warn_jq_failed "SINCE_CUTOFF"
    SINCE_CUTOFF="[]"
  fi
else
  SINCE_CUTOFF="$RAW_COMMENTS"
fi

# Fetch verify-fail marker comments regardless of cutoff (defense in depth)
if ! VERIFYFAIL=$(echo "$RAW_COMMENTS" | \
  jq '[.[] | select(.body | contains("<!-- wholework-event: type=verify-fail"))]' \
  2>/dev/null); then
  warn_jq_failed "VERIFYFAIL"
  VERIFYFAIL="[]"
fi

# Combine and deduplicate by URL
if ! ALL_COMMENTS=$(jq -n \
  --argjson a "$SINCE_CUTOFF" \
  --argjson b "$VERIFYFAIL" \
  '($a + $b) | unique_by(.url)' 2>/dev/null); then
  warn_jq_failed "ALL_COMMENTS"
  ALL_COMMENTS="[]"
fi

HEADING_LINE=$(grep -n "^## Consumed Comments" "$SPEC_FILE" 2>/dev/null | head -1 | cut -d: -f1 || true)

if [[ -z "$HEADING_LINE" ]]; then
  # No existing section: create it (current behavior, unchanged).
  ENTRIES=$(format_entries "$ALL_COMMENTS")

  printf '\n%s\n' "## Consumed Comments" >> "$SPEC_FILE" 2>/dev/null || {
    echo "append-consumed-comments-section.sh: WARNING — skip (cannot append to spec file)" >&2
    exit 0
  }

  if [[ -z "$ENTRIES" ]]; then
    printf '%s\n' "No new comments since last phase." >> "$SPEC_FILE" 2>/dev/null || true
  else
    printf '%s\n' "$ENTRIES" >> "$SPEC_FILE" 2>/dev/null || true
  fi
else
  # Existing section: append only entries whose URL is not already recorded in
  # the existing section body. If nothing new, leave the file untouched.
  TOTAL_LINES=$(wc -l < "$SPEC_FILE" 2>/dev/null | tr -d ' ')
  BOUNDARY_LINE=$(awk -v start="$HEADING_LINE" 'NR>start && /^## /{print NR; exit}' "$SPEC_FILE" 2>/dev/null || true)
  if [[ -z "$BOUNDARY_LINE" ]]; then
    BOUNDARY_LINE=$((TOTAL_LINES + 1))
  fi

  EXISTING_BODY=$(sed -n "$((HEADING_LINE + 1)),$((BOUNDARY_LINE - 1))p" "$SPEC_FILE" 2>/dev/null || true)

  # Match on the exact last "/"-delimited field of each existing entry line
  # (the URL), not raw substring containment: GitHub issuecomment IDs are not
  # fixed-width, so a shorter new URL can be a literal string-prefix of an
  # already-recorded longer URL (e.g. "issuecomment-5123" vs
  # "issuecomment-51230"), which would falsely match via `contains()` and
  # silently drop a legitimate new comment forever.
  if ! NEW_COMMENTS=$(echo "$ALL_COMMENTS" | \
    jq --arg body "$EXISTING_BODY" '
      ($body | split("\n") | map(split(" / ") | last)) as $existing_urls |
      [.[] | select((.url // "") as $u | ($existing_urls | index($u) != null) | not)]
    ' 2>/dev/null); then
    warn_jq_failed "NEW_COMMENTS"
    NEW_COMMENTS="[]"
  fi

  NEW_ENTRIES=$(format_entries "$NEW_COMMENTS")

  if [[ -z "$NEW_ENTRIES" ]]; then
    # No new entries for this run — nothing to change (also covers a same-phase
    # re-run where every comment is already recorded).
    exit 0
  fi

  {
    sed -n "1,$((BOUNDARY_LINE - 1))p" "$SPEC_FILE"
    printf '%s\n' "$NEW_ENTRIES"
    sed -n "${BOUNDARY_LINE},\$p" "$SPEC_FILE"
  } > "$SPEC_FILE.tmp" 2>/dev/null && mv "$SPEC_FILE.tmp" "$SPEC_FILE" || {
    echo "append-consumed-comments-section.sh: WARNING — skip (cannot update spec file)" >&2
    rm -f "$SPEC_FILE.tmp" 2>/dev/null || true
    exit 0
  }
fi

# Defense-in-depth: warn if not running inside an isolated worktree (was
# skills/verify/SKILL.md Step 3 skipped?). --git-dir and --git-common-dir
# are equal only in the main tree; they differ inside any linked worktree.
_git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
_git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"
if [[ -n "$_git_dir" && -n "$_git_common_dir" && "$_git_dir" == "$_git_common_dir" ]]; then
  echo "append-consumed-comments-section.sh: WARNING — not running inside an isolated worktree (was skills/verify/SKILL.md Step 3 skipped?); commit/push below lands directly on the current branch" >&2
fi

# Commit (and push unless --no-push) — best-effort; failures do not block caller
SPEC_REL="${SPEC_FILE#$_repo_root/}"
if ! git -C "$_repo_root" diff --quiet "$SPEC_REL" 2>/dev/null; then
  if git -C "$_repo_root" add "$SPEC_REL" 2>/dev/null \
    && git -C "$_repo_root" commit -s \
         -m "Add consumed comments fallback for issue #${ISSUE_NUMBER} (${PHASE_NAME} phase)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" 2>/dev/null; then
    if [[ "$NO_PUSH" == "true" ]]; then
      : # commit only, push is the caller's responsibility (in-session mandatory call path)
    elif [[ -n "$_git_dir" && -n "$_git_common_dir" && "$_git_dir" == "$_git_common_dir" ]]; then
      # Main tree: route through the locked merge-push script instead of a bare push.
      # Bound the lock wait (default 300s) to a short timeout: this call site is reached
      # from the bash-wrapper post-processor fallback (run-code.sh / run-spec.sh, after the
      # phase's own claude subprocess has already exited), so a long silent stall here has no
      # watchdog covering it. Let diagnostics (lock-wait / rebase-failure messages) reach the
      # caller's log instead of suppressing them a second time on top of this script's own
      # best-effort warning.
      _current_branch="$(git -C "$_repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
      WHOLEWORK_PATCH_LOCK_TIMEOUT="${WHOLEWORK_PATCH_LOCK_TIMEOUT:-30}" \
        "$SCRIPT_DIR/worktree-merge-push.sh" --base "$_current_branch" \
        || echo "append-consumed-comments-section.sh: WARNING — worktree-merge-push.sh failed (best-effort)" >&2
    else
      git -C "$_repo_root" push origin HEAD 2>/dev/null \
        || echo "append-consumed-comments-section.sh: WARNING — push failed (best-effort)" >&2
    fi
  else
    echo "append-consumed-comments-section.sh: WARNING — commit failed (best-effort)" >&2
  fi
fi

exit 0
