#!/usr/bin/env bash
set -euo pipefail

SCAN_DIRS="skills/ modules/ agents/ tests/ docs/ scripts/"
VIOLATIONS=0

# Deprecated terms from docs/product.md § Terms (Formerly called column)
DEPRECATED_TERMS=(
  "Dispatch"
  "Design file"
  "Issue Spec"
  "verification hint"
  "acceptance check"
  "shared procedure document"
  "verify hint"
  "verify ヒント"
  "検証ヒント"
)

# Self-reference exclusions: this script and its bats file hold every deprecated term as literals.
check_term() {
  local term="$1"
  local grep_flags="$2"
  local pattern="$3"
  local extra_grep_v="${4:-}"

  local result
  # shellcheck disable=SC2086
  result=$(grep $grep_flags "$pattern" $SCAN_DIRS \
    | grep -v 'Formerly called' \
    | grep -v '旧称' \
    | grep -v 'tests/check-forbidden-expressions.bats' \
    | grep -v '^scripts/check-forbidden-expressions.sh:' \
    | grep -iv "| $term |" \
    | grep -v '^docs/sessions/' \
    | grep -v '^docs/reports/' \
    || true)

  if [ -n "$extra_grep_v" ] && [ -n "$result" ]; then
    result=$(printf '%s\n' "$result" | grep -v -- "$extra_grep_v" || true)
  fi

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
      # Word boundary + case-sensitive: avoids false positives "command dispatch" in prose
      # and longer words that start with the term (e.g. noun and plural forms)
      check_term "$TERM" "-rE" '\bDispatch\b' || VIOLATIONS=1
      ;;
    "Design file")
      # Word boundary: avoids false positive "design files" (plural)
      check_term "$TERM" "-riE" '\bDesign file\b' || VIOLATIONS=1
      ;;
    "Issue Spec")
      # Word boundary + case-sensitive: avoids "Issue Specification" and lowercase "issue spec" in shell arrays
      # extra_grep_v excludes hyphen-preceded (per-Issue Spec) and backtick-quoted (`Issue Spec`) false positives
      check_term "$TERM" "-rE" '\bIssue Spec\b' '[-`]Issue Spec' || VIOLATIONS=1
      ;;
    *)
      check_term "$TERM" "-ri" "$TERM" || VIOLATIONS=1
      ;;
  esac
done

if [ "$VIOLATIONS" -gt 0 ]; then
  exit 1
fi
