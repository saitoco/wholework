#!/bin/bash
# check-session-findings-disposition.sh - Detect ## Findings bullets missing a canonical disposition tag
#
# Usage: check-session-findings-disposition.sh <session-md-path>
#
# Exit codes:
#   0 — no ## Findings section, or every top-level bullet carries a canonical disposition tag
#   1 — usage error (missing argument or unreadable file)
#   2 — one or more ## Findings bullets lack a canonical disposition tag (printed to stdout, one per line)
#
# Canonical disposition tags (exhaustive): [Filed: #<digits>] / [No action: ...] / [Resolved directly: ...]
# [Filed: pending] has no digits after '#' and is therefore non-canonical (catches backfill omissions).

set -euo pipefail

SESSION_MD="${1:-}"

if [[ -z "$SESSION_MD" ]] || [[ ! -r "$SESSION_MD" ]]; then
  echo "Usage: check-session-findings-disposition.sh <session-md-path>" >&2
  exit 1
fi

# Extract the ## Findings section body: lines after the heading up to the next
# h2 (## ) heading or EOF. h3+ headings inside the section do not terminate it.
findings_section=$(awk '
  /^## Findings[[:space:]]*$/ { in_section=1; next }
  /^## / { if (in_section) exit }
  in_section { print }
' "$SESSION_MD")

if [[ -z "$findings_section" ]]; then
  exit 0
fi

untagged_found=false
while IFS= read -r line; do
  # Only top-level bullets (line starts with "- "); indented continuation/sub-bullets are out of scope.
  case "$line" in
    "- "*) ;;
    *) continue ;;
  esac
  if [[ "$line" =~ \[Filed:\ \#[0-9]+\] ]] || [[ "$line" == *"[No action:"* ]] || [[ "$line" == *"[Resolved directly:"* ]]; then
    continue
  fi
  echo "$line"
  untagged_found=true
done <<< "$findings_section"

if [[ "$untagged_found" == "true" ]]; then
  exit 2
fi

# Best-effort existence check for [Filed: #N] tags — non-fatal, warns to stderr only.
while IFS= read -r line; do
  case "$line" in
    "- "*) ;;
    *) continue ;;
  esac
  if [[ "$line" =~ \[Filed:\ \#([0-9]+)\] ]]; then
    n="${BASH_REMATCH[1]}"
    if ! gh issue view "$n" >/dev/null 2>&1; then
      echo "Warning: [Filed: #$n] could not be verified (gh issue view failed) — network/auth issue or issue does not exist" >&2
    fi
  fi
done <<< "$findings_section"

exit 0
