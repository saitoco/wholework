#!/bin/bash
# append-consumed-comments-section.sh - Fallback: append ## Consumed Comments to Spec
# when the LLM phase did not write it (post-processor pattern, Candidate B).
#
# Usage: append-consumed-comments-section.sh <ISSUE_NUMBER> <PHASE_NAME>
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

# Check if section already exists; skip if present (deduplicate guard)
if grep -q "^## Consumed Comments" "$SPEC_FILE" 2>/dev/null; then
  exit 0
fi

# Get cutoff timestamp from GitHub Issue timeline (most recent phase/* label assignment)
CUTOFF=$(gh api "repos/{owner}/{repo}/issues/${ISSUE_NUMBER}/timeline" --paginate \
  --jq '[.[] | select(.event=="labeled" and (.label.name|startswith("phase/"))) | .created_at] | last // empty' \
  2>/dev/null || true)

# Fetch all comments from the Issue
RAW_COMMENTS=$(gh issue view "$ISSUE_NUMBER" --json comments \
  --jq '.comments' 2>/dev/null || echo "[]")

# Filter comments since cutoff
if [[ -n "$CUTOFF" ]]; then
  SINCE_CUTOFF=$(echo "$RAW_COMMENTS" | \
    jq --arg c "$CUTOFF" '[.[] | select(.createdAt > $c)]' 2>/dev/null || echo "[]")
else
  SINCE_CUTOFF="$RAW_COMMENTS"
fi

# Fetch verify-fail marker comments regardless of cutoff (defense in depth)
VERIFYFAIL=$(echo "$RAW_COMMENTS" | \
  jq '[.[] | select(.body | contains("<!-- wholework-event: type=verify-fail"))]' \
  2>/dev/null || echo "[]")

# Combine and deduplicate by URL
ALL_COMMENTS=$(jq -n \
  --argjson a "$SINCE_CUTOFF" \
  --argjson b "$VERIFYFAIL" \
  '($a + $b) | unique_by(.url)' 2>/dev/null || echo "[]")

# Format entries applying trust boundary classification
# Trust tiers: OWNER/MEMBER/COLLABORATOR = first-class, CONTRIBUTOR/NONE = external
# Logins ending with [bot] = bot (skip), unless body contains <!-- wholework-event:
ENTRIES=$(echo "$ALL_COMMENTS" | jq -r '
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
' 2>/dev/null || true)

# Append section to spec file
printf '\n%s\n' "## Consumed Comments" >> "$SPEC_FILE" 2>/dev/null || {
  echo "append-consumed-comments-section.sh: WARNING — skip (cannot append to spec file)" >&2
  exit 0
}

if [[ -z "$ENTRIES" ]]; then
  printf '%s\n' "No new comments since last phase." >> "$SPEC_FILE" 2>/dev/null || true
else
  printf '%s\n' "$ENTRIES" >> "$SPEC_FILE" 2>/dev/null || true
fi

# Defense-in-depth: warn if not running inside an isolated worktree (was
# skills/verify/SKILL.md Step 3 skipped?). --git-dir and --git-common-dir
# are equal only in the main tree; they differ inside any linked worktree.
_git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
_git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"
if [[ -n "$_git_dir" && -n "$_git_common_dir" && "$_git_dir" == "$_git_common_dir" ]]; then
  echo "append-consumed-comments-section.sh: WARNING — not running inside an isolated worktree (was skills/verify/SKILL.md Step 3 skipped?); commit/push below lands directly on the current branch" >&2
fi

# Commit and push (best-effort; failures do not block caller)
SPEC_REL="${SPEC_FILE#$_repo_root/}"
if ! git -C "$_repo_root" diff --quiet "$SPEC_REL" 2>/dev/null; then
  git -C "$_repo_root" add "$SPEC_REL" 2>/dev/null \
    && git -C "$_repo_root" commit -s \
         -m "Add consumed comments fallback for issue #${ISSUE_NUMBER} (${PHASE_NAME} phase)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" 2>/dev/null \
    && git -C "$_repo_root" push origin HEAD 2>/dev/null \
    || echo "append-consumed-comments-section.sh: WARNING — commit/push failed (best-effort)" >&2
fi

exit 0
