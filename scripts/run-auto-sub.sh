#!/bin/bash
# run-auto-sub.sh - Execute code→review→merge phases for each sub-issue.
# verify is deferred to the parent /auto session (issue #485)
#
# Usage: run-auto-sub.sh <sub-issue-number> [--base <branch>]

set -euo pipefail

# Resolved before cd (below) -- a relative $0 would break dirname resolution once CWD changes.
SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

# Absolute path to this script itself, resolved before cd (below) for the same reason
# as SCRIPT_DIR. Used by the spawn detachment shim, which re-execs this script after
# CWD has already changed to REPO_ROOT. Deliberately NOT derived from
# WHOLEWORK_SCRIPT_DIR: the shim must re-exec this exact script, not a test mock.
_SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# Repo root of the caller's actual working directory (the project being worked on),
# not the plugin's own install path. Resolved as the *main* worktree root even when
# this script is invoked from inside a non-main worktree (e.g. a code/review worktree
# CWD), so that recovery commits/pushes always target main -- never the calling
# worktree (see #1005: a --write-manual-recovery call run from a code worktree CWD
# pushed its record to that worktree's PR branch instead of main).
REPO_ROOT="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')" || true
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(pwd)"
fi
cd "$REPO_ROOT"
[[ -d "$SCRIPT_DIR" ]] || SCRIPT_DIR="$REPO_ROOT/scripts"

# --- Spawn detachment shim (issue #1142) --------------------------------------
# Opt-in via WHOLEWORK_SPAWN_DETACH=1: re-exec this wrapper as the leader of a new
# session/process group, so a process-group-wide external SIGKILL aimed at the
# spawning group cannot take down the wrapper subtree. macOS has no setsid(1)
# binary, so python3 subprocess start_new_session=True is used instead. Default
# (flag unset) leaves existing behavior completely unchanged. Experiment context:
# docs/reports/external-kill-investigation.md (H-a vs H-b' arbitration).
#
# Placement: must run after cd "$REPO_ROOT" so the .tmp/auto-session-${PGID}
# pointer read below resolves relative to the repo root.

# True when detachment is requested and this process is not already the re-exec'd
# child (_WHOLEWORK_DETACHED is the recursion guard set before re-exec).
_should_detach() {
  [[ "${WHOLEWORK_SPAWN_DETACH:-}" == "1" && -z "${_WHOLEWORK_DETACHED:-}" ]]
}

if _should_detach; then
  # Resolve AUTO_SESSION_ID with the CURRENT (pre-detach) PGID and burn it into
  # the environment: detaching changes the child's PGID, so the PGID-keyed
  # pointer file (read again on the main path below) would no longer match and
  # emitted events would lose their session_id.
  if [[ -z "${AUTO_SESSION_ID:-}" ]]; then
    _detach_pgid=$(ps -o pgid= -p $$ | tr -d ' ')
    AUTO_SESSION_ID="$(cat ".tmp/auto-session-${_detach_pgid}" 2>/dev/null || echo '')"
  fi
  if [[ -n "${AUTO_SESSION_ID:-}" ]]; then
    export AUTO_SESSION_ID
  fi
  export _WHOLEWORK_DETACHED=1
  # Synchronous by design: p.wait() keeps the caller-visible contract (blocking
  # call, exit code passthrough) identical to the non-detached path -- including
  # the --write-manual-recovery subcommand. A negative returncode (child killed
  # by signal N) is mapped to the conventional 128+N shell encoding so
  # retry-on-kill.sh's 137/143 detection keeps working through the shim.
  exec python3 -c '
import subprocess, sys
p = subprocess.Popen(sys.argv[1:], start_new_session=True)
rc = p.wait()
sys.exit(128 - rc if rc < 0 else rc)
' bash "$_SELF_PATH" "$@"
fi
# --- End spawn detachment shim -------------------------------------------------

# Pushes HEAD to origin, retrying with fetch+rebase on non-fast-forward rejection.
# Lock+push-only mode variant (no --from branch to rebase separately) of the push
# retry loop in scripts/worktree-merge-push.sh.
# See modules/orchestration-fallbacks.md#ff-only-merge-fallback
# Usage: _push_with_retry REPO_ROOT
# Returns 0 on success, 1 if all retries are exhausted or a step fails. Never exits
# the script -- callers keep their existing best-effort if/else WARNING handling.
_push_with_retry() {
  local repo_root="$1"
  local attempt=0
  local branch

  while true; do
    if git -C "$repo_root" push origin HEAD; then
      return 0
    fi
    attempt=$((attempt + 1))
    if [[ $attempt -ge 3 ]]; then
      return 1
    fi
    branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD) || return 1
    git -C "$repo_root" fetch origin "$branch" || return 1
    if ! git -C "$repo_root" rebase "origin/${branch}"; then
      git -C "$repo_root" rebase --abort 2>/dev/null || true
      return 1
    fi
  done
}

# Fast-forward-only pulls REPO_ROOT before a manual-recovery read/write/commit, so a
# local main left behind by an un-pulled prior merge (e.g. #1006: a PR merged between
# sessions) doesn't cause the subsequent commit's push to be rejected non-fast-forward.
# Non-fatal: on pull failure, warns to stderr and falls through -- callers proceed with
# their existing commit/push flow, with _push_with_retry as the secondary safety net.
# Must stay a single `git pull --ff-only` call (not a decomposed fetch+rebase): the
# "push retry: gives up after 3 attempts" bats test counts fetch/rebase invocations by
# grep -c and a decomposed form here would inflate that count.
# Usage: _pull_ff_only REPO_ROOT
_pull_ff_only() {
  local repo_root="$1"
  if ! git -C "$repo_root" pull --ff-only; then
    echo "WARNING: git pull --ff-only failed in ${repo_root}; continuing with possibly stale local state" >&2
  fi
  return 0
}

