#!/bin/bash
# check-verify-dirty.sh - Session-aware dirty file classifier for /verify Step 1
#
# Usage: check-verify-dirty.sh <issue-number>
#
# Exit codes:
#   0 — working directory is clean, or all dirty files are self-worktree / other-worktree /
#       other-session / self-spec / foreign-session
#   1 — dirty files include own-issue-scope, or parent-main files with undetermined attribution
#       (hard-error abort)
#   2 — all remaining (parent-main) dirty files are unrelated spec files (docs/spec/issue-N-*.md, N != issue-number)
#
# Outputs classify=... lines to stderr for each dirty file. Full classification set:
#   self-worktree, other-worktree, other-session, self-spec, own-issue-scope, foreign-session,
#   parent-main (fallback, attribution undetermined).
# On exit 2, prints the unrelated spec file paths to stdout (one per line).
#
# "Files relevant to me" (own-issue-scope) = paths enumerated in this Issue's own Spec
# (docs/spec/issue-<issue-number>-*.md) `## Changed Files` section. A dirty file matching that
# Spec's own path (docs/spec/issue-<issue-number>-*.md itself) is classified self-spec and never
# blocks — it can only be this session's own write-back (Consumed Comments / retrospective
# append), never another session's work. When the Spec or its `## Changed Files` section is
# missing, attribution cannot be determined; parent-main files fall back to the pre-#1123
# behavior of blocking everything.

set -euo pipefail

NUMBER="${1:-}"

