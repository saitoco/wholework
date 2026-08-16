#!/bin/bash
# dedupe-phase-handoff-section.sh - deterministic rotation fallback for the
# "## Phase Handoff" section (Issue #1374).
#
# modules/phase-handoff.md's Write Procedure asks the LLM to detect an existing
# "## Phase Handoff" block and replace it in place (rotation). That detection is
# prose-driven and has no mechanical verification, so under context pressure or
# boundary-detection ambiguity the replace can silently fail and a second block
# gets appended instead, violating the "latest 1 phase" invariant. This script is
# the deterministic Secondary layer: it collapses any Spec file with 2+
# "## Phase Handoff" headings down to the last (most recent) one, deleting every
# earlier block. With 0 or 1 heading it is a no-op.
#
# Usage: dedupe-phase-handoff-section.sh <ISSUE_NUMBER>
#
# No commit/push: this script is always invoked immediately after the Phase
# Handoff write step and immediately before the phase's own existing commit
# step, so any rewrite it makes rides along in that commit's `git add`.
#
# Fail-closed: if awk fails or the rewrite would produce an empty file, the
# original Spec file is left untouched. Always exits 0 (best-effort; never
# blocks the caller's own commit step).
# Bash 3.2+ compatible.

set -uo pipefail

ISSUE_NUMBER="${1:-}"

if [[ -z "$ISSUE_NUMBER" ]]; then
  echo "dedupe-phase-handoff-section.sh: WARNING — skip (missing ISSUE_NUMBER)" >&2
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
  echo "dedupe-phase-handoff-section.sh: no spec file for issue #${ISSUE_NUMBER}, skipping" >&2
  exit 0
fi

# grep -c always prints a numeric count to stdout even on 0 matches (exit
# status 1 in that case, which we intentionally ignore here).
MATCH_COUNT=$(grep -c "^## Phase Handoff" "$SPEC_FILE" 2>/dev/null)
MATCH_COUNT="${MATCH_COUNT:-0}"

if [[ "$MATCH_COUNT" -le 1 ]]; then
  # 0 or 1 heading: nothing to rotate away.
  exit 0
fi

LAST_LINE=$(grep -n "^## Phase Handoff" "$SPEC_FILE" 2>/dev/null | tail -1 | cut -d: -f1)

if [[ -z "$LAST_LINE" ]]; then
  echo "dedupe-phase-handoff-section.sh: WARNING — could not determine latest block, leaving spec file unchanged" >&2
  exit 0
fi

TMP_FILE="${SPEC_FILE}.dedupe.tmp"

# Single-pass rewrite: any "## Phase Handoff" heading other than the last one
# opens a skip region that runs through the line before the next "## "
# (level-2) heading — the same boundary-detection idea used by
# append-consumed-comments-section.sh's own awk pass. Content between old
# blocks (e.g. an intervening "## review retrospective" section) is preserved.
if ! awk -v last="$LAST_LINE" '
  BEGIN { in_old = 0 }
  /^## Phase Handoff/ {
    if (NR == last) {
      in_old = 0
      print
      next
    } else {
      in_old = 1
      next
    }
  }
  in_old && /^## / {
    in_old = 0
    print
    next
  }
  in_old { next }
  { print }
' "$SPEC_FILE" > "$TMP_FILE" 2>/dev/null; then
  echo "dedupe-phase-handoff-section.sh: WARNING — awk failed, leaving spec file unchanged" >&2
  rm -f "$TMP_FILE" 2>/dev/null || true
  exit 0
fi

if [[ ! -s "$TMP_FILE" ]]; then
  echo "dedupe-phase-handoff-section.sh: WARNING — rewrite produced empty output, leaving spec file unchanged" >&2
  rm -f "$TMP_FILE" 2>/dev/null || true
  exit 0
fi

mv "$TMP_FILE" "$SPEC_FILE" 2>/dev/null || {
  echo "dedupe-phase-handoff-section.sh: WARNING — failed to update spec file" >&2
  rm -f "$TMP_FILE" 2>/dev/null || true
  exit 0
}

exit 0