# Validates recovery function arguments to prevent path traversal via glob patterns.
# Usage: _validate_recovery_args ISSUE [PHASE] [RECOVERY_TYPE] [EXIT_CODE]
# Returns 1 and prints to stderr if any argument fails validation.
_validate_recovery_args() {
  local _issue="${1:-}"
  local _phase="${2:-}"
  local _recovery_type="${3:-}"
  local _exit_code="${4:-}"

  if [[ -z "$_issue" ]] || ! [[ "$_issue" =~ ^[0-9]+$ ]]; then
    echo "_validate_recovery_args: invalid issue: '${_issue}'" >&2
    return 1
  fi

  if [[ -n "$_phase" ]] && ! [[ "$_phase" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "_validate_recovery_args: invalid phase: '${_phase}'" >&2
    return 1
  fi

  if [[ -n "$_recovery_type" ]] && ! [[ "$_recovery_type" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "_validate_recovery_args: invalid recovery_type: '${_recovery_type}'" >&2
    return 1
  fi

  if [[ -n "$_exit_code" ]] && ! [[ "$_exit_code" =~ ^[0-9]+$ ]]; then
    echo "_validate_recovery_args: invalid exit_code: '${_exit_code}'" >&2
    return 1
  fi
}

# Returns the "number" of the first issue in a `gh issue list --json number,title,<DATE_FIELD>`
# result whose title exactly equals TARGET, sorted by DATE_FIELD descending. Empty
# output on no match or any failure (gh error, empty/malformed JSON) -- never exits the script.
# Uses exact-title matching (not substring/"contains") so a bare group-key TARGET (e.g.
# "recoveries: manual-recovery-review-rerun") never accidentally matches a cause-suffixed
# sibling title (e.g. "recoveries: manual-recovery-review-rerun/dirty-guard") or vice versa
# -- see Issue #1123 review: a "contains" policy makes the bare key a string prefix of every
# cause-specific key once cause-aware group-keys (<symptom-short>/<cause-slug>) exist, causing
# the bare-key group to be silently and permanently treated as already-filed. Kept consistent
# with scripts/collect-recovery-candidates.sh's duplicate check (also exact-match as of #1123).
# Usage: _search_recoveries_issue TARGET STATE DATE_FIELD LIMIT
_search_recoveries_issue() {
  local target="$1"
  local state="$2"
  local date_field="$3"
  local limit="$4"
  local issues_json
  issues_json="$(gh issue list --state "$state" --json "number,title,${date_field}" --limit "$limit" 2>/dev/null)" || issues_json=""
  [[ -z "$issues_json" ]] && return 0
  printf '%s' "$issues_json" | python3 -c "
import json, sys
target = sys.argv[1]
date_field = sys.argv[2]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
matches = [item for item in data if item.get('title', '') == target]
matches.sort(key=lambda item: item.get(date_field) or '', reverse=True)
if matches:
    print(matches[0].get('number', ''))
" "$target" "$date_field" 2>/dev/null || true
}

# Resolves the known Issue number for a given symptom-short (e.g.
# "manual-recovery-push-only") by matching `recoveries: <symptom-short>` against Issue
# titles (exact match, see _search_recoveries_issue). Prefers an open Issue (most
# recently created); falls back to the most recently closed Issue if no open match exists.
# Empty output if neither search matches.
# Usage: _find_known_recoveries_issue SYMPTOM_SHORT
_find_known_recoveries_issue() {
  local symptom_short="$1"
  local target="recoveries: ${symptom_short}"
  local matched
  matched="$(_search_recoveries_issue "$target" open createdAt 500)"
  if [[ -n "$matched" ]]; then
    printf '%s' "$matched"
    return 0
  fi
  _search_recoveries_issue "$target" closed closedAt 1000
}

# _write_manual_recovery_to_recoveries_log ISSUE PHASE RECOVERY_TYPE [EXIT_CODE] [CAUSE] [DIAGNOSIS]
# Records a parent-session-driven manual recovery event to orchestration-recoveries.md,
# in the canonical H2 entry format so scripts/collect-recovery-candidates.sh can pick it
# up for frequency detection / recoveries-auto-fire (unlike the H3 wrapper-retry-on-kill
# entries defined further below -- see #1005 spec Notes). Defined here, immediately
# after _search_recoveries_issue / _find_known_recoveries_issue since it depends on them,
# and before the --write-manual-recovery dispatch below which calls it before an early
# exit, so it must be defined earlier in the script than that call site (bash only
# registers a function once its definition line has executed).
# Skips silently if the file does not exist (file not in repo → return 0).
# See modules/orchestration-fallbacks.md#external-kill-parent-respawn
#
# CAUSE/DIAGNOSIS (Issue #1123): when CAUSE is supplied, the H2 header and _is_duplicate()
# duplicate-detection regex are left unchanged (avoids touching the existing 4 recoveries-log
# entries and tests/collect-recovery-candidates.bats fixtures) -- only the ### Diagnosis body
# gains a machine-readable "- cause: <slug>" line, and the group key passed to
# _find_known_recoveries_issue becomes "<symptom-short>/<cause>" so scripts/collect-recovery-
# candidates.sh's cause-aware grouping (reads the "- cause:" line back out) can separate
# same-symptom-different-cause events instead of merging them.
_write_manual_recovery_to_recoveries_log() {
  local issue="$1"
  local phase="${2:-unknown}"
  local recovery_type="${3:-unspecified}"
  local exit_code="${4:-unknown}"
  local cause="${5:-}"
  local diagnosis="${6:-}"
  local _repo_root="$REPO_ROOT"
  local _recoveries_file="${_repo_root}/docs/reports/orchestration-recoveries.md"
  _pull_ff_only "$_repo_root"
  if [[ ! -f "$_recoveries_file" ]]; then
    return 0
  fi
  local _symptom_short="manual-recovery-${recovery_type}"
  local _group_key="$_symptom_short"
  if [[ -n "$cause" ]]; then
    _group_key="${_symptom_short}/${cause}"
  fi
  local _matched_issue
  _matched_issue="$(_find_known_recoveries_issue "$_group_key")"
  local _improvement_candidate="未起票"
  if [[ -n "$_matched_issue" ]]; then
    _improvement_candidate="起票済み #${_matched_issue}"
  fi
  local _date
  _date=$(date -u '+%Y-%m-%d %H:%M UTC')
  # cause/diagnosis are passed to Python via environment variables (WW_CAUSE/WW_DIAGNOSIS)
  # rather than interpolated into the heredoc's Python source text. Interpolation requires
  # escaping every character with meaning inside a Python string literal; the previous
  # backslash/double-quote-only sed escaping did not cover newlines, so a --diagnosis value
  # containing a newline broke the embedded string literal with a SyntaxError that the
  # `2>/dev/null || true` below silently discarded -- a silent no-op (Issue #1123 review
  # finding). Environment variables carry arbitrary text (including newlines) verbatim with
  # no source-text escaping needed.
  WW_CAUSE="$cause" WW_DIAGNOSIS="$diagnosis" python3 << PYEOF 2>/dev/null || true
import os
import re
from datetime import datetime, timezone, timedelta

fpath = "${_recoveries_file}"
marker = "<!-- Log entries appear below, newest first. -->"
symptom_short = "${_symptom_short}"
context_line = "- Issue #${issue}, phase: ${phase}"

_cause = os.environ.get("WW_CAUSE", "")
_diagnosis = os.environ.get("WW_DIAGNOSIS", "")
if _cause:
    _diagnosis_text = _diagnosis or "Parent session recovered the phase outside the Tier 1/2/3 machinery (recovery type: ${recovery_type})"
    _diagnosis_body = "- cause: {}\n- {}\n".format(_cause, _diagnosis_text)
else:
    _diagnosis_body = "- Parent session recovered the phase outside the Tier 1/2/3 machinery (recovery type: ${recovery_type})\n"

entry = (
    "\n## ${_date}: manual-recovery-${recovery_type}\n"
    "\n### Context\n"
    "- Issue #${issue}, phase: ${phase}\n"
    "- Source: parent-session-manual-recovery\n"
    "- Wrapper: run-auto-sub.sh, exit code: ${exit_code}\n"
    "\n### Diagnosis\n"
    + _diagnosis_body +
    "\n### Recovery Applied\n"
    "- modules/orchestration-fallbacks.md#manual-recovery-spec-write\n"
    "\n### Outcome\n"
    "- success\n"
    "\n### Improvement Candidate\n"
    "- ${_improvement_candidate}\n"
)

def _is_duplicate(tail):
    now = datetime.now(timezone.utc)
    for m in re.finditer(
        r"^## (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) UTC: (\S+)\n(.*?)(?=\n## |\Z)",
        tail,
        re.DOTALL | re.MULTILINE,
    ):
        ts_str, existing_symptom, block = m.group(1), m.group(2), m.group(3)
        if existing_symptom != symptom_short or context_line not in block:
            continue
        try:
            existing_ts = datetime.strptime(ts_str, "%Y-%m-%d %H:%M").replace(tzinfo=timezone.utc)
        except ValueError:
            continue
        if now - existing_ts <= timedelta(hours=24):
            return True
    return False

try:
    content = open(fpath).read()
    idx = content.find(marker)
    if idx != -1:
        pos = idx + len(marker)
        if _is_duplicate(content[pos:]):
            print("[#${issue}] [recovery] manual-recovery-${recovery_type} already recorded for issue #${issue} phase ${phase} within the last 24h; skipping duplicate recoveries log entry")
        else:
            content = content[:pos] + entry + content[pos:]
            open(fpath, "w").write(content)
except Exception:
    pass
PYEOF
  if ! git -C "$_repo_root" diff --quiet "docs/reports/orchestration-recoveries.md" 2>/dev/null; then
    if git -C "$_repo_root" add "docs/reports/orchestration-recoveries.md" \
       && git -C "$_repo_root" commit -s -m "Record manual-recovery-${recovery_type} recovery for issue #${issue} ${phase}

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" \
       && _push_with_retry "$_repo_root"; then
      echo "[#${issue}] [recovery] manual-recovery-${recovery_type} recovery log committed and pushed"
    else
      echo "[#${issue}] WARNING: could not commit/push manual recovery log" >&2
    fi
  fi
}

if [[ "${1:-}" == "--write-manual-recovery" ]]; then
  shift
  if [[ -z "${1:-}" ]]; then
    echo "Error: --write-manual-recovery requires: ISSUE [PHASE] [RECOVERY_TYPE] [EXIT_CODE] [--cause SLUG] [--diagnosis TEXT]" >&2
    exit 1
  fi
  _mr_issue="$1"
  shift
  # Positional args (PHASE, RECOVERY_TYPE, EXIT_CODE) keep their original order/meaning
  # regardless of where --cause/--diagnosis appear among the remaining arguments (Issue #1123).
  _mr_phase="unknown"
  _mr_recovery_type="unspecified"
  # EXIT_CODE left un-defaulted (unlike PHASE/RECOVERY_TYPE above): passed through as-is to
  # _validate_recovery_args, which only applies its numeric-format check when non-empty.
  # Defaulting to the literal "unknown" here would make that check fail every time no
  # EXIT_CODE is supplied, since "unknown" does not match ^[0-9]+$.
  _mr_exit_code=""
  _mr_cause=""
  _mr_diagnosis=""
  _mr_pos_idx=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cause)
        [[ $# -ge 2 ]] || { echo "Error: --cause requires a value" >&2; exit 1; }
        _mr_cause="$2"
        shift 2
        ;;
      --diagnosis)
        [[ $# -ge 2 ]] || { echo "Error: --diagnosis requires a value" >&2; exit 1; }
        _mr_diagnosis="$2"
        shift 2
        ;;
      *)
        case "$_mr_pos_idx" in
          0) _mr_phase="$1" ;;
          1) _mr_recovery_type="$1" ;;
          2) _mr_exit_code="$1" ;;
        esac
        _mr_pos_idx=$((_mr_pos_idx + 1))
        shift
        ;;
    esac
  done

  _validate_recovery_args "$_mr_issue" "$_mr_phase" "$_mr_recovery_type" "$_mr_exit_code"

  source "$SCRIPT_DIR/emit-event.sh"
  restore_auto_session_pointer
  export EMIT_ISSUE_NUMBER="$_mr_issue"

  _write_manual_recovery_to_recoveries_log "$_mr_issue" "$_mr_phase" "$_mr_recovery_type" "$_mr_exit_code" "$_mr_cause" "$_mr_diagnosis"
  emit_event "manual_intervention" "recovery_target=${_mr_phase}" "wrapper_exit_code=${_mr_exit_code:-unknown}" "intervention_type=${_mr_recovery_type}"
  exit 0
fi

SUB_NUMBER="${1:?Usage: run-auto-sub.sh <sub-issue-number> [--base <branch>]}"
shift

# Parse options
BASE_BRANCH=""
BASE_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --base requires a branch name" >&2
        exit 1
      fi
      BASE_BRANCH="$2"
      BASE_FLAG="--base $2"
      shift 2
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      echo "Usage: run-auto-sub.sh <sub-issue-number> [--base <branch>]" >&2
      exit 1
      ;;
  esac
done

if ! [[ "$SUB_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Issue number must be numeric: $SUB_NUMBER" >&2
  exit 1
fi

# Session isolation check: detect other-session dirty files (best-effort)
if [[ -x "${SCRIPT_DIR}/check-verify-dirty.sh" ]]; then
  _dirty_exit=0
  bash "${SCRIPT_DIR}/check-verify-dirty.sh" "${SUB_NUMBER}" || _dirty_exit=$?
  case "${_dirty_exit}" in
    0) ;;
    1)
      echo "Error: parent main has uncommitted changes. Resolve before proceeding." >&2
      exit 1
      ;;
    2)
      echo "Warning: detected other-session dirty files. Proceeding (best-effort)." >&2
      ;;
  esac
fi
LOG_PREFIX="[#${SUB_NUMBER}]"
AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
export AUTO_EVENTS_LOG
PGID=$(ps -o pgid= -p $$ | tr -d ' ')
AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || echo '')}"
export AUTO_SESSION_ID
export EMIT_ISSUE_NUMBER="$SUB_NUMBER"

