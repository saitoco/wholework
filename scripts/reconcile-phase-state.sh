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
    _handle_mismatch "spec file not found under ${spec_path} for issue #${ISSUE_NUMBER}" "$actual_json"
    return
  fi

  if echo "$labels" | grep -qE '^phase/(ready|code|review|merge|verify|done)$'; then
    _emit_result "true" "spec file found and phase label is ready-or-later for issue #${ISSUE_NUMBER}" "$actual_json"
  else
    _handle_mismatch "spec file found but no ready-or-later phase label for issue #${ISSUE_NUMBER}" "$actual_json"
  fi
}

_completion_code_patch() {
  git fetch origin main --quiet 2>/dev/null || _handle_error "git fetch failed"

  local found=false
  if git log origin/main --oneline --grep="closes #${ISSUE_NUMBER}" 2>/dev/null | grep -q .; then
    found=true
  fi

  local actual_json="{\"commits_found\":${found}}"

  if [[ "$found" == "true" ]]; then
    _emit_result "true" "commit with closes #${ISSUE_NUMBER} found on origin/main" "$actual_json"
  else
    _handle_mismatch "no commit with closes #${ISSUE_NUMBER} found on origin/main" "$actual_json"
  fi
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

  local actual_json="{\"pr_number\":${PR_NUMBER}}"

  if echo "$comments" | grep -q "## Review Response Summary"; then
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

  local spec_file
  spec_file=$(ls "${spec_path}/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1)

  local labels_json
  labels_json=$(_labels_to_json_array "$labels")
  local spec_val="null"
  [[ -n "$spec_file" ]] && spec_val="\"$(_escape_json "$spec_file")\""
  local actual_json="{\"labels\":${labels_json},\"spec_file\":${spec_val}}"

  if ! echo "$labels" | grep -q "^phase/ready$"; then
    _handle_mismatch "issue #${ISSUE_NUMBER} does not have phase/ready label (code phase precondition not met)" "$actual_json"
    return
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
