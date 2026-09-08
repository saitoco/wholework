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
# Fail-safe behavior (fail-safe critical — see Spec § Notes "fail-safe critical 判定"):
#   - A `merge-strategy` value that is empty, or does not exactly match
#     squash/merge/rebase (special characters, multibyte, CRLF, oversized,
#     etc.), falls back to `squash` with a warning on stderr. Exit 0 — this is
#     a warning, not an error. No value is ever re-interpreted by the shell
#     (no eval/expansion of the raw value).
#   - If get-config-value.sh exits non-zero or is missing, resolution
#     fail-closes silently to `squash` (the pre-existing behavior) — command
#     substitution failure under `set -euo pipefail` must not abort this
#     script, so the result is captured with `|| RAW=""`.
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

if [ $# -gt 1 ]; then
  echo "Error: unexpected extra argument: $2" >&2
  usage >&2
  exit 1
fi

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

RAW=$(bash "$SCRIPT_DIR/get-config-value.sh" merge-strategy squash 2>/dev/null) || RAW=""

# Strip a single trailing CR (accepts a value line saved with CRLF endings).
RAW="${RAW%$'\r'}"

case "$RAW" in
  squash|merge|rebase)
    STRATEGY="$RAW"
    ;;
  *)
    echo "Warning: invalid merge-strategy '${RAW}' in .wholework.yml; falling back to 'squash'." >&2
    STRATEGY="squash"
    ;;
esac

if [ "$MODE" = "flag" ]; then
  printf -- '--%s\n' "$STRATEGY"
else
  printf '%s\n' "$STRATEGY"
fi
