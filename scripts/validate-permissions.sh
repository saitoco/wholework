#!/bin/bash
# validate-permissions.sh
# Validates bidirectional consistency between skills/ directories and
# the name: frontmatter field in each skill's SKILL.md.
#
# Checks:
#   1. skills/<name>/SKILL.md has a name: field matching the directory name
#   2. The name: field in SKILL.md points back to an existing skills/<name>/ directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

errors=0

# --- Check 1: skills/<name>/SKILL.md -> name: field matches directory name ---
echo "=== Check 1: skills/<name>/SKILL.md -> name: field matches directory name ==="

for skill_md in "$PROJECT_ROOT"/skills/*/SKILL.md; do
  [ -f "$skill_md" ] || continue
  dir_name=$(basename "$(dirname "$skill_md")")

  # Extract the name: field from SKILL.md frontmatter
  name_field=$(awk '/^---/{if(found) exit; found=1; next} found && /^name:/{print $2; exit}' "$skill_md" || true)

  if [ -z "$name_field" ]; then
    echo "ERROR: skills/$dir_name/SKILL.md is missing the 'name:' frontmatter field"
    errors=$((errors + 1))
  elif [ "$name_field" != "$dir_name" ]; then
    echo "ERROR: skills/$dir_name/SKILL.md has name: '$name_field' but directory is '$dir_name'"
    errors=$((errors + 1))
  fi
done

# --- Check 2: name: field -> skills/<name>/ directory exists ---
echo "=== Check 2: name: field -> skills/<name>/ directory exists ==="

for skill_md in "$PROJECT_ROOT"/skills/*/SKILL.md; do
  [ -f "$skill_md" ] || continue

  name_field=$(awk '/^---/{if(found) exit; found=1; next} found && /^name:/{print $2; exit}' "$skill_md" || true)
  [ -z "$name_field" ] && continue  # already reported in Check 1

  if [ ! -d "$PROJECT_ROOT/skills/$name_field" ]; then
    echo "ERROR: SKILL.md has name: '$name_field' but skills/$name_field/ directory does not exist"
    errors=$((errors + 1))
  fi
done

# --- Result ---
echo ""
if [ "$errors" -gt 0 ]; then
  echo "FAILED: $errors inconsistencies found"
  exit 1
fi

echo "OK: all permissions are consistent"
exit 0
