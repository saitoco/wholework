#!/usr/bin/env bash
# Verify that a SKILL.md's <!-- skill-body-sha: H --> marker matches the
# content hash actually computed from the file, catching edits (renames,
# word substitutions, same-line-count rewrites) that keep the line count
# marker in sync but silently drift the content marker. See docs/spec/issue-1468-*.md.
#
# Usage: check-skill-body-hash.sh [target-file]
#   target-file: file to check (default: skills/verify/SKILL.md)
# Exit codes: 0 = match (or target file absent, fail-open), 1 = mismatch or marker absent
#
# bash 3.2+ compatible: no associative arrays, no mapfile.
set -euo pipefail

TARGET_FILE="${1:-skills/verify/SKILL.md}"

if [ ! -f "$TARGET_FILE" ]; then
  exit 0
fi

MARKER_LINE=$(grep -m1 '<!-- skill-body-sha: ' "$TARGET_FILE" || true)

if [ -z "$MARKER_LINE" ]; then
  echo "Error: '<!-- skill-body-sha: H -->' marker not found in $TARGET_FILE" >&2
  exit 1
fi

EXPECTED_HASH=$(printf '%s\n' "$MARKER_LINE" | grep -oE '[0-9a-f]{8}')
ACTUAL_HASH=$(grep -v '<!-- skill-body-' "$TARGET_FILE" | shasum -a 256 | cut -c1-8)

if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
  echo "Error: $TARGET_FILE 's skill-body-sha marker is stale (marker: $EXPECTED_HASH, computed: $ACTUAL_HASH). Recompute the hash and update the marker." >&2
  exit 1
fi

exit 0
