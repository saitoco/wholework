#!/usr/bin/env bash
# check-translation-sync.sh — compare git timestamps of docs/* against docs/ja/* counterparts
# Outputs a table showing IN_SYNC / OUTDATED / MISSING_JA status per file.
# Always exits 0 (informational only; use --fail-if-outdated for CI enforcement).
#
# Usage:
#   bash scripts/check-translation-sync.sh
#   bash scripts/check-translation-sync.sh --fail-if-outdated   (exit 1 if any OUTDATED/MISSING_JA)

set -euo pipefail

FAIL_IF_OUTDATED=false
for arg in "$@"; do
  case "$arg" in
    --fail-if-outdated) FAIL_IF_OUTDATED=true ;;
  esac
done

# Collect source files: docs/*.md and docs/guide/*.md
# Exclude docs/spec/ and docs/stats/ (auto-generated or disposable)
SOURCE_FILES=()
while IFS= read -r f; do SOURCE_FILES+=("$f"); done < <(
  find docs -maxdepth 1 -name '*.md' -not -path 'docs/spec/*' -not -path 'docs/stats/*' | sort
  find docs/guide -maxdepth 1 -name '*.md' 2>/dev/null | sort
)

# Column widths
COL_FILE=40
COL_STATUS=12

printf "%-${COL_FILE}s  %-${COL_STATUS}s  %s\n" "File" "Status" "Details"
printf '%s\n' "$(printf '─%.0s' $(seq 1 80))"

outdated_count=0
missing_count=0

for en_file in "${SOURCE_FILES[@]}"; do
  # Derive the docs/ja/* counterpart path
  ja_file="${en_file/docs\//docs/ja/}"

  if [ ! -f "$ja_file" ]; then
    status="MISSING_JA"
    details="$ja_file does not exist"
    missing_count=$((missing_count + 1))
  else
    # Get unix timestamps from git log (empty string if file not in git)
    en_ts=$(git log -1 --format="%ct" -- "$en_file" 2>/dev/null)
    ja_ts=$(git log -1 --format="%ct" -- "$ja_file" 2>/dev/null)

    en_ts=${en_ts:-0}
    ja_ts=${ja_ts:-0}

    if [ "$en_ts" -le "$ja_ts" ]; then
      status="IN_SYNC"
      details=""
    else
      status="OUTDATED"
      en_date=$(date -r "$en_ts" "+%Y-%m-%d" 2>/dev/null || date -d "@$en_ts" "+%Y-%m-%d" 2>/dev/null || echo "unknown")
      ja_date=$(date -r "$ja_ts" "+%Y-%m-%d" 2>/dev/null || date -d "@$ja_ts" "+%Y-%m-%d" 2>/dev/null || echo "unknown")
      details="en: $en_date  ja: $ja_date"
      outdated_count=$((outdated_count + 1))
    fi
  fi

  printf "%-${COL_FILE}s  %-${COL_STATUS}s  %s\n" "$en_file" "$status" "$details"
done

printf '%s\n' "$(printf '─%.0s' $(seq 1 80))"
printf "Summary: %d OUTDATED, %d MISSING_JA\n" "$outdated_count" "$missing_count"

if [ "$FAIL_IF_OUTDATED" = "true" ] && [ $((outdated_count + missing_count)) -gt 0 ]; then
  exit 1
fi

exit 0
