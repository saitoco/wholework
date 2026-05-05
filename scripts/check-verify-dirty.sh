#!/bin/bash
# check-verify-dirty.sh - Classify dirty files for /verify Step 1
#
# Usage: check-verify-dirty.sh <issue-number>
#
# Exit codes:
#   0 — working directory is clean
#   1 — dirty files include related or non-spec files (hard-error abort)
#   2 — all dirty files are unrelated spec files (docs/spec/issue-N-*.md, N != issue-number)
#
# On exit 2, prints the unrelated spec file paths to stdout (one per line).

set -euo pipefail

NUMBER="${1:-}"

if [[ -z "$NUMBER" ]] || ! [[ "$NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Usage: check-verify-dirty.sh <issue-number>" >&2
  exit 1
fi

# Get list of dirty files (paths only, strip status prefix)
dirty_files=()
while IFS= read -r line; do
  # git status --short: "XY path" or "XY path -> dest"
  # Strip the 2-char status + space, take the first path token
  path="${line:3}"
  # Handle rename "old -> new" — take the destination
  if [[ "$path" == *" -> "* ]]; then
    path="${path##* -> }"
  fi
  dirty_files+=("$path")
done < <(git status --short 2>/dev/null | grep -v '^$' || true)

# Clean working directory
if [[ ${#dirty_files[@]} -eq 0 ]]; then
  exit 0
fi

# Classify each dirty file
unrelated_spec_files=()
has_other=false
spec_regex="^docs/spec/issue-([0-9]+)-"

for file in "${dirty_files[@]}"; do
  if [[ "$file" =~ $spec_regex ]]; then
    file_issue="${BASH_REMATCH[1]}"
    if [[ "$file_issue" != "$NUMBER" ]]; then
      unrelated_spec_files+=("$file")
    else
      has_other=true
    fi
  else
    has_other=true
  fi
done

if [[ "$has_other" == "true" ]]; then
  exit 1
fi

# All dirty files are unrelated spec files
for f in "${unrelated_spec_files[@]}"; do
  echo "$f"
done
exit 2
