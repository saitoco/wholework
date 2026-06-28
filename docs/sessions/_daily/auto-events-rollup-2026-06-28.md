---
type: report
description: Daily rollup of /auto session events from .tmp/auto-events.jsonl
generated_by: scripts/auto-events-rollup.sh
generated_at: 2026-06-28T04:39:46Z
---

# /auto Event Rollup — 2026-06-28

## Sessions

| Issue | Size | Start (UTC) | End (UTC) | Duration | Phases | Recoveries | Outcome |
|-------|------|-------------|-----------|----------|--------|------------|---------|
| #429 | S | 03:04:22 | 03:29:33 | 25m | code-patch | — | success |
| #429 | - | 02:53:22 | 03:11:16 | 17m | issue→spec | — | success |
| #431 | S | 03:39:23 | 03:52:53 | 13m | code-patch | — | success |
| #431 | - | 03:32:09 | 03:39:12 | 7m | issue | — | success |
| #432 | S | 04:03:42 | 04:28:04 | 24m | code-patch | — | success |
| #432 | - | 03:54:40 | 04:12:37 | 17m | issue→spec | — | success |
| #434 | M | 04:37:24 | - | - |  | — | incomplete |
| #434 | - | 04:29:09 | 04:37:13 | 8m | issue | — | success |
| #788 | S | 00:11:57 | 00:21:20 | 9m | issue→spec | — | success |
| #789 | S | 00:48:13 | 01:01:39 | 13m | issue→code-patch | — | success |
| #790 | S | 01:09:53 | 01:43:11 | 33m | issue→spec→code-patch | 1 | success |
| #794 | S | 01:49:56 | 02:11:26 | 21m | issue→spec→code-patch | — | success |
| #795 | S | 02:24:42 | 02:52:04 | 27m | issue→code-patch | — | success |
| #795 | - | 02:24:43 | 02:36:56 | 12m | spec | — | success |
| #796 | S | 03:02:57 | 03:25:48 | 22m | code-patch | — | success |
| #796 | - | 02:53:11 | 03:11:31 | 18m | issue→spec | — | success |
| #797 | M | 03:34:04 | 03:50:24 | 16m | code-patch | — | success |
| #797 | - | 03:26:35 | 03:43:17 | 16m | issue→spec | — | success |
| #798 | M | 03:57:43 | 04:22:14 | 24m | code-pr | — | success |
| #798 | - | 03:51:16 | 04:08:27 | 17m | issue→spec | — | success |
| #804 | S | 00:47:36 | 01:12:59 | 25m | issue→issue→spec→code-patch | — | success |
| #806 | L | 01:24:00 | 02:01:34 | 37m | issue→spec→code-pr | — | success |
| #807 | L | 02:29:34 | 03:21:12 | 51m | issue→spec→spec→code-pr | — | success |
| #811 | - | 00:00:11 | 00:51:49 | 51m | issue→spec→code-pr | — | success |
| #812 | - | 00:11:49 | 00:33:03 | 21m | review→merge | — | success |
| #813 | - | 00:52:02 | 01:06:30 | 14m | review | — | success |
| #814 | - | 01:50:09 | 02:21:20 | 31m | review→merge | — | success |
| #815 | - | 02:01:35 | 02:20:28 | 18m | review→merge | — | success |
| #816 | - | 03:21:13 | 03:44:06 | 22m | review→merge | — | success |
| #817 | - | 04:22:15 | 04:38:27 | 16m | review→merge | — | success |

## Phase Distribution

| Phase | Count | Median Duration | p95 |
|-------|-------|-----------------|-----|
| code-patch | 10 | 14m | 25m |
| code-pr | 4 | 22m | 26m |
| issue | 17 | 8m | 12m |
| merge | 5 | 4m | 5m |
| review | 6 | 16m | 26m |
| spec | 14 | 9m | 20m |

## Recovery Tier Invocations

| Tier | Count | Issues |
|------|-------|--------|
| 2 | 1 | #790 |

## Anomalies

- (none)
