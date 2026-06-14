# Issue #465: run-code exit-0 reconcile silent failure detection

## Overview

`run-code.sh` was calling `reconcile-phase-state.sh --check-completion` only on watchdog timeout (exit code 143). By also calling it on normal exit (exit code 0), silent failures — where the code skill returns exit 0 without actually implementing anything (misrouted dispatch, ignored errors, etc.) — can be detected early in the `/auto` pipeline. When `matches_expected: false`, the wrapper exits 1 and feeds into the existing 3-tier recovery in `/auto` Step 6.

Implementation was completed as part of #520 (PR #525) and all pre-merge ACs are already satisfied.

## Changed Files

- `scripts/run-code.sh`: extend reconcile condition from `EXIT_CODE -eq 143` to `EXIT_CODE -eq 143 || EXIT_CODE -eq 0`; on exit-0 with `matches_expected: false`, emit stderr warning and set `EXIT_CODE=1` — bash 3.2+ compatible
- `tests/run-code.bats`: add three reconcile tests — exit 0 + `matches_expected:false` → exit 1; exit 0 + `matches_expected:true` → exit 0; exit 0 + empty reconcile output → exit 0 (no false alarm)

## Implementation Steps

1. In `scripts/run-code.sh`, change the reconcile trigger condition from `EXIT_CODE -eq 143` to `EXIT_CODE -eq 143 || EXIT_CODE -eq 0` so `reconcile-phase-state.sh --check-completion` is called on any non-error exit (→ AC1, AC2)
2. Add an `elif` branch: when `EXIT_CODE -eq 0` and reconcile output contains `"matches_expected":false`, emit a stderr warning and set `EXIT_CODE=1` — enabling the `/auto` 3-tier recovery (→ AC3, AC4)
3. Add bats tests in `tests/run-code.bats` covering the three exit-0 reconcile scenarios (→ AC5)

Note: All three steps are already implemented in #520 (PR #525). The `/code` phase should verify the existing implementation satisfies all ACs.

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/run-code.sh" "--check-completion" --> `run-code.sh` が `reconcile-phase-state.sh --check-completion` を呼び出す
- <!-- verify: grep "EXIT_CODE -eq 0" "scripts/run-code.sh" --> exit 0 時も reconcile の条件分岐に含まれている
- <!-- verify: grep "matches_expected" "scripts/run-code.sh" --> `matches_expected: false` 時の処理が存在する
- <!-- verify: grep "EXIT_CODE=1" "scripts/run-code.sh" --> silent failure 時に exit 1 を返す
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) の bats テストが green（`tests/run-code.bats` の exit-0 reconcile テストを含む）

### Post-merge

- `/auto` 実行で silent no-op（exit 0 だが実装なし）が自動検出され、3-tier recovery へ流れることを実運用でモニタする

## Notes

- 実装は #520（PR #525）で完了済み。`scripts/run-code.sh` L187–L198 および `tests/run-code.bats` L392–L428 が対象コード
- スコープは `run-code.sh` のみ（タイトルに明記）。他スクリプト（`run-spec.sh` / `run-review.sh` / `run-merge.sh` / `run-issue.sh`）は #520 で別途対応済み
- `matches_expected: false` 時の exit code は exit 1 に確定（`/auto` 3-tier recovery フローへ接続するために必要）
- Exit 0 + empty reconcile output は false alarm を避けるため exit 0 のまま維持（AC4 の `grep "EXIT_CODE=1"` は `elif` ブランチの存在チェックであり、空出力ケースを排除するものではない）
