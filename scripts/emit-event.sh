#!/bin/bash
# emit-event.sh - Shared event emission helper for auto-events.jsonl
# Source this file to use emit_event() in run-*.sh and watchdog scripts.
#
# Usage: source emit-event.sh
#
# Required env vars:
#   AUTO_EVENTS_LOG    - Path to the JSONL log file (default: .tmp/auto-events.jsonl)
#   EMIT_ISSUE_NUMBER  - Issue number for the current phase (set by caller)
#
# Optional env vars:
#   EMIT_PHASE_NAME    - Phase name for the current execution context
#   EMIT_PR_NUMBER     - PR number when the current phase is called with a PR number
#                        (e.g. review/merge); adds a "pr" field distinct from "issue"

# Documented event schemas:
#
# manual_intervention: parent session manually recovered a child wrapper failure.
# Emitted by run-auto-sub.sh --write-manual-recovery (see #1005).
#   recovery_target=<phase>       e.g. code-patch, verify
#   wrapper_exit_code=<code|unknown>   original wrapper exit code; "unknown" when the
#                                  parent session could not observe the wrapper's exit
#                                  status (e.g. an external kill left no exit trailer)
#   intervention_type=<type>      silent_no_op_manual_fix | tier3_abort_manual_fix | direct_commit |
#                                  respawn | push-only | pr-create | review-rerun
#                                  (the last four are --write-manual-recovery RECOVERY_TYPE values)
#
# verify_reopen_cycle: /verify FAIL -> issue reopen fix cycle entered
#   iteration=<n>                 verify iteration counter (from get-verify-iteration.sh)
#   reopen_reason=<reason>        pre_merge_ac_fail | post_merge_observation_fail | manual_judgment
#
# comments_consumed: skill consumed comments added since the previous phase
#   phase=<phase-name>            e.g. spec, code, verify
#   count=<n>                     total number of comments consumed
#   authors=<comma-separated>     comma-separated list of author logins
#   trust_breakdown=<flat>        KEY:n format — OWNER:n,MEMBER:n,COLLABORATOR:n,CONTRIBUTOR:n,NONE:n
#                                 (flat format avoids JSON quoting issues with emit_event() sanitization)
#
# verify_retry_fire: tail extension fired /code to retry after FAIL
#   iteration=<n>                 verify retry iteration counter (1-based within auto-retry)
#   trigger_reason=<reason>       ac_fail | verify_timeout | verify_uncertain
#   budget_remaining_tokens=<n|unknown>   estimated remaining token budget; "unknown" when token tracking is not yet implemented
#
# code_retry_fire: run-code.sh detected silent no-op and fired auto-retry
#   iteration=<n>                 code retry iteration counter (1-based within auto-retry)
#   trigger_reason=<reason>       silent_no_op
#
# recoveries_threshold_fire: verify tail detected threshold-exceeding symptom and auto-filed Issue
#   symptom=<symptom-short>       symptom identifier from orchestration-recoveries.md
#   count=<n>                     occurrence count that exceeded threshold
#   issue_number=<NNN>            GitHub Issue number created (0 if L1 advisory only)
#
# next_cycle_seeded: batch completion tail emitted next-cycle candidate issues
#   candidate_count=<n>           total number of candidate issues emitted
#   source_breakdown=<flat>       flat format: "audit/drift:N1,audit/fragility:N2"
#   batch_session_id=<sid>        AUTO_SESSION_ID of the batch that produced the candidates
#
# verify_fail_marker_posted: /verify FAIL 時に machine-readable marker comment を Issue に append した
#   iteration=<n>                 verify iteration counter (NEXT_ITERATION)
#   failed_ac_count=<n>           number of FAIL conditions in auto-verification targets
#
# verify_user_confirm: /verify interactive mode で manual AC の AskUserQuestion に回答した
#   ac_index=<n>                  acceptance condition index (1-based) the question was asked for
#   response=<response>           Claude Execute | Manual Verification (Show Guide) | SKIP
#
# worktree-path-block: hook-worktree-path-guard.sh blocked an Edit/Write/NotebookEdit call
#   that passed a parent-repo absolute path while the session was inside a worktree
#   tool=<name>                   Edit | Write | NotebookEdit
#   cwd=<path>                    working directory at block time
#   file_path=<path>              the blocked absolute path
#   worktree_root=<path>          the worktree root the session was inside

