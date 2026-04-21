#!/usr/bin/env bash
# Parse orchestration-recoveries.md and output frequency-filtered candidate list.
# Output format: <symptom-short>\t<count> (tab-separated, one per line)
# Only entries with count >= threshold and no "起票済み" Improvement Candidate are included.
# Entries whose symptom-short matches an open issue title are excluded (duplicate check).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$SCRIPT_DIR}"

THRESHOLD=3
ISSUES_JSON=""
RECOVERY_FILE=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --threshold)
      THRESHOLD="$2"
      shift 2
      ;;
    --threshold=*)
      THRESHOLD="${1#--threshold=}"
      shift
      ;;
    --issues-json)
      ISSUES_JSON="$2"
      shift 2
      ;;
    --issues-json=*)
      ISSUES_JSON="${1#--issues-json=}"
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [ -z "$RECOVERY_FILE" ]; then
        RECOVERY_FILE="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$RECOVERY_FILE" ]; then
  echo "Usage: $0 <recovery-file> [--threshold K] [--issues-json PATH]" >&2
  exit 1
fi

if [ ! -f "$RECOVERY_FILE" ]; then
  echo "File not found: $RECOVERY_FILE" >&2
  exit 1
fi

# Load open issue titles for duplicate detection
ISSUE_TITLES=""
if [ -n "$ISSUES_JSON" ] && [ -f "$ISSUES_JSON" ]; then
  # Extract titles from JSON array: [{"number": N, "title": "..."}]
  ISSUE_TITLES="$(python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
for item in data:
    print(item.get('title', ''))
" "$ISSUES_JSON" 2>/dev/null || true)"
fi

# Parse the recovery file.
# Track current entry state: symptom-short and whether it has a "起票済み" candidate.
# Use associative-array-free approach for bash 3.2 compatibility:
# - SYMPTOM_LIST: newline-separated list of symptom-shorts (in order, possibly duplicated)
# - EXCLUDED_LIST: newline-separated list of symptom-shorts that are excluded (起票済み)

SYMPTOM_LIST=""
EXCLUDED_LIST=""
CURRENT_SYMPTOM=""
IN_ENTRY=0

while IFS= read -r line; do
  # Detect entry header: "## YYYY-MM-DD HH:MM UTC: <symptom-short>"
  if echo "$line" | grep -qE '^## [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC: .+'; then
    # Extract symptom-short (everything after "UTC: ")
    CURRENT_SYMPTOM="${line#*UTC: }"
    IN_ENTRY=1
  elif [ $IN_ENTRY -eq 1 ]; then
    # Detect "Improvement Candidate" line with 起票済み
    if echo "$line" | grep -qE '^\- 起票済み #[0-9]+'; then
      EXCLUDED_LIST="${EXCLUDED_LIST}${CURRENT_SYMPTOM}
"
    fi
    # Detect next entry header resets current entry
    if echo "$line" | grep -qE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}'; then
      CURRENT_SYMPTOM="${line#*UTC: }"
    fi
  fi

  # Record all seen symptom-shorts (including excluded ones; we filter later)
  if echo "$line" | grep -qE '^## [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC: .+'; then
    sym="${line#*UTC: }"
    SYMPTOM_LIST="${SYMPTOM_LIST}${sym}
"
  fi
done < "$RECOVERY_FILE"

# Count frequency for each unique symptom-short that is not excluded
# and not a duplicate of an open issue title.
# Collect unique symptom-shorts first.
UNIQUE_SYMPTOMS=""
while IFS= read -r sym; do
  [ -z "$sym" ] && continue
  # Skip if already in UNIQUE_SYMPTOMS
  if ! echo "$UNIQUE_SYMPTOMS" | grep -qxF "$sym"; then
    UNIQUE_SYMPTOMS="${UNIQUE_SYMPTOMS}${sym}
"
  fi
done <<EOF
$SYMPTOM_LIST
EOF

# For each unique symptom, compute count and apply filters
while IFS= read -r sym; do
  [ -z "$sym" ] && continue

  # Skip if excluded (起票済み)
  if echo "$EXCLUDED_LIST" | grep -qxF "$sym"; then
    continue
  fi

  # Skip if sym matches an open issue title (duplicate check)
  if [ -n "$ISSUE_TITLES" ]; then
    if echo "$ISSUE_TITLES" | grep -qF "$sym"; then
      continue
    fi
  fi

  # Count occurrences in SYMPTOM_LIST
  count=0
  while IFS= read -r s; do
    [ "$s" = "$sym" ] && count=$((count + 1))
  done <<EOF2
$SYMPTOM_LIST
EOF2

  # Apply threshold
  if [ "$count" -ge "$THRESHOLD" ]; then
    printf '%s\t%d\n' "$sym" "$count"
  fi
done <<EOF3
$UNIQUE_SYMPTOMS
EOF3
