#!/usr/bin/env bash
# resolve-preview-env.sh
# Shared resolver for project-declared preview environment config, extracted
# from scripts/run-review.sh's _resolve_preview_url_command() (Issue #1410)
# so both the bash wrapper and skills/review/SKILL.md's Step 8.0 Fast path
# (direct /review execution) can resolve preview-url-command (Issue #1428).
#
# Usage: resolve-preview-env.sh url <pr-number>
#
# Output (mode=url):
#   Success: resolved URL printed to stdout (single line), exit 0.
#   Failure (any guard below): empty stdout, exit 0 (fail-open — callers treat
#     empty stdout as "fall back to the Deployments API lookup").
#     - preview-url-command not declared in .wholework.yml
#     - dependent command times out (30s), exits non-zero, or produces empty
#       output
#     - output exceeds 2048 chars
#     - output does not match ^https?://[^[:space:]/]+ (not an http(s) URL)
#   Argument error (unknown mode, non-numeric pr-number): exit 1.
#
# bash 3.2+ compatible (no mapfile/associative arrays).
#
# .wholework.yml is resolved relative to the main repository root (via
# `git worktree list --porcelain`), not the caller's CWD — this keeps the
# trust boundary identical whether the caller is scripts/run-review.sh
# (already runs from main repo root) or skills/review/SKILL.md's Step 8.0
# invoked directly from inside a PR worktree.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $(basename "$0") url <pr-number>" >&2
  exit 1
fi

MODE="$1"
PR_NUMBER="$2"

if [ "$MODE" != "url" ]; then
  echo "Error: unknown mode: $MODE (only 'url' is supported)" >&2
  exit 1
fi

if ! echo "$PR_NUMBER" | grep -qE '^[0-9]+$'; then
  echo "Error: PR number must be a positive integer, got: $PR_NUMBER" >&2
  exit 1
fi

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

MAIN_REPO_ROOT="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')" || true
if [[ -n "$MAIN_REPO_ROOT" ]]; then
  cd "$MAIN_REPO_ROOT"
  [[ -d "$SCRIPT_DIR" ]] || SCRIPT_DIR="$MAIN_REPO_ROOT/scripts"
fi

_cmd=$("$SCRIPT_DIR/get-config-value.sh" preview-url-command "" 2>/dev/null || echo "")
[[ -z "$_cmd" ]] && exit 0

_cmd="${_cmd//\{pr\}/$PR_NUMBER}"

_resolved=""
_resolved_status=0
if command -v timeout >/dev/null 2>&1; then
  _resolved=$(timeout --kill-after=10 30 bash -c "$_cmd" 2>/dev/null) || _resolved_status=$?
elif command -v gtimeout >/dev/null 2>&1; then
  _resolved=$(gtimeout 30 bash -c "$_cmd" 2>/dev/null) || _resolved_status=$?
else
  # No timeout/gtimeout available (e.g. stock macOS without coreutils):
  # bound the command manually via a background watchdog, since an
  # unbounded arbitrary project command would otherwise stall the caller
  # indefinitely.
  mkdir -p .tmp 2>/dev/null || true
  _tmpout=".tmp/preview-url-command-output.$$"
  bash -c "$_cmd" >"$_tmpout" 2>/dev/null &
  _cmd_pid=$!
  ( sleep 30; kill -0 "$_cmd_pid" 2>/dev/null && kill -9 "$_cmd_pid" 2>/dev/null ) &
  _watchdog_pid=$!
  wait "$_cmd_pid" 2>/dev/null && _resolved_status=0 || _resolved_status=$?
  kill "$_watchdog_pid" 2>/dev/null || true
  wait "$_watchdog_pid" 2>/dev/null || true
  _resolved=$(cat "$_tmpout" 2>/dev/null)
  rm -f "$_tmpout"
fi

if [[ "$_resolved_status" -ne 0 ]]; then
  echo "Warning: preview-url-command exited non-zero (status=${_resolved_status}); falling back to Deployments API polling" >&2
  exit 0
fi

_resolved=$(printf '%s' "$_resolved" | head -n 1 | tr -d '\r')
_resolved_trimmed="${_resolved#"${_resolved%%[![:space:]]*}"}"
_resolved_trimmed="${_resolved_trimmed%"${_resolved_trimmed##*[![:space:]]}"}"

if [[ -z "$_resolved_trimmed" ]]; then
  echo "Warning: preview-url-command produced empty output; falling back to Deployments API polling" >&2
  exit 0
fi
if [[ "${#_resolved_trimmed}" -gt 2048 ]]; then
  echo "Warning: preview-url-command output exceeds 2048 chars; falling back to Deployments API polling" >&2
  exit 0
fi
if ! [[ "$_resolved_trimmed" =~ ^https?://[^[:space:]/]+ ]]; then
  echo "Warning: preview-url-command output is not an http(s) URL; falling back to Deployments API polling" >&2
  exit 0
fi

echo "$_resolved_trimmed"
echo "Resolved PREVIEW_URL via preview-url-command for PR #${PR_NUMBER}" >&2
exit 0
