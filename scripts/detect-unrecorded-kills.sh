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
# Usage: detect-unrecorded-kills.sh <events-jsonl-path> <recoveries-md-path> \
#          [--window SECONDS] [--recorded-window SECONDS] [--since SECONDS]
#
# Detection:
#   For each (issue, phase) group of "phase_start" events in <events-jsonl-path>,
#   sorted by ts, a consecutive pair (start_i, start_{i+1}) is a "respawn
#   signal" when none of wrapper_exit / phase_complete (backfilled or not) /
#   manual_intervention occurred for that (issue, phase) strictly between
#   start_i.ts and start_{i+1}.ts -- EXCEPT that a (issue, phase) group whose
#   phase has no wrapper script is excluded from signal generation entirely
#   (see "Wrapper-less phase exclusion" below).
#
#   Wrapper-less phase exclusion: a phase's wrapper base is the part of its
#   name before the first "-" (e.g. "code-pr"/"code-patch" -> "code";
#   "verify" -> "verify"). A phase is considered to have a wrapper when
#   <SCRIPT_DIR>/run-<base>.sh exists on disk -- a generic, non-hardcoded
#   check (SCRIPT_DIR resolves via WHOLEWORK_SCRIPT_DIR when set, same
#   convention other scripts/*.sh use for BATS mocking, else the directory
#   this script itself lives in). Phases without a wrapper (currently only
#   "verify") cannot structurally emit wrapper_exit -- there is no
#   run-verify.sh to emit it -- so their only possible terminal signal is
#   phase_complete, which can also legitimately go missing for reasons other
#   than a kill (e.g. an early-return code path). Treating a phase_complete-
#   less run as a respawn is therefore a false positive whenever the phase
#   is later re-run for an unrelated reason (observed: opportunistic verify
#   re-running the same Issue's verify phase 3.5 days after an earlier run
#   that exited without phase_complete). Excluding wrapper-less phases from
#   signal generation avoids this false-positive class entirely, at the cost
#   of never detecting a genuine kill in a wrapper-less phase -- accepted
#   because no alternative terminal-event source exists for these phases.
#
#   Each respawn signal is cross-referenced against <recoveries-md-path>: an
#   entry whose "### Context" contains "Issue #<issue>, phase: <phase-or-prefix>"
#   (an exact phase match, or a hyphen-prefix match such as "code" matching
#   "code-pr"/"code-patch" -- recoveries.md entries are sometimes hand-written
#   with a generic phase family instead of the concrete phase name) and whose
#   heading timestamp is within --recorded-window seconds of the respawn's
#   kill time (start_{i+1}.ts) marks the signal recorded=yes; otherwise
#   recorded=no.
#
#   All respawn signals (recorded or not) are sorted by kill time and grouped
#   into bursts using a greedy adjacent-gap-within-window rule -- a lone
#   respawn signal is still reported as a burst of concurrency 1.
#
# --window SECONDS: burst-grouping window only (default: 300 -- the prior
#   default of 120 was derived from a single 2026-08-16 burst (bursts cluster
#   within 16s); a 2026-08-17 burst measured a 169-second respawn interval,
#   exceeding that default and causing one real burst to be mis-split into
#   two. 300 covers the observed 169s with margin for respawn
#   detection/notification delay).
#
# --recorded-window SECONDS: recoveries.md cross-reference tolerance (default:
#   86400 -- a parent session's manual recording of a kill can lag the actual
#   respawn by tens of minutes to hours, a fundamentally different scale than
#   burst-grouping adjacency; see Issue #1387's Spec retrospective "Design
#   Gaps/Ambiguities" for the measured gap on a real entry).
#
# --since SECONDS: when set, only respawn signals whose kill time is within
#   the last SECONDS seconds (relative to the time this script runs) are
#   considered. Unset (default) means no recency filtering -- every historical
#   signal in <events-jsonl-path> is reported, matching prior behavior. The
#   `/verify` Step 15 call site passes an explicit value so routine runs only
#   surface recent findings instead of the full history.
#
# Exit codes: 0 on a normal run (with or without findings); non-zero + stderr
# message when an input file does not exist (same convention as
# collect-recovery-candidates.sh), or when an option is missing its required
# value. No burst/unrecorded-kill found -> no stdout output, exit 0.

set -uo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

