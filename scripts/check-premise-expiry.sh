#!/usr/bin/env bash
# check-premise-expiry.sh - Re-evaluate <!-- premise: ... --> markers against the current work tree
#
# Usage:
#   scripts/check-premise-expiry.sh <issue-body-md-path>
#
# Run with the repository root as CWD. <issue-body-md-path> is a Markdown file containing
# zero or more Issue-body prose lines with <!-- premise: <expr> --> markers.
#
# SSoT for the supported premise expression syntax and its limits (referenced by
# skills/audit/SKILL.md and skills/issue/SKILL.md rather than a modules/*.md file — see
# the Spec's "Notes" section for why: the two consumers sit on the modules/ extraction
# boundary, and get-config-value.sh's own header/SSoT pattern is the established precedent
# for keeping a small grammar's implementation and spec in one file).
#
# Supported premise expressions (exhaustive, 3 types):
#
#   | Expression                                    | Meaning                                   | Evaluation |
#   |------------------------------------------------|--------------------------------------------|------------|
#   | grep_count "<pattern>" "<paths>" <op> <N>       | line count of literal-string matches for    | `git grep -F -- "<pattern>" -- <paths>` piped to `wc -l`, compared with `[ "$COUNT" <op> "$N" ]` |
#   |                                                  | `<pattern>` under tracked files in `<paths>` satisfies `<op> <N>` | |
#   | file_exists "<path>"                            | `<path>` exists                             | `test -e "<path>"` |
#   | file_not_exists "<path>"                        | `<path>` does not exist                     | `test ! -e "<path>"` |
#
#   - `<op>` is one of the 6 shell test comparators: -eq / -ne / -lt / -le / -gt / -ge.
#     `==`/`<`/`>` are not supported — HTML comment markers must not contain a bare `>`
#     (it collides with attribute-extraction patterns like `grep -oE 'config=[^ >]+'`
#     elsewhere in the codebase, and with the marker's own closing `-->`).
#   - `<N>` is a non-negative integer.
#   - `<paths>` is a single quoted, space-separated list of one or more paths
#     (e.g. "scripts/ skills/ modules/").
#
# Exit codes and output (exhaustive):
#
#   0  Normal: (a) zero markers found, (b) every premise holds, or (c) only UNEVALUABLE
#      markers were found. stdout is empty in all three cases.
#   2  Expired: at least one premise no longer holds. stdout carries one line per expired
#      premise: `EXPIRED: <expr> (actual: <value>)`. `<value>` is the observed line count
#      for grep_count, the literal string "not found" for file_exists, or the literal
#      string "exists" for file_not_exists.
#   1  Usage error: missing argument, the file does not exist, or it is not readable.
#      stderr carries `Usage: check-premise-expiry.sh <issue-body-md-path>`; stdout is
#      empty.
#
# Fail-open (does not affect the exit code — never counted as EXPIRED, to avoid the exact
# silent-false-negative failure mode this script exists to catch): stderr carries
# `UNEVALUABLE: <expr> (reason: <reason>)` and evaluation continues with the next marker.
#
#   - Not inside a git work tree (`git rev-parse --is-inside-work-tree` is non-zero) —
#     applies to grep_count markers only (file_exists/file_not_exists use plain `test`).
#     reason: "not inside a git work tree"
#   - A grep_count `<paths>` entry fails `test -e` — reason: "path not found: <p>". This
#     check is mandatory: `git grep` returns exit 1 (identical to zero matches) for a
#     pathspec that does not exist, so skipping this check would let a typo'd path read as
#     "zero matches" = premise holds, silently reproducing the exact failure mode this
#     script is meant to catch.
#   - Unsupported expression type (command name is none of the 3 above) — reason:
#     "unsupported expression"
#   - Malformed expression (command name recognized but arguments do not parse — wrong
#     operator, non-numeric N, unbalanced quotes) — reason: "malformed expression"
#
# There is no timeout condition: the script has no external I/O, only local `git grep` /
# `test`, so it inherits whatever timeout the caller (e.g. verify-executor's `command` type,
# 60s) applies. There is no kill condition: no long-running loop.
#
# What this script cannot detect (recorded here as the exhaustive limits statement, per
# Spec's requirement that the header document "the range of detectable premises and how
# undetectable ones are handled"):
#
#   - Untracked files (gitignored, or created but never `git add`-ed) are invisible to
#     grep_count — it only searches tracked files (modules/filesystem-scope.md's Approved
#     Patterns mandate `git grep` for bash script search). This is intentional, not a gap.
#   - Regular expressions are not supported — grep_count is fixed-string only (`git grep
#     -F`), to avoid the ERE/BRE mismatch class of bug modules/verify-executor.md records.
#   - Premises that cannot be expressed as one of the 3 types above (e.g. "this design
#     decision depends on future direction X") are outside this script's scope entirely.
#     `/audit premise` Layer 2 (LLM judgment) surfaces these as marker-conversion
#     candidates; it does not — and cannot — determine whether they have expired.
#   - Markers must be placed in prose sections (e.g. `## Background`, `## Purpose`), never
#     on an Acceptance Criteria checkbox line (`- [ ] ...`). The existing AC parsers
#     (scripts/check-pre-merge-ac.sh, scripts/scan-pending-ac.sh,
#     scripts/check-ac-checkbox-format.sh) key off that same line shape for `verify:` /
#     `verify-type:` attributes; this script does not enforce placement, it simply is never
#     invoked against checkbox lines in the intended workflow.
#
# bash 3.2+ compatible: no mapfile, no ${VAR,,}; arrays are built with IFS + read -r -a only.

