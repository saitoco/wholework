---
type: report
description: Daily rollup of /auto session events from .tmp/auto-events.jsonl
generated_by: scripts/auto-events-rollup.sh
generated_at: 2026-06-29T04:30:28Z
---

# /auto Event Rollup — 2026-06-29

## Sessions

| Issue | Size | Start (UTC) | End (UTC) | Duration | Phases | Recoveries | Outcome |
|-------|------|-------------|-----------|----------|--------|------------|---------|
| #821 | M | 02:02:53 | 02:50:23 | 47m | code-patch | 1 | success |
| #821 | - | 01:55:10 | 02:02:43 | 7m | issue | — | success |
| #832 | - | 00:01:25 | 00:10:03 | 8m | spec→code-pr | — | success |
| #834 | S | 01:05:24 | 01:20:48 | 15m | spec→code-patch | — | success |
| #834 | - | 00:57:32 | 01:05:15 | 7m | issue | — | success |
| #836 | S | 00:34:34 | 00:56:18 | 21m | spec→code-patch | — | success |
| #836 | - | 00:28:42 | 00:34:25 | 5m | issue | — | success |
| #841 | S | 01:30:00 | 01:53:24 | 23m | spec→code-patch | — | success |
| #841 | - | 01:21:36 | 01:29:49 | 8m | issue | — | success |
| #846 | - | 00:10:04 | 00:27:29 | 17m | review→merge | — | success |
| #848 | S | 04:25:39 | 04:30:10 | 4m | code-patch | — | success |
| #848 | S | 02:34:08 | 03:03:23 | 29m | issue→spec→code-patch | — | success |
| #849 | S | 03:16:34 | 03:33:08 | 16m | issue→spec→code-pr | — | success |
| #850 | XS | 04:00:54 | 04:27:35 | 26m | issue→code-patch | 1 | success |
| #851 | - | 03:33:09 | 03:53:04 | 19m | review→merge | — | success |

## Phase Distribution

| Phase | Count | Median Duration | p95 |
|-------|-------|-----------------|-----|
| code-patch | 7 | 13m | 28m |
| code-pr | 2 | 8m | 8m |
| issue | 7 | 7m | 9m |
| merge | 2 | 5m | 5m |
| review | 2 | 15m | 15m |
| spec | 5 | 8m | 14m |

## Recovery Tier Invocations

| Tier | Count | Issues |
|------|-------|--------|
| 2 | 2 | #821, #850 |

## Anomalies

- (none)