WINDOW=300
RECORDED_WINDOW=86400
SINCE=""
EVENTS_FILE=""
RECOVERIES_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --window)
      [ $# -ge 2 ] || { echo "Error: --window requires a value" >&2; exit 1; }
      WINDOW="$2"
      shift 2
      ;;
    --window=*)
      WINDOW="${1#--window=}"
      shift
      ;;
    --recorded-window)
      [ $# -ge 2 ] || { echo "Error: --recorded-window requires a value" >&2; exit 1; }
      RECORDED_WINDOW="$2"
      shift 2
      ;;
    --recorded-window=*)
      RECORDED_WINDOW="${1#--recorded-window=}"
      shift
      ;;
    --since)
      [ $# -ge 2 ] || { echo "Error: --since requires a value" >&2; exit 1; }
      SINCE="$2"
      shift 2
      ;;
    --since=*)
      SINCE="${1#--since=}"
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
  echo "Usage: $0 <events-jsonl-path> <recoveries-md-path> [--window SECONDS] [--recorded-window SECONDS] [--since SECONDS]" >&2
  exit 1
fi

case "$WINDOW" in
  ''|*[!0-9]*)
    echo "Error: --window must be a positive integer, got: $WINDOW" >&2
    exit 1
    ;;
esac
if [ "$WINDOW" -eq 0 ]; then
  echo "Error: --window must be a positive integer, got: $WINDOW" >&2
  exit 1
fi

case "$RECORDED_WINDOW" in
  ''|*[!0-9]*)
    echo "Error: --recorded-window must be a positive integer, got: $RECORDED_WINDOW" >&2
    exit 1
    ;;
esac
if [ "$RECORDED_WINDOW" -eq 0 ]; then
  echo "Error: --recorded-window must be a positive integer, got: $RECORDED_WINDOW" >&2
  exit 1
fi

if [ -n "$SINCE" ]; then
  case "$SINCE" in
    ''|*[!0-9]*)
      echo "Error: --since must be a positive integer, got: $SINCE" >&2
      exit 1
      ;;
  esac
  if [ "$SINCE" -eq 0 ]; then
    echo "Error: --since must be a positive integer, got: $SINCE" >&2
    exit 1
  fi
fi

if [ ! -f "$EVENTS_FILE" ]; then
  echo "File not found: $EVENTS_FILE" >&2
  exit 1
fi

if [ ! -f "$RECOVERIES_FILE" ]; then
  echo "File not found: $RECOVERIES_FILE" >&2
  exit 1
fi

python3 - "$EVENTS_FILE" "$RECOVERIES_FILE" "$WINDOW" "$RECORDED_WINDOW" "$SINCE" "$SCRIPT_DIR" <<'PYEOF'
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

events_file, recoveries_file, window_arg, recorded_window_arg, since_arg, script_dir = sys.argv[1:7]
window_s = int(window_arg)
recorded_window_s = int(recorded_window_arg)
since_s = int(since_arg) if since_arg else None


def has_wrapper(phase):
    base = phase.split("-", 1)[0]
    return os.path.isfile(os.path.join(script_dir, f"run-{base}.sh"))


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
        if not isinstance(ev, dict):
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
    if not has_wrapper(phase):
        continue
    for i in range(len(lst) - 1):
        start_i = lst[i]
        start_next = lst[i + 1]
        has_terminal = any(
            t["issue"] == issue and t["phase"] == phase
            and start_i["ts_dt"] < t["ts_dt"] <= start_next["ts_dt"]
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

if since_s is not None:
    cutoff = datetime.now(timezone.utc) - timedelta(seconds=since_s)
    signals = [s for s in signals if s["kill_ts_dt"] >= cutoff]

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
        if line.startswith("#"):
            in_context = False
            continue
        if in_context:
            cm = context_re.match(line)
            if cm and cur_ts is not None:
                entries.append((cur_ts, int(cm.group(1)), cm.group(2)))


def phase_matches(entry_phase, signal_phase):
    if entry_phase == signal_phase:
        return True
    # recoveries.md entries are sometimes hand-written with a generic phase
    # family (e.g. "code") instead of the concrete phase_start name (e.g.
    # "code-pr" / "code-patch"); treat that as a match too.
    return signal_phase.startswith(entry_phase + "-")


for sig in signals:
    recorded = "no"
    for (ets, eissue, ephase) in entries:
        if eissue == sig["issue"] and phase_matches(ephase, sig["phase"]):
            if abs((ets - sig["kill_ts_dt"]).total_seconds()) <= recorded_window_s:
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
