#!/usr/bin/env bash
# Detect capability-specific guidance content in eager-load shared modules.
# Called by /audit drift Step 2 (Project Documents categories).
#
# Exit 0 in all cases; prints ISSUE lines when violations are found.

set -euo pipefail

ROOT="."

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      ROOT="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 [--root <path>]" >&2
      exit 1
      ;;
  esac
done

TARGET_FILES="modules/verify-patterns.md modules/verify-executor.md"

# Collect capability names from bundled adapter files.
capabilities=""
for adapter in "$ROOT"/modules/*-adapter.md; do
  [ -f "$adapter" ] || continue
  base="$(basename "$adapter" -adapter.md)"
  capabilities="$capabilities $base"
done

if [ -z "$capabilities" ]; then
  exit 0
fi

for cap in $capabilities; do
  for target in $TARGET_FILES; do
    target_path="$ROOT/$target"
    [ -f "$target_path" ] || continue

    # Detect section headings containing the capability name (case-insensitive).
    # Only match lines starting with one or more '#' characters.
    if grep -i -q "^#\+.*${cap}" "$target_path" 2>/dev/null; then
      # Check if a Domain file exists anywhere under skills/.
      domain_found=0
      for skill_dir in "$ROOT"/skills/*/; do
        [ -d "$skill_dir" ] || continue
        if [ -f "${skill_dir}${cap}-guidance.md" ]; then
          domain_found=1
          break
        fi
      done

      if [ "$domain_found" -eq 0 ]; then
        echo "ISSUE: capability '${cap}' guidance found in ${target} (no Domain file at skills/*/${cap}-guidance.md)"
      fi
    fi
  done
done
