#!/bin/bash
# reconcile-phase-state.sh - General-purpose phase state reconciler
# Checks preconditions or completion state for a given phase.
# Outputs JSON (schema v1) to stdout; see modules/phase-state.md for schema definition.
#
# Usage:
#   reconcile-phase-state.sh <phase> <issue_number> \
#     [--check-precondition | --check-completion] \
#     [--pr <pr_number>] [--strict | --warn-only]
#
# Phases: issue, spec, code-patch, code-pr, review, merge, verify
# Modes:
#   --check-precondition: verify conditions required before the phase runs
#   --check-completion:   verify success signature (default)
#   --warn-only (default): mismatch exits 0 with stderr warning
#   --strict:             mismatch exits 1
#
# Exit codes: 0=matches_expected (or warn-only), 1=mismatch (strict), 2=error
#
# Stage 2 recovery (push+PR creation for code-pr) is delegated to #316 recovery sub-agent.
# bash 3.2+ compatible (no declare -A, no mapfile)

set -uo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

_usage() {
  echo "Usage: reconcile-phase-state.sh <phase> <issue_number> [--check-precondition | --check-completion] [--pr <pr_number>] [--strict | --warn-only]" >&2
  echo "Phases: issue, spec, code-patch, code-pr, review, merge, verify" >&2
}

if [[ $# -lt 2 ]]; then
  _usage
  exit 2
fi

PHASE="$1"
ISSUE_NUMBER="$2"
shift 2

MODE="completion"
PR_NUMBER=""
STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-precondition) MODE="precondition"; shift ;;
    --check-completion)   MODE="completion";   shift ;;
    --pr)
      if [[ -z "${2:-}" ]]; then
        echo "reconcile-phase-state: --pr requires a PR number" >&2
        exit 2
      fi
      PR_NUMBER="$2"
      shift 2
      ;;
    --strict)    STRICT=true;  shift ;;
    --warn-only) STRICT=false; shift ;;
    *)
      echo "reconcile-phase-state: unknown option: $1" >&2
      _usage
      exit 2
      ;;
  esac
done

if ! echo "$ISSUE_NUMBER" | grep -qE '^[0-9]+$'; then
  echo "reconcile-phase-state: invalid issue number: $ISSUE_NUMBER" >&2
  exit 2
fi

# --- JSON helpers ---

_escape_json() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n'
}

_labels_to_json_array() {
  local labels="$1"
  local arr="["
  local first=true
  local label
  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    if [[ "$first" == "true" ]]; then
      arr="${arr}\"$label\""
      first=false
    else
      arr="${arr},\"$label\""
    fi
  done <<< "$labels"
  arr="${arr}]"
  printf '%s' "$arr"
}

_emit_result() {
  local matches_expected="$1"
  local diagnosis="$2"
  local actual_json="$3"
  local matches_str
  if [[ "$matches_expected" == "true" ]]; then
    matches_str="true"
  else
    matches_str="false"
  fi
  printf '{"schema_version":"v1","phase":"%s","matches_expected":%s,"actual":%s,"diagnosis":"%s"}\n' \
    "$PHASE" "$matches_str" "$actual_json" "$(_escape_json "$diagnosis")"
}

_handle_mismatch() {
  local diagnosis="$1"
  local actual_json="$2"
  _emit_result "false" "$diagnosis" "$actual_json"
  if [[ "$STRICT" == "true" ]]; then
    exit 1
  else
    echo "reconcile-phase-state: warning: $diagnosis" >&2
    exit 0
  fi
}

_handle_error() {
  echo "reconcile-phase-state: $1" >&2
  exit 2
}

# --- Completion checks ---

