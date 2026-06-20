# Issue #727: recoveries: investigate and resolve code-patch-tier3-recovery recurring pattern

## Overview

`docs/reports/orchestration-recoveries.md` には `code-patch-tier3-recovery` エントリが 3 件記録されており、設定されたしきい値 3 に達したため `recoveries-auto-fire` が本 Issue を自動起票した。

3 件は 2 つの原因グループに分類される:

**原因グループ 1 — サイレント no-op (Issues #658, #489)**:
- `run-code.sh` が patch route で Claude を起動し、Claude が exit 0 で終了するが `origin/main` にコミットが存在しない
- `run-code.sh` が `reconcile-phase-state.sh code-patch $N --check-completion` でコミット不在を検出し exit 1
- Tier 1 (reconcile): `matches_expected:false`
- Tier 2 (`apply-fallback.sh`): `dco-signoff-missing-autofix` のみ実装済みで、このパターンを処理するハンドラが存在しない
- 結果: **Tier 3 (`spawn-recovery-subagent.sh`) に毎回エスカレーション** — `claude -p` を起動して `action=retry` を返すが、reconcile で `commits_found:false` が確認済みならば retry は常に安全であり Tier 3 呼び出しは不要なコストとなる

根本原因: `code-patch-silent-no-op` パターンが `apply-fallback.sh` の Tier 2 カタログに未登録のため、本来 Tier 2 で安全に処理できる retry を Tier 3 に委譲している。

**原因グループ 2 — Watchdog Kill (Issue #486)**:
- `run-code.sh` が watchdog タイムアウト 1800s (30 分) 後に SIGTERM で終了 (exit 143)
- コミットなし → Tier 1 失敗 → Tier 2 ハンドラなし → Tier 3 に auto-retry
- Tier 3 の診断は `action=retry` (clean state 確認済みのため安全)

根本原因: code-patch の watchdog タイムアウト (デフォルト 1800s) が一部実装の実行時間に対して短く、Tier 2 に watchdog kill ハンドラが未実装のため Tier 3 に到達する。本グループは今 Issue では文書化のみとし、Tier 2 への昇格は follow-up で検討。

## Changed Files

- `docs/reports/orchestration-recoveries.md`: 3 件の `code-patch-tier3-recovery` エントリの `Improvement Candidate` を `未起票` → `起票済み #727` に更新
- `modules/orchestration-fallbacks.md`: `code-patch-silent-no-op` エントリを追加 — bash 3.2+ compatible な注記は不要 (Markdown ドキュメント)
- `scripts/apply-fallback.sh`: `detect_symptom_anchor()` に `code-patch-silent-no-op` パターンを追加し、ハンドラ `apply_code_patch_silent_no_op_retry()` を実装する — bash 3.2+ compatible
- `tests/apply-fallback.bats`: `code-patch-silent-no-op` ハンドラのテストを 2 件追加

## Implementation Steps

1. `docs/reports/orchestration-recoveries.md` の 3 件の `code-patch-tier3-recovery` エントリで `- 未起票` を `- 起票済み #727` に変更する (→ AC3)

2. `modules/orchestration-fallbacks.md` に `code-patch-silent-no-op` エントリを追加する (→ AC1, AC2 の文書化部分):
   - Symptom: `run-code.sh` exits 1; log contains `"silent no-op"` warning; reconcile confirms `commits_found:false`
   - Applicable Phases: code (patch route)
   - Fallback Steps: retry `run-code.sh <issue> --patch` once; if second run also exits 1 → escalate to Tier 3
   - Rationale: first observed in Issues #658 and #489; cataloged in Issue #727

3. `scripts/apply-fallback.sh` に以下を追加する (→ AC2, AC4):
   - `detect_symptom_anchor()` 内: `[[ "$PHASE" == "code-patch" ]] && grep -q "silent no-op" "$log"` の条件で `echo "code-patch-silent-no-op"` を返すブランチを追加 (`# See modules/orchestration-fallbacks.md#code-patch-silent-no-op` コメント付き)
   - `apply_code_patch_silent_no_op_retry()` 関数を追加: `"$SCRIPT_DIR/run-code.sh" "$ISSUE" --patch` を実行
   - `case "$symptom_anchor"` に `code-patch-silent-no-op)` ブランチを追加

4. `tests/apply-fallback.bats` に 2 件のテストを追加する:
   - `code-patch-silent-no-op pattern triggers run-code.sh retry`: log に `"silent no-op"` がある場合に `run-code.sh $ISSUE --patch` が呼ばれることを確認
   - `code-patch-silent-no-op pattern does not fire for non-code-patch phase`: 同じログで phase が `verify` の場合は exit 1 (Tier 3 エスカレーション) になることを確認

## Verification

### Pre-merge

- <!-- verify: rubric "Spec or Issue #727 comments contain an identified root cause for both the silent no-op cause group (Issues #658, #489) and the watchdog kill cause group (Issue #486)" --> 各原因グループの根本原因が特定・文書化されている
- <!-- verify: rubric "a code change, script update, or documented mitigation plan addressing at least one code-patch-tier3-recovery cause group is present in the implementing PR or Spec" --> 少なくとも 1 つの原因グループに対する修正または緩和策が実装されている
- <!-- verify: grep "起票済み #727" "docs/reports/orchestration-recoveries.md" --> <!-- verify: rubric "all 3 code-patch-tier3-recovery entries in docs/reports/orchestration-recoveries.md have Improvement Candidate set to 起票済み #727" --> 既存 3 件の `code-patch-tier3-recovery` エントリの `Improvement Candidate` が `起票済み #727` に更新されている
- <!-- verify: file_contains "scripts/apply-fallback.sh" "code-patch-silent-no-op" --> `apply-fallback.sh` に `code-patch-silent-no-op` ハンドラが追加されている

### Post-merge

- 2026-06-21 以降に `code-patch-tier3-recovery` かつ `Improvement Candidate: 未起票` のエントリが `docs/reports/orchestration-recoveries.md` に現れないことを確認 <!-- verify-type: opportunistic -->

## Notes

- `write_recovery_entry()` in `scripts/spawn-recovery-subagent.sh` は常に `- 未起票` を書き込む仕様のため、今後 Tier 3 経由で記録されたエントリも `未起票` のままになる。Tier 2 (`apply-fallback.sh`) で `code-patch-silent-no-op` を処理できるようになれば、このパターンが Tier 3 に到達しなくなり、新規の `未起票` エントリは発生しなくなる。`write_recovery_entry()` 自体の改修 (起票済み番号を受け取るパラメータ追加等) は本 Issue のスコープ外。
- `detect_symptom_anchor()` での pattern マッチは `grep -q "silent no-op" "$log"` の fixed-string 検索で十分。`run-code.sh` が出力する警告文は `"Warning: claude exited 0 but code-patch phase did not complete (silent no-op)."` であり、文字列 `"silent no-op"` は安定した識別子となる。
- watchdog kill (原因グループ 2) の Tier 2 ハンドラ追加は本 Issue のスコープ外。文書化 (`orchestration-fallbacks.md` エントリ) のみで AC2 を充足する (rubric は "documented mitigation plan" も対象)。

## Consumed Comments

- saito (MEMBER, first-class) — Issue Retrospective + Autonomous Auto-Resolve Log: AC 分割、verify command 設計の決定記録。spec フェーズへの引継ぎ情報として利用。

## Code Retrospective

### Deviations from Design
- `docs/structure.md` と `docs/ja/structure.md` の `apply-fallback.sh` 記述更新を追加実装した。Spec の Changed Files には含まれていなかったが、doc-checker が "(initial full-impl: dco-signoff-missing-autofix)" 記述を stale と検出したため更新した。

### Design Gaps/Ambiguities
- None

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `detect_symptom_anchor()` でのパターンマッチは `grep -q "silent no-op"` を使用した。Spec Notes の指示通り、`run-code.sh` が出力する `"silent no-op"` は安定した識別子であり、regex なしで十分。
- watchdog kill (原因グループ 2) の Tier 2 ハンドラは Spec の方針通りスコープ外とし、文書化のみで AC2 を充足した。
- `apply_code_patch_silent_no_op_retry()` では `"$SCRIPT_DIR/run-code.sh" "$ISSUE" --patch` を呼び出す。`SCRIPT_DIR` は `WHOLEWORK_SCRIPT_DIR` 環境変数で上書き可能なため BATS テストで hermetic な実行が確保できる。

### Deferred Items
- watchdog kill (原因グループ 2) の Tier 2 ハンドラ (`code-patch-watchdog-kill-retry`) は follow-up Issue で検討予定。
- `write_recovery_entry()` が常に `- 未起票` を書き込む仕様の改修は本 Issue のスコープ外。

### Notes for Next Phase
- bats tests 全 9 件 PASS、forbidden expressions チェック PASS、validate-skill-syntax.py エラーなし (既存警告 1 件のみ)。
- PR #741 が作成済み。CI が通過した後 `/merge 741` を実行できる状態。
- AC1/AC2 は `rubric` 検証。`rubric` は PR ブランチのファイル内容を参照するため、review フェーズで正確に評価される。
