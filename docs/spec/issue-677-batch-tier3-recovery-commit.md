# Issue #677: auto/batch: Tier 3 recovery 後の orchestration-recoveries.md 自動 commit を batch route で明示化

## Overview

`/auto --batch` List mode または XL route で `run-auto-sub.sh` を経由して Tier 3 recovery が発火すると、`spawn-recovery-subagent.sh` が `docs/reports/orchestration-recoveries.md` に直接 log エントリを書き込む。この書き込みは commit されず dirty 状態のまま残るため、次フェーズで `check-verify-dirty.sh` が exit 1 を返し、parent session による手動 commit が必要になっていた。

本 Issue は Candidate A（`scripts/run-auto-sub.sh` 修正）を採択し、Tier 3 recovery 成功直後に `orchestration-recoveries.md` の git add + commit + push を `run-auto-sub.sh` が担う設計に変更する。

## Changed Files

- `scripts/run-auto-sub.sh`: `run_phase_with_recovery()` 内の Tier 3 ブロックに recovery log commit ステップを追加 — bash 3.2+ compatible
- `skills/auto/SKILL.md`: Step 4a Source 2 の説明に「`run-auto-sub.sh` が Tier 3 成功後に recovery log を commit + push する」旨を明記
- `tests/run-auto-sub.bats`: Tier 3 recovery 後の git commit が呼ばれることを確認するテストを追加

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` 関数内、`spawn-recovery-subagent.sh` 成功後ブロック（`echo "${LOG_PREFIX} [recovery] tier3 sub-agent: recovered"` の直後）に以下を追加（→ AC: run-auto-sub 修正、rubric）:
   - `local _repo_root; _repo_root="$(dirname "$SCRIPT_DIR")"` を宣言
   - `git -C "$_repo_root" diff --quiet "docs/reports/orchestration-recoveries.md" 2>/dev/null` で dirty 確認
   - dirty の場合（exit 非 0）: `git -C "$_repo_root" add "docs/reports/orchestration-recoveries.md"` → `git -C "$_repo_root" commit -s -m "Record Tier 3 recovery event for issue #${issue} ${phase} phase"` → `git -C "$_repo_root" push origin HEAD`
   - commit/push 失敗時は `echo "${LOG_PREFIX} WARNING: could not commit/push recovery log; /verify may detect dirty file" >&2` を出力して続行（非致命的）
   - 成功時は `echo "${LOG_PREFIX} [recovery] recovery log committed and pushed"` を出力

2. `skills/auto/SKILL.md` Step 4a Source 2 の段落末尾（「…single-Issue parent sessions (M/L/patch).」の直後）に以下を追記（→ AC: SKILL.md grep、rubric）:
   - 「`run-auto-sub.sh` commits and pushes `docs/reports/orchestration-recoveries.md` immediately after Tier 3 success to prevent dirty-file conflicts at `/verify` invocation (see #677).」

3. `tests/run-auto-sub.bats` に Tier 3 recovery git commit テストを追加（→ テスト品質）:
   - テスト名: `"run-auto-sub: tier3 recovery: commits orchestration-recoveries.md when dirty"`
   - `spawn-recovery-subagent.sh` mock: exit 0 (Tier 3 成功)
   - `git` mock: `diff` サブコマンドで exit 1（dirty ファイル検知）; それ以外は exit 0; 全呼び出しを `$GIT_LOG` に記録
   - 検証: `status -eq 0`、`$GIT_LOG` に `commit.*Record Tier 3 recovery event` が含まれる

## Verification

### Pre-merge

- <!-- verify: grep "orchestration-recoveries.md" "skills/auto/SKILL.md" --> `skills/auto/SKILL.md` の batch route セクションまたは関連箇所で recovery log commit の責任が明示されている
- <!-- verify: rubric "skills/auto/SKILL.md または scripts/run-auto-sub.sh のいずれかで、batch route (List mode / XL route) の Tier 3 recovery 発火後に docs/reports/orchestration-recoveries.md を次フェーズ前に commit + push する責任が明示的に定義されている" --> rubric 基準を満たす
- <!-- verify: grep "Record Tier 3 recovery event" "scripts/run-auto-sub.sh" --> `scripts/run-auto-sub.sh` に Tier 3 recovery 後の recovery log commit ロジックが追加されている

### Post-merge

- 次回 `/auto --batch` 実行で Tier 3 recovery が発火した際、parent session が手動 commit せずとも verify dirty チェックが clean になることを確認

## Notes

- **Auto-resolve (非対話モード)**: 候補 A（`scripts/run-auto-sub.sh` 修正）を選択。理由: bash レベルで発生源に最も近い場所を修正でき、LLM-executed な SKILL.md 変更なしに List mode・XL route 両方をカバーできる。
- `git -C "$_repo_root"` を使用する理由: `run-auto-sub.sh` が worktree 内から呼ばれる XL 並列実行時でも、メインリポジトリ（scripts/ の親ディレクトリ）を対象に git 操作を行うため。
- `spawn-recovery-subagent.sh` の `write_recovery_entry()` は `docs/reports/orchestration-recoveries.md` が存在しない場合は skip するため、ファイル不在時は `git diff` が exit 0 を返し commit ブロックはスキップされる（非致命的）。
- commit は非致命的（失敗時は警告を出して続行）とする。push の競合は `WHOLEWORK_MAX_RECOVERY_SUBAGENTS=1` によるシリアライズで実運用上 XL 並列でも発生しない。
- `git commit -s` の DCO sign-off は実行環境の git user.name/email 設定に依存する（他フェーズと同一条件）。
- 既存の happy-path BATS テスト（Tier 3 成功時）は `git diff` mock が exit 0（clean）を返すため、commit ブロックがスキップされ影響なし。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Candidate A（`scripts/run-auto-sub.sh` 修正）を採択。Tier 3 成功直後に `git -C "$_repo_root" diff --quiet` で dirty 確認し、dirty の場合のみ commit + push を実行。
- commit/push 失敗は非致命的（警告のみ）として続行する設計を維持。
- `git -C "$_repo_root"` で worktree 外のメインリポジトリを対象にした（XL 並列実行時の worktree 内からの呼び出しを考慮）。

### Deferred Items
- Post-merge 観測 AC: 次回 `/auto --batch` 実行で Tier 3 recovery 発火時に verify dirty チェックが clean になることの確認（event=auto-run observation）。
- XL 並列（`WHOLEWORK_MAX_RECOVERY_SUBAGENTS > 1`）での push 競合リスクは現在 `cap=1` のシリアライズで回避しているが、将来的なキャップ引き上げ時には排他制御の追加を検討。

### Notes for Next Phase
- `/verify` でのチェック: Pre-merge 3AC はすべて PASS（grep × 2 + rubric）、Issue body チェックボックス更新済み。
- Post-merge AC は `verify-type: observation event=auto-run` のため通常の verify ではスキップされる。
- 既存の Tier 3 テスト（happy-path）は影響なし（git mock なしで非致命的 fallback に入るが PASS を維持）。

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- 既存の Tier 3 テスト（`run-auto-sub: phase exit nonzero + tier1+tier2 fail + tier3 spawn succeeds: recover`）では `git` がモックされておらず、BATS_TEST_TMPDIR に git リポジトリがないため `git diff` が非 0 を返し commit ブロックが実行される。commit 失敗時は警告のみ（非致命的）なので既存テストの PASS は維持されるが、副作用として stderr に git エラーメッセージが出力される。新規テストで `git` モックを追加して動作を明確に分離した。

### Rework
- None