source "$SCRIPT_DIR/emit-event.sh"
source "$SCRIPT_DIR/retry-on-kill.sh"

_maybe_emit_phase_complete() {
  local _exit_code=$?
  [[ "$_exit_code" -ne 0 && "$_exit_code" -ne 143 ]] && return 0
  [[ -z "${AUTO_EVENTS_LOG:-}" ]] && return 0
  [[ -z "${AUTO_SESSION_ID:-}" ]] && return 0
  [[ -z "${EMIT_ISSUE_NUMBER:-}" ]] && return 0
  [[ -z "${EMIT_PHASE_NAME:-}" ]] && return 0
  local _last_event _last_checkpoint _last_json
  _last_json=$(grep "\"session_id\":\"${AUTO_SESSION_ID}\"" "${AUTO_EVENTS_LOG}" 2>/dev/null \
      | jq -rs --argjson n "${EMIT_ISSUE_NUMBER}" \
        '[.[] | select(.issue == $n)] | last // empty' 2>/dev/null || true)
  _last_event=$(echo "${_last_json}" | jq -r '.event // ""' 2>/dev/null || true)
  _last_checkpoint=$(echo "${_last_json}" | jq -r '.checkpoint // ""' 2>/dev/null || true)
  # wrapper_alive checkpoint=pre_subprocess is emitted right after phase_start and before the
  # blocking subprocess call, so it carries the same "phase not yet complete" meaning as
  # phase_start for backfill purposes. The other checkpoints (pre_phase_dispatch,
  # post_code_pre_review) occur in gaps AFTER a phase has already completed normally, so they
  # must NOT trigger a backfill here — doing so would emit a duplicate phase_complete for a
  # phase that already recorded one. (#1045)
  if [[ "${_last_event}" == "phase_start" ]] || \
     { [[ "${_last_event}" == "wrapper_alive" ]] && [[ "${_last_checkpoint}" == "pre_subprocess" ]]; }; then
    local _ts; _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local _pr_field=""
    [[ -n "${EMIT_PR_NUMBER:-}" ]] && _pr_field=",\"pr\":${EMIT_PR_NUMBER}"
    printf '%s\n' \
      "{\"ts\":\"${_ts}\",\"issue\":${EMIT_ISSUE_NUMBER},\"event\":\"phase_complete\",\"session_id\":\"${AUTO_SESSION_ID}\"${_pr_field},\"phase\":\"${EMIT_PHASE_NAME}\",\"backfilled\":true}" \
      >> "${AUTO_EVENTS_LOG}" 2>/dev/null || true
  fi
}
trap '_maybe_emit_phase_complete' EXIT

