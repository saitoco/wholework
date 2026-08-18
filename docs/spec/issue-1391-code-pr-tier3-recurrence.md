# Issue #1391: recoveries: code-pr-tier3-recovery の再発パターンを分析し恒久対策を検討

## Overview

`code-pr-tier3-recovery` symptom が #799 クローズ (2026-06-27 22:23 UTC) 後に3件 (#1224, #995, #893) 再発した。`docs/reports/orchestration-recoveries.md` の該当エントリ (L306, L1384, L1470) を精査した結果、**単一の共通 root cause ではなく、少なくとも3つの異なる原因**に分かれることが判明した。

1. **#1224 (2026-08-07 07:41 UTC)**: diagnosis に「Five silent no-op retries wasted ~90 minutes re-running /code instead of pushing the existing work」と明記されている通り、`run-code.sh` の内蔵 auto-retry-on-fail 機構 (exec ベース、`scripts/run-code.sh` L377-414) が、worktree branch `worktree-code+issue-1224` に既にコミット済み (未 push) の実装が存在する場合でも区別できず、`/code` フェーズをフルに再実行する retry を繰り返した。**根本原因は `_completion_code_pr()` (`scripts/reconcile-phase-state.sh` L334-357) が `_completion_code_patch()` (同ファイル L212-333) に既に実装されている `worktree_commits_found` 診断シグナル (L297-311) を持たないこと** — このシグナルの欠如により、pr route の retry gate は「何も完了していない」状態と「実装済みだが push 未了」の状態を区別できず、後者でも前者と同じ exec retry を選択してしまう。
2. **#995 (2026-07-12 06:18 UTC)**: diagnosis は「bats実行待ちのwatchdog kill が繰り返され、コミット・push・PR作成の直前で毎回中断された」と記録しており、commit 自体が未実施 (`git rev-list` 上は HEAD が main と同一) である点で #1224 と異なる。bats 実行時間に起因する watchdog kill (exit 143) の反復という点で、既存の「background wait」再発系統 (#994→#1102→#1212/#1213/#1234、真因は test-runner 側の固定タイムアウト) に近い形状。
3. **#893 (2026-07-04 15:25 UTC)**: diagnosis は「/code フェーズ自身の L0 comment-consumption ログ書き込みが `docs/spec/issue-893-l3-findings-disposition-tags.md` として parent main に直接コミットされ、`check-verify-dirty` がブロックした」と記録しており、worktree-path-misuse 系統 (#882/#888 — worktree 向けの編集が parent main に landing する既知パターン) に近い形状。

