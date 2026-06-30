#!/usr/bin/env bash
# Check for SKILL.md body-to-allowed-tools mismatches before intermediate commits.
# Calls validate-skill-syntax.py and filters for allowed-tools mismatch errors.
# Usage: check-allowed-tools.sh [skill-dir]
#   skill-dir: directory to scan (default: skills/)
# Exit codes: 0 = no mismatches (or validator absent), 1 = mismatches detected

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
VALIDATOR="$SCRIPT_DIR/validate-skill-syntax.py"
SKILL_DIR="${1:-skills/}"

if [ ! -f "$VALIDATOR" ]; then
    exit 0
fi

output=$(python3 "$VALIDATOR" "$SKILL_DIR" 2>&1) || true

mismatches=$(printf '%s\n' "$output" | grep "allowed-tools の Bash" || true)

if [ -n "$mismatches" ]; then
    echo "Warning: allowed-tools mismatch detected in SKILL.md:" >&2
    printf '%s\n' "$mismatches" >&2
    echo "Fix the allowed-tools frontmatter before committing." >&2
    exit 1
fi

exit 0