_completion_issue() {
  local labels
  labels=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null) || \
    _handle_error "gh issue view failed for #$ISSUE_NUMBER"
  local labels_json
  labels_json=$(_labels_to_json_array "$labels")
  local actual_json="{\"labels\":${labels_json}}"

  if echo "$labels" | grep -q "^triaged$"; then
    _emit_result "true" "triaged label found on issue #${ISSUE_NUMBER}" "$actual_json"
  else
    _handle_mismatch "triaged label not found on issue #${ISSUE_NUMBER}" "$actual_json"
  fi
}

# Append restoration hints to an actual JSON object for phase label recovery.
# Input: existing actual JSON string (must end with })
# Output: JSON with hint_recent_commit and hint_pr_state appended
_append_hints_to_actual() {
  local json="$1"

  local recent_commit
  recent_commit=$(git log --oneline -1 --grep="#${ISSUE_NUMBER}" 2>/dev/null | head -1 || true)
  local hint_commit_val="null"
  [[ -n "$recent_commit" ]] && hint_commit_val="\"$(_escape_json "$recent_commit")\""

  local pr_state
  pr_state=$(gh pr list --search "closes #${ISSUE_NUMBER}" --state all --json state \
    -q '.[0].state' 2>/dev/null || true)
  local hint_pr_val="null"
  [[ -n "$pr_state" ]] && hint_pr_val="\"$(_escape_json "$pr_state")\""

  printf '%s,"hint_recent_commit":%s,"hint_pr_state":%s}' \
    "${json%\}}" "$hint_commit_val" "$hint_pr_val"
}

