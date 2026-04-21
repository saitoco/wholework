#!/bin/bash
# spawn-recovery-subagent.sh - Tier 3 recovery orchestrator for run-auto-sub.sh
# Spawns agents/orchestration-recovery via claude -p, validates the returned plan
# with validate-recovery-plan.sh (SSoT shared with #316), and executes the recovery.
#
# Usage: spawn-recovery-subagent.sh <phase> <issue> --log <log-file> [--exit-code <code>]
# Exit 0 on successful recovery, exit 1 on abort or unrecoverable failure.
# Bash 3.2+ compatible (no associative arrays, no mapfile).

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

PHASE="${1:?Usage: spawn-recovery-subagent.sh <phase> <issue> --log <log-file>}"
ISSUE="${2:?Usage: spawn-recovery-subagent.sh <phase> <issue> --log <log-file>}"
shift 2

LOG_FILE=""
EXIT_CODE_PARAM="unknown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --log requires a file path" >&2
        exit 1
      fi
      LOG_FILE="$2"
      shift 2
      ;;
    --exit-code)
      EXIT_CODE_PARAM="${2:-unknown}"
      shift 2
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$LOG_FILE" ]]; then
  echo "Error: --log <log-file> is required" >&2
  exit 1
fi

# --- Concurrency control: mkdir-based slot lock (following worktree-merge-push.sh precedent) ---
# WHOLEWORK_MAX_RECOVERY_SUBAGENTS controls the maximum number of concurrent Tier 3 invocations.
# Default 1 serializes recovery to avoid claude -p cost burst during XL parallel runs.
MAX_SLOTS="${WHOLEWORK_MAX_RECOVERY_SUBAGENTS:-1}"
LOCK_DIR=""

mkdir -p .tmp

acquire_slot() {
  local slot=1
  while [[ $slot -le $MAX_SLOTS ]]; do
    local candidate_dir=".tmp/recovery-subagent-slot-${slot}"

    if mkdir "$candidate_dir" 2>/dev/null; then
      LOCK_DIR="$candidate_dir"
      echo "$$" > "${LOCK_DIR}/pid"
      trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT
      return 0
    fi

    # Stale lock reclaim: if recorded pid is no longer running, take the slot
    local existing_pid
    existing_pid=$(cat "${candidate_dir}/pid" 2>/dev/null || true)
    if [[ -n "$existing_pid" ]] && ! kill -0 "$existing_pid" 2>/dev/null; then
      echo "Stale recovery slot lock detected (pid=$existing_pid not running), reclaiming..." >&2
      rm -rf "$candidate_dir"
      if mkdir "$candidate_dir" 2>/dev/null; then
        LOCK_DIR="$candidate_dir"
        echo "$$" > "${LOCK_DIR}/pid"
        trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT
        return 0
      fi
    fi

    slot=$((slot + 1))
  done

  echo "Error: All ${MAX_SLOTS} recovery subagent slot(s) occupied; aborting tier3" >&2
  return 1
}

acquire_slot

# --- Build prompt ---
AGENT_FILE="${SCRIPT_DIR}/../agents/orchestration-recovery.md"
if [[ ! -f "$AGENT_FILE" ]]; then
  echo "Error: agents/orchestration-recovery.md not found: $AGENT_FILE" >&2
  exit 1
fi

# Strip frontmatter: detect first --- after line 1, take everything from the next line onward
# (same pattern as run-review.sh:53 and other run-*.sh scripts)
FRONTMATTER_END=$(awk 'NR>1 && /^---$/{print NR; exit}' "$AGENT_FILE")
if [[ -z "$FRONTMATTER_END" ]]; then
  echo "Error: agents/orchestration-recovery.md frontmatter not found" >&2
  exit 1
fi
AGENT_BODY=$(tail -n +"$((FRONTMATTER_END + 1))" "$AGENT_FILE")

LOG_TAIL=$(tail -200 "$LOG_FILE" 2>/dev/null || true)

RECONCILE_OUTPUT=""
RECONCILE_OUTPUT=$("$SCRIPT_DIR/reconcile-phase-state.sh" "$PHASE" "$ISSUE" --check-completion 2>/dev/null || true)

RAW_FILE=".tmp/recovery-raw-${ISSUE}-${PHASE}.txt"
PLAN_FILE=".tmp/recovery-plan-${ISSUE}-${PHASE}.json"

