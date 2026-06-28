# Issue #802: event-emission: Fix Backfill section inconsistency with _maybe_emit_phase_complete guard

## Overview

`modules/event-emission.md` has two inconsistent descriptions of backfill behavior:

1. `### phase_complete (backfilled)` section (line 47-48): "This covers abnormal exits (SIGTERM / watchdog timeout)." — **incorrect** (says SIGTERM is covered but code doesn't implement this)
2. `## Backfill` section (lines 131-138): "on clean (exit code 0) exits only" — **correct** (matches code)

All four `run-*.sh` scripts have the identical guard `[[ "$_exit_code" -ne 0 ]] && return 0` as the first line of `_maybe_emit_phase_complete()`, so SIGTERM (exit 143) causes an early return without backfill.

Resolution: implement Option 2 (code extension) — extend the exit_code guard to allow SIGTERM (exit 143), then fix both description inconsistencies. This improves data-layer accuracy for Tier 3 recovery analysis.

## Reproduction Steps

1. Run `/auto` on an issue that triggers a watchdog timeout (SIGTERM kill)
2. Inspect `.tmp/auto-events.jsonl` — `phase_start` is emitted but `phase_complete (backfilled)` is absent despite the `### phase_complete (backfilled)` doc claiming it "covers SIGTERM / watchdog timeout"
3. Compare with `## Backfill` section which correctly says "exit code 0 only"

## Root Cause

`_maybe_emit_phase_complete()` in all 4 wrappers guards with:
```bash
local _exit_code=$?
[[ "$_exit_code" -ne 0 ]] && return 0
```

SIGTERM causes exit 143 (128+15). The `[[ "$_exit_code" -ne 0 ]] && return 0` guard fires immediately, skipping all backfill logic. The EXIT trap fires (bash ensures this), but the function returns before writing the backfill entry.

The `### phase_complete (backfilled)` description was written to reflect intended behavior that was never implemented. The later-added `## Backfill` section correctly documented the actual behavior, creating internal inconsistency.

## Changed Files

- `modules/event-emission.md`: fix `### phase_complete (backfilled)` description to say "exit code 0 or exit code 143 (SIGTERM / watchdog timeout)"; update `## Backfill` guard conditions to say "exit code 0 or 143"
- `scripts/run-issue.sh`: change exit_code guard from `[[ "$_exit_code" -ne 0 ]]` to `[[ "$_exit_code" -ne 0 && "$_exit_code" -ne 143 ]]` — bash 3.2+ compatible
- `scripts/run-spec.sh`: same guard change — bash 3.2+ compatible
- `scripts/run-code.sh`: same guard change — bash 3.2+ compatible
- `scripts/run-auto-sub.sh`: same guard change — bash 3.2+ compatible
- `tests/auto-sub-observability.bats`: add `@test "backfill-emit: SIGTERM (exit 143) with phase_start emits phase_complete with backfilled"` — uses a minimal inline helper script (written to `$BATS_TEST_TMPDIR`) that sources `emit-event.sh`, defines `_maybe_emit_phase_complete()` with the updated guard, pre-writes `phase_start` to the log, and exits 143; asserts `"backfilled":true` in log

## Implementation Steps

1. Update `modules/event-emission.md` (→ AC 1):
   - In `### phase_complete (backfilled)` section: replace "This covers abnormal exits (SIGTERM / watchdog timeout)." with "This covers exit code 0 (clean exit) and exit code 143 (SIGTERM / watchdog timeout)."
   - In `## Backfill` section main body: replace "on clean (exit code 0) exits only." with "on exit code 0 (clean exit) or exit code 143 (SIGTERM / watchdog timeout)."
   - In `## Backfill` guard conditions list: replace the "Exit code must be 0 ..." bullet with "Exit code must be 0 or 143 (SIGTERM): other non-zero exits are not backfilled (non-SIGTERM failures tracked by `wrapper_exit` events from `run-auto-sub.sh`)"

2. Change `_maybe_emit_phase_complete()` exit_code guard in all 4 scripts (→ AC 1, AC 2):
   - In `scripts/run-issue.sh` line ~33, `scripts/run-spec.sh` line ~54, `scripts/run-code.sh` line ~57, `scripts/run-auto-sub.sh` line ~52:
   - Change: `[[ "$_exit_code" -ne 0 ]] && return 0`
   - To: `[[ "$_exit_code" -ne 0 && "$_exit_code" -ne 143 ]] && return 0`

3. Add bats test to `tests/auto-sub-observability.bats` immediately after the existing `backfill-emit: exits 0 ...` test (→ AC 2):
   - `@test "backfill-emit: SIGTERM (exit 143) with phase_start emits phase_complete with backfilled"`
   - Setup: export `AUTO_SESSION_ID`, `EMIT_ISSUE_NUMBER=42`, `EMIT_PHASE_NAME`, `AUTO_EVENTS_LOG`; pre-write `phase_start` JSONL entry to `$AUTO_EVENTS_LOG`
   - Create `$BATS_TEST_TMPDIR/sigterm-helper.sh` with the updated `_maybe_emit_phase_complete()` function (using the 143-aware guard), trap, and `exit 143`; source the mock `emit-event.sh` from `$MOCK_DIR`
   - `run bash "$BATS_TEST_TMPDIR/sigterm-helper.sh"` (exits 143; `run` captures it)
   - Assert: `grep -q '"backfilled":true' "$AUTO_EVENTS_LOG"`

## Verification

### Pre-merge

- <!-- verify: rubric "modules/event-emission.md の Backfill セクション記述と scripts/run-*.sh の _maybe_emit_phase_complete 関数の動作が一致している (exit code に関する記述が正確、SIGTERM/watchdog timeout 対応の有無が明示されている)" --> `modules/event-emission.md` の Backfill セクションが `_maybe_emit_phase_complete()` の実動作と一致 (exit code 限定 or SIGTERM 対応のいずれかで明確化)
- <!-- verify: rubric "tests/run-*.bats のいずれかで Backfill 仕様 (SIGTERM 対応 or exit 0 限定) を assert する test が追加されている" --> bats test で SIGTERM ケースの backfill 動作 (実装する場合) または exit 0 限定の動作 (記述修正の場合) が assert されている
- <!-- verify: github_check "gh run view $(gh run list --workflow=test.yml --limit=1 --json databaseId --jq '.[0].databaseId') --json jobs --jq '.jobs[] | select(.name==\"Run bats tests\").conclusion'" "success" --> CI bats tests pass

### Post-merge

- 次回 Tier 3 recovery 発生時 (`code-pr-tier3-recovery` パターン等) に対象 Issue の data-layer report が SIGTERM 経路を反映していることを観察

## Notes

- **Auto-resolved (non-interactive)**: Issue offers Option 1 (doc fix) or Option 2 (code extension). Chose Option 2 because: (1) guard change is trivial (single condition addition), (2) same function appears identically in all 4 scripts, (3) SIGTERM backfill improves Tier 3 recovery data accuracy (post-merge AC), (4) existing bats infrastructure supports the test. Option 1 would leave an observable gap in the event log that the post-merge AC explicitly targets.
- **Bash compatibility**: `&&` in `[[ ... ]]` compound condition is bash 3.2+ compatible (no `mapfile` or other bash 4+ constructs used).
- **Exit 143 = SIGTERM**: `_exit_code=143` corresponds to SIGTERM (128+15). Only SIGTERM is special-cased; other non-zero exits (e.g., 1 from claude failure, 127 from command-not-found) continue to skip backfill — they are tracked by `wrapper_exit` events instead.
- **Test approach**: The bats test uses an inline helper script written to `$BATS_TEST_TMPDIR` rather than running the full `run-auto-sub.sh`, because triggering actual SIGTERM on a complex script in a bats test is timing-sensitive and flaky. The helper script directly exercises the updated `_maybe_emit_phase_complete()` logic.
- **No `docs/structure.md` update needed**: `modules/event-emission.md` is already listed in Key Files; its description ("event emission contract SSoT") remains accurate.
- **Count alignment warning**: Issue body has 2 pre-merge AC checkboxes; Spec has 3 verification lines (AC 2 carries 2 verify commands). This mismatch is expected — one AC item has two verify commands.

## Consumed Comments

No new comments since last phase.