# _emit_comments_consumed() is now defined in emit-event.sh (Issue #791).
# Sourced via: source "$SCRIPT_DIR/emit-event.sh" above.

# _write_wrapper_retry_recovery ISSUE PHASE EXIT_CODE [RUNNER_SCRIPT_NAME]
# Records a wrapper-retry-on-kill recovery event to orchestration-recoveries.md, in the
# canonical H2 entry format so scripts/collect-recovery-candidates.sh can pick it up for
# frequency detection / recoveries-auto-fire (see #1009; previously an H3 entry that the
# H2-only parser skipped over).
# Skips silently if the file does not exist (file not in repo → return 0).
# See modules/orchestration-fallbacks.md#wrapper-retry-on-kill
_write_wrapper_retry_recovery() {
  local issue="$1"
  local phase="$2"
  local exit_code_arg="$3"
  local runner_name="${4:-run-auto-sub.sh}"
  local _repo_root="$REPO_ROOT"
  local _recoveries_file="${_repo_root}/docs/reports/orchestration-recoveries.md"
  if [[ ! -f "$_recoveries_file" ]]; then
    return 0
  fi
  local _date _outcome
  _date=$(date -u '+%Y-%m-%d %H:%M UTC')
  if [[ "$exit_code_arg" -eq 0 ]]; then
    _outcome="success"
  else
    _outcome="escalated (retry also killed)"
  fi
  local _matched_issue
  _matched_issue="$(_find_known_recoveries_issue "wrapper-retry-on-kill")"
  local _improvement_candidate="未起票"
  if [[ -n "$_matched_issue" ]]; then
    _improvement_candidate="起票済み #${_matched_issue}"
  fi
  python3 << PYEOF 2>/dev/null || true
fpath = "${_recoveries_file}"
marker = "<!-- Log entries appear below, newest first. -->"
entry = (
    "\n## ${_date}: wrapper-retry-on-kill\n"
    "\n### Context\n"
    "- Issue #${issue}, phase: ${phase}\n"
    "- Source: retry-on-kill.sh\n"
    "- Wrapper: ${runner_name}, exit code: ${exit_code_arg}\n"
    "\n### Diagnosis\n"
    "- wrapper (${runner_name}) が early-kill window (WHOLEWORK_RETRY_ON_KILL_MAX_SEC) 内に exit code ${exit_code_arg} で終了し、retry-on-kill.sh が自動再試行した\n"
    "\n### Recovery Applied\n"
    "- modules/orchestration-fallbacks.md#wrapper-retry-on-kill\n"
    "\n### Outcome\n"
    "- ${_outcome}\n"
    "\n### Improvement Candidate\n"
    "- ${_improvement_candidate}\n"
)
try:
    content = open(fpath).read()
    idx = content.find(marker)
    if idx != -1:
        pos = idx + len(marker)
        content = content[:pos] + entry + content[pos:]
        open(fpath, "w").write(content)
except Exception:
    pass
PYEOF
  if ! git -C "$_repo_root" diff --quiet "docs/reports/orchestration-recoveries.md" 2>/dev/null; then
    if git -C "$_repo_root" add "docs/reports/orchestration-recoveries.md" \
       && git -C "$_repo_root" commit -s -m "Record wrapper-retry-on-kill recovery for issue #${issue} ${phase}

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" \
       && _push_with_retry "$_repo_root"; then
      echo "${LOG_PREFIX} [recovery] wrapper-retry-on-kill recovery log committed and pushed"
    else
      echo "${LOG_PREFIX} WARNING: could not commit/push wrapper-retry-on-kill recovery log" >&2
    fi
  fi
}

# _observe_code_milestone NUMBER
# Probes observable git/GitHub state to determine the current code_phase_milestone value.
# Used by the pr-route resume preamble to reconcile the checkpoint with live state.
# Priority: post-PR-create > post-push > post-commit > pre-commit > initial
# Uses 2>/dev/null guards to avoid failures in offline/test environments.
_observe_code_milestone() {
  local number="$1"
  local branch_name="worktree-code+issue-${number}"
  local repo_root="$REPO_ROOT"

  # Check for open PR with this branch as head
  local pr_match
  pr_match=$(gh pr list --json headRefName,state 2>/dev/null | \
    jq -r ".[] | select(.headRefName == \"${branch_name}\") | select(.state == \"OPEN\") | .headRefName" \
    2>/dev/null || true)
  if [[ -n "$pr_match" ]]; then
    echo "post-PR-create"
    return
  fi

  # Check for remote branch
  if git -C "$repo_root" ls-remote --heads origin "$branch_name" 2>/dev/null | grep -q .; then
    echo "post-push"
    return
  fi

  # Check for local branch with commits ahead of base
  local ahead
  ahead=$(git -C "$repo_root" rev-list "$branch_name" \
    --not "${BASE_BRANCH:-main}" --count 2>/dev/null || echo "0")
  if [[ "${ahead:-0}" -gt 0 ]]; then
    echo "post-commit"
    return
  fi

  # Check for dirty worktree (uncommitted changes)
  local worktree_dir="${repo_root}/.claude/worktrees/code+issue-${number}"
  if [[ -d "$worktree_dir" ]] && \
     git -C "$worktree_dir" status --porcelain 2>/dev/null | grep -q .; then
    echo "pre-commit"
    return
  fi

  echo "initial"
}

