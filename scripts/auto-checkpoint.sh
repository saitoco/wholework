#!/bin/bash
# auto-checkpoint.sh - Checkpoint operations for /auto resume support
#
# Usage:
#   auto-checkpoint.sh read_single <NUMBER>
#   auto-checkpoint.sh write_single <NUMBER> <COUNT>
#   auto-checkpoint.sh delete_single <NUMBER>
#   auto-checkpoint.sh read_milestone <NUMBER>
#   auto-checkpoint.sh write_milestone <NUMBER> <MILESTONE>
#   auto-checkpoint.sh resume_action <MILESTONE>
#   auto-checkpoint.sh read_batch [<BATCH_ID>]
#   auto-checkpoint.sh write_batch [<BATCH_ID>] <REMAINING> <COMPLETED> <FAILED>
#   auto-checkpoint.sh update_batch [<BATCH_ID>] <NUMBER> complete|fail
#   auto-checkpoint.sh delete_batch [<BATCH_ID>]
#   auto-checkpoint.sh list_active_batches
#
# Subcommand descriptions:
#   read_single  NUMBER            Print verify_iteration_count (stale/absent -> 0)
#   write_single NUMBER COUNT      Write .tmp/auto-state-NUMBER.json atomically
#                                  (preserves code_phase_milestone via merge)
#   delete_single NUMBER           Delete .tmp/auto-state-NUMBER.json (absent is noop)
#   read_milestone NUMBER          Print code_phase_milestone (stale/absent -> "initial")
#   write_milestone NUMBER MS      Write code_phase_milestone atomically; validates MS
#                                  against 6-value enum; exit 1 on invalid value
#                                  (preserves verify_iteration_count via merge)
#   resume_action MILESTONE        Print resume action for a given milestone (pure mapping):
#                                  initial/pre-commit -> run-code
#                                  post-commit        -> push-and-pr
#                                  post-push/pre-PR-create -> create-pr
#                                  post-PR-create     -> skip-to-review
#   read_batch [BATCH_ID]          Print remaining list (space-separated; absent/empty -> "")
#   write_batch [BATCH_ID] REM COM FAIL  Write per-BATCH_ID state file atomically;
#                                        adds BATCH_ID to active index (skips "default")
#   update_batch [BATCH_ID] NUMBER state  Move NUMBER from remaining to completed or failed
#   delete_batch [BATCH_ID]        Delete batch state file; remove from active index
#   list_active_batches            Print active BATCH_IDs one per line (absent/empty -> "")
#
# Backward compatibility: BATCH_ID omitted or "default" maps to .tmp/auto-batch-state.json
# (same as the pre-BATCH_ID single-file behavior). "default" is not added to the active index.
# write_batch and update_batch auto-detect old (3/2-arg) vs. new (4/3-arg) API by arg count.
#
# Design: reconciler-first / checkpoint-as-hint
#   - Phase authority: GitHub labels + reconcile-phase-state.sh
#   - Checkpoint carries: verify_iteration_count + code_phase_milestone (single) or
#     remaining list (batch)
#   - code_phase_milestone: hint for run-auto-sub.sh resume preamble; fine milestone
#     is reconciled from observable git/GitHub state at resume time
#   - Stale detection: issue_number mismatch -> discard (return defaults)
#   - Atomic write: write to *.json.tmp then mv to target
#   - Merge semantics: write_single and write_milestone preserve each other's field

set -uo pipefail

TMP_DIR=".tmp"
ACTIVE_INDEX_PATH="${TMP_DIR}/auto-batch-active.json"

_ensure_tmp() {
  mkdir -p "$TMP_DIR"
}