if [[ -z "$NUMBER" ]] || ! [[ "$NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Usage: check-verify-dirty.sh <issue-number>" >&2
  exit 1
fi

# Get list of dirty files (paths only, strip status prefix)
dirty_files=()
while IFS= read -r line; do
  # git status --short: "XY path" or "XY path -> dest"
  # Strip the 2-char status + space, take the first path token
  path="${line:3}"
  # Handle rename "old -> new" — take the destination
  if [[ "$path" == *" -> "* ]]; then
    path="${path##* -> }"
  fi
  dirty_files+=("$path")
done < <(git status --short --untracked-files=all 2>/dev/null | grep -v '^$' || true)

# Clean working directory
if [[ ${#dirty_files[@]} -eq 0 ]]; then
  exit 0
fi

# Load verify-ignore-paths from .wholework.yml (block list format)
ignore_patterns=()
if [[ -f ".wholework.yml" ]]; then
  in_section=false
  while IFS= read -r line; do
    case "$line" in \#*) continue ;; esac
    if [[ "$line" =~ ^verify-ignore-paths[[:space:]]*: ]]; then
      in_section=true; continue
    fi
    if $in_section; then
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
        p="${BASH_REMATCH[1]//\'/}"; p="${p//\"/}"
        ignore_patterns+=("$p")
      elif [[ "$line" =~ ^[^[:space:]] ]]; then
        in_section=false
      fi
    fi
  done < ".wholework.yml"
fi

# Check if a file matches any ignore pattern
# Handles both "file/path" and "dir/" (trailing slash from untracked directory entries)
_is_ignored() {
  local file="$1" pat
  local file_stripped="${file%/}"
  for pat in "${ignore_patterns[@]+"${ignore_patterns[@]}"}"; do
    if [[ "$pat" == *"/**" ]]; then
      local pfx="${pat%/**}"
      [[ "$file_stripped" == "$pfx" || "$file_stripped" == "$pfx/"* ]] && return 0
    else
      case "$file" in $pat) return 0 ;; esac
      case "$file_stripped" in $pat) return 0 ;; esac
    fi
  done
  return 1
}

# Apply ignore filter before classification
ignored_files=()
filtered=()
for f in "${dirty_files[@]}"; do
  if _is_ignored "$f"; then ignored_files+=("$f")
  else filtered+=("$f"); fi
done
if [[ ${#ignored_files[@]} -gt 0 ]]; then
  for f in "${ignored_files[@]}"; do
    echo "Warning: ignoring dirty file excluded by verify-ignore-paths: $f" >&2
  done
  if [[ ${#filtered[@]} -eq 0 ]]; then exit 0; fi
  dirty_files=("${filtered[@]}")
fi

# Session-aware classification: classify dirty files by origin before spec classification.
# self-worktree: own session's worktree directory -> exit 0 (not a true dirty conflict)
# other-worktree: another session's worktree directory -> stderr warning only (not blocking)
# other-session: another session's docs/sessions dir -> stderr warning only (not blocking)
# parent-main: everything else -> pass through to existing classification
parent_main_files=()
for f in "${dirty_files[@]}"; do
  if [[ "$f" == .claude/worktrees/*+issue-${NUMBER}/* ]]; then
    echo "[check-verify-dirty] classify=self-worktree path=$f" >&2
  elif [[ "$f" == .claude/worktrees/* ]]; then
    echo "[check-verify-dirty] classify=other-worktree path=$f" >&2
  elif [[ "$f" == docs/sessions/*-*/* ]]; then
    echo "[check-verify-dirty] classify=other-session path=$f" >&2
  else
    echo "[check-verify-dirty] classify=parent-main path=$f" >&2
    parent_main_files+=("$f")
  fi
done
if [[ ${#parent_main_files[@]} -eq 0 ]]; then
  exit 0
fi
dirty_files=("${parent_main_files[@]}")

# Build the own-issue-scope manifest: paths listed in this Issue's own Spec's
# `## Changed Files` section. Path extraction uses awk (isolate the section) + grep
# (pull backtick-quoted path tokens) — no associative arrays / mapfile (bash 3.2 compat).
own_spec_file=""
for f in docs/spec/issue-"${NUMBER}"-*.md; do
  if [[ -f "$f" ]]; then
    own_spec_file="$f"
    break
  fi
done

manifest_available=false
changed_files_manifest=""
if [[ -n "$own_spec_file" ]] && grep -q '^## Changed Files' "$own_spec_file" 2>/dev/null; then
  manifest_available=true
  changed_files_manifest="$(awk '/^## Changed Files/{flag=1; next} /^## /{flag=0} flag' "$own_spec_file" \
    | grep -oE '^- `[^`]+`' | sed -E 's/^- `//; s/`$//' || true)"
else
  echo "Warning: attribution undetermined for issue #${NUMBER} (no Spec, or Spec has no '## Changed Files' section) — parent-main dirty files fall back to blocking" >&2
fi

_in_changed_files_manifest() {
  local file="$1"
  [[ -n "$changed_files_manifest" ]] || return 1
  grep -qxF "$file" <<<"$changed_files_manifest"
}

# Classify each dirty file
unrelated_spec_files=()
has_other=false
spec_regex="^docs/spec/issue-([0-9]+)-"

for file in "${dirty_files[@]}"; do
  if [[ "$file" =~ $spec_regex ]]; then
    file_issue="${BASH_REMATCH[1]}"
    if [[ "$file_issue" != "$NUMBER" ]]; then
      unrelated_spec_files+=("$file")
    else
      echo "[check-verify-dirty] classify=self-spec path=$file" >&2
    fi
  elif [[ "$manifest_available" == "true" ]] && _in_changed_files_manifest "$file"; then
    echo "[check-verify-dirty] classify=own-issue-scope path=$file" >&2
    has_other=true
  elif [[ "$manifest_available" == "true" ]]; then
    echo "[check-verify-dirty] classify=foreign-session path=$file" >&2
  else
    echo "[check-verify-dirty] classify=parent-main path=$file" >&2
    has_other=true
  fi
done

if [[ "$has_other" == "true" ]]; then
  exit 1
fi

# All remaining dirty files are non-blocking: self-spec, foreign-session, and/or unrelated
# spec files belonging to a different issue (M != NUMBER). Only the latter print to stdout.
# (bash 3.2 empty-array workaround: "${arr[@]}" alone is unbound-variable under set -u when arr
# has zero elements — self-spec/foreign-session-only runs now legitimately reach this point with
# an empty unrelated_spec_files array.)
for f in "${unrelated_spec_files[@]+"${unrelated_spec_files[@]}"}"; do
  echo "$f"
done
if [[ ${#unrelated_spec_files[@]} -gt 0 ]]; then
  exit 2
fi
exit 0