run_phase_with_recovery() {
  local phase issue runner_script exit_code log_file
  phase="$1"; issue="$2"; runner_script="$3"; shift 3
  _TIER3_RECOVERY_ACTION=""

  mkdir -p .tmp
  log_file=".tmp/wrapper-out-${issue}-${phase}.log"

  if [[ -n "${_EXTRA_SELF_ISSUE:-}" ]] && [[ "${_EXTRA_SELF_ISSUE}" != "${issue}" ]]; then
    export EMIT_ISSUE_NUMBER="$_EXTRA_SELF_ISSUE"
    export EMIT_PR_NUMBER="$issue"
  else
    export EMIT_ISSUE_NUMBER="$issue"
    unset EMIT_PR_NUMBER
  fi
  export EMIT_PHASE_NAME="$phase"

  # Bash-side comments_consumed emit for code phases (issue-level comment consumption).
  # Emitted before phase_start so _maybe_emit_phase_complete backfill detection
  # still sees phase_start as the last event when phase_complete is absent. (Issue #705)
  if [[ "$phase" == code* ]]; then
    _emit_comments_consumed "$issue" "code" || true
  fi

  local PHASE_START
  PHASE_START=$(date +%s)
  emit_event "phase_start" "phase=${phase}"
  emit_event "wrapper_alive" "checkpoint=pre_subprocess" "phase=${phase}"

  set +e
  # See modules/orchestration-fallbacks.md#wrapper-retry-on-kill
  run_with_retry_on_kill "$runner_script" "$issue" "$@" > "$log_file" 2>&1
  exit_code=$?
  set -e

  if [[ "${_RETRY_ON_KILL_FIRED:-false}" == "true" ]]; then
    _write_wrapper_retry_recovery "$EMIT_ISSUE_NUMBER" "$phase" "$exit_code" "$(basename "$runner_script")"
  fi

  emit_event "wrapper_exit" "phase=${phase}" "exit_code=${exit_code}"

  # token_usage: parse from TOKEN_USAGE_FILE if it exists
  local _token_usage_file=".tmp/token-usage-${issue}.json"
  if [[ -f "$_token_usage_file" ]]; then
    local _model _input _output _cache_read
    _model=$(jq -r '.modelUsage // {} | to_entries | if length == 0 then empty else (max_by(.value.inputTokens + .value.outputTokens) | .key) end' "$_token_usage_file" 2>/dev/null || true)
    _input=$(jq -r '.usage.input_tokens // empty' "$_token_usage_file" 2>/dev/null || true)
    _output=$(jq -r '.usage.output_tokens // empty' "$_token_usage_file" 2>/dev/null || true)
    _cache_read=$(jq -r '.usage.cache_read_input_tokens // empty' "$_token_usage_file" 2>/dev/null || true)
    if [[ -n "$_input" ]]; then
      emit_event "token_usage" "phase=${phase}" \
        "model=${_model:-unknown}" \
        "input_tokens=${_input}" \
        "output_tokens=${_output:-0}" \
        "cache_read_tokens=${_cache_read:-0}"
    fi
  fi

  # concurrent_commit_detected: check for commits on origin/main since phase start,
  # excluding this issue's own phase commits (identified via #N in the subject line).
  # For review/merge phases, `issue` holds the PR number, but self-commits (squash
  # merge, phase handoffs) reference the originating Issue number instead — callers
  # set _EXTRA_SELF_ISSUE to that Issue number so both are excluded (issue #974).
  local _commits
  _commits=$(git log origin/main --since="@${PHASE_START}" --format="%H %an" 2>/dev/null || true)
  if [[ -n "$_commits" ]]; then
    local _phase_end; _phase_end=$(date +%s)
    local _since_sec=$(( _phase_end - PHASE_START ))
    local _self_issue_pattern="#${issue}([^0-9]|$)"
    if [[ -n "${_EXTRA_SELF_ISSUE:-}" ]] && [[ "${_EXTRA_SELF_ISSUE}" != "${issue}" ]]; then
      _self_issue_pattern="#(${issue}|${_EXTRA_SELF_ISSUE})([^0-9]|$)"
    fi
    while IFS= read -r _commit_line; do
      [[ -z "$_commit_line" ]] && continue
      local _sha="${_commit_line%% *}"
      local _author="${_commit_line#* }"
      local _subject; _subject=$(git log -1 --format="%s" "$_sha" 2>/dev/null || true)
      if [[ "$_subject" =~ $_self_issue_pattern ]]; then
        continue
      fi
      emit_event "concurrent_commit_detected" "phase=${phase}" \
        "commit_sha=${_sha}" \
        "author=${_author}" \
        "since_phase_start_sec=${_since_sec}"
    done <<< "$_commits"
  fi

  # test_result: parse bats output from log_file (code-patch / code-pr / code phases)
  if [[ "$phase" == code* ]] && [[ -f "$log_file" ]]; then
    local _bats_line
    _bats_line=$(grep -E "[0-9]+ tests?, [0-9]+ failures?" "$log_file" 2>/dev/null | tail -1 || true)
    if [[ -n "$_bats_line" ]]; then
      local _passed _failed
      _passed=$(echo "$_bats_line" | grep -oE "^[0-9]+" || echo 0)
      _failed=$(echo "$_bats_line" | grep -oE "[0-9]+ failures?" | grep -oE "^[0-9]+" || echo 0)
      emit_event "test_result" "phase=${phase}" \
        "framework=bats" \
        "passed=${_passed}" \
        "failed=${_failed}" \
        "pattern=unit"
    fi
  fi

  # _complete_phase_after_success: shared by the first-try success path and
  # the PENDING-retry success path below so both get the same silent no-op
  # anomaly detection (issue #1115 review feedback).
  _complete_phase_after_success() {
    local anomaly_out
    anomaly_out=$("$SCRIPT_DIR/detect-wrapper-anomaly.sh" --log "$log_file" --exit-code 0 --issue "$issue" --phase "$phase" 2>/dev/null || true)
    if [[ -n "$anomaly_out" ]]; then
      echo "${LOG_PREFIX} [anomaly] silent no-op detected in ${phase}:"
      echo "$anomaly_out"
    fi
    emit_event "phase_complete" "phase=${phase}"
  }

  if [[ $exit_code -eq 0 ]]; then
    _complete_phase_after_success
    return 0
  fi

  # PENDING pre-check (review phase only): run-review.sh exit code 2 means
  # CI/preview state is not yet confirmed — an intended non-failure wait
  # state, not an anomaly. Retry after a delay, bounded, before falling
  # through to Tier 1/2/3 recovery. See
  # modules/orchestration-fallbacks.md#review-pending-not-failure
  if [[ "$phase" == "review" ]] && [[ $exit_code -eq 2 ]]; then
    local _pending_retry_sec="${WHOLEWORK_REVIEW_PENDING_RETRY_SEC:-300}"
    local _pending_max_retries="${WHOLEWORK_REVIEW_PENDING_MAX_RETRIES:-2}"
    local _pending_attempt=0
    while [[ $exit_code -eq 2 ]] && [[ $_pending_attempt -lt $_pending_max_retries ]]; do
      _pending_attempt=$((_pending_attempt + 1))
      echo "${LOG_PREFIX} [pending] review phase PENDING (exit 2); retry ${_pending_attempt}/${_pending_max_retries} after ${_pending_retry_sec}s"
      sleep "$_pending_retry_sec"
      set +e
      run_with_retry_on_kill "$runner_script" "$issue" "$@" > "$log_file" 2>&1
      exit_code=$?
      set -e
    done
    if [[ $exit_code -eq 0 ]]; then
      echo "${LOG_PREFIX} [pending] review phase completed after PENDING retry"
      _complete_phase_after_success
      return 0
    fi
  fi

  # Tier 1: reconciler (bash, cheap) — completion check
  # See modules/orchestration-fallbacks.md (Observe-Diagnose-Act pattern)
  if "$SCRIPT_DIR/reconcile-phase-state.sh" "$phase" "$issue" --check-completion 2>/dev/null | grep -q '"matches_expected":true'; then
    echo "${LOG_PREFIX} [recovery] tier1 reconciler: phase completed despite wrapper exit $exit_code"
    emit_event "recovery" "phase=${phase}" "tier=1" "result=recovered"
    emit_event "phase_complete" "phase=${phase}"
    return 0
  fi

  # Tier 2: fallback catalog (bash, cheap) — known pattern recovery
  # See modules/orchestration-fallbacks.md#code-patch-silent-no-op
  local _fallback_exit=0
  mkdir -p .tmp
  "$SCRIPT_DIR/apply-fallback.sh" "$phase" "$issue" --log "$log_file" --record-issue "$EMIT_ISSUE_NUMBER" > /dev/null 2>/dev/null || _fallback_exit=$?
  if [[ $_fallback_exit -eq 0 ]]; then
    echo "${LOG_PREFIX} [recovery] tier2 fallback catalog: recovered"
    local _repo_root="$REPO_ROOT"
    if ! git -C "$_repo_root" diff --quiet "docs/reports/orchestration-recoveries.md" 2>/dev/null; then
      if git -C "$_repo_root" add "docs/reports/orchestration-recoveries.md" \
         && git -C "$_repo_root" commit -s -m "Record Tier 2 recovery event for issue #${EMIT_ISSUE_NUMBER} ${phase} phase" \
         && _push_with_retry "$_repo_root"; then
        echo "${LOG_PREFIX} [recovery] recovery log committed and pushed"
      else
        echo "${LOG_PREFIX} WARNING: could not commit/push recovery log; /verify may detect dirty file" >&2
      fi
    fi
    emit_event "recovery" "phase=${phase}" "tier=2" "result=recovered"
    emit_event "phase_complete" "phase=${phase}"
    return 0
  fi
  if [[ $_fallback_exit -eq 2 ]]; then
    echo "${LOG_PREFIX} [recovery] tier2 fallback catalog: anchor matched but handler failed"
    emit_event "recovery" "phase=${phase}" "tier=2" "result=failed"
  fi

  # Tier 3: recovery sub-agent via claude -p (expensive, unknown anomaly only)
  if "$SCRIPT_DIR/spawn-recovery-subagent.sh" "$phase" "$issue" --log "$log_file" --exit-code "$exit_code" --record-issue "$EMIT_ISSUE_NUMBER"; then
    echo "${LOG_PREFIX} [recovery] tier3 sub-agent: recovered"
    local _plan_file=".tmp/recovery-plan-${issue}-${phase}.json"
    _TIER3_RECOVERY_ACTION=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('action','unknown'))" "$_plan_file" 2>/dev/null || echo "unknown")
    rm -f "$_plan_file"
    local _repo_root="$REPO_ROOT"
    if ! git -C "$_repo_root" diff --quiet "docs/reports/orchestration-recoveries.md" 2>/dev/null; then
      if git -C "$_repo_root" add "docs/reports/orchestration-recoveries.md" \
         && git -C "$_repo_root" commit -s -m "Record Tier 3 recovery event for issue #${EMIT_ISSUE_NUMBER} ${phase} phase" \
         && _push_with_retry "$_repo_root"; then
        echo "${LOG_PREFIX} [recovery] recovery log committed and pushed"
      else
        echo "${LOG_PREFIX} WARNING: could not commit/push recovery log; /verify may detect dirty file" >&2
      fi
    fi
    emit_event "recovery" "phase=${phase}" "tier=3" "result=recovered"
    emit_event "phase_complete" "phase=${phase}"
    return 0
  else
    local _plan_file=".tmp/recovery-plan-${issue}-${phase}.json"
    local _tier3_fail_action="unknown"
    if [[ -f "$_plan_file" ]]; then
      _tier3_fail_action=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('action','unknown'))" "$_plan_file" 2>/dev/null || echo "unknown")
      rm -f "$_plan_file"
    fi
    emit_event "recovery" "phase=${phase}" "tier=3" "result=failed" "action=${_tier3_fail_action}"
  fi

  return $exit_code
}

