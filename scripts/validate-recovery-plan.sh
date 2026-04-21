#!/bin/bash
# Validate a recovery plan JSON produced by orchestration-recovery sub-agent.
# Usage: validate-recovery-plan.sh [file]
#   file: path to JSON file (reads stdin if omitted)
# Exit 0 on valid plan, exit 1 on invalid (error written to stderr).
# Bash 3.2+ compatible (no associative arrays, no mapfile).

set -euo pipefail

if [ $# -ge 1 ]; then
  JSON_INPUT=$(cat "$1")
else
  JSON_INPUT=$(cat)
fi

python3 - <<'PYEOF' "$JSON_INPUT"
import sys
import json

raw = sys.argv[1]

try:
    plan = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"ERROR: invalid JSON: {e}", file=sys.stderr)
    sys.exit(1)

errors = []

# Required keys
for key in ("action", "rationale", "steps"):
    if key not in plan:
        errors.append(f"missing required key: '{key}'")

if errors:
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)

# action value
valid_actions = {"retry", "skip", "recover", "abort"}
if plan["action"] not in valid_actions:
    errors.append(f"invalid action '{plan['action']}'; must be one of {sorted(valid_actions)}")

# steps must be a list
if not isinstance(plan["steps"], list):
    errors.append("'steps' must be an array")
else:
    # step count limit
    if len(plan["steps"]) > 5:
        errors.append(f"'steps' has {len(plan['steps'])} entries; maximum is 5")

    # forbidden op check (case-insensitive substring match on 'op' and 'cmd' fields)
    forbidden_ops = ["force_push", "reset_hard", "close_issue", "merge_pr", "direct_push_main"]
    # forbidden cmd patterns applied to run_command steps
    import re as _re
    forbidden_cmd_patterns = [
        r"--force\b", r"-f\s", r"push\s.*origin\s.*(main|master)",
        r"reset\s+--hard", r"gh\s+issue\s+close", r"gh\s+pr\s+merge",
    ]
    for i, step in enumerate(plan["steps"]):
        if not isinstance(step, dict):
            errors.append(f"steps[{i}] is not an object")
            continue
        op_value = str(step.get("op", "")).lower()
        for forbidden in forbidden_ops:
            if forbidden in op_value:
                errors.append(f"steps[{i}] contains forbidden op '{forbidden}' in op='{step.get('op')}'")
        if op_value == "run_command":
            cmd_value = str(step.get("cmd", ""))
            for pattern in forbidden_cmd_patterns:
                if _re.search(pattern, cmd_value):
                    errors.append(f"steps[{i}] run_command contains forbidden pattern in cmd='{step.get('cmd')}'")

if errors:
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF
