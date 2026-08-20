# Issue #736: test: add direct bats coverage for scripts/get-auto-session-report.sh

## Overview

`scripts/get-auto-session-report.sh` is the data layer for `/audit auto-session`. It has multiple modes: session_id filter, `--since` list mode, period aggregation, and `--narrative-draft` insertion. The existing tests in `tests/audit-auto-session.bats` and `tests/audit-auto-session-full.bats` provide broad coverage but treat the tests as integration-level rather than direct unit tests targeting specific edge cases. This Issue adds `tests/get-auto-session-report.bats` with direct unit tests for the four key modes identified in the Issue: session_id filter, `--since` list mode, empty jsonl graceful degrade, and `--narrative-draft` insertion.

## Changed Files

- `tests/get-auto-session-report.bats`: new file — 4 @test cases for session_id filter / `--since` list mode / empty jsonl / `--narrative-draft` insertion — bash 3.2+ compatible
- `docs/structure.md`: update `tests/` line from "(81 files)" to "(82 files)"
- `docs/ja/structure.md`: update `tests/` line from "（81 ファイル）" to "（82 ファイル）"

## Implementation Steps

1. Create `tests/get-auto-session-report.bats` with the following 4 @test cases (→ AC1, AC2, AC3, AC4). All tests use `--no-github` for hermetic execution. `AUTO_EVENTS_LOG`, `OUTPUT_PATH` are set in `setup()` using `BATS_TEST_TMPDIR`.

   - `@test "session_id filter: only specified session events appear in report"` — write 2-session fixture, run with session-A ID, confirm report contains session-A's issue number and `Issues processed | 1`, not session-B data
   - `@test "--since list mode: lists distinct session_ids from event log"` — write 2-session fixture, run with `--since 2020-01-01` (old date cutoff to include all events), confirm output prints both session IDs
   - `@test "empty jsonl: graceful degrade when log file is empty"` — create empty file with `touch`, run in session_id mode with arbitrary ID, confirm exit 0, report created, `Issues processed | 0`
   - `@test "--narrative-draft: draft content inserted into report"` — write fixture, create draft file with `### What worked` section, run with `--narrative-draft` flag, confirm draft text appears in output report

2. Update `docs/structure.md`: change `tests/               # Bats test files for scripts (81 files)` → `(82 files)` (→ SHOULD: doc sync per translation-workflow.md)

3. Update `docs/ja/structure.md`: change `tests/               # スクリプトの Bats テストファイル（81 ファイル）` → `（82 ファイル）` (→ SHOULD: doc/ja sync per translation-workflow.md)

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/get-auto-session-report.bats" --> direct test ファイルが新規作成されている
- <!-- verify: file_contains "tests/get-auto-session-report.bats" "@test" --> 最低 4 件以上の @test (session_id 指定 / `--since` list mode / 空 jsonl / `--narrative-draft` 挿入) を含む
- <!-- verify: command "bats tests/get-auto-session-report.bats" --> 追加した bats テストすべて green
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI bats 全件 green

### Post-merge

- 次回 get-auto-session-report.sh を変更する Issue で direct unit test が regression を検出することを観察 <!-- verify-type: manual -->

## Consumed Comments

- `saito` / MEMBER / first-class / Issue Retrospective (AP1: file_contains "@test" is sufficient; AP2: --no-github implicit in all tests, bad draft path is implementation-discretion) / https://github.com/saitoco/wholework/issues/736#issuecomment-4759814090

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/736#issuecomment-4759863981
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5200981911
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5212260733
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5225314464
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5229258259
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5235400832
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5246554413
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5255742181
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5296376396
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5304271652
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5310544765
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5327720762
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5341228246
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/736#issuecomment-5354365012
## Notes

- Auto-Resolved Ambiguity Points (from Issue body):
  - **AP1 (verify command の数量保証)**: AC2 の `file_contains "@test"` は 1 件でも PASS。「4 件以上」は実装ガイダンス。AC3 の bats 実行成功で品質補完。`command "grep -c '@test'"` は safe mode で UNCERTAIN になるため不採用。
  - **AP2 (Background edge case と AC の対応)**: `--no-github` は全 @test で使用するため独立 @test 不要。narrative draft 不正 path は実装者判断。
- `tests/get-auto-session-report.bats` is covered by CI `test.yml` alongside all other `.bats` files
- The `--since` list mode test uses a date-based cutoff (`--since 2020-01-01`) to ensure all fixture events are included regardless of test run time
- `WHOLEWORK_ISSUE_BODY_DIR` env var is available for fixture-based testing of verify-type breakdown if needed in future tests, but is not required for the 4 core @test cases in this Issue

## Code Retrospective

### Deviations from Design
- None — all 4 @test cases implemented exactly as specified in the Spec.

### Design Gaps/Ambiguities
- The Spec says "not session-B data" for the session_id filter test, but did not specify the exact negative assertion pattern. Used `! grep -q "| #200 |"` targeting the per-issue table row format `| #N |` to avoid false matches from issue numbers appearing in timestamps or other fields.

### Rework
- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Used `echo "$output" | grep -q "..."` pattern for list-mode output checks (consistent with bats idiom for checking stdout captured in `$output`).
- The `--since 2020-01-01` cutoff in the list-mode test is date-based (not hour-based) to avoid time-of-day sensitivity.
- Negative assertion `! grep -q "| #200 |"` scopes the check to the per-issue table row format, reducing false-positive risk.

### Deferred Items
- AC4 (CI green check via `github_check "gh run list ..."`) can only be verified after the commit is pushed; it will be checked by `/verify`.
- Background edge case `--narrative-draft` with invalid/missing file path was not added as a separate `@test` (per AP2 auto-resolve).

### Notes for Next Phase
- All 4 bats tests are green locally; CI (`test.yml`) will run them as part of the full bats suite.
- The `github_check` AC uses `--commit=$(git rev-parse HEAD)` which resolves at verify time — verify should confirm the correct commit SHA is used.

## Verify Retrospective

### Phase-by-Phase Review

#### verify
- pre-merge AC1-3 PASS。AC4 (CI) は setup-labels.bats の pre-existing failure。本 Issue の対象 bats は green、代替検証 PASS。

### Improvement Proposals
- N/A

### 2026-08-21 再確認 (/auto --batch セッション、#1406 修正後の dispatch)

`#1406` (ラウンドロビン回転方式) 後の `Event-based observation scan` で dispatch。Post-merge observation AC (`event=auto-run`) の実質初回評価。

`scripts/get-auto-session-report.sh` は #1007/#1279/#1300/#1312 等で複数回 "fix: ... + regression coverage" 形式の変更を受けており (#731/#732 の shallow doc-test とは異なり実際の script 動作を検証する direct test)、regression-detection サイクルの蓋然性自体は高い。しかし #1300 の Code Retrospective では Rework=N/A (手戻りなし、実装は1回で完了) と記録されており、新規テストが修正前コードに対して実際に FAIL した直接証跡は見つからなかった。AC の保守的規定に従い SKIPPED を維持。

#### Improvement Proposals (再評価分)
- N/A — ただし、このパターン (テスト新設 Issue の post-merge observation AC が、後続の "fix + regression test" 型変更でも FAIL 証跡を得られず恒常的に SKIPPED のまま推移する) が #731/#732/#736 の3件で共通して観測されており、AC 設計自体が「テストファースト開発では FAIL が commit 履歴に残らない」という構造的制約を持つ可能性がある。再発性は認識したが、単体では Tier 1 の multi-file ripple/SSoT 基準を満たさないため見送り。3件目以降さらに同型が続く場合は改めて評価する。
