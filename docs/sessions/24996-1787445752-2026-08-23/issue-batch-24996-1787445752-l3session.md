## Auto Retrospective
### Improvement Proposals
- Missing PGID pointer-file regeneration before `run-issue.sh`/`run-auto-sub.sh` calls in Count mode caused several phase events (issue/spec/code/review/merge for #1447, #1446, #1444) to record an empty `session_id`, degrading event-based session-boundary detection and L3 metrics attribution for those phases.
