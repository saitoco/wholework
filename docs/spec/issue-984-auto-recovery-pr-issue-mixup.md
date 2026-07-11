# Issue #984: run-auto-sub: recovery 記録の PR番号/Issue番号 混同を修正 (review/merge フェーズ)

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 2026-07-11T16:04:37Z
  - 要旨: `/issue 984 --non-interactive` の Issue Retrospective (Auto-Resolve Log)。AC1 の verify command を実装手段非依存の outcome ベース表現に書き換えた理由、`run-auto-sub.sh` 調査で判明した `_EXTRA_SELF_ISSUE` 再利用方針を Purpose に追記した経緯、Manual recovery をスコープ外と明記した理由を記録。Issue 本文の Purpose / スコープ外の明記と同内容。
  - URL: https://github.com/saitoco/wholework/issues/984#issuecomment-4947428573

## Overview

`run-auto-sub.sh` の Tier 2/3 recovery (自動発火経路) が `docs/reports/orchestration-recoveries.md` および Spec `## Auto Retrospective` に書き込む際、review/merge phase では issue 番号ではなく **PR 番号**を記録してしまうバグを修正する。

Issue 本文の調査メモの通り、`run_phase_with_recovery()` の呼び出し元 (review/merge 呼び出し箇所 4 か所) は既に `_EXTRA_SELF_ISSUE="$SUB_NUMBER"` で実 Issue 番号を渡しており (#974 で導入)、関数冒頭では `EMIT_ISSUE_NUMBER` としてこれを正しく解決済み (#987 で `emit_event()` 系イベントに配線済み)。今回のバグ箇所 (`_write_wrapper_retry_recovery` / `_write_tier2_recovery_to_spec` / Tier 3 コミットメッセージ / `_write_tier3_recovery_to_spec` / `spawn-recovery-subagent.sh` の記録処理) はこの `EMIT_ISSUE_NUMBER` を参照せず生の `$issue` (PR 番号) を使っていたことが根本原因であり、新規 GitHub API 呼び出しなしに `EMIT_ISSUE_NUMBER` へ配線し直すだけで修正できる。

## Reproduction Steps

1. Size M または L の Issue を `/auto` (内部的には `run-auto-sub.sh`) で PR route 実行する
2. code-pr phase 完了後、review phase (`run_phase_with_recovery "review" "$PR_NUMBER" ...`、`_EXTRA_SELF_ISSUE="$SUB_NUMBER"` 付き) が呼ばれる (`scripts/run-auto-sub.sh:717,720,787,790`)
3. `run-review.sh` (または `run-merge.sh`) が非ゼロ終了し、Tier 1 (reconciler) が回復と判定できず、Tier 2 (`apply-fallback.sh`) または Tier 3 (`spawn-recovery-subagent.sh`) recovery が発火・成功する
4. 記録される内容を確認すると:
   - `_write_tier2_recovery_to_spec` / `_write_tier3_recovery_to_spec` が `docs/spec/issue-${PR番号}-*.md` という誤ったファイル (存在しなければ新規作成) に `## Auto Retrospective` を書き込む
   - `docs/reports/orchestration-recoveries.md` の該当エントリに `Issue #<PR番号>` と誤記録される
   - 実例: Issue #970 の `/auto --batch` 実行 (2026-07-10 18:09 UTC) で PR #983 の review phase Tier 3 recovery が `docs/spec/issue-983-recovery.md` と `orchestration-recoveries.md` の「Issue #983」に誤記録された (verify フェーズで是正転記・削除済み: commit `25d693bb`)

## Root Cause

`scripts/run-auto-sub.sh` の `run_phase_with_recovery(phase, issue, runner_script, ...)` は、review/merge phase 呼び出し時に第 2 引数 `issue` として `$PR_NUMBER` を受け取る。関数冒頭 (`run-auto-sub.sh:430-436`) では `_EXTRA_SELF_ISSUE` (呼び出し元が渡す実 Issue 番号) の有無で `EMIT_ISSUE_NUMBER` を正しく解決しており、これは #987 で `emit_event()` 系イベント (`phase_start`/`phase_complete`/`concurrent_commit_detected` 等、`.tmp/auto-events.jsonl` 行き) に既に配線済みである。

しかし、以下の recovery **記録**処理 (`docs/reports/orchestration-recoveries.md` / Spec `## Auto Retrospective` 行き。`emit_event()` を経由しない別経路) は `EMIT_ISSUE_NUMBER` を参照せず、関数ローカル変数の生の `$issue` (review/merge phase では PR 番号) をそのまま使っている:

1. `_write_wrapper_retry_recovery "$issue" "$phase" "$exit_code"` (`run-auto-sub.sh:457` — `_RETRY_ON_KILL_FIRED=true` 時。Issue 本文の AC1 括弧書きには列挙されていないが、同一バグパターンかつ Purpose が挙げる書き込み先 (`orchestration-recoveries.md`、コミットメッセージ) に完全一致するため、コードベース調査で追加検出し本 Spec のスコープに含める — 詳細は Notes 参照)
2. `_write_tier2_recovery_to_spec "$issue" "$_fallback_meta_file"` (`run-auto-sub.sh:553` — Tier 2 成功時)
3. Tier 3 の `orchestration-recoveries.md` コミットメッセージ `"Record Tier 3 recovery event for issue #${issue} ${phase} phase"` (`run-auto-sub.sh:568`)
4. `_write_tier3_recovery_to_spec "$issue" "$phase" "$exit_code"` (`run-auto-sub.sh:575`)
5. `spawn-recovery-subagent.sh` の `write_recovery_entry()` が `docs/reports/orchestration-recoveries.md` に書き込む `Issue #{issue}` 行 (`spawn-recovery-subagent.sh:230,252` — `WRE_ISSUE="$ISSUE"` 経由。`$ISSUE` は同スクリプトの第 2 位置引数で、`reconcile-phase-state.sh` 呼び出しやリトライ実行 (`run-${PHASE}.sh "$ISSUE"`) にも使われる実操作用の値のため、単純な置き換えは不可 — Notes 参照)

`_write_tier2_recovery_to_spec` / `_write_tier3_recovery_to_spec` はいずれも `docs/spec/issue-${issue}-*.md` をファイル名検索・新規作成に使うため (`run-auto-sub.sh:245,284`)、`$issue` が PR 番号のままだと存在しない Issue 用の誤設置ファイルを作ってしまう。

## Changed Files

- `scripts/run-auto-sub.sh`: `run_phase_with_recovery()` 内の 4 箇所の recovery 記録呼び出し引数を `$EMIT_ISSUE_NUMBER` に変更し、`spawn-recovery-subagent.sh` 呼び出しに `--record-issue "$EMIT_ISSUE_NUMBER"` を追加 — bash 3.2+ compatible (既存の `if`/`export` パターンのみ、新規 bashism なし)
- `scripts/spawn-recovery-subagent.sh`: `--record-issue` オプション引数を追加し、`write_recovery_entry()` の `WRE_ISSUE` をこの値で上書き可能にする — bash 3.2+ compatible (既存の `case`/`while` オプション解析パターンを踏襲)
- `tests/run-auto-sub.bats`: review/merge phase (Size M デフォルトフィクスチャ: `SUB_NUMBER=42`, `PR_NUMBER=99`) で Tier 2 / Tier 3 recovery が発火した際、Spec ファイル名・`orchestration-recoveries.md` コミットメッセージが Issue 番号 (42) を参照し PR 番号 (99) を参照しないことを検証する regression テストを追加
- `tests/spawn-recovery-subagent.bats`: `--record-issue` が `write_recovery_entry()` の記録内容のみを上書きし、リトライ実行や `reconcile-phase-state.sh` 呼び出しに渡る位置引数 `<issue>` には影響しないことを検証する regression テストを追加
- `docs/tech.md` / `docs/workflow.md` / `docs/structure.md` / `docs/product.md` (および `docs/ja/` 対応ファイル): [Steering Docs sync candidate] `run-auto-sub.sh` / `spawn-recovery-subagent.sh` への言及あり (grep 済み)。いずれもアーキテクチャ・役割概要レベルの記述で、記録先の Issue 番号解決という本 Issue の変更内容には踏み込んでいないため、調査時点では更新不要と判断 (Notes 参照)。`/code` フェーズで最終差分に対し再確認すること

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` 内、4 箇所の recovery 記録呼び出しの第 1 引数 (`$issue`) を `$EMIT_ISSUE_NUMBER` に置き換える: `_write_wrapper_retry_recovery` 呼び出し (`_RETRY_ON_KILL_FIRED` ブロック内、L457 付近)、Tier 2 の `_write_tier2_recovery_to_spec` 呼び出し (L553 付近)、Tier 3 の `orchestration-recoveries.md` コミットメッセージ文字列内の `#${issue}` (L568 付近)、`_write_tier3_recovery_to_spec` 呼び出し (L575 付近)。あわせて `spawn-recovery-subagent.sh` 呼び出し (L563 付近、`"$SCRIPT_DIR/spawn-recovery-subagent.sh" "$phase" "$issue" --log "$log_file" --exit-code "$exit_code"`) の末尾に `--record-issue "$EMIT_ISSUE_NUMBER"` を追加する。既存の第 2 位置引数 `$issue` (PR 番号) 自体は変更しない (→ acceptance criteria A)
2. `scripts/spawn-recovery-subagent.sh` の引数解析部に `--record-issue` オプションを追加する: `LOG_FILE=""` / `EXIT_CODE_PARAM="unknown"` の初期化 (L20-21 付近) に並べて `RECORD_ISSUE="$ISSUE"` を初期化し、`while [[ $# -gt 0 ]]; do case "$1" in` (L23 付近) に `--record-issue) RECORD_ISSUE="${2:-$ISSUE}"; shift 2 ;;` を追加する。`write_recovery_entry()` 内の `WRE_ISSUE="$ISSUE"` (L230 付近) を `WRE_ISSUE="$RECORD_ISSUE"` に変更する。`reconcile-phase-state.sh` 呼び出し・リトライ実行 (`run-${PHASE}.sh "$ISSUE"` 等)・`INPUT_JSON` の `issue` フィールドは `$ISSUE` のまま変更しない (after 1) (→ acceptance criteria A)
3. `tests/run-auto-sub.bats` に、既存の Size M デフォルトフィクスチャ (`setup()` の `SUB_NUMBER=42` 相当の `bash "$SCRIPT" 42`、`gh pr list` モックが返す `PR_NUMBER=99`) を使い、`run-review.sh` を非ゼロ終了させて Tier 2 recovery (mock `apply-fallback.sh` exit 0) と Tier 3 recovery (mock `spawn-recovery-subagent.sh` exit 0) をそれぞれ発火させる regression テストを追加する。`docs/spec/issue-42-*.md` (`issue-99-*.md` ではない) に `## Auto Retrospective` が書き込まれること、および git commit ログが `#42` を参照し `#99` を参照しないことを、既存の「tier2/tier3 recovery: writes Auto Retrospective to spec file」テスト (L1017, L1074 付近) と「review/merge phase events emit issue=<real Issue number> and pr=<PR number> (issue #987)」テスト (L992 付近) のモックパターンを踏襲して検証する (after 1, 2) (→ acceptance criteria B)
4. `tests/spawn-recovery-subagent.bats` に、位置引数 `<issue>` に `99`、`--record-issue` に `42` を渡して呼び出す regression テストを追加する。`docs/reports/orchestration-recoveries.md` 相当のフィクスチャファイル (`<!-- Log entries appear below, newest first. -->` マーカーを含む) を用意し、action=retry のリトライ実行ログには `99` が渡ること (リトライ対象は不変)、書き込まれた recovery エントリには `Issue #42` が記録されること (`Issue #99` ではないこと) を検証する (after 2) (→ acceptance criteria B)
5. Changed Files に挙げた Steering Docs sync candidate 4 ファイル (+ `docs/ja/` 対応ファイル) を確認し、本 Issue の変更 (記録先 Issue 番号解決) を反映する記述があれば追記する。調査時点ではアーキテクチャ概要レベルの記述のみで対象箇所なしと判断済みのため、通常は変更なしで完了する想定 (after 1, 2) (→ SHOULD: ドキュメント完全性)

## Verification

### Pre-merge
- <!-- verify: rubric "run-auto-sub.sh の recovery 記録経路 (_write_tier2_recovery_to_spec / _write_tier3_recovery_to_spec の呼び出し引数、Tier 3 の orchestration-recoveries.md コミットメッセージ、spawn-recovery-subagent.sh への issue 引数) が、review/merge phase では PR 番号ではなく本来の Issue 番号を参照するよう修正されている (実装手段は問わない)" --> recovery 記録が review/merge phase でも正しい Issue 番号を使用する
- <!-- verify: rubric "tests/ 配下に、review または merge phase の recovery 記録が PR 番号ではなく Issue 番号で Spec ファイル名と recoveries log エントリを生成することを検証するテストが存在する" --> PR番号/Issue番号 解決の regression テストが追加されている

### Post-merge
- 次回 review/merge phase で Tier 2/3 recovery が発火した際、記録が正しい Issue 番号で作成されることを観察 (`<!-- verify-type: observation event=auto-run -->` — `auto-run` イベント発火時に `<!-- verify: rubric "直近の /auto 実行で review または merge phase の Tier 2/3 recovery (または wrapper-retry-on-kill recovery) が発火した場合、docs/reports/orchestration-recoveries.md の該当エントリおよび対象 Issue の Spec `## Auto Retrospective` が、PR 番号ではなく本来の Issue 番号で記録されている (該当する recovery 発火が観測されない場合は対象外として扱う)" -->` で再評価)

## Notes

- **`_write_wrapper_retry_recovery` をスコープに追加した判断**: Issue 本文 AC1 の括弧書きは `_write_tier2_recovery_to_spec` / `_write_tier3_recovery_to_spec` / Tier 3 コミットメッセージ / `spawn-recovery-subagent.sh` の 4 箇所のみを列挙しているが、コードベース調査で `_write_wrapper_retry_recovery` (`_RETRY_ON_KILL_FIRED=true` 時に発火する第 5 の recovery 記録経路) も同一の `$issue` 直接参照バグを持つことを確認した。Purpose が定義する書き込み先 (「orchestration-recoveries.md 書き込み — コミットメッセージを含む」) に完全に一致し、「実装手段は問わない」という AC1 の書き方とも矛盾しないため、AC 文言・Issue 本文は変更せず実装のみ対象に含めた。この判断は SPEC_DEPTH=light の「conflict detection は Notes 記載のみ (ユーザー確認不要)」の扱いに準じる。
- **`spawn-recovery-subagent.sh` の issue 引数を新設フラグで分離した判断**: AC1 は「spawn-recovery-subagent.sh への issue 引数」の修正を求めるが、既存の位置引数 `<issue>` は `reconcile-phase-state.sh` の completion check とリトライ実行 (`run-${PHASE}.sh "$ISSUE"`) の対象特定に使われており、review/merge phase では PR 番号でなければ機能しない (Issue 番号に置き換えると誤った PR/Issue を操作してしまう)。そのため既存引数はそのまま残し、記録専用の `--record-issue` を新設する設計とした。これは #987 が確立した `EMIT_ISSUE_NUMBER`/`EMIT_PR_NUMBER` 分離パターン (記録用の値と操作対象を独立させる) と同型であり、AC1 の「実装手段は問わない」「正しい Issue 番号を参照する」という意図 (操作対象の変更ではなく記録の正しさ) を満たす。
- **`log_file`/`_token_usage_file` の一時ファイル名は対象外**: `run_phase_with_recovery()` 内の `.tmp/wrapper-out-${issue}-${phase}.log` (L428 付近) と `.tmp/token-usage-${issue}.json` (L463 付近) は `$issue` (review/merge phase では PR 番号) をそのまま使うが、これらは同一プロセス内で完結する一時ファイル名であり (`run_with_retry_on_kill "$runner_script" "$issue" "$@"` で子スクリプトに渡す引数も同じ PR 番号のまま不変)、GitHub や Spec に永続化される「記録」ではないため本 Issue のスコープ外とした。
- **#974 / #987 は着地済み**: 両 Issue とも現在 CLOSED (2026-07-12 時点で確認)。#974 は `_EXTRA_SELF_ISSUE` 伝搬パターンと `concurrent_commit_detected` 自己除外を導入、#987 はそのパターンを `EMIT_ISSUE_NUMBER`/`EMIT_PR_NUMBER` として `emit_event()` 系イベント (`.tmp/auto-events.jsonl` 行き) に配線済み。本 Issue はそれらとは別経路の `docs/reports/orchestration-recoveries.md` / Spec `## Auto Retrospective` 書き込みのみを対象とし、重複実装は発生しない。
- **post-merge observation AC への rubric 付与 (`/spec` Step 10 自動対応)**: 元の post-merge AC は `<!-- verify-type: observation event=auto-run -->` タグのみで、観測イベントと期待される出力構造の分離が prose 内に留まっていた。#987 と同じ Option B (同一行への rubric verify command 付与) を採用し、Issue 本文を更新済み。Spec の Post-merge Verification には更新後の内容を反映した。

## Auto Retrospective
### Orchestration Anomalies
- **[json-mode-silent-hang]** Tier 2 fallback applied: phase=`code-pr`, action=run-code.sh-pr-retry, result=recovered.

### Improvement Proposals
- N/A (resolved by Tier 2 fallback catalog)

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜4 は Spec 記載の変更箇所・行番号・引数名の通りに実装完了。Steering Docs sync candidate (Step 5) も Spec の事前調査 (更新不要) を再確認した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 5 箇所の recovery 記録呼び出し (`_write_wrapper_retry_recovery` / `_write_tier2_recovery_to_spec` / Tier 3 コミットメッセージ / `_write_tier3_recovery_to_spec` / `spawn-recovery-subagent.sh` 呼び出し) を Spec の指示通り `$EMIT_ISSUE_NUMBER` に置き換えた
- `spawn-recovery-subagent.sh` に `--record-issue` を新設し、既存の位置引数 `<issue>` (reconcile-phase-state.sh / リトライ実行の対象特定) はそのまま維持した (記録用の値と操作対象の分離)
- regression テストは `tests/run-auto-sub.bats` に review phase での Tier2/Tier3 発火テストを 2 件、`tests/spawn-recovery-subagent.bats` に `--record-issue` の分離を検証するテストを 1 件追加した

### Deferred Items
- Post-merge の observation AC (次回 review/merge phase での Tier 2/3 recovery 発火時の実記録確認) は本 PR merge 後の `/verify` フェーズに委譲

### Notes for Next Phase
- `bats tests/` フルスイート 1135 件 PASS 済み (behavioral change detection によりフルスイート実行が必須と判定されたため)
- Steering Docs (`docs/tech.md` / `docs/structure.md` / `docs/product.md`) は既存記述がアーキテクチャ概要レベルに留まり、本 Issue の変更 (記録先 Issue 番号解決) に踏み込んでいないため更新不要と判断 (Spec Notes の事前判断を再確認済み)