_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# _merge_single_field NUMBER FIELD VALUE
# Read-then-write helper: reads existing state file (if valid), updates one field,
# writes back atomically. Both verify_iteration_count and code_phase_milestone are
# preserved across independent writes (merge semantics).
# Stale or absent files are initialized to defaults before applying the field update.
_merge_single_field() {
  local number="$1"
  local field="$2"
  local value="$3"
  _ensure_tmp
  local path="${TMP_DIR}/auto-state-${number}.json"
  local tmp_path="${path}.tmp"
  local ts
  ts=$(_now)

  local existing_count="0"
  local existing_milestone="initial"

  if [[ -f "$path" ]]; then
    local stored_number
    stored_number=$(jq -r '.issue_number // empty' "$path" 2>/dev/null || true)
    if [[ "$stored_number" == "$number" ]]; then
      local _c _m
      _c=$(jq -r '.verify_iteration_count // 0' "$path" 2>/dev/null || true)
      _m=$(jq -r '.code_phase_milestone // "initial"' "$path" 2>/dev/null || true)
      [[ -n "$_c" ]] && existing_count="$_c"
      [[ -n "$_m" ]] && existing_milestone="$_m"
    fi
  fi

  case "$field" in
    verify_iteration_count) existing_count="$value" ;;
    code_phase_milestone)   existing_milestone="$value" ;;
  esac

  if ! jq -n \
    --arg sv "v1" \
    --argjson n "$number" \
    --argjson c "$existing_count" \
    --arg m "$existing_milestone" \
    --arg ts "$ts" \
    '{schema_version: $sv, issue_number: $n, verify_iteration_count: $c, code_phase_milestone: $m, last_update: $ts}' \
    > "$tmp_path" 2>/dev/null; then
    rm -f "$tmp_path"
    echo "auto-checkpoint: merge failed for issue $number field $field" >&2
    return 1
  fi
  mv "$tmp_path" "$path"
}

# Return the file path for a given BATCH_ID.
# Empty string or "default" -> .tmp/auto-batch-state.json (backward compat)
# Any other value -> .tmp/auto-batch-state-${batch_id}.json
_batch_file_path() {
  local batch_id="${1:-}"
  if [[ -z "$batch_id" || "$batch_id" == "default" ]]; then
    echo "${TMP_DIR}/auto-batch-state.json"
  else
    echo "${TMP_DIR}/auto-batch-state-${batch_id}.json"
  fi
}

# Emit a JSON array from a space-separated list of numbers.
# Empty string produces [].
_numbers_to_json_array() {
  local list="$1"
  if [[ -z "$list" ]]; then
    echo "[]"
    return
  fi
  local arr="["
  local first=true
  for n in $list; do
    if [[ "$first" == "true" ]]; then
      arr="${arr}${n}"
      first=false
    else
      arr="${arr},${n}"
    fi
  done
  arr="${arr}]"
  echo "$arr"
}