echo "${LOG_PREFIX} === run-auto-sub.sh: Starting sub-issue #${SUB_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
print_start_banner "issue" "$SUB_NUMBER" "auto"
echo "${LOG_PREFIX} Started at: $(date '+%Y-%m-%d %H:%M:%S')"
if [[ -n "$BASE_BRANCH" ]]; then
  echo "${LOG_PREFIX} Base branch: ${BASE_BRANCH}"
fi
echo "${LOG_PREFIX} ---"

# Determine route by fetching Size (before spec phase)
SIZE=$("$SCRIPT_DIR/get-issue-size.sh" --no-cache "$SUB_NUMBER" 2>/dev/null || true)

emit_event "sub_start" "size=${SIZE}"

# spec phase: run only if phase/ready is absent AND the issue hasn't already progressed
# past spec. "spec 完了以降" (spec-complete-or-later) covers phase/code, phase/review,
# phase/merge, phase/verify, and phase/done — phase/ready is removed once /code starts
# and is not restored on this path, so without this check every one of those states
# would redundantly re-dispatch run-spec.sh on a resumed run (issue #977).
# Also skip when Size is XS: skills/auto/SKILL.md Step 3 (single-issue route) treats
# spec as not required for XS, and this batch/XL route must reach the same conclusion
# for the same Size (issue #1108) — otherwise a `phase/issue` (no `phase/ready`) XS
# issue would dispatch run-spec.sh here despite the single-issue route skipping it.
LABELS=$(gh issue view "$SUB_NUMBER" --json labels -q '.labels[].name' 2>/dev/null || true)
if echo "$LABELS" | grep -qE "phase/(code|review|merge|verify|done)"; then
  echo "${LOG_PREFIX} spec phase: skipping dispatch for issue #${SUB_NUMBER} (phase/code, phase/review, phase/merge, phase/verify, or phase/done label present; spec already completed)"
elif [[ "$SIZE" == "XS" ]]; then
  echo "${LOG_PREFIX} spec phase: skipping dispatch for issue #${SUB_NUMBER} (Size XS; spec not required per skills/auto/SKILL.md Step 3)"
elif ! echo "$LABELS" | grep -q "phase/ready"; then
  echo "${LOG_PREFIX} --- spec phase: issue #${SUB_NUMBER} ---"
  # Bash-side comments_consumed emit for spec phase. (Issue #705)
  _emit_comments_consumed "$SUB_NUMBER" "spec" || true
  if [[ "$SIZE" == "L" ]]; then
    "$SCRIPT_DIR/run-spec.sh" "$SUB_NUMBER" --opus
  else
    "$SCRIPT_DIR/run-spec.sh" "$SUB_NUMBER"
  fi
fi

