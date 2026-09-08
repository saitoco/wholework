#!/usr/bin/env bash
# resolve-merge-strategy.sh
# Resolve .wholework.yml's `merge-strategy` key to either the bare strategy
# name (default mode) or the corresponding `gh pr merge` flag (--flag mode).
# Extracted as a shared resolver (not written directly into
# skills/merge/SKILL.md prose) so the branching is bats-verifiable, following
# the scripts/resolve-preview-env.sh precedent (#1428/#1429). See
# docs/spec/issue-1457-merge-strategy-config.md for the full design.
#
# Usage:
#   resolve-merge-strategy.sh          # prints strategy name (squash|merge|rebase)
#   resolve-merge-strategy.sh --flag   # prints gh pr merge flag (--squash|--merge|--rebase)
#   resolve-merge-strategy.sh --help   # usage, exit 0
#
# Fail-safe behavior (fail-safe critical — see the Spec's Notes section on the
# fail-safe-critical classification):
#   - A non-empty `merge-strategy` value that does not exactly match
#     squash/merge/rebase (special characters, multibyte, CRLF, oversized,
#     etc.) falls back to `squash` with a warning on stderr. Exit 0 — this is
#     a warning, not an error. No value is ever re-interpreted by the shell
#     (no eval/expansion of the raw value).
#   - A genuinely empty `merge-strategy` value (`merge-strategy:` with nothing
#     after the colon, or `merge-strategy: ""`) falls back to `squash`
#     SILENTLY (no warning) — get-config-value.sh's own default-substitution
#     (`squash` is passed as its default argument below) absorbs the empty
#     value before it ever reaches this script's own case/warning logic.
#   - If get-config-value.sh exits non-zero or is missing, resolution
#     fail-closes to `squash` and prints a DISTINCT warning naming the
#     dependency failure as the cause — never the ".wholework.yml has a bad
#     value" wording, which would misdirect triage when the config file is
#     fine. The exit status is captured with an `if` (command substitution
#     failure under `set -euo pipefail` must not abort this script).
#   - The raw value is truncated and stripped of non-printables before it is
#     echoed back in a warning: the caller (skills/merge/SKILL.md Step 4) is an
#     LLM agent holding repo-write credentials, and the Bash tool merges stderr
#     into its context, so an unbounded verbatim echo of repository-controlled
#     text is not appropriate here. Same rationale as the 2048-char bound in
#     scripts/resolve-preview-env.sh.
#
# Output is always exactly one line (stdout). Warnings go to stderr only.
#
# bash 3.2+ compatible (no associative arrays, mapfile, or readarray).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: resolve-merge-strategy.sh [--flag|--help]

  (no argument)  Print the resolved merge-strategy name (squash|merge|rebase)
  --flag         Print the corresponding gh pr merge flag (--squash|--merge|--rebase)
  --help         Show this usage and exit 0
EOF
}

if [ $# -gt 1 ]; then
  echo "Error: unexpected extra argument: $2" >&2
  usage >&2
  exit 1
fi

MODE="name"
case "${1:-}" in
  "") ;;
  --flag)
    MODE="flag"
    ;;
  --help)
    usage
    exit 0
    ;;
  *)
    echo "Error: unknown argument: $1" >&2
    usage >&2
    exit 1
    ;;
esac

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

if RAW=$(bash "$SCRIPT_DIR/get-config-value.sh" merge-strategy squash 2>/dev/null); then
  CONFIG_READ_OK=true
else
  CONFIG_READ_OK=false
  RAW=""
fi

# Defensive only: get-config-value.sh's own `s/[[:space:]]*$//` already strips a
# trailing CR (POSIX [[:space:]] includes \r), so this is belt-and-braces against
# a future change there rather than a load-bearing transform.
RAW="${RAW%$'\r'}"

case "$RAW" in
  squash|merge|rebase)
    STRATEGY="$RAW"
    ;;
  *)
    if [ "$CONFIG_READ_OK" = "false" ]; then
      echo "Warning: could not read merge-strategy (get-config-value.sh failed or is missing); falling back to 'squash'." >&2
    else
      # Bound and sanitize before echoing repository-controlled text back to an
      # LLM caller (see the Fail-safe behavior notes at the top of this file).
      SAFE_RAW=$(printf '%s' "$RAW" | LC_ALL=C tr -cd '[:print:]' | cut -c1-40)
      echo "Warning: invalid merge-strategy '${SAFE_RAW}' in .wholework.yml; falling back to 'squash'." >&2
    fi
    STRATEGY="squash"
    ;;
esac

if [ "$MODE" = "flag" ]; then
  printf -- '--%s\n' "$STRATEGY"
else
  printf '%s\n' "$STRATEGY"
fi