# Add BATCH_ID to active index. Skips "default" and empty.
_add_to_active_index() {
  local batch_id="$1"
  [[ -z "$batch_id" || "$batch_id" == "default" ]] && return 0
  _ensure_tmp
  local tmp_path="${ACTIVE_INDEX_PATH}.tmp"
  local ts
  ts=$(_now)

  if [[ -f "$ACTIVE_INDEX_PATH" ]]; then
    if ! jq --arg id "$batch_id" --arg ts "$ts" '
      .active_batch_ids = ((.active_batch_ids // []) | if any(. == $id) then . else . + [$id] end) |
      .last_update = $ts
    ' "$ACTIVE_INDEX_PATH" > "$tmp_path"; then
      rm -f "$tmp_path"
      return 1
    fi
  else
    jq -n \
      --arg sv "v1" \
      --arg id "$batch_id" \
      --arg ts "$ts" \
      '{schema_version: $sv, active_batch_ids: [$id], last_update: $ts}' \
      > "$tmp_path"
  fi
  mv "$tmp_path" "$ACTIVE_INDEX_PATH"
}

# Remove BATCH_ID from active index. Skips "default" and empty.
_remove_from_active_index() {
  local batch_id="$1"
  [[ -z "$batch_id" || "$batch_id" == "default" ]] && return 0
  [[ ! -f "$ACTIVE_INDEX_PATH" ]] && return 0
  local tmp_path="${ACTIVE_INDEX_PATH}.tmp"
  local ts
  ts=$(_now)

  if ! jq --arg id "$batch_id" --arg ts "$ts" '
    .active_batch_ids = ([(.active_batch_ids // [])[] | select(. != $id)]) |
    .last_update = $ts
  ' "$ACTIVE_INDEX_PATH" > "$tmp_path"; then
    rm -f "$tmp_path"
    return 1
  fi
  mv "$tmp_path" "$ACTIVE_INDEX_PATH"
}

# -----------------------------------------------------------------------
# read_single NUMBER
# Prints verify_iteration_count from .tmp/auto-state-NUMBER.json.
# Returns 0 on stale or absent file.
# -----------------------------------------------------------------------
cmd_read_single() {
  local number="$1"
  local path="${TMP_DIR}/auto-state-${number}.json"

  if [[ ! -f "$path" ]]; then
    echo "0"
    return 0
  fi

  local stored_number
  stored_number=$(jq -r '.issue_number // empty' "$path" 2>/dev/null)
  if [[ "$stored_number" != "$number" ]]; then
    echo "0"
    return 0
  fi

  local count
  count=$(jq -r '.verify_iteration_count // 0' "$path" 2>/dev/null)
  echo "$count"
}

# -----------------------------------------------------------------------
# write_single NUMBER COUNT
# Writes verify_iteration_count to .tmp/auto-state-NUMBER.json atomically.
# Uses merge helper to preserve code_phase_milestone.
# -----------------------------------------------------------------------
cmd_write_single() {
  local number="$1"
  local count="$2"
  _merge_single_field "$number" "verify_iteration_count" "$count"
}

# -----------------------------------------------------------------------
# delete_single NUMBER
# Deletes .tmp/auto-state-NUMBER.json. Absent is noop.
# -----------------------------------------------------------------------
cmd_delete_single() {
  local number="$1"
  local path="${TMP_DIR}/auto-state-${number}.json"
  rm -f "$path"
}

# -----------------------------------------------------------------------
# read_milestone NUMBER
# Prints code_phase_milestone from .tmp/auto-state-NUMBER.json.
# Returns "initial" on stale or absent file.
# -----------------------------------------------------------------------
cmd_read_milestone() {
  local number="$1"
  local path="${TMP_DIR}/auto-state-${number}.json"

  if [[ ! -f "$path" ]]; then
    echo "initial"
    return 0
  fi

  local stored_number
  stored_number=$(jq -r '.issue_number // empty' "$path" 2>/dev/null || true)
  if [[ "$stored_number" != "$number" ]]; then
    echo "initial"
    return 0
  fi

  local milestone
  milestone=$(jq -r '.code_phase_milestone // "initial"' "$path" 2>/dev/null || echo "initial")
  echo "$milestone"
}

# -----------------------------------------------------------------------
# write_milestone NUMBER MILESTONE
# Writes code_phase_milestone to .tmp/auto-state-NUMBER.json atomically.
# Uses merge helper to preserve verify_iteration_count.
# Valid MILESTONE values: initial pre-commit post-commit post-push pre-PR-create post-PR-create
# Exits 1 on invalid MILESTONE value.
# -----------------------------------------------------------------------
_VALID_MILESTONES="initial pre-commit post-commit post-push pre-PR-create post-PR-create"

cmd_write_milestone() {
  local number="$1"
  local milestone="$2"

  local valid=false
  local ms
  for ms in $_VALID_MILESTONES; do
    if [[ "$ms" == "$milestone" ]]; then
      valid=true
      break
    fi
  done

  if [[ "$valid" == "false" ]]; then
    echo "Usage: auto-checkpoint.sh write_milestone <NUMBER> <MILESTONE>" >&2
    echo "Valid milestones: $_VALID_MILESTONES" >&2
    exit 1
  fi

  _merge_single_field "$number" "code_phase_milestone" "$milestone"
}

# -----------------------------------------------------------------------
# resume_action MILESTONE
# Pure mapping: prints the resume action for a given milestone.
#   initial / pre-commit  -> run-code
#   post-commit           -> push-and-pr
#   post-push / pre-PR-create -> create-pr
#   post-PR-create        -> skip-to-review
# Unknown milestone defaults to run-code (safe fallback).
# -----------------------------------------------------------------------
cmd_resume_action() {
  local milestone="$1"
  case "$milestone" in
    initial)         echo "run-code" ;;
    pre-commit)      echo "run-code" ;;
    post-commit)     echo "push-and-pr" ;;
    post-push)       echo "create-pr" ;;
    pre-PR-create)   echo "create-pr" ;;
    post-PR-create)  echo "skip-to-review" ;;
    *)               echo "run-code" ;;
  esac
}