# Always re-fetch SIZE after spec phase (spec may have re-judged the Size)
# Mirror of skills/auto/SKILL.md Step 3a (Issue #616 for the parent path)
INITIAL_SIZE="$SIZE"
SIZE=$("$SCRIPT_DIR/get-issue-size.sh" --no-cache "$SUB_NUMBER" 2>/dev/null || true)
if [[ -n "$INITIAL_SIZE" && "$INITIAL_SIZE" != "$SIZE" ]]; then
  echo "${LOG_PREFIX} Post-spec route demotion/upgrade: ${INITIAL_SIZE} → ${SIZE}, remaining phases re-planned"
  emit_event "size_refresh" "from=${INITIAL_SIZE}" "to=${SIZE}"
fi
if [[ -z "$SIZE" ]]; then
  echo "${LOG_PREFIX} Error: Size is not set for issue #${SUB_NUMBER}" >&2
  exit 1
fi

if [[ "$SIZE" == "XL" ]]; then
  echo "${LOG_PREFIX} Error: issue #${SUB_NUMBER} is XL. Further sub-issue splitting is required" >&2
  exit 1
fi

echo "${LOG_PREFIX} Size: ${SIZE}"

ALWAYS_PR=$("$SCRIPT_DIR/get-config-value.sh" always-pr false 2>/dev/null || echo false)
AUTO_STOP_AT=$("$SCRIPT_DIR/get-config-value.sh" auto-stop-at verify 2>/dev/null || echo verify)
EFFECTIVE_SIZE="$SIZE"
if [[ "$ALWAYS_PR" == "true" ]] && [[ "$SIZE" =~ ^(XS|S)$ ]]; then
  echo "${LOG_PREFIX} always-pr: true is set in .wholework.yml. Promoting to pr route."
  emit_event "always_pr_promotion" "size=${SIZE}"
  EFFECTIVE_SIZE="M"
fi

emit_event "wrapper_alive" "checkpoint=pre_phase_dispatch"

