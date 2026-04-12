#!/bin/bash
# check-file-overlap.sh - Detect overlapping changed files across sub-issues
#
# Usage: check-file-overlap.sh <parent-issue-number>
#
# Output (JSON):
# {"overlaps": [{"file": "path/to/file", "issues": [N1, N2]}]}
# No overlaps: {"overlaps": []}

set -euo pipefail

PARENT_NUMBER="${1:-}"

if [[ "$PARENT_NUMBER" == "--help" || "$PARENT_NUMBER" == "-h" || -z "$PARENT_NUMBER" ]]; then
  echo "Usage: check-file-overlap.sh <parent-issue-number>"
  echo ""
  echo "Detects overlapping changed files among sub-issues of an XL Issue and outputs the result as JSON."
  echo ""
  echo "Examples:"
  echo "  check-file-overlap.sh 853"
  echo ""
  echo "Output (with overlaps):"
  echo '  {"overlaps": [{"file": "skills/review/SKILL.md", "issues": [854, 857]}]}'
  echo ""
  echo "Output (no overlaps):"
  echo '  {"overlaps": []}'
  exit 0
fi

if ! [[ "$PARENT_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Issue number must be numeric: $PARENT_NUMBER" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get sub-issue list (OPEN sub-issues only)
SUB_ISSUE_JSON=$("$SCRIPT_DIR/get-sub-issue-graph.sh" "$PARENT_NUMBER" 2>/dev/null)

# Extract sub-issue numbers
SUB_ISSUE_NUMBERS=$(echo "$SUB_ISSUE_JSON" | jq -r '.sub_issues[].number' 2>/dev/null || true)

if [[ -z "$SUB_ISSUE_NUMBERS" ]]; then
  echo '{"overlaps": []}'
  exit 0
fi

# Collect changed files for each sub-issue
# Format: "issue_number\tfile_path"
ISSUE_FILE_PAIRS=""

while IFS= read -r issue_num; do
  [[ -z "$issue_num" ]] && continue

  # Search for Spec file (spec-path is configurable via .wholework.yml)
  SPEC_DIR="$REPO_ROOT/$("$SCRIPT_DIR/get-config-value.sh" spec-path "docs/spec")"
  SPEC_FILES=$(find "$SPEC_DIR" -name "issue-${issue_num}-*.md" 2>/dev/null || true)

  if [[ -z "$SPEC_FILES" ]]; then
    echo "Warning: Spec not found for Issue #${issue_num}. Skipping." >&2
    continue
  fi

  SPEC_FILE=$(echo "$SPEC_FILES" | head -1)

  # Extract file paths from the "Changed Files" section
  # Pattern: `- \`path/to/file\`` or `- \`path/to/file\`: description`
  FILES_IN_SPEC=$(awk '/^## 変更対象ファイル/{found=1; next} /^## /{if(found) exit} found && /`/{print}' "$SPEC_FILE" \
    | grep -o '`[^`]*`' \
    | sed 's/`//g' \
    | grep -v '^\s*$' \
    || true)

  if [[ -z "$FILES_IN_SPEC" ]]; then
    continue
  fi

  while IFS= read -r fpath; do
    [[ -z "$fpath" ]] && continue
    if [[ -n "$ISSUE_FILE_PAIRS" ]]; then
      ISSUE_FILE_PAIRS="${ISSUE_FILE_PAIRS}"$'\n'"${issue_num}"$'\t'"${fpath}"
    else
      ISSUE_FILE_PAIRS="${issue_num}"$'\t'"${fpath}"
    fi
  done <<< "$FILES_IN_SPEC"

done <<< "$SUB_ISSUE_NUMBERS"

if [[ -z "$ISSUE_FILE_PAIRS" ]]; then
  echo '{"overlaps": []}'
  exit 0
fi

# Aggregate issue numbers per file path and detect overlaps (2 or more)
echo "$ISSUE_FILE_PAIRS" | sort -t$'\t' -k2,2 | awk -F'\t' '
{
  file = $2
  issue = $1
  files[file] = files[file] " " issue
  counts[file]++
}
END {
  first = 1
  printf "{\"overlaps\": ["
  for (f in files) {
    if (counts[f] >= 2) {
      if (!first) printf ","
      first = 0
      n = split(files[f], issues, " ")
      printf "{\"file\": \"%s\", \"issues\": [", f
      ifirst = 1
      for (i = 1; i <= n; i++) {
        if (issues[i] != "") {
          if (!ifirst) printf ","
          ifirst = 0
          printf "%s", issues[i]
        }
      }
      printf "]}"
    }
  }
  printf "]}\n"
}'