INPUT_JSON=$(python3 -c "
import json, sys
print(json.dumps({
    'phase': sys.argv[1],
    'issue': sys.argv[2],
    'exit_code': sys.argv[3],
    'log_tail': sys.argv[4],
    'reconcile_snapshot': sys.argv[5]
}))
" "$PHASE" "$ISSUE" "$EXIT_CODE_PARAM" "$LOG_TAIL" "$RECONCILE_OUTPUT")

PROMPT="${AGENT_BODY}

---
INPUT JSON:
${INPUT_JSON}"

# --- Invoke claude -p (following run-*.sh precedent) ---
PERMISSION_MODE=$("$SCRIPT_DIR/get-config-value.sh" permission-mode bypass 2>/dev/null || echo bypass)
if [[ "$PERMISSION_MODE" == "auto" ]]; then
  PERMISSION_FLAG="--permission-mode auto"
else
  PERMISSION_FLAG="--dangerously-skip-permissions"
fi

source "$SCRIPT_DIR/watchdog-defaults.sh"
load_watchdog_timeout "$SCRIPT_DIR"

set +e
ANTHROPIC_MODEL="claude-sonnet-4-6" \
  WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
  env -u CLAUDECODE \
  "$SCRIPT_DIR/claude-watchdog.sh" \
  "$CLAUDE_BIN" -p "$PROMPT" \
  --model sonnet \
  --effort medium \
  $PERMISSION_FLAG > "$RAW_FILE" 2>&1
CLAUDE_EXIT=$?
set -e

if [[ $CLAUDE_EXIT -ne 0 ]]; then
  echo "Error: claude -p exited with code ${CLAUDE_EXIT}" >&2
  cat "$RAW_FILE" >&2 || true
  exit 1
fi

# Extract first balanced-brace JSON block from claude output
python3 - "$RAW_FILE" "$PLAN_FILE" <<'PYEOF'
import sys, json

input_file = sys.argv[1]
output_file = sys.argv[2]

with open(input_file, 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

depth = 0
start = None
for i, ch in enumerate(content):
    if ch == '{':
        if depth == 0:
            start = i
        depth += 1
    elif ch == '}':
        depth -= 1
        if depth == 0 and start is not None:
            block = content[start:i+1]
            try:
                json.loads(block)
                with open(output_file, 'w') as out:
                    out.write(block)
                sys.exit(0)
            except json.JSONDecodeError:
                depth = 0
                start = None

print("ERROR: no valid JSON object found in claude output", file=sys.stderr)
sys.exit(1)
PYEOF

# --- Safety guard (SSoT: scripts/validate-recovery-plan.sh, shared with #316 /auto parent) ---
if ! "$SCRIPT_DIR/validate-recovery-plan.sh" "$PLAN_FILE"; then
  echo "Error: recovery plan failed safety validation" >&2
  exit 1
fi

# --- Action dispatch ---
ACTION=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['action'])" "$PLAN_FILE")

case "$ACTION" in
  retry)
    echo "[spawn-recovery] action=retry: re-invoking run-${PHASE}.sh ${ISSUE}"
    "$SCRIPT_DIR/run-${PHASE}.sh" "$ISSUE"
    ;;
  skip)
    echo "[spawn-recovery] action=skip: treating phase as complete"
    exit 0
    ;;
  recover)
    echo "[spawn-recovery] action=recover: executing recovery steps"
    python3 - "$PLAN_FILE" <<'PYEOF'
import json, subprocess, sys

plan = json.load(open(sys.argv[1]))

for i, step in enumerate(plan.get("steps", [])):
    op = step.get("op", "")
    cmd = step.get("cmd", "")
    print(f"[spawn-recovery] step {i+1}: op={op}")

    if op == "run_command" and cmd:
        result = subprocess.run(cmd, shell=True)
        if result.returncode != 0:
            print(f"ERROR: step {i+1} failed with exit code {result.returncode}", file=sys.stderr)
            sys.exit(1)
    elif op == "git_commit_amend_signoff":
        result = subprocess.run(["git", "commit", "--amend", "-s", "--no-edit"])
        if result.returncode != 0:
            print("ERROR: git commit --amend failed", file=sys.stderr)
            sys.exit(1)
    else:
        print(f"ERROR: unsupported op '{op}' in step {i+1}", file=sys.stderr)
        sys.exit(1)

print("[spawn-recovery] all recovery steps completed")
PYEOF
    ;;
  abort)
    echo "[spawn-recovery] action=abort: tier3 cannot recover this failure" >&2
    exit 1
    ;;
  *)
    echo "Error: unknown action: ${ACTION}" >&2
    exit 1
    ;;
esac