# Execute phases according to Size-based route.
# verify is deferred to the parent /auto session (issue #485)
case "$EFFECTIVE_SIZE" in
  XS|S)
    echo "${LOG_PREFIX} --- code phase (patch): issue #${SUB_NUMBER} ---"
    run_phase_with_recovery "code-patch" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --patch ${BASE_FLAG:-}
    if [[ "${_TIER3_RECOVERY_ACTION:-}" == "skip" ]]; then
      _SKIP_PR_NUMBER=$(gh pr list --json number,headRefName 2>/dev/null | jq -r ".[] | select(.headRefName == \"worktree-code+issue-${SUB_NUMBER}\") | .number" | head -1 || true)
      if [[ -n "$_SKIP_PR_NUMBER" ]]; then
        if [[ "$AUTO_STOP_AT" == "code" || "$AUTO_STOP_AT" == "spec" ]]; then
          echo "${LOG_PREFIX} [recovery] tier3 skip revealed PR #${_SKIP_PR_NUMBER} for issue #${SUB_NUMBER}, but auto-stop-at=${AUTO_STOP_AT}: not continuing"
        elif [[ "$AUTO_STOP_AT" == "review" ]]; then
          echo "${LOG_PREFIX} [recovery] tier3 skip revealed PR #${_SKIP_PR_NUMBER} for issue #${SUB_NUMBER}; continuing to review only (auto-stop-at=review)"
          echo "${LOG_PREFIX} --- review phase (light): PR #${_SKIP_PR_NUMBER} ---"
          _EXTRA_SELF_ISSUE="$SUB_NUMBER" run_phase_with_recovery "review" "$_SKIP_PR_NUMBER" "$SCRIPT_DIR/run-review.sh" --light
        else
          echo "${LOG_PREFIX} [recovery] tier3 skip revealed PR #${_SKIP_PR_NUMBER} for issue #${SUB_NUMBER}; continuing to review/merge"
          echo "${LOG_PREFIX} --- review phase (light): PR #${_SKIP_PR_NUMBER} ---"
          _EXTRA_SELF_ISSUE="$SUB_NUMBER" run_phase_with_recovery "review" "$_SKIP_PR_NUMBER" "$SCRIPT_DIR/run-review.sh" --light
          echo "${LOG_PREFIX} --- merge phase: PR #${_SKIP_PR_NUMBER} ---"
          _EXTRA_SELF_ISSUE="$SUB_NUMBER" run_phase_with_recovery "merge" "$_SKIP_PR_NUMBER" "$SCRIPT_DIR/run-merge.sh"
        fi
      fi
    fi
    ;;
  M)
    # Resume preamble: if residual worktree/branch exists from a prior interrupted run,
    # observe the current milestone and dispatch to the appropriate recovery action.
    # Gate: fire only when local branch or worktree dir exists (avoids first-run path).
    _CODE_PR_DONE=false
    _REPO_ROOT="$REPO_ROOT"
    _WORKTREE_DIR="${_REPO_ROOT}/.claude/worktrees/code+issue-${SUB_NUMBER}"
    _BRANCH_NAME="worktree-code+issue-${SUB_NUMBER}"
    if [[ -d "$_WORKTREE_DIR" ]] || \
       git -C "$_REPO_ROOT" rev-parse --verify "$_BRANCH_NAME" >/dev/null 2>&1; then
      echo "${LOG_PREFIX} [resume] residual artifact detected for issue #${SUB_NUMBER}"
      _OBSERVED_MS=$(_observe_code_milestone "$SUB_NUMBER")
      echo "${LOG_PREFIX} [resume] observed milestone: ${_OBSERVED_MS}"
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "$_OBSERVED_MS" || true
      _RESUME_ACTION=$("$SCRIPT_DIR/auto-checkpoint.sh" resume_action "$_OBSERVED_MS")
      echo "${LOG_PREFIX} [resume] action: ${_RESUME_ACTION}"
      case "$_RESUME_ACTION" in
        skip-to-review)
          echo "${LOG_PREFIX} [resume] PR exists, skipping code phase"
          _CODE_PR_DONE=true
          ;;
        create-pr)
          echo "${LOG_PREFIX} [resume] push done, creating PR"
          if gh pr create --head "$_BRANCH_NAME" --base "${BASE_BRANCH:-main}" \
               --title "Issue #${SUB_NUMBER}: resume recovery" \
               --body "$(printf 'Closes #%s\n\nSpec: docs/spec/issue-%s-*.md' \
                          "$SUB_NUMBER" "$SUB_NUMBER")"; then
            "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
            _CODE_PR_DONE=true
          else
            echo "${LOG_PREFIX} [resume] create-pr failed, falling back to code phase" >&2
          fi
          ;;
        push-and-pr)
          echo "${LOG_PREFIX} [resume] commits done, pushing branch and creating PR"
          if git -C "$_REPO_ROOT" push -u origin "$_BRANCH_NAME" 2>/dev/null \
             && gh pr create --head "$_BRANCH_NAME" --base "${BASE_BRANCH:-main}" \
               --title "Issue #${SUB_NUMBER}: resume recovery" \
               --body "$(printf 'Closes #%s\n\nSpec: docs/spec/issue-%s-*.md' \
                          "$SUB_NUMBER" "$SUB_NUMBER")"; then
            "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
            _CODE_PR_DONE=true
          else
            echo "${LOG_PREFIX} [resume] push-and-pr failed, falling back to code phase" >&2
          fi
          ;;
        run-code)
          echo "${LOG_PREFIX} [resume] no milestone recovery needed, running code phase normally"
          ;;
      esac
    fi

    if [[ "$_CODE_PR_DONE" == "false" ]]; then
      echo "${LOG_PREFIX} --- code phase (pr): issue #${SUB_NUMBER} ---"
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "initial" || true
      run_phase_with_recovery "code-pr" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --pr ${BASE_FLAG:-}
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
    fi

    emit_event "wrapper_alive" "checkpoint=post_code_pre_review"
    PR_NUMBER=$(gh pr list --json number,headRefName 2>/dev/null | jq -r ".[] | select(.headRefName == \"worktree-code+issue-${SUB_NUMBER}\") | .number" | head -1 || true)
    if [[ -z "$PR_NUMBER" ]]; then
      echo "${LOG_PREFIX} Error: Could not retrieve PR number for issue #${SUB_NUMBER}" >&2
      exit 1
    fi
    echo "${LOG_PREFIX} PR number: ${PR_NUMBER}"

    if [[ "$AUTO_STOP_AT" == "spec" || "$AUTO_STOP_AT" == "code" ]]; then
      echo "${LOG_PREFIX} Stopped at phase: code (auto-stop-at=${AUTO_STOP_AT})"
    else
      echo "${LOG_PREFIX} --- review phase (light): PR #${PR_NUMBER} ---"
      _EXTRA_SELF_ISSUE="$SUB_NUMBER" run_phase_with_recovery "review" "$PR_NUMBER" "$SCRIPT_DIR/run-review.sh" --light

      if [[ "$AUTO_STOP_AT" == "review" ]]; then
        echo "${LOG_PREFIX} Stopped at phase: review (auto-stop-at=review)"
      else
        echo "${LOG_PREFIX} --- merge phase: PR #${PR_NUMBER} ---"
        _EXTRA_SELF_ISSUE="$SUB_NUMBER" run_phase_with_recovery "merge" "$PR_NUMBER" "$SCRIPT_DIR/run-merge.sh"
      fi
    fi
    ;;
  L)
    # Resume preamble (same logic as M, pr route)
    _CODE_PR_DONE=false
    _REPO_ROOT="$REPO_ROOT"
    _WORKTREE_DIR="${_REPO_ROOT}/.claude/worktrees/code+issue-${SUB_NUMBER}"
    _BRANCH_NAME="worktree-code+issue-${SUB_NUMBER}"
    if [[ -d "$_WORKTREE_DIR" ]] || \
       git -C "$_REPO_ROOT" rev-parse --verify "$_BRANCH_NAME" >/dev/null 2>&1; then
      echo "${LOG_PREFIX} [resume] residual artifact detected for issue #${SUB_NUMBER}"
      _OBSERVED_MS=$(_observe_code_milestone "$SUB_NUMBER")
      echo "${LOG_PREFIX} [resume] observed milestone: ${_OBSERVED_MS}"
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "$_OBSERVED_MS" || true
      _RESUME_ACTION=$("$SCRIPT_DIR/auto-checkpoint.sh" resume_action "$_OBSERVED_MS")
      echo "${LOG_PREFIX} [resume] action: ${_RESUME_ACTION}"
      case "$_RESUME_ACTION" in
        skip-to-review)
          echo "${LOG_PREFIX} [resume] PR exists, skipping code phase"
          _CODE_PR_DONE=true
          ;;
        create-pr)
          echo "${LOG_PREFIX} [resume] push done, creating PR"
          if gh pr create --head "$_BRANCH_NAME" --base "${BASE_BRANCH:-main}" \
               --title "Issue #${SUB_NUMBER}: resume recovery" \
               --body "$(printf 'Closes #%s\n\nSpec: docs/spec/issue-%s-*.md' \
                          "$SUB_NUMBER" "$SUB_NUMBER")"; then
            "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
            _CODE_PR_DONE=true
          else
            echo "${LOG_PREFIX} [resume] create-pr failed, falling back to code phase" >&2
          fi
          ;;
        push-and-pr)
          echo "${LOG_PREFIX} [resume] commits done, pushing branch and creating PR"
          if git -C "$_REPO_ROOT" push -u origin "$_BRANCH_NAME" 2>/dev/null \
             && gh pr create --head "$_BRANCH_NAME" --base "${BASE_BRANCH:-main}" \
               --title "Issue #${SUB_NUMBER}: resume recovery" \
               --body "$(printf 'Closes #%s\n\nSpec: docs/spec/issue-%s-*.md' \
                          "$SUB_NUMBER" "$SUB_NUMBER")"; then
            "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
            _CODE_PR_DONE=true
          else
            echo "${LOG_PREFIX} [resume] push-and-pr failed, falling back to code phase" >&2
          fi
          ;;
        run-code)
          echo "${LOG_PREFIX} [resume] no milestone recovery needed, running code phase normally"
          ;;
      esac
    fi

    if [[ "$_CODE_PR_DONE" == "false" ]]; then
      echo "${LOG_PREFIX} --- code phase (pr): issue #${SUB_NUMBER} ---"
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "initial" || true
      run_phase_with_recovery "code-pr" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --pr ${BASE_FLAG:-}
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
    fi

    emit_event "wrapper_alive" "checkpoint=post_code_pre_review"
    PR_NUMBER=$(gh pr list --json number,headRefName 2>/dev/null | jq -r ".[] | select(.headRefName == \"worktree-code+issue-${SUB_NUMBER}\") | .number" | head -1 || true)
    if [[ -z "$PR_NUMBER" ]]; then
      echo "${LOG_PREFIX} Error: Could not retrieve PR number for issue #${SUB_NUMBER}" >&2
      exit 1
    fi
    echo "${LOG_PREFIX} PR number: ${PR_NUMBER}"

    if [[ "$AUTO_STOP_AT" == "spec" || "$AUTO_STOP_AT" == "code" ]]; then
      echo "${LOG_PREFIX} Stopped at phase: code (auto-stop-at=${AUTO_STOP_AT})"
    else
      echo "${LOG_PREFIX} --- review phase (full): PR #${PR_NUMBER} ---"
      _EXTRA_SELF_ISSUE="$SUB_NUMBER" run_phase_with_recovery "review" "$PR_NUMBER" "$SCRIPT_DIR/run-review.sh" --full

      if [[ "$AUTO_STOP_AT" == "review" ]]; then
        echo "${LOG_PREFIX} Stopped at phase: review (auto-stop-at=review)"
      else
        echo "${LOG_PREFIX} --- merge phase: PR #${PR_NUMBER} ---"
        _EXTRA_SELF_ISSUE="$SUB_NUMBER" run_phase_with_recovery "merge" "$PR_NUMBER" "$SCRIPT_DIR/run-merge.sh"
      fi
    fi
    ;;
  *)
    echo "${LOG_PREFIX} Error: Unknown Size: ${SIZE}" >&2
    exit 1
    ;;
esac

echo "${LOG_PREFIX} ---"
echo "${LOG_PREFIX} === run-auto-sub.sh: Completed sub-issue #${SUB_NUMBER} ==="
print_end_banner "issue" "$SUB_NUMBER" "auto"
echo "${LOG_PREFIX} Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
emit_event "sub_complete" "exit_code=0"
exit 0
