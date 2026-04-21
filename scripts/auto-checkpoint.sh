#!/bin/bash
# auto-checkpoint.sh - Checkpoint operations for /auto resume support
#
# Usage:
#   auto-checkpoint.sh read_single <NUMBER>
#   auto-checkpoint.sh write_single <NUMBER> <COUNT>
#   auto-checkpoint.sh delete_single <NUMBER>
#   auto-checkpoint.sh read_batch
#   auto-checkpoint.sh write_batch <REMAINING> <COMPLETED> <FAILED>
#   auto-checkpoint.sh update_batch <NUMBER> complete|fail
#   auto-checkpoint.sh delete_batch
#
# Subcommand descriptions:
#   read_single  NUMBER        Print verify_iteration_count (stale/absent -> 0)
#   write_single NUMBER COUNT  Write .tmp/auto-state-NUMBER.json atomically
#   delete_single NUMBER       Delete .tmp/auto-state-NUMBER.json (absent is noop)
#   read_batch                 Print remaining list (space-separated; absent/empty -> "")
#   write_batch REM COM FAIL   Write .tmp/auto-batch-state.json atomically
#                              (each arg is space-separated number list; empty -> "")
#   update_batch NUMBER state  Move NUMBER from remaining to completed or failed (atomic)
#   delete_batch               Delete .tmp/auto-batch-state.json (absent is noop)
#
# Design: reconciler-first / checkpoint-as-hint
#   - Phase authority: GitHub labels + reconcile-phase-state.sh
#   - Checkpoint carries only: verify_iteration_count (single) or remaining list (batch)
#   - Stale detection: issue_number mismatch -> discard (return 0)
#   - Atomic write: write to *.json.tmp then mv to target

set -uo pipefail

TMP_DIR=".tmp"

_ensure_tmp() {
  mkdir -p "$TMP_DIR"
}

_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
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
# Writes .tmp/auto-state-NUMBER.json atomically.
# -----------------------------------------------------------------------
cmd_write_single() {
  local number="$1"
  local count="$2"
  _ensure_tmp
  local path="${TMP_DIR}/auto-state-${number}.json"
  local tmp_path="${path}.tmp"
  local ts
  ts=$(_now)

  jq -n \
    --arg sv "v1" \
    --argjson n "$number" \
    --argjson c "$count" \
    --arg ts "$ts" \
    '{schema_version: $sv, issue_number: $n, verify_iteration_count: $c, last_update: $ts}' \
    > "$tmp_path"
  mv "$tmp_path" "$path"
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
# read_batch
# Prints remaining list as space-separated numbers. "" if absent or empty.
# -----------------------------------------------------------------------
cmd_read_batch() {
  local path="${TMP_DIR}/auto-batch-state.json"

  if [[ ! -f "$path" ]]; then
    echo ""
    return 0
  fi

  local remaining
  remaining=$(jq -r '(.remaining // []) | map(tostring) | join(" ")' "$path" 2>/dev/null)
  echo "$remaining"
}

# -----------------------------------------------------------------------
# write_batch REMAINING COMPLETED FAILED
# Each argument is a space-separated number list (empty string for empty).
# Writes .tmp/auto-batch-state.json atomically.
# -----------------------------------------------------------------------
cmd_write_batch() {
  local remaining="$1"
  local completed="$2"
  local failed="$3"
  _ensure_tmp
  local path="${TMP_DIR}/auto-batch-state.json"
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
}

# -----------------------------------------------------------------------
# update_batch NUMBER complete|fail
# Moves NUMBER from remaining to completed or failed. Atomic write.
# -----------------------------------------------------------------------
cmd_update_batch() {
  local number="$1"
  local action="$2"
  local path="${TMP_DIR}/auto-batch-state.json"
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
# delete_batch
# Deletes .tmp/auto-batch-state.json. Absent is noop.
# -----------------------------------------------------------------------
cmd_delete_batch() {
  local path="${TMP_DIR}/auto-batch-state.json"
  rm -f "$path"
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
  read_batch)
    cmd_read_batch
    ;;
  write_batch)
    [[ $# -lt 3 ]] && { echo "Usage: auto-checkpoint.sh write_batch <REMAINING> <COMPLETED> <FAILED>" >&2; exit 1; }
    cmd_write_batch "$1" "$2" "$3"
    ;;
  update_batch)
    [[ $# -lt 2 ]] && { echo "Usage: auto-checkpoint.sh update_batch <NUMBER> complete|fail" >&2; exit 1; }
    cmd_update_batch "$1" "$2"
    ;;
  delete_batch)
    cmd_delete_batch
    ;;
  *)
    echo "Unknown subcommand: $SUBCMD" >&2
    exit 1
    ;;
esac