# -----------------------------------------------------------------------
# read_batch BATCH_ID
# Prints remaining list as space-separated numbers. "" if absent or empty.
# BATCH_ID omitted or "default" -> .tmp/auto-batch-state.json (backward compat)
# -----------------------------------------------------------------------
cmd_read_batch() {
  local batch_id="${1:-default}"
  local path
  path=$(_batch_file_path "$batch_id")

  if [[ ! -f "$path" ]]; then
    echo ""
    return 0
  fi

  local remaining
  remaining=$(jq -r '(.remaining // []) | map(tostring) | join(" ")' "$path" 2>/dev/null)
  echo "$remaining"
}

# -----------------------------------------------------------------------
# write_batch BATCH_ID REMAINING COMPLETED FAILED
# Each list argument is a space-separated number list (empty string for empty).
# Writes per-BATCH_ID state file atomically.
# Adds BATCH_ID to active index (skips "default").
# -----------------------------------------------------------------------
cmd_write_batch() {
  local batch_id="$1"
  local remaining="$2"
  local completed="$3"
  local failed="$4"
  _ensure_tmp
  local path
  path=$(_batch_file_path "$batch_id")
  local tmp_path="${path}.tmp"
  local ts
  ts=$(_now)

  local rem_json comp_json fail_json
  rem_json=$(_numbers_to_json_array "$remaining")
  comp_json=$(_numbers_to_json_array "$completed")
  fail_json=$(_numbers_to_json_array "$failed")

  jq -n \
    --arg sv "v1" \
    --argjson rem "$rem_json" \
    --argjson comp "$comp_json" \
    --argjson fail "$fail_json" \
    --arg ts "$ts" \
    '{schema_version: $sv, mode: "list", remaining: $rem, completed: $comp, failed: $fail, last_update: $ts}' \
    > "$tmp_path"
  mv "$tmp_path" "$path"

  if ! _add_to_active_index "$batch_id"; then
    echo "Warning: failed to register batch_id '$batch_id' in active index" >&2
  fi
}

# -----------------------------------------------------------------------
# update_batch BATCH_ID NUMBER complete|fail
# Moves NUMBER from remaining to completed or failed. Atomic write.
# -----------------------------------------------------------------------
cmd_update_batch() {
  local batch_id="$1"
  local number="$2"
  local action="$3"
  local path
  path=$(_batch_file_path "$batch_id")
  local tmp_path="${path}.tmp"

  if [[ ! -f "$path" ]]; then
    return 0
  fi

  local ts
  ts=$(_now)

  if [[ "$action" == "complete" ]]; then
    if ! jq --argjson n "$number" --arg ts "$ts" '
      .remaining = ([.remaining[] | select(. != $n)]) |
      .completed = (.completed + [$n]) |
      .last_update = $ts
    ' "$path" > "$tmp_path"; then
      rm -f "$tmp_path"
      return 1
    fi
  else
    if ! jq --argjson n "$number" --arg ts "$ts" '
      .remaining = ([.remaining[] | select(. != $n)]) |
      .failed = (.failed + [$n]) |
      .last_update = $ts
    ' "$path" > "$tmp_path"; then
      rm -f "$tmp_path"
      return 1
    fi
  fi
  mv "$tmp_path" "$path"
}