# Return the createdAt timestamp of the most recent operate route completion
# marker comment (execution-log for L2/L3, or execution-plan for L1 advisory)
# on the issue, or empty string if none found or the gh call fails.
_operate_signal_ts() {
  local ts
  ts=$(gh issue view "$ISSUE_NUMBER" --json comments \
    --jq "[.comments[] | select(.body | contains(\"<!-- wholework-event: type=execution-log phase=code issue=${ISSUE_NUMBER}\") or contains(\"<!-- wholework-event: type=execution-plan phase=code issue=${ISSUE_NUMBER}\")) | .createdAt] | sort | last // empty" \
    2>/dev/null) || true
  # Accept only ISO8601-shaped values: the freshness gate compares this string
  # against reopen_ts lexicographically, so a non-timestamp value (e.g. from a
  # degraded gh that prints unrelated text) must not pass as a marker signal.
  if [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
    printf '%s\n' "$ts"
  fi
}

_completion_spec() {
  local spec_path
  spec_path=$("$SCRIPT_DIR/get-config-value.sh" spec-path "docs/spec" 2>/dev/null) || spec_path="docs/spec"

  local spec_file
  spec_file=$(ls "${spec_path}/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1)

  local labels
  labels=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null) || \
    _handle_error "gh issue view failed for #$ISSUE_NUMBER"

  local labels_json
  labels_json=$(_labels_to_json_array "$labels")
  local spec_val="null"
  [[ -n "$spec_file" ]] && spec_val="\"$(_escape_json "$spec_file")\""
  local actual_json="{\"labels\":${labels_json},\"spec_file\":${spec_val}}"

  if [[ -z "$spec_file" ]]; then
    _handle_mismatch "spec file not found under ${spec_path} for issue #${ISSUE_NUMBER}" \
      "$(_append_hints_to_actual "$actual_json")"
    return
  fi

  if echo "$labels" | grep -qE '^phase/(ready|code|review|merge|verify|done)$'; then
    _emit_result "true" "spec file found and phase label is ready-or-later for issue #${ISSUE_NUMBER}" "$actual_json"
  else
    _handle_mismatch "spec file found but no ready-or-later phase label for issue #${ISSUE_NUMBER}" \
      "$(_append_hints_to_actual "$actual_json")"
  fi
}

_completion_code_patch() {
  git fetch origin main --quiet 2>/dev/null || _handle_error "git fetch failed"

  local reopen_ts
  reopen_ts=$("$SCRIPT_DIR/gh-graphql.sh" --query get-last-reopen \
    -F "num=${ISSUE_NUMBER}" \
    --jq '.data.repository.issue.timelineItems.nodes[0].createdAt' 2>/dev/null \
    | tr -d '"' || true)

  local found=false
  local actual_json
  local mismatch_diag
  if [[ -n "$reopen_ts" && "$reopen_ts" != "null" ]]; then
    if git log origin/main --after="$reopen_ts" --oneline --grep="closes #${ISSUE_NUMBER}" 2>/dev/null | grep -q .; then
      found=true
    fi
    actual_json="{\"commits_found\":${found},\"reopen_ts\":\"$(_escape_json "$reopen_ts")\"}"
    if [[ "$found" == "true" ]]; then
      _emit_result "true" "fresh commit after reopen (${reopen_ts}) with closes #${ISSUE_NUMBER} found on origin/main" "$actual_json"
      return
    fi
    mismatch_diag="no fresh commit after reopen (${reopen_ts}) with closes #${ISSUE_NUMBER} found on origin/main"
  else
    if git log origin/main --oneline --grep="closes #${ISSUE_NUMBER}" 2>/dev/null | grep -q .; then
      found=true
    fi
    actual_json="{\"commits_found\":${found}}"
    if [[ "$found" == "true" ]]; then
      _emit_result "true" "commit with closes #${ISSUE_NUMBER} found on origin/main (fallback: reopen timestamp unavailable; fix-cycle false positive possible)" "$actual_json"
      return
    fi
    mismatch_diag="no commit with closes #${ISSUE_NUMBER} found on origin/main"
  fi

  # Operate route completion signal: operate route (see Step 0 ROUTE=operate in
  # skills/code/SKILL.md) never produces a closes #N commit, so accept an
  # execution-log/execution-plan marker comment as an alternate success signature.
  # Checked before the label/state fallback so it also applies during a fix-cycle
  # re-run (reopen_ts non-null skips the label/state fallback below).
  # See modules/phase-state.md#operate-route-completion-signature
  local operate_ts
  operate_ts=$(_operate_signal_ts)
  local operate_signal=false
  if [[ -n "$operate_ts" && "$operate_ts" != "null" ]]; then
    if [[ -z "$reopen_ts" || "$reopen_ts" == "null" ]] || [[ "$operate_ts" > "$reopen_ts" ]]; then
      operate_signal=true
    fi
  fi

  if [[ "$operate_signal" == "true" ]]; then
    actual_json="${actual_json%\}},\"operate_signal\":true}"
    _emit_result "true" "operate route completion: execution-log/plan marker comment found (${operate_ts}) for issue #${ISSUE_NUMBER}; no closes #${ISSUE_NUMBER} commit expected" "$actual_json"
    return
  fi
  actual_json="${actual_json%\}},\"operate_signal\":false}"

  # Fallback: check phase labels or issue state for async external commit areas.
  # See modules/orchestration-fallbacks.md#async-external-commit
  local labels state
  labels=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null) || true
  state=$(gh issue view "$ISSUE_NUMBER" --json state -q '.state' 2>/dev/null) || true

  # When issue was reopened (reopen_ts != null), phase/verify is stale from the previous
  # verify run and must not be treated as a completion signal.
  if [[ -n "$reopen_ts" && "$reopen_ts" != "null" ]]; then
    _handle_mismatch "$mismatch_diag" "$actual_json"
    return
  fi

  if echo "$labels" | grep -qE '^phase/(verify|done)$' || [[ "$state" == "CLOSED" ]]; then
    _emit_result "true" "async external commit area: closes #${ISSUE_NUMBER} not in git log but phase label or state confirms completion" "$actual_json"
    return
  fi

  _handle_mismatch "$mismatch_diag" "$actual_json"
}

