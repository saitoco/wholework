---
type: report
description: Daily rollup of /auto session events from .tmp/auto-events.jsonl
generated_by: scripts/auto-events-rollup.sh
generated_at: 2026-06-26T05:33:07Z
---

# /auto Event Rollup — 2026-06-26

## Sessions

| Issue | Size | Start (UTC) | End (UTC) | Duration | Phases | Recoveries | Outcome |
|-------|------|-------------|-----------|----------|--------|------------|---------|
| #744 | M | 00:48:51 | 01:10:29 | 21m | code-patch | — | success |
| #745 | S | 02:25:45 | 02:49:54 | 24m | code-patch | — | success |
| #748 | S | 01:12:19 | 01:30:37 | 18m | code-patch | — | success |
| #749 | M | 00:04:32 | 00:31:21 | 26m | code-pr | — | success |
| #752 | S | 05:02:14 | 05:30:21 | 28m | code-patch | 1 | success |
| #753 | XS | 04:34:43 | 04:53:57 | 19m | code-patch | — | success |
| #754 | M | 03:55:27 | 04:25:37 | 30m | code-patch | — | success |
| #755 | M | 03:00:52 | 03:25:13 | 24m | code-pr | — | success |
| #756 | - | 00:31:21 | 00:47:31 | 16m | review→merge | — | success |
| #757 | - | 03:25:14 | 03:43:45 | 18m | review→merge | — | success |

## Phase Distribution

| Phase | Count | Median Duration | p95 |
|-------|-------|-----------------|-----|
| code-patch | 6 | 14m | 21m |
| code-pr | 2 | 15m | 15m |
| merge | 2 | 5m | 5m |
| review | 2 | 15m | 15m |

## Recovery Tier Invocations

| Tier | Count | Issues |
|------|-------|--------|
| 2 | 1 | #752 |

## Anomalies

- (none)
