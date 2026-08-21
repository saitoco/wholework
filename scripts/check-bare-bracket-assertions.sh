#!/usr/bin/env bash
# Detect bare [[ "$output"/"$status" ]] bats assertions without a || false
# safety net. On bash 3.2 (macOS system bash), a bare [[ ]] compound command
# written as a standalone statement inside a bats @test body does not
# propagate its failure through set -e, so a FAIL can be silently reported
# as "ok" (PASS). See skills/code/skill-dev-validation.md and Issue #1412.
#
# This script is informational only: it always exits 0 regardless of how
# many bare assertions it finds. It visualizes the existing ~1000 instances
# in tests/*.bats without blocking CI or /code (bulk rewrite is out of scope
# for #1412; see the Issue's Out of Scope section).

SELF_TEST_FILE="tests/check-bare-bracket-assertions.bats"

matches=$(grep -nHE '^[[:space:]]*\[\[ "\$(output|status)"' tests/*.bats 2>/dev/null)

count=0
if [ -n "$matches" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    file="${line%%:*}"
    if [ "$file" = "$SELF_TEST_FILE" ]; then
      continue
    fi
    case "$line" in
      *'|| false'*) continue ;;
    esac
    # Backslash line continuation: "|| false" may appear on the next
    # physical line (e.g. `[[ ... ]] \` followed by `  || false`), which
    # is bash-equivalent to a single-line `[[ ... ]] || false` and
    # propagates correctly. Treat it as safe too.
    case "$line" in
      *'\')
        rest="${line#*:}"
        lineno="${rest%%:*}"
        next_line=$(sed -n "$((lineno + 1))p" "$file" 2>/dev/null)
        if printf '%s\n' "$next_line" | grep -qE '^[[:space:]]*\|\| false'; then
          continue
        fi
        ;;
    esac
    echo "$line"
    count=$((count + 1))
  done <<BAREBRACKET
$matches
BAREBRACKET
fi

if [ "$count" -gt 0 ]; then
  echo ""
  echo "Warning: $count bare [[ \"\$output\"/\"\$status\" assertion(s) detected without || false."
  echo "See skills/code/skill-dev-validation.md for the bash 3.2 set -e non-propagation pitfall (Issue #1412)."
else
  echo "No bare [[ \"\$output\"/\"\$status\" assertions detected without || false."
fi

exit 0