# -----------------------------------------------------------------------
# delete_batch BATCH_ID
# Deletes batch state file. Removes BATCH_ID from active index.
# Absent is noop.
# -----------------------------------------------------------------------
cmd_delete_batch() {
  local batch_id="${1:-default}"
  local path
  path=$(_batch_file_path "$batch_id")
  rm -f "$path"
  _remove_from_active_index "$batch_id"
}

# -----------------------------------------------------------------------
# list_active_batches
# Prints active BATCH_IDs one per line. Empty output if absent or none active.
# -----------------------------------------------------------------------
cmd_list_active_batches() {
  if [[ ! -f "$ACTIVE_INDEX_PATH" ]]; then
    return 0
  fi

  jq -r '(.active_batch_ids // []) | .[]' "$ACTIVE_INDEX_PATH" 2>/dev/null
}

# -----------------------------------------------------------------------
# Main dispatch
# -----------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: auto-checkpoint.sh <subcommand> [args...]" >&2
  exit 1
fi

SUBCMD="$1"
shift

case "$SUBCMD" in
  read_single)
    [[ $# -lt 1 ]] && { echo "Usage: auto-checkpoint.sh read_single <NUMBER>" >&2; exit 1; }
    cmd_read_single "$1"
    ;;
  write_single)
    [[ $# -lt 2 ]] && { echo "Usage: auto-checkpoint.sh write_single <NUMBER> <COUNT>" >&2; exit 1; }
    cmd_write_single "$1" "$2"
    ;;
  delete_single)
    [[ $# -lt 1 ]] && { echo "Usage: auto-checkpoint.sh delete_single <NUMBER>" >&2; exit 1; }
    cmd_delete_single "$1"
    ;;
  read_milestone)
    [[ $# -lt 1 ]] && { echo "Usage: auto-checkpoint.sh read_milestone <NUMBER>" >&2; exit 1; }
    cmd_read_milestone "$1"
    ;;
  write_milestone)
    [[ $# -lt 2 ]] && { echo "Usage: auto-checkpoint.sh write_milestone <NUMBER> <MILESTONE>" >&2; exit 1; }
    cmd_write_milestone "$1" "$2"
    ;;
  resume_action)
    [[ $# -lt 1 ]] && { echo "Usage: auto-checkpoint.sh resume_action <MILESTONE>" >&2; exit 1; }
    cmd_resume_action "$1"
    ;;
  read_batch)
    cmd_read_batch "${1:-}"
    ;;
  write_batch)
    # Detect old API (3 args: remaining completed failed) vs new API (4 args: batch_id remaining completed failed)
    if [[ $# -eq 3 ]]; then
      cmd_write_batch "default" "$1" "$2" "$3"
    elif [[ $# -ge 4 ]]; then
      cmd_write_batch "$1" "$2" "$3" "$4"
    else
      echo "Usage: auto-checkpoint.sh write_batch [<BATCH_ID>] <REMAINING> <COMPLETED> <FAILED>" >&2
      exit 1
    fi
    ;;
  update_batch)
    # Detect old API (2 args: number action) vs new API (3 args: batch_id number action)
    if [[ $# -eq 2 ]]; then
      cmd_update_batch "default" "$1" "$2"
    elif [[ $# -ge 3 ]]; then
      cmd_update_batch "$1" "$2" "$3"
    else
      echo "Usage: auto-checkpoint.sh update_batch [<BATCH_ID>] <NUMBER> complete|fail" >&2
      exit 1
    fi
    ;;
  delete_batch)
    cmd_delete_batch "${1:-}"
    ;;
  list_active_batches)
    cmd_list_active_batches
    ;;
  *)
    echo "Unknown subcommand: $SUBCMD" >&2
    exit 1
    ;;
esac