emit_event() {
  local event_type="$1"; shift
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local _log="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
  local _issue="${EMIT_ISSUE_NUMBER:-0}"
  local _sid="${AUTO_SESSION_ID:-}"
  local json="{\"ts\":\"${ts}\",\"issue\":${_issue},\"event\":\"${event_type}\",\"session_id\":\"${_sid}\""
  if [[ -n "${EMIT_PR_NUMBER:-}" ]]; then
    json="${json},\"pr\":${EMIT_PR_NUMBER}"
  fi
  while [[ $# -gt 0 ]]; do
    local kv="$1"; local k="${kv%%=*}"; local v="${kv#*=}"
    # sanitize value: strip newlines, replace tabs, escape backslash and double-quote
    local v_sanitized="${v//$'\n'/}"
    v_sanitized="${v_sanitized//$'\t'/ }"
    v_sanitized="${v_sanitized//\\/\\\\}"
    v_sanitized="${v_sanitized//\"/\\\"}"
    json="${json},\"${k}\":\"${v_sanitized}\""
    shift
  done
  json="${json}}"
  mkdir -p "$(dirname "${_log}")"
  if command -v flock >/dev/null 2>&1; then
    (flock -x 9; echo "${json}" >> "${_log}") 9>"${_log}.lock"
  else
    local lock_dir="${_log}.lockdir"
    local tries=0
    while ! mkdir "${lock_dir}" 2>/dev/null; do
      tries=$((tries + 1))
      if (( tries > 50 )); then
        echo "${json}" >> "${_log}"
        return 0
      fi
      sleep 0.1
    done
    echo "${json}" >> "${_log}"
    rmdir "${lock_dir}" 2>/dev/null || true
  fi
}

# Restores AUTO_SESSION_ID/AUTO_EVENTS_LOG from pointer files when the caller's
# environment does not already have AUTO_EVENTS_LOG set. Issue #902 Fix Cycle —
# /verify runs via in-session Skill() calls (e.g. /auto --batch List mode), so
# each Bash tool call is a separate process group and does not inherit env vars
# exported by a wrapper script. Priority: env var > PGID pointer file >
# auto-session-current pointer file > no-op (standalone /verify stays
# uninstrumented by design). bash 3.2+ compatible.
#
# Issue #1006: pointer file lookup and AUTO_EVENTS_LOG must not be CWD-relative,
# because /verify Step 11's FAIL-branch emits run after Worktree Entry (CWD =
# verify/issue-N worktree), where .tmp/ (gitignored) does not exist. Resolve the
# main repo root via `git worktree list --porcelain` (same idiom as
# detect-foreign-worktree.sh / run-code.sh) and prefix both the pointer file
# search and AUTO_EVENTS_LOG with it. Outside a git repo (e.g. bats tmpdir
# fixtures), `git worktree list` fails and the prefix stays empty, preserving
# the previous CWD-relative behavior.
restore_auto_session_pointer() {
  [[ -n "${AUTO_EVENTS_LOG:-}" ]] && return 0
  local _root
  _root="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
  local _prefix=""
  [[ -n "${_root}" ]] && _prefix="${_root}/"
  local _pgid; _pgid=$(ps -o pgid= -p $$ | tr -d ' ')
  local _sid
  _sid="$(cat "${_prefix}.tmp/auto-session-${_pgid}" 2>/dev/null || cat "${_prefix}.tmp/auto-session-current" 2>/dev/null || echo '')"
  [[ -z "${_sid}" ]] && return 0
  AUTO_SESSION_ID="${AUTO_SESSION_ID:-$_sid}"
  AUTO_EVENTS_LOG="${_prefix}.tmp/auto-events.jsonl"
  export AUTO_SESSION_ID AUTO_EVENTS_LOG
}

# Bash-side Consumed Comments section appender. Issue #811 — post-processor
# fallback: calls append-consumed-comments-section.sh to write the
# ## Consumed Comments section when the LLM phase did not write it.
# Always exits 0 (best-effort). Called by run-spec.sh and run-code.sh after
# the claude subprocess exits when the pre/post count comparison shows no
# section was added by the LLM.
_append_consumed_comments_section() {
  "$SCRIPT_DIR/append-consumed-comments-section.sh" "$@" 2>/dev/null || true
}

# Bash-side comments_consumed event emitter. Issue #705 — replaces the LLM
# Step 6 in l0-surfaces.md Comment Consumption Procedure, which was not firing
# reliably because the LLM skips the emit step. Extracted from run-auto-sub.sh
# (Issue #791) so run-code.sh and other run-*.sh wrappers can call it on the
# parent /auto single Issue path without going through run-auto-sub.sh.
# Guard: exits early when AUTO_EVENTS_LOG or AUTO_SESSION_ID is unset.
_emit_comments_consumed() {
  local issue="$1"
  local phase="$2"
  [[ -z "${AUTO_EVENTS_LOG:-}" ]] && return 0
  [[ -z "${AUTO_SESSION_ID:-}" ]] && return 0

  local cutoff=""
  cutoff=$(gh api "repos/{owner}/{repo}/issues/${issue}/timeline" --paginate \
    --jq '[.[] | select(.event=="labeled" and (.label.name|startswith("phase/"))) | .created_at] | last // empty' \
    2>/dev/null || true)

  local comments_json="[]"
  comments_json=$(gh issue view "$issue" --json comments --jq '.comments' 2>/dev/null || echo "[]")
  if [[ -n "$cutoff" ]]; then
    comments_json=$(echo "$comments_json" \
      | jq --arg c "$cutoff" '[.[] | select(.createdAt > $c)]' 2>/dev/null || echo "[]")
  fi

  local count=0 owner_n=0 member_n=0 collab_n=0 contrib_n=0 none_n=0 authors=""
  count=$(echo "$comments_json" | jq 'length' 2>/dev/null || echo 0)
  owner_n=$(echo "$comments_json" | jq '[.[] | select(.authorAssociation=="OWNER")] | length' 2>/dev/null || echo 0)
  member_n=$(echo "$comments_json" | jq '[.[] | select(.authorAssociation=="MEMBER")] | length' 2>/dev/null || echo 0)
  collab_n=$(echo "$comments_json" | jq '[.[] | select(.authorAssociation=="COLLABORATOR")] | length' 2>/dev/null || echo 0)
  contrib_n=$(echo "$comments_json" | jq '[.[] | select(.authorAssociation=="CONTRIBUTOR")] | length' 2>/dev/null || echo 0)
  none_n=$(echo "$comments_json" | jq '[.[] | select(.authorAssociation=="NONE")] | length' 2>/dev/null || echo 0)
  authors=$(echo "$comments_json" | jq -r '[.[] | .author.login] | unique | join(",")' 2>/dev/null || true)

  EMIT_ISSUE_NUMBER="$issue" emit_event "comments_consumed" \
    "phase=${phase}" \
    "count=${count}" \
    "authors=${authors:-}" \
    "trust_breakdown=OWNER:${owner_n},MEMBER:${member_n},COLLABORATOR:${collab_n},CONTRIBUTOR:${contrib_n},NONE:${none_n}" \
    2>/dev/null || true
}