_completion_code_pr() {
  # Stage 2 recovery (push+PR creation) is delegated to #316 recovery sub-agent.
  # This function only checks if an open PR exists for the SSoT branch name.
  local pr_count
  pr_count=$(gh pr list --head "worktree-code+issue-${ISSUE_NUMBER}" --state open --json number -q 'length' 2>/dev/null) || \
    _handle_error "gh pr list failed for issue #$ISSUE_NUMBER"

  local pr_num_val="null"
  local pr_state_val="null"
  if [[ "${pr_count:-0}" -gt 0 ]]; then
    local pr_num
    pr_num=$(gh pr list --head "worktree-code+issue-${ISSUE_NUMBER}" --state open --json number -q '.[0].number' 2>/dev/null) || pr_num=""
    [[ -n "$pr_num" ]] && pr_num_val="$pr_num"
    pr_state_val="\"OPEN\""
  fi

  local actual_json="{\"pr_state\":${pr_state_val},\"pr_number\":${pr_num_val}}"

  if [[ "${pr_count:-0}" -gt 0 ]]; then
    _emit_result "true" "open PR found for worktree-code+issue-${ISSUE_NUMBER} branch" "$actual_json"
  else
    _handle_mismatch "no open PR found for worktree-code+issue-${ISSUE_NUMBER} branch (stage2 recovery delegated to #316)" "$actual_json"
  fi
}

_completion_review() {
  if [[ -z "$PR_NUMBER" ]]; then
    echo "reconcile-phase-state: review phase requires --pr <pr_number>" >&2
    exit 2
  fi

  local comments
  comments=$(gh pr view "$PR_NUMBER" --json comments -q '.comments[].body' 2>/dev/null) || \
    _handle_error "gh pr view failed for PR #$PR_NUMBER"

  local reviews
  reviews=$(gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/reviews" -q '.[].body' 2>/dev/null) || true
  local combined="${comments}${reviews}"

  local actual_json="{\"pr_number\":${PR_NUMBER}}"

  if echo "$combined" | grep -qE "<!--[[:space:]]*review-summary[[:space:]]*-->|## Review Response Summary|## レビュー回答サマリ"; then
    _emit_result "true" "Review Response Summary found in PR #${PR_NUMBER} comments" "$actual_json"
  else
    _handle_mismatch "Review Response Summary not found in PR #${PR_NUMBER} comments" "$actual_json"
  fi
}

_completion_merge() {
  if [[ -z "$PR_NUMBER" ]]; then
    echo "reconcile-phase-state: merge phase requires --pr <pr_number>" >&2
    exit 2
  fi

  local state
  state=$(gh pr view "$PR_NUMBER" --json state -q '.state' 2>/dev/null) || \
    _handle_error "gh pr view failed for PR #$PR_NUMBER"

  local actual_json="{\"pr_state\":\"$(_escape_json "$state")\",\"pr_number\":${PR_NUMBER}}"

  if [[ "$state" == "MERGED" ]]; then
    _emit_result "true" "PR #${PR_NUMBER} is in MERGED state" "$actual_json"
  else
    _handle_mismatch "PR #${PR_NUMBER} state is ${state}, not MERGED" "$actual_json"
  fi
}

_completion_verify() {
  local state
  state=$(gh issue view "$ISSUE_NUMBER" --json state -q '.state' 2>/dev/null) || \
    _handle_error "gh issue view failed for #$ISSUE_NUMBER"

  local labels
  labels=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null) || \
    _handle_error "gh issue view failed for #$ISSUE_NUMBER"

  local labels_json
  labels_json=$(_labels_to_json_array "$labels")
  local actual_json="{\"issue_state\":\"$(_escape_json "$state")\",\"labels\":${labels_json}}"

  if [[ "$state" == "CLOSED" ]]; then
    _emit_result "true" "issue #${ISSUE_NUMBER} is CLOSED" "$actual_json"
    return
  fi

  if echo "$labels" | grep -q '^phase/done$'; then
    _emit_result "true" "issue #${ISSUE_NUMBER} has phase/done label" "$actual_json"
  else
    _handle_mismatch "issue #${ISSUE_NUMBER} is OPEN with no phase/done label" "$actual_json"
  fi
}

