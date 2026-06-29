# /auto Session Report — 62650-1782653419

**Session start**: 2026-06-28T13:36:54Z
**Session end**: 2026-06-28T18:11:27Z
**Wall-clock**: 04:34:33
**Route mix**: patch: 0, pr: 5, xl: 0

## Summary

| Metric | Value |
|---|---|
| Issues processed | 10 |
| Fully closed (phase/done) | 0 |
| phase/verify remaining | 5 |
| Throughput | 2.2 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 |
| Watchdog kills | 0 |
| Max silent window (any phase) | 1490s |
| Phase silent windows > threshold | 0 |
| Total token usage | input 3495 / output 235534 |
| Concurrent commits detected | 10 |
| Parent session manual interventions | 0 |
| verify FAIL → reopen fix cycles | 0 |
| Backfilled phase_complete events | 0 |
| Merge conflicts | 0 |

## Per-Issue Durations

| Issue | Size/Route | Duration | Phase breakdown | PR | Notes |
|---|---|---|---|---|---|
| #819 | M/pr | 2026-06-28T13:36:56Z – 2026-06-28T13:56:38Z | code-pr 8m → spec 11m | #825 | Silent 660s |
| #820 | M/pr | 2026-06-28T14:31:41Z – 2026-06-28T14:51:24Z | code-pr 10m → spec 9m | #828 | Silent 630s |
| #822 | M/pr | 2026-06-28T15:17:15Z – 2026-06-28T15:58:59Z | code-pr 23m → spec 18m | #830 | Size M→L;Silent 1400s |
| #823 | M/pr | 2026-06-28T16:35:57Z – 2026-06-28T17:08:52Z | code-pr 24m → spec 7m | #833 | Silent 1490s |
| #824 | M/pr | 2026-06-28T17:36:02Z – 2026-06-28T17:57:05Z | code-pr 12m → spec 8m | #835 | Silent 760s |
| #825 | ?/? | 2026-06-28T13:56:39Z – 2026-06-28T14:14:42Z | merge 4m → review 13m | #825 | Silent 750s;2 concurrent commits |
| #828 | ?/? | 2026-06-28T14:51:25Z – 2026-06-28T15:05:47Z | merge 5m → review 8m | #828 | 2 concurrent commits |
| #830 | ?/? | 2026-06-28T15:59:00Z – 2026-06-28T16:23:22Z | merge 4m → review 19m | #830 | Silent 1110s;2 concurrent commits |
| #833 | ?/? | 2026-06-28T17:08:53Z – 2026-06-28T17:24:04Z | merge 4m → review 10m | #833 | 2 concurrent commits |
| #835 | ?/? | 2026-06-28T17:57:06Z – 2026-06-28T18:11:27Z | merge 3m → review 10m | #835 | 2 concurrent commits |


## Recovery Events

(no recovery events)

## Verify Phase Residuals

(none)

## Concurrent Sessions Detected

- [2026-06-28T14:14:41Z] phase=merge sha=3d9bc008 → #819 (author=Toshihiro Saito)
- [2026-06-28T14:14:41Z] phase=merge sha=baf70311 → #819 (author=Toshihiro Saito)
- [2026-06-28T15:05:47Z] phase=merge sha=7001ef2c → #820 (author=Toshihiro Saito)
- [2026-06-28T15:05:47Z] phase=merge sha=947240ad → #820 (author=Toshihiro Saito)
- [2026-06-28T16:23:22Z] phase=merge sha=e858edc3 → #822 (author=Toshihiro Saito)
- [2026-06-28T16:23:22Z] phase=merge sha=f2a34051 → #822 (author=Toshihiro Saito)
- [2026-06-28T17:24:04Z] phase=merge sha=d98f016d → #823 (author=Toshihiro Saito)
- [2026-06-28T17:24:04Z] phase=merge sha=f70ec5eb → #823 (author=Toshihiro Saito)
- [2026-06-28T18:11:27Z] phase=merge sha=fd515553 → #824 (author=Toshihiro Saito)
- [2026-06-28T18:11:27Z] phase=merge sha=ae818958 → #824 (author=Toshihiro Saito)


## Improvement Candidates Surfaced

(none — no Tier 3 recoveries or Tier 2 approaching recoveries-auto-fire threshold)
