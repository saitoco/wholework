# Issue #735: test: add bats coverage for scripts/collect-recovery-candidates.sh

## Overview

`scripts/collect-recovery-candidates.sh` の集約ロジックを bats で固定し、threshold 変更や substring 比較の regression を検出可能にする。`tests/audit-recoveries.bats` が integration coverage (5 @test: parse / threshold / exclusion / issues-json / normalize) を提供しているが、dedicated direct unit test ファイルが存在しない。本 Issue で `tests/collect-recovery-candidates.bats` を新規作成し、空ログ / threshold 未満 skip / 重複除外 (起票済み) / 通常検出の 4 @test を追加する。

## Changed Files

- `tests/collect-recovery-candidates.bats`: 新規作成 — 4 @test (empty log / below threshold / exclusion / normal detection) — bash 3.2+ compatible
- `docs/structure.md`: `tests/` 行を "(82 files)" → "(83 files)" に更新
- `docs/ja/structure.md`: `tests/` 行を "（82 ファイル）" → "（83 ファイル）" に更新

## Implementation Steps

1. `tests/collect-recovery-candidates.bats` を新規作成する。`setup()` で `RECOVERY_FILE="$BATS_TEST_TMPDIR/recovery.md"` を設定し、各 @test でインライン fixture を書き込む形式で以下の 4 @test を実装する (→ AC1, AC2, AC3):
   - `@test "empty log: no entries → empty output and exit 0"` — 空ファイル (`touch`) を渡し、exit 0 かつ出力が空であることを確認
   - `@test "below threshold: single entry count=1 with default threshold=3 → no output"` — 1 件のエントリを持つ fixture で `--threshold 3` を指定し、出力が空になることを確認
   - `@test "exclusion: 起票済み mark → symptom excluded from output"` — 3 件の同一 symptom-short を持つ fixture でうち 1 件に `- 起票済み #N` を付加して threshold 以上でも除外されることを確認 (count=3、threshold=1 で除外検証)
   - `@test "normal detection: count >= threshold and no exclusion → appears in output"` — 3 件の同一 symptom-short (未起票) を持つ fixture で `--threshold 3` を指定し、symptom-short と count がタブ区切りで出力されることを確認

2. `docs/structure.md`: `(82 files)` → `(83 files)` に更新 (→ SHOULD: doc sync per translation-workflow.md)

3. `docs/ja/structure.md`: `（82 ファイル）` → `（83 ファイル）` に更新 (→ SHOULD: doc/ja sync per translation-workflow.md)

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/collect-recovery-candidates.bats" --> 新規ファイルが存在する
- <!-- verify: file_contains "tests/collect-recovery-candidates.bats" "@test" --> @test が含まれている
- <!-- verify: command "bats tests/collect-recovery-candidates.bats" --> 全 bats テストが green
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI bats 全件 green

### Post-merge

- 次回 collect-recovery-candidates.sh を変更する Issue で動作 regression が test で検出されることを観察<!-- verify-type: manual -->

## Code Retrospective

### Deviations from Design
- None: Implementation followed Spec steps exactly (4 @test in inline fixture style, docs count update).

### Design Gaps/Ambiguities
- `→` in Spec @test name examples is a multibyte Unicode character; used ASCII `->` instead per tech.md bats naming rule (ASCII only). This is consistent with existing tests like `audit-recoveries.bats`.

### Rework
- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Used ASCII `->` instead of `→` in @test names per tech.md bats naming rule (multibyte chars cause 0 tests executed).
- Inline fixture style (`BATS_TEST_TMPDIR`) — no external fixture file dependencies, same pattern as `tests/get-auto-session-report.bats`.
- Threshold exclusion test uses count=3 threshold=1 to confirm filed mark overrides even a passing count.

### Deferred Items
- Pre-existing `run-code.bats` failures (tests 621, 623) for emit behavior are unrelated to this change; left for the responsible issue.

### Notes for Next Phase
- AC1-3 all PASS (verified locally). AC4 (`github_check`) pending CI after push to main.
- No implementation deviation; Spec steps match implementation exactly.
- `tests/audit-recoveries.bats` (integration coverage) remains untouched per AP2 decision.

## Consumed Comments

- saito (MEMBER, first-class) — issue retrospective: AP1/AP2/AP3 の auto-resolve 結果を記録。`file_contains "@test"` は存在確認として適切、`audit-recoveries.bats` は integration coverage として残し新規 direct unit test を作成する方針を確認 — https://github.com/saitoco/wholework/issues/735#issuecomment-4759879388

## Notes

- AP1 (verify command の数量保証): AC2 の `file_contains "@test"` は 1 件でも PASS。「4 件以上」は実装ガイダンス。AC3 の bats 実行 green で品質補完。`command "grep -c '@test'"` は safe mode で UNCERTAIN になるため不採用。
- AP2 (audit-recoveries.bats との関係): `tests/audit-recoveries.bats` は integration coverage として残す (5 @test)。`collect-recovery-candidates.bats` は Issue #736 の `audit-auto-session.bats` / `get-auto-session-report.bats` パターンと同様に dedicated direct unit test として新規作成。
- AP3 (github_check の `$(git rev-parse HEAD)` 展開): Issue #736 spec で同パターンが採用・確認済み。patch route (Size S) の `gh run list` フォームとして正しい。
- `collect-recovery-candidates.sh` はシブリングスクリプトを呼ばないため `WHOLEWORK_SCRIPT_DIR` モック不要 (ただし `SCRIPT_DIR` 変数は宣言されているので環境変数上書きには対応済み)。
- テストは `BATS_TEST_TMPDIR` を使ったインライン fixture 方式 (外部 fixture ファイルへの依存なし)。これは `tests/get-auto-session-report.bats` と同じパターン。

## Verify Retrospective

### Phase-by-Phase Review

#### verify
- pre-merge AC1-3 PASS。AC4 (CI green) は CI job in_progress のため PENDING。CI 完了後に `/verify 735` 再実行で確認可能。

### Improvement Proposals
- N/A