# --- Precondition checks ---

_precondition_issue() {
  local state
  state=$(gh issue view "$ISSUE_NUMBER" --json state -q '.state' 2>/dev/null) || \
    _handle_error "gh issue view failed for #$ISSUE_NUMBER"

  local actual_json="{\"issue_state\":\"$(_escape_json "$state")\"}"

  if [[ "$state" == "CLOSED" ]]; then
    _handle_mismatch "issue #${ISSUE_NUMBER} is CLOSED; issue phase cannot run on a closed issue" "$actual_json"
    return
  fi

  _emit_result "true" "issue #${ISSUE_NUMBER} exists and is not CLOSED" "$actual_json"
}

_precondition_spec() {
  local labels
  labels=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null) || \
    _handle_error "gh issue view failed for #$ISSUE_NUMBER"

  local labels_json
  labels_json=$(_labels_to_json_array "$labels")
  local actual_json="{\"labels\":${labels_json}}"

  if echo "$labels" | grep -qE '^phase/(issue|spec)$'; then
    _emit_result "true" "issue #${ISSUE_NUMBER} has phase/issue or phase/spec label (spec precondition met)" "$actual_json"
  else
    _handle_mismatch "issue #${ISSUE_NUMBER} does not have phase/issue or phase/spec label (spec precondition not met)" "$actual_json"
  fi
}

_precondition_code_common() {
  local labels
  labels=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null) || \
    _handle_error "gh issue view failed for #$ISSUE_NUMBER"

  local spec_path
  spec_path=$("$SCRIPT_DIR/get-config-value.sh" spec-path "docs/spec" 2>/dev/null) || spec_path="docs/spec"

  local SPEC_EXISTS
  SPEC_EXISTS=$(ls "${spec_path}/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1)

  local labels_json
  labels_json=$(_labels_to_json_array "$labels")
  local spec_val="null"
  [[ -n "$SPEC_EXISTS" ]] && spec_val="\"$(_escape_json "$SPEC_EXISTS")\""
  local actual_json="{\"labels\":${labels_json},\"spec_file\":${spec_val}}"

  if ! echo "$labels" | grep -q "^phase/ready$"; then
    _handle_mismatch "issue #${ISSUE_NUMBER} does not have phase/ready label (code phase precondition not met)" "$actual_json"
    return
  fi

  if [[ -z "$SPEC_EXISTS" ]]; then
    local SIZE
    SIZE=$("$SCRIPT_DIR/get-issue-size.sh" "$ISSUE_NUMBER" 2>/dev/null || true)
    if [[ "$SIZE" != "XS" ]]; then
      actual_json="{\"labels\":${labels_json},\"spec_file\":${spec_val},\"size\":\"$(_escape_json "$SIZE")\"}"
      _handle_mismatch "Spec missing and Size != XS" "$actual_json"
      return
    fi
  fi

  _emit_result "true" "issue #${ISSUE_NUMBER} has phase/ready label (code phase precondition met)" "$actual_json"
}

_precondition_code_patch() { _precondition_code_common; }
_precondition_code_pr()    { _precondition_code_common; }

_precondition_review() {
  if [[ -z "$PR_NUMBER" ]]; then
    echo "reconcile-phase-state: review precondition requires --pr <pr_number>" >&2
    exit 2
  fi

  local pr_state
  pr_state=$(gh pr view "$PR_NUMBER" --json state -q '.state' 2>/dev/null) || \
    _handle_error "gh pr view failed for PR #$PR_NUMBER"

  local actual_json="{\"pr_state\":\"$(_escape_json "$pr_state")\",\"pr_number\":${PR_NUMBER}}"

  if [[ "$pr_state" == "OPEN" ]]; then
    _emit_result "true" "PR #${PR_NUMBER} is OPEN (review precondition met)" "$actual_json"
  else
    _handle_mismatch "PR #${PR_NUMBER} state is ${pr_state}, not OPEN (review precondition not met)" "$actual_json"
  fi
}