USAGE="Usage: $(basename "$0") <issue-body-md-path>"

if [ $# -ne 1 ]; then
  echo "$USAGE" >&2
  exit 1
fi

BODY_FILE="$1"

if [ ! -e "$BODY_FILE" ] || [ ! -r "$BODY_FILE" ]; then
  echo "$USAGE" >&2
  exit 1
fi

IS_GIT_WORKTREE=true
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || IS_GIT_WORKTREE=false

GREP_COUNT_RE='^grep_count[[:space:]]+"([^"]*)"[[:space:]]+"([^"]*)"[[:space:]]+(-eq|-ne|-lt|-le|-gt|-ge)[[:space:]]+([0-9]+)$'
FILE_EXISTS_RE='^file_exists[[:space:]]+"([^"]*)"$'
FILE_NOT_EXISTS_RE='^file_not_exists[[:space:]]+"([^"]*)"$'

EXPIRED_LINES=()
HAS_EXPIRED=false

emit_unevaluable() {
  # $1 = expr, $2 = reason
  echo "UNEVALUABLE: $1 (reason: $2)" >&2
}

MARKER_LINES=$(grep -oE '<!-- premise:[^>]*-->' "$BODY_FILE" 2>/dev/null || true)

if [ -z "$MARKER_LINES" ]; then
  exit 0
fi

while IFS= read -r marker_line; do
  [ -z "$marker_line" ] && continue

  expr="${marker_line#<!-- premise:}"
  expr="${expr%-->}"
  # trim leading/trailing whitespace
  expr="$(printf '%s' "$expr" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  first_word="${expr%% *}"

  case "$first_word" in
    grep_count)
      if [[ "$expr" =~ $GREP_COUNT_RE ]]; then
        pattern="${BASH_REMATCH[1]}"
        paths_str="${BASH_REMATCH[2]}"
        op="${BASH_REMATCH[3]}"
        n="${BASH_REMATCH[4]}"

        if [ "$IS_GIT_WORKTREE" != true ]; then
          emit_unevaluable "$expr" "not inside a git work tree"
          continue
        fi

        IFS=' ' read -r -a paths_arr <<< "$paths_str"

        path_missing=""
        for p in "${paths_arr[@]}"; do
          [ -z "$p" ] && continue
          if [ ! -e "$p" ]; then
            path_missing="$p"
            break
          fi
        done
        if [ -n "$path_missing" ]; then
          emit_unevaluable "$expr" "path not found: $path_missing"
          continue
        fi

        count="$(git grep -F -- "$pattern" -- "${paths_arr[@]}" 2>/dev/null | wc -l | tr -d ' ')"

        if [ "$count" "$op" "$n" ]; then
          : # premise holds
        else
          EXPIRED_LINES+=("EXPIRED: $expr (actual: $count)")
          HAS_EXPIRED=true
        fi
      else
        emit_unevaluable "$expr" "malformed expression"
      fi
      ;;
    file_exists)
      if [[ "$expr" =~ $FILE_EXISTS_RE ]]; then
        target="${BASH_REMATCH[1]}"
        if [ ! -e "$target" ]; then
          EXPIRED_LINES+=("EXPIRED: $expr (actual: not found)")
          HAS_EXPIRED=true
        fi
      else
        emit_unevaluable "$expr" "malformed expression"
      fi
      ;;
    file_not_exists)
      if [[ "$expr" =~ $FILE_NOT_EXISTS_RE ]]; then
        target="${BASH_REMATCH[1]}"
        if [ -e "$target" ]; then
          EXPIRED_LINES+=("EXPIRED: $expr (actual: exists)")
          HAS_EXPIRED=true
        fi
      else
        emit_unevaluable "$expr" "malformed expression"
      fi
      ;;
    *)
      emit_unevaluable "$expr" "unsupported expression"
      ;;
  esac
done <<< "$MARKER_LINES"

if [ "$HAS_EXPIRED" = true ]; then
  for line in "${EXPIRED_LINES[@]}"; do
    printf '%s\n' "$line"
  done
  exit 2
fi

exit 0