3件とも exit code 1 で共通するが、これは `run-code.sh` の内蔵 auto-retry が尽きた際の終端コード (`scripts/run-code.sh` L413 `EXIT_CODE=1`) であり、根本原因の共通性を意味しない。`_completion_code_pr()` 自身のコメント (L335: 「Stage 2 recovery (push+PR creation) is delegated to #316 recovery sub-agent」) が示す通り、push+PR 実行そのものを Tier 2 で自動化しない設計は元々意図的な判断であり、本 Issue はその判断自体を覆すものではない — 対象とするのは「retry すべきでない状態で retry してしまう」という gate 側の判別不足のみである。3件は #799 が対象とした watchdog kill (exit 143) 系の直接的な再発ではない。

本 Issue では、3件のうち最も直接的な証拠 (diagnosis 内の明示的な記述) と機械的な修正可能性を備える **原因1 (#1224)** を恒久対策の対象とする。原因2・3は性質が異なり Size S の本 Issue 単体では解決しない — 詳細を Notes に記録し、再発時は別 cause slug での起票を推奨する。

## Changed Files

- `scripts/reconcile-phase-state.sh`: `_completion_code_pr()` (L334-357) に `worktree_commits_found` 診断シグナルを追加。`_completion_code_patch()` (L297-311) の既存パターンをミラー。bash 3.2+ 互換
- `modules/phase-state.md`: Field contract table の `actual.worktree_commits_found` 行 (L120) の `Required` 列を `code-pr` completion にも対応するよう拡張
- `scripts/run-code.sh`: auto-retry 判定ブロック (L384-407) に短絡分岐を追加 — `_RECONCILE_PHASE == "code-pr"` かつ reconcile 出力が `"worktree_commits_found":true` を含む場合、exec ベースの retry をスキップし即座に `EXIT_CODE=1` で終了 (Tier 1/2/3 へ早期委譲)。bash 3.2+ 互換
- `docs/tech.md`: 「code/spec-side auto-retry (silent no-op)」bullet (L132) に新しい短絡動作の説明を追記
- `tests/reconcile-phase-state.bats`: `_completion_code_pr()` の `worktree_commits_found` シグナルを検証する新規テストケースを追加 (既存の code-patch 版テスト L1462 相当をミラー)
- `tests/run-code.bats`: `run-code.sh` の新短絡分岐を検証する新規テストケースを追加 (既存 auto-retry テスト群 L738-849 と同じ形式)

## Implementation Steps

1. `scripts/reconcile-phase-state.sh` の `_completion_code_pr()` に `worktree_commits_found` 診断シグナルを追加する。`_completion_code_patch()` の該当ブロック (L306-311: `git rev-list --count "origin/main..worktree-code+issue-${ISSUE_NUMBER}"` を fail-open (`|| worktree_commit_count=0`) で実行し `actual_json` に追記) と同一パターンを踏襲する。あわせて `modules/phase-state.md` の Field contract table (`actual.worktree_commits_found` 行) の `Required` 列に「or `code-pr` completion does not find an open PR」を追記し、code-patch/code-pr 両方に対応する記述へ更新する (→ 恒久対策)
2. `scripts/run-code.sh` の auto-retry 判定ブロック (L384 の `elif echo "$_reconcile_out" | grep -q '"matches_expected":false'; then` 直後) に、既存の retry 適格性チェック (L386-388) より前に新しい分岐を追加する: `_RECONCILE_PHASE == "code-pr"` かつ `$_reconcile_out` が `"worktree_commits_found":true` を含む場合、理由を stderr に echo したうえで exec retry を行わず `EXIT_CODE=1` を設定する。既存の CODE_RETRY_COUNT 加算・exec 再起動ロジック (L388-407) はそのまま温存し、この新分岐に該当する場合のみそちらへ到達しないよう条件分岐を追加する (after 1) (→ 恒久対策)
3. `docs/tech.md` の「code/spec-side auto-retry (silent no-op)」bullet 末尾に、code-pr phase で `worktree_commits_found:true` が検出された場合は exec retry をスキップし Tier 1/2/3 へ早期委譲する旨を追記する (#1391 参照) (after 2) (→ 恒久対策)
4. `tests/reconcile-phase-state.bats` に `_completion_code_pr()` の `worktree_commits_found:true`/`false` それぞれを検証する新規 `@test` を追加し (既存 L1462 の code-patch 版と対の形式)、`tests/run-code.bats` に新短絡分岐 (retry せず exit 1) を検証する新規 `@test` を追加する。既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケースを追加したうえで両スイートが PASS すること (after 2) (→ 恒久対策、new test case requirement)
5. 3件 (#1224/#995/#893) の diagnosis 比較と root cause 判定結果を本 Spec の Overview/Notes に記録する (→ root cause 特定、AC1)

## Verification

### Pre-merge
- <!-- verify: command "bats tests/reconcile-phase-state.bats" --> `_completion_code_pr()` の `worktree_commits_found` シグナル追加を含め、既存 + 新規テストケースが PASS する
- <!-- verify: command "bats tests/run-code.bats" --> `run-code.sh` の新短絡分岐を含め、既存 + 新規テストケースが PASS する
- <!-- verify: file_contains "modules/phase-state.md" "code-pr` completion does not find an open PR" --> `actual.worktree_commits_found` 行の Required 列が code-pr completion にも言及している
- <!-- verify: file_contains "docs/tech.md" "worktree_commits_found:true" --> 「code/spec-side auto-retry (silent no-op)」bullet に code-pr 短絡動作の説明が追記されている

### Post-merge
- #1224 / #995 / #893 の3件を diagnosis 精査し、共通の root cause (exit 1 かつ worktree 残存物あり) を特定する <!-- verify-type: manual -->
- 特定した root cause に対する恒久対策 (または既知パターンとして `orchestration-fallbacks.md` への catalog 追加) が実装され、Issue #1391 作成日 (2026-08-17) 以降に `docs/reports/orchestration-recoveries.md` へ同型の `code-pr-tier3-recovery` エントリが追加されていないことを、次回 `/auto` 完了時点で `docs/reports/orchestration-recoveries.md` を grep して確認する <!-- verify-type: observation event=auto-run -->

## Notes

### 原因2・3 (#995, #893) を本 Issue の対策対象から除外した判断

Size S / SPEC_DEPTH=light の制約 (Implementation Steps ≤5) の下で、3件の診断結果は同一の `code-pr-tier3-recovery` ラベルを共有するが実体は異なる3系統であると判断した (詳細は Overview 参照)。#799 自身も同じラベル配下で「Active-implementation watchdog kill」と「Clean-slate transient hang」の2系統に分けて別々に対処した前例があり、本 Issue でも同じ方針を踏襲する。

- **#995 系統 (uncommitted diff + bats 待ち watchdog kill 反復)**: 対策には bats 実行時間そのものの短縮または watchdog タイムアウト戦略の見直しが必要と見られ、既存の「background wait」再発系統 ([[project_background_wait_recurrence]] 参照、真因は test-runner 側の固定タイムアウト) との重複調査が必要になる可能性が高い。本 Issue の Size では扱わず、再発時に独立した cause slug (例: `code-pr-uncommitted-diff-bats-kill`) で起票することを推奨する。
- **#893 系統 (comment-consumption ログの parent main 直接コミット)**: L0 comment-consumption 手続き (`modules/l0-surfaces.md`) が worktree 境界を越えて書き込まれた経路の特定が必要で、`worktree-path-misuse-parent-dirty` (#882/#888) との関係精査を要する別テーマ。本 Issue の Size では扱わず、再発時に独立した cause slug (例: `code-comment-consumption-parent-dirty`) で起票することを推奨する。

### Fail-safe critical script identification

`scripts/reconcile-phase-state.sh` は `/auto` の Tier 1 completion gate (`modules/orchestration-fallbacks.md` の Observe-Diagnose-Act パターンにおける Diagnose 相当) であり、fail-safe critical スクリプトの基準 (a) に該当する。ただし本 Issue の変更は `matches_expected` の判定ロジック自体には触れず、`_completion_code_patch()` の既存 `worktree_commits_found` フィールド (L306-311 のコメントに明記: 「Diagnostic only — does not affect `matches_expected`」) と全く同じ設計を `_completion_code_pr()` に複製するのみである。依存コマンド (`git rev-list --count`) が失敗した場合の挙動も既存パターンと同一の fail-open (`|| worktree_commit_count=0` → ブランチ不存在時は `false` 側に倒れる) を踏襲し、新たな edge case 設計は発生しない。

`scripts/run-code.sh` の新短絡分岐についても、`reconcile-phase-state.sh` の出力が空/不正な場合は `grep -q` が単純にマッチせず、既存の retry 適格性チェック側にフォールスルーする (fail-open — 短絡せず、これまで通り retry を試みる)。短絡条件を誤って満たした場合の最悪ケースは「本来 retry で解決できたはずの状態を retry せず Tier 1/2/3 に早期委譲する」ことであり、Tier 3 は3件とも100%の成功率 (Outcome: success) を記録しているため、安全側に倒れる設計である。

### New test case requirement summary (SPEC_DEPTH=light — Step 13 retrospective 省略のため本節に記録)

Implementation Step 1・2 はそれぞれ新規分岐ロジックを追加する:
- `_completion_code_pr()` への `worktree_commits_found` フィールド追加 (新規診断ロジック) → `tests/reconcile-phase-state.bats` に true/false 両ケースの新規 `@test` が必要
- `run-code.sh` の auto-retry 判定への短絡分岐追加 (新規分岐ロジック) → `tests/run-code.bats` に「code-pr + worktree_commits_found:true で retry せず exit 1」を検証する新規 `@test` が必要

いずれも Implementation Step 4 および Pre-merge Verification の `command` 検証で担保する。

## Consumed Comments

| Login | Association | Trust tier | Intent | URL |
|-------|-------------|-----------|--------|-----|
| saito | MEMBER | first-class | `/issue --non-interactive` の Issue Retrospective。AC2 を `verify-type: manual` から `verify-type: observation event=auto-run` に再分類したことを報告 (`modules/verify-classifier.md` の Evidence Collection Patterns に合致すると判断)。spec phase 時点で Issue body は既にこの再分類を反映済みであることを確認済み | https://github.com/saitoco/wholework/issues/1391#issuecomment-5326725458 |
