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
done < <(git status --short --untracked-files=all 2>/dev/null | grep -v '^$' || true)

# Clean working directory
if [[ ${#dirty_files[@]} -eq 0 ]]; then
  exit 0
fi

# Load verify-ignore-paths from .wholework.yml (block list format)
ignore_patterns=()
if [[ -f ".wholework.yml" ]]; then
  in_section=false
  while IFS= read -r line; do
    case "$line" in \#*) continue ;; esac
    if [[ "$line" =~ ^verify-ignore-paths[[:space:]]*: ]]; then
      in_section=true; continue
    fi
    if $in_section; then
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
        p="${BASH_REMATCH[1]//\'/}"; p="${p//\"/}"
        ignore_patterns+=("$p")
      elif [[ "$line" =~ ^[^[:space:]] ]]; then
        in_section=false
      fi
    fi
  done < ".wholework.yml"
fi

# Built-in exempt: loop-state heartbeat files are exempt from the dirty check.
# Case B adopted (#798): verify-side exemption avoids commit/push overhead in append-loop-state-heartbeat.sh
ignore_patterns+=("docs/sessions/_daily/loop-state-*.md")
# auto-events-rollup files are exempt as a fallback for when auto-commit in auto-events-rollup.sh fails (#824)
ignore_patterns+=("docs/sessions/_daily/auto-events-rollup-*.md")

# Check if a file matches any ignore pattern
# Handles both "file/path" and "dir/" (trailing slash from untracked directory entries)
_is_ignored() {
  local file="$1" pat
  local file_stripped="${file%/}"
  for pat in "${ignore_patterns[@]+"${ignore_patterns[@]}"}"; do
    if [[ "$pat" == *"/**" ]]; then
      local pfx="${pat%/**}"
      [[ "$file_stripped" == "$pfx" || "$file_stripped" == "$pfx/"* ]] && return 0
    else
      case "$file" in $pat) return 0 ;; esac
      case "$file_stripped" in $pat) return 0 ;; esac
    fi
  done
  return 1
}

# Apply ignore filter before classification
ignored_files=()
filtered=()
for f in "${dirty_files[@]}"; do
  if _is_ignored "$f"; then ignored_files+=("$f")
  else filtered+=("$f"); fi
done
if [[ ${#ignored_files[@]} -gt 0 ]]; then
  for f in "${ignored_files[@]}"; do
    echo "Warning: ignoring dirty file excluded by verify-ignore-paths: $f" >&2
  done
  if [[ ${#filtered[@]} -eq 0 ]]; then exit 0; fi
  dirty_files=("${filtered[@]}")
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
