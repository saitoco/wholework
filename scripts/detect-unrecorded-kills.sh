#!/usr/bin/env bash
# detect-unrecorded-kills.sh - Detect unrecorded external kills and group them
# into bursts by cross-referencing .tmp/auto-events.jsonl phase_start
# duplication against docs/reports/orchestration-recoveries.md entries.
#
# Execution path: called from `/verify` Step 15 (Recovery Candidates Tail
# Check), immediately after the existing collect-recovery-candidates.sh call
# in that same step (advisory, read-only diagnostic output -- see
# skills/verify/SKILL.md Step 15). Issue #1387.
#
# Usage: detect-unrecorded-kills.sh <events-jsonl-path> <recoveries-md-path> [--window SECONDS]
#
# Detection:
#   For each (issue, phase) group of "phase_start" events in <events-jsonl-path>,
#   sorted by ts, a consecutive pair (start_i, start_{i+1}) is a "respawn
#   signal" when none of wrapper_exit / phase_complete (backfilled or not) /
#   manual_intervention occurred for that (issue, phase) strictly between
#   start_i.ts and start_{i+1}.ts.
#
#   Each respawn signal is cross-referenced against <recoveries-md-path>: an
#   entry whose "### Context" contains "Issue #<issue>, phase: <phase>" and
#   whose heading timestamp is within --window seconds of the respawn's
#   kill time (start_{i+1}.ts) marks the signal recorded=yes; otherwise
#   recorded=no.
#
#   All respawn signals (recorded or not) are sorted by kill time and grouped
#   into bursts using a greedy adjacent-gap-within-window rule -- a lone
#   respawn signal is still reported as a burst of concurrency 1.
#
# --window SECONDS: burst-grouping / recoveries.md cross-reference window
#   (default: 120 -- observed bursts cluster within 16s, with margin for
#   respawn detection/notification delay).
#
# Exit codes: 0 on a normal run (with or without findings); non-zero + stderr
# message when an input file does not exist (same convention as
# collect-recovery-candidates.sh). No burst/unrecorded-kill found -> no
# stdout output, exit 0.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$SCRIPT_DIR}"

WINDOW=120
EVENTS_FILE=""
RECOVERIES_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --window)
      WINDOW="${2:-}"
      shift 2
      ;;
    --window=*)
      WINDOW="${1#--window=}"
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [ -z "$EVENTS_FILE" ]; then
        EVENTS_FILE="$1"
      elif [ -z "$RECOVERIES_FILE" ]; then
        RECOVERIES_FILE="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$EVENTS_FILE" ] || [ -z "$RECOVERIES_FILE" ]; then
  echo "Usage: $0 <events-jsonl-path> <recoveries-md-path> [--window SECONDS]" >&2
  exit 1
fi

case "$WINDOW" in
  ''|*[!0-9]*)
    echo "Error: --window must be a positive integer, got: $WINDOW" >&2
    exit 1
    ;;
esac

if [ ! -f "$EVENTS_FILE" ]; then
  echo "File not found: $EVENTS_FILE" >&2
  exit 1
fi

if [ ! -f "$RECOVERIES_FILE" ]; then
  echo "File not found: $RECOVERIES_FILE" >&2
  exit 1
fi

python3 - "$EVENTS_FILE" "$RECOVERIES_FILE" "$WINDOW" <<'PYEOF'
import json
import re
import sys
from datetime import datetime, timezone

events_file, recoveries_file, window_arg = sys.argv[1], sys.argv[2], sys.argv[3]
window_s = int(window_arg)


def parse_ts(ts):
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


TERMINAL_EVENTS = {"wrapper_exit", "phase_complete"}

starts = []
terminals = []