_precondition_merge() {
  if [[ -z "$PR_NUMBER" ]]; then
    echo "reconcile-phase-state: merge precondition requires --pr <pr_number>" >&2
    exit 2
  fi

  local pr_state
  pr_state=$(gh pr view "$PR_NUMBER" --json state -q '.state' 2>/dev/null) || \
    _handle_error "gh pr view failed for PR #$PR_NUMBER"

  local pr_review_decision
  pr_review_decision=$(gh pr view "$PR_NUMBER" --json reviewDecision -q '.reviewDecision' 2>/dev/null) || \
    _handle_error "gh pr view failed for PR #$PR_NUMBER"

  local actual_json="{\"pr_state\":\"$(_escape_json "$pr_state")\",\"pr_number\":${PR_NUMBER}}"

  if [[ "$pr_state" != "OPEN" ]]; then
    _handle_mismatch "PR #${PR_NUMBER} state is ${pr_state}, not OPEN (merge precondition not met)" "$actual_json"
    return
  fi

  if [[ "$pr_review_decision" == "APPROVED" ]]; then
    _emit_result "true" "PR #${PR_NUMBER} is OPEN and APPROVED (merge precondition met)" "$actual_json"
  else
    _handle_mismatch "PR #${PR_NUMBER} reviewDecision is ${pr_review_decision}, not APPROVED (merge precondition not met)" "$actual_json"
  fi
}

_precondition_verify() {
  local state
  state=$(gh issue view "$ISSUE_NUMBER" --json state -q '.state' 2>/dev/null) || \
    _handle_error "gh issue view failed for #$ISSUE_NUMBER"

  local labels
  labels=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null) || \
    _handle_error "gh issue view failed for #$ISSUE_NUMBER"

  local labels_json
  labels_json=$(_labels_to_json_array "$labels")
  local actual_json="{\"issue_state\":\"$(_escape_json "$state")\",\"labels\":${labels_json}}"

  if [[ "$state" == "CLOSED" ]]; then
    _emit_result "true" "issue #${ISSUE_NUMBER} is CLOSED (verify precondition met)" "$actual_json"
    return
  fi

  if echo "$labels" | grep -q "^phase/verify$"; then
    _emit_result "true" "issue #${ISSUE_NUMBER} has phase/verify label (verify precondition met)" "$actual_json"
  else
    _handle_mismatch "issue #${ISSUE_NUMBER} is not CLOSED and has no phase/verify label (verify precondition not met)" "$actual_json"
  fi
}

# --- Dispatcher ---

_dispatch_completion() {
  case "$PHASE" in
    issue)      _completion_issue ;;
    spec)       _completion_spec ;;
    code-patch) _completion_code_patch ;;
    code-pr)    _completion_code_pr ;;
    review)     _completion_review ;;
    merge)      _completion_merge ;;
    verify)     _completion_verify ;;
    *)
      echo "reconcile-phase-state: unknown phase: $PHASE" >&2
      _usage
      exit 2
      ;;
  esac
}

_dispatch_precondition() {
  case "$PHASE" in
    issue)      _precondition_issue ;;
    spec)       _precondition_spec ;;
    code-patch) _precondition_code_patch ;;
    code-pr)    _precondition_code_pr ;;
    review)     _precondition_review ;;
    merge)      _precondition_merge ;;
    verify)     _precondition_verify ;;
    *)
      echo "reconcile-phase-state: unknown phase: $PHASE" >&2
      _usage
      exit 2
      ;;
  esac
}

if [[ "$MODE" == "precondition" ]]; then
  _dispatch_precondition
else
  _dispatch_completion
fi
