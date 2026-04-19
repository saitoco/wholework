#!/usr/bin/env bash
set -euo pipefail

SCAN_DIRS="skills/ modules/ agents/ tests/ docs/"
VIOLATIONS=0

# Deprecated terms from docs/product.md § Terms (Formerly called column)
DEPRECATED_TERMS=(
  "Dispatch"
  "Design file"
  "Issue Spec"
  "verification hint"
  "acceptance check"
  "shared procedure document"
)

check_term() {
  local term="$1"
  local grep_flags="$2"
  local pattern="$3"

  local result
  # shellcheck disable=SC2086
  result=$(grep $grep_flags "$pattern" $SCAN_DIRS \
    | grep -v 'docs/spec/' \
    | grep -v 'Formerly called' \
    | grep -v '旧称' \
    | grep -v 'tests/check-forbidden-expressions.bats' \
    | grep -iv "| $term |" \
    || true)

  if [ -n "$result" ]; then
    echo "Forbidden expression '$term' detected:"
    printf '%s\n' "$result"
    return 1
  fi
  return 0
}

for TERM in "${DEPRECATED_TERMS[@]}"; do
  case "$TERM" in
    "Dispatch")
      # Case-sensitive: avoids false positive "command dispatch" in prose
      check_term "$TERM" "-r" "$TERM" || VIOLATIONS=1
      ;;
    "Design file")
      # Word boundary: avoids false positive "design files" (plural)
      check_term "$TERM" "-riE" '\bDesign file\b' || VIOLATIONS=1
      ;;
    "Issue Spec")
      # Word boundary + case-sensitive: avoids "Issue Specification" and lowercase "issue spec" in shell arrays
      check_term "$TERM" "-rE" '\bIssue Spec\b' || VIOLATIONS=1
      ;;
    *)
      check_term "$TERM" "-ri" "$TERM" || VIOLATIONS=1
      ;;
  esac
done

if [ "$VIOLATIONS" -gt 0 ]; then
  exit 1
fi
