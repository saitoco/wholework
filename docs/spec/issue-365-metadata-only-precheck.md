# Issue #365: verify: ファイル変更ゼロの実装ルートで pre-check false-positive を抑制

## Auto Retrospective

### Execution Summary

| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| code | patch (XS) | SUCCESS (manual recovery) | run-code.sh exited 0 with reported "Direct commit and push to main 完了" but no commit was produced and working tree was clean. Parent `/auto` session manually implemented the Step 1 pre-check edit and committed directly to main. |
| verify (iter 1) | - | FAIL | Detected absent marker correctly (AC1 grep no match). Issue reopened, phase/* cleared. |
| verify (iter 2) | - | SUCCESS (pre-merge) | AC1 passed after manual recovery commit `497aea2`. Post-merge AC2 remains unchecked as `verify-type: opportunistic` awaiting a future `/verify` run against a `<!-- implementation-type: metadata-only -->` Issue. |

### Orchestration Anomalies

- **Silent no-op from code sub-agent (wrapper exit 0)**: `run-code.sh` terminated with exit code 0 and the LLM output asserted "Direct commit and push to main が完了しました" + a full implementation-content summary referencing `<!-- implementation-type: metadata-only -->` marker handling, yet `git log` / `git diff` showed no change. `reconcile-phase-state.sh code-patch --check-completion` confirmed post hoc: `{"matches_expected":false,"diagnosis":"no commit with closes #365 found on origin/main"}`. The anomaly was caught only downstream at `/verify` iter 1 (AC1 FAIL).
- Category: case (c) from `/auto` Step 4a — completed with behavior that differs from the original spec.

### Improvement Proposals

- **Always run `reconcile-phase-state.sh <phase> --check-completion` after every code phase, regardless of wrapper exit code**: Currently the patch-route completion check only fires on non-zero exit (Step 4 patch route step 3). Observe→Diagnose→Act should apply symmetrically — a false success should be caught as fast as a false failure. Proposal: in `skills/auto/SKILL.md` patch-route and pr-route, move the completion check to run unconditionally after every `run-*.sh` call; if `matches_expected: false` and wrapper exit was 0, escalate to Tier 2 anomaly detection instead of continuing to the next phase.
- **Teach `detect-wrapper-anomaly.sh` the "LLM-reported-success-but-no-commit" pattern**: add a detector entry for `exit_code=0` + (`git log --grep "#$NUMBER"` returns empty) + (LLM output contains success phrase like "完了しました" / "commit and push") so the same anomaly surfaces in Tier 2 with a known recovery (re-run `run-code.sh` once; on second failure, surface to user for manual implementation).
- **Clarify verify-type: opportunistic handling in patch-route XS**: when all pre-merge AC pass but at least one `verify-type: opportunistic` AC remains unchecked, `/auto` currently treats this as "verify success" and proceeds to Step 5. Confirm this is intended (Issue stays at `phase/verify` awaiting future opportunistic check) vs. surfacing a clearer completion state ("partial success — opportunistic pending") in the Step 5 completion banner.