with open(events_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        etype = ev.get("event")
        issue = ev.get("issue")
        if issue is None:
            continue
        ts = ev.get("ts", "")
        try:
            ts_dt = parse_ts(ts)
        except ValueError:
            continue
        if etype == "phase_start":
            starts.append({
                "issue": issue,
                "phase": ev.get("phase", ""),
                "ts": ts,
                "ts_dt": ts_dt,
                "spawn_detach": ev.get("spawn_detach", "unknown"),
            })
        elif etype in TERMINAL_EVENTS:
            terminals.append({"issue": issue, "phase": ev.get("phase", ""), "ts_dt": ts_dt})
        elif etype == "manual_intervention":
            # manual_intervention carries the phase under recovery_target, not phase
            # (see scripts/emit-event.sh's documented schema).
            terminals.append({"issue": issue, "phase": ev.get("recovery_target", ""), "ts_dt": ts_dt})

groups = {}
for s in starts:
    key = (s["issue"], s["phase"])
    groups.setdefault(key, []).append(s)
for key in groups:
    groups[key].sort(key=lambda x: x["ts_dt"])

signals = []
for (issue, phase), lst in groups.items():
    for i in range(len(lst) - 1):
        start_i = lst[i]
        start_next = lst[i + 1]
        has_terminal = any(
            t["issue"] == issue and t["phase"] == phase
            and start_i["ts_dt"] < t["ts_dt"] < start_next["ts_dt"]
            for t in terminals
        )
        if has_terminal:
            continue
        elapsed = (start_next["ts_dt"] - start_i["ts_dt"]).total_seconds()
        signals.append({
            "issue": issue,
            "phase": phase,
            "kill_ts_dt": start_next["ts_dt"],
            "kill_ts": start_next["ts"],
            "elapsed": elapsed,
            "spawn_detach": start_i["spawn_detach"],
        })

if not signals:
    sys.exit(0)

# Parse docs/reports/orchestration-recoveries.md entries: heading timestamp +
# "### Context" block's "Issue #N, phase: <phase>" line.
heading_re = re.compile(r'^## (\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}) UTC: ')
context_re = re.compile(r'^- Issue #(\d+), phase: (\S+)')
entries = []
cur_ts = None
in_context = False
with open(recoveries_file) as f:
    for line in f:
        line = line.rstrip("\n")
        m = heading_re.match(line)
        if m:
            cur_ts = datetime.strptime(
                f"{m.group(1)} {m.group(2)}", "%Y-%m-%d %H:%M"
            ).replace(tzinfo=timezone.utc)
            in_context = False
            continue
        if line.startswith("### Context"):
            in_context = True
            continue
        if line.startswith("### ") and line.strip() != "### Context":
            in_context = False
            continue
        if in_context:
            cm = context_re.match(line)
            if cm and cur_ts is not None:
                entries.append((cur_ts, int(cm.group(1)), cm.group(2)))

for sig in signals:
    recorded = "no"
    for (ets, eissue, ephase) in entries:
        if eissue == sig["issue"] and ephase == sig["phase"]:
            if abs((ets - sig["kill_ts_dt"]).total_seconds()) <= window_s:
                recorded = "yes"
                break
    sig["recorded"] = recorded

signals.sort(key=lambda s: s["kill_ts_dt"])

bursts = [[signals[0]]]
for sig in signals[1:]:
    gap = (sig["kill_ts_dt"] - bursts[-1][-1]["kill_ts_dt"]).total_seconds()
    if gap <= window_s:
        bursts[-1].append(sig)
    else:
        bursts.append([sig])

for burst in bursts:
    start_ts = burst[0]["kill_ts"]
    end_ts = burst[-1]["kill_ts"]
    print(f"## Burst: {start_ts} - {end_ts} UTC (concurrency={len(burst)})")
    for m in burst:
        print(
            f"- Issue #{m['issue']}, phase: {m['phase']}, kill: {m['kill_ts']}, "
            f"elapsed: {int(m['elapsed'])}s, spawn_detach: {m['spawn_detach']}, "
            f"recorded: {m['recorded']}"
        )
    print()
PYEOF
