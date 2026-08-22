#!/usr/bin/env bash
# resolve-preview-env.sh
# Shared resolver for project-declared preview environment config, extracted
# from scripts/run-review.sh's _resolve_preview_url_command() (Issue #1410)
# so both the bash wrapper and skills/review/SKILL.md's Step 8.0 Fast path
# (direct /review execution) can resolve preview-url-command (Issue #1428).
# Extended with a basic-auth mode (Issue #1429) so modules/verify-executor.md
# and modules/browser-adapter.md can resolve preview-basic-auth-command from
# a direct /review execution, mirroring scripts/run-review.sh's
# _resolve_preview_basic_auth_command().
#
# Usage:
#   resolve-preview-env.sh url <pr-number>
#   resolve-preview-env.sh basic-auth <pr-number> [--format curl-config|user-pass]
#
# Output (mode=url):
#   Success: resolved URL printed to stdout (single line), exit 0.
#   Failure (any guard below): empty stdout, exit 0 (fail-open — callers treat
#     empty stdout as "fall back to the Deployments API lookup").
#     - preview-url-command not declared in .wholework.yml
#     - dependent command times out (30s), exits non-zero, or produces empty
#       output
#     - output exceeds 2048 chars
#     - output does not match ^https?://[^[:space:]/]+[^[:space:]]*$ (not an
#       http(s) URL, or trailing non-whitespace content after a valid URL)
#
# Output (mode=basic-auth):
#   Success: the path to a freshly created 600-permission temp file, printed
#     to stdout (single line), exit 0. Callers must not read or print the
#     file's contents — pass the path straight through. Two mutually
#     exclusive formats, selected with --format (default: curl-config, the
#     safer default since it does not hand back a plaintext credential pair):
#       - curl-config: one line, `user = "<escaped>"`, where <escaped> is the
#         full "username:password" string with `\` -> `\\` then `"` -> `\"`
#         applied (in that order). Ready to pass directly to
#         `curl --config <path>`.
#       - user-pass: two lines, username then password, with no escaping.
#         Callers read it with
#         `{ IFS= read -r U; IFS= read -r P; } < <path>`.
#     Callers must `rm -f` the returned path after use, whether the
#     consuming command succeeded or failed.
#   Failure (any guard below): empty stdout, exit 0 (fail-open — callers fall
#     back to unauthenticated access). No file is created.
#     - preview-basic-auth-command not declared in .wholework.yml
#     - dependent command times out (30s), exits non-zero, or produces empty
#       output
#     - output exceeds 2048 chars
#     - output (trimmed first line) is not in username:password format: must
#       contain `:`, with non-empty text on both sides of the first `:`
#
# Argument error (unknown mode, unknown --format value, non-numeric
#   pr-number, wrong argument count for the mode): exit 1. This is
#   fail-closed by design — a caller-side typo (e.g. an unsupported --format
#   value) must not be silently swallowed into the unauthenticated fallback.
#
# bash 3.2+ compatible (no mapfile/associative arrays, no ${var^^}).
#
# .wholework.yml is resolved relative to the main repository root (via
# `git worktree list --porcelain`), not the caller's CWD — this keeps the
# trust boundary identical whether the caller is scripts/run-review.sh
# (already runs from main repo root) or skills/review/SKILL.md's Step 8.0 /
# modules/verify-executor.md / modules/browser-adapter.md, each of which may
# be invoked directly from inside a PR worktree.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $(basename "$0") url <pr-number>" >&2
  echo "       $(basename "$0") basic-auth <pr-number> [--format curl-config|user-pass]" >&2
  exit 1
fi

MODE="$1"
PR_NUMBER="$2"

case "$MODE" in
  url)
    if [ $# -ne 2 ]; then
      echo "Usage: $(basename "$0") url <pr-number>" >&2
      exit 1
    fi
    ;;
  basic-auth)
    if [ $# -ne 2 ] && [ $# -ne 4 ]; then
      echo "Usage: $(basename "$0") basic-auth <pr-number> [--format curl-config|user-pass]" >&2
      exit 1
    fi
    ;;
  *)
    echo "Error: unknown mode: $MODE (supported: url, basic-auth)" >&2
    exit 1
    ;;
esac

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: PR number must be a positive integer, got: $PR_NUMBER" >&2
  exit 1
fi

FORMAT="curl-config"
if [ "$MODE" = "basic-auth" ] && [ $# -eq 4 ]; then
  if [ "$3" != "--format" ]; then
    echo "Error: unknown argument: $3 (expected --format)" >&2
    exit 1
  fi
  FORMAT="$4"
  if [ "$FORMAT" != "curl-config" ] && [ "$FORMAT" != "user-pass" ]; then
    echo "Error: unknown --format value: $FORMAT (supported: curl-config, user-pass)" >&2
    exit 1
  fi
fi

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

MAIN_REPO_ROOT="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')" || true
if [[ -n "$MAIN_REPO_ROOT" ]]; then
  cd "$MAIN_REPO_ROOT"
  [[ -d "$SCRIPT_DIR" ]] || SCRIPT_DIR="$MAIN_REPO_ROOT/scripts"
fi

if [ "$MODE" = "url" ]; then
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
    _resolved=$(cat "$_tmpout" 2>/dev/null) || true
    rm -f "$_tmpout"
  fi

  if [[ "$_resolved_status" -ne 0 ]]; then
    echo "Warning: preview-url-command exited non-zero (status=${_resolved_status}); falling back to Deployments API polling" >&2
    exit 0
  fi

  # Pure bash first-line extraction (no pipe) — a pipe here (e.g. `printf ... |
  # head -n 1`) risks SIGPIPE against a large multi-line `_resolved`: `head`
  # exits after line 1, `printf` is killed by SIGPIPE, and `pipefail` (set
  # above) propagates that as a nonzero status that aborts the script under
  # `set -e` before a perfectly valid first line is ever read.
  _resolved="${_resolved%%$'\n'*}"
  _resolved="${_resolved//$'\r'/}"
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
  if ! [[ "$_resolved_trimmed" =~ ^https?://[^[:space:]/]+[^[:space:]]*$ ]]; then
    echo "Warning: preview-url-command output is not an http(s) URL; falling back to Deployments API polling" >&2
    exit 0
  fi

  echo "$_resolved_trimmed"
  echo "Resolved PREVIEW_URL via preview-url-command for PR #${PR_NUMBER}" >&2
  exit 0
fi

# MODE == basic-auth
_cmd=$("$SCRIPT_DIR/get-config-value.sh" preview-basic-auth-command "" 2>/dev/null || echo "")
[[ -z "$_cmd" ]] && exit 0

_cmd="${_cmd//\{pr\}/$PR_NUMBER}"

_resolved=""
_resolved_status=0
if command -v timeout >/dev/null 2>&1; then
  _resolved=$(timeout --kill-after=10 30 bash -c "$_cmd" 2>/dev/null) || _resolved_status=$?
elif command -v gtimeout >/dev/null 2>&1; then
  _resolved=$(gtimeout 30 bash -c "$_cmd" 2>/dev/null) || _resolved_status=$?
else
  # No timeout/gtimeout available: same manual-watchdog bound as the url
  # mode above. The output temp file holds credentials, so its template
  # ends in X (BSD mktemp only randomizes a trailing XXXXXX run) and it is
  # always removed after being read, success or failure.
  mkdir -p .tmp 2>/dev/null || true
  _tmpout="$(mktemp .tmp/preview-basic-auth-command-output-XXXXXX)"
  bash -c "$_cmd" >"$_tmpout" 2>/dev/null &
  _cmd_pid=$!
  ( sleep 30; kill -0 "$_cmd_pid" 2>/dev/null && kill -9 "$_cmd_pid" 2>/dev/null ) &
  _watchdog_pid=$!
  wait "$_cmd_pid" 2>/dev/null && _resolved_status=0 || _resolved_status=$?
  kill "$_watchdog_pid" 2>/dev/null || true
  wait "$_watchdog_pid" 2>/dev/null || true
  _resolved=$(cat "$_tmpout" 2>/dev/null) || true
  rm -f "$_tmpout"
fi

if [[ "$_resolved_status" -ne 0 ]]; then
  echo "Warning: preview-basic-auth-command exited non-zero (status=${_resolved_status}); leaving Basic Auth unset" >&2
  exit 0
fi

# Pure bash first-line extraction (no pipe) — same SIGPIPE hazard under
# `set -euo pipefail` as the url mode above; the original
# _resolve_preview_basic_auth_command() used `printf ... | head -n 1 | tr -d`
# which does not carry this hazard inside a function (no `set -e` propagates
# out of a pipeline the same way), but this is now a standalone `set -e`
# script, so the pipe form is replaced with pure parameter expansion.
_resolved="${_resolved%%$'\n'*}"
_resolved="${_resolved//$'\r'/}"
_resolved_trimmed="${_resolved#"${_resolved%%[![:space:]]*}"}"
_resolved_trimmed="${_resolved_trimmed%"${_resolved_trimmed##*[![:space:]]}"}"

if [[ -z "$_resolved_trimmed" ]]; then
  echo "Warning: preview-basic-auth-command produced empty output; leaving Basic Auth unset" >&2
  exit 0
fi
if [[ "${#_resolved_trimmed}" -gt 2048 ]]; then
  echo "Warning: preview-basic-auth-command output exceeds 2048 chars; leaving Basic Auth unset" >&2
  exit 0
fi
if [[ "$_resolved_trimmed" != *:* ]] \
   || [[ -z "${_resolved_trimmed%%:*}" ]] \
   || [[ -z "${_resolved_trimmed#*:}" ]]; then
  echo "Warning: preview-basic-auth-command output is not in username:password format; leaving Basic Auth unset" >&2
  exit 0
fi

_user="${_resolved_trimmed%%:*}"
_pass="${_resolved_trimmed#*:}"

mkdir -p .tmp 2>/dev/null || true
if [ "$FORMAT" = "curl-config" ]; then
  # Template's X run must be at the very end — BSD mktemp (macOS default)
  # does not randomize a XXXXXX run followed by a literal suffix (e.g.
  # "-XXXXXX.cfg"), producing a predictable, colliding filename instead.
  _outfile="$(mktemp .tmp/curl-auth-XXXXXX)"
  # curl's -K/--config double-quoted string escaping (see the curl manual,
  # -K/--config): only \\ \" \t \n \r \v are recognized escapes; any other
  # backslash is passed through literally. Escaping `\` before `"` (in that
  # order) round-trips correctly for any password containing either
  # character — reversing the order would double-escape the backslash
  # introduced by the `"` substitution.
  _escaped="${_resolved_trimmed//\\/\\\\}"
  _escaped="${_escaped//\"/\\\"}"
  printf 'user = "%s"\n' "$_escaped" > "$_outfile"
else
  # user-pass: two unescaped lines. Deliberately not a sourceable
  # KEY='value' shell format — a password containing `'` would break that
  # quoting; plain `{ IFS= read -r U; IFS= read -r P; } < file` has no
  # quoting to break.
  _outfile="$(mktemp .tmp/preview-basic-auth-XXXXXX)"
  printf '%s\n%s\n' "$_user" "$_pass" > "$_outfile"
fi

echo "$_outfile"
echo "Resolved PREVIEW_BASIC_USER/PREVIEW_BASIC_PASS via preview-basic-auth-command for PR #${PR_NUMBER}" >&2
exit 0
