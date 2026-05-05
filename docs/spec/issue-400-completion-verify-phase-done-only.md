# Issue #400: reconcile: verify completion 判定で phase/done を必須化

## Overview

`scripts/reconcile-phase-state.sh` の `_completion_verify` は、現在 `phase/(verify|done)` パターンで OPEN Issue の成功判定を行っている。`phase/verify` は verify 実行中を示すラベルであり、verify が PASS して完了した状態は `phase/done` のみ。このバグにより `/auto` の Tier 1 reconcile が `phase/verify` 状態でも `matches_expected: true` を返し、verify 未完了のまま成功扱いされるリスクがある（Issue #393 retrospective で観測）。成功判定を `phase/done` のみに限定して誤判定を防ぐ。

## Reproduction Steps

1. Issue を `phase/verify` 状態（OPEN、`phase/verify` ラベル付き）のまま停止させる
2. `bash scripts/reconcile-phase-state.sh verify <issue-number> --check-completion --strict` を実行
3. `"matches_expected":true` が返る（期待: `false`）

## Root Cause

`_completion_verify` の条件（line 271）が `grep -qE '^phase/(verify|done)$'` で `phase/verify` を誤って成功状態として扱っている。`phase/verify` は「verify フェーズが開始されたが未完了」を示すラベルであり、成功（全受入条件 PASS）は `phase/done` への遷移後にのみ確定する。

## Changed Files

- `scripts/reconcile-phase-state.sh`: `_completion_verify` の grep パターンを `phase/(verify|done)` から `phase/done` のみに変更 — bash 3.2+ 互換
- `tests/reconcile-phase-state.bats`: テスト `"verify completion: issue OPEN + phase/verify label -> matches_expected true"` を `-> matches_expected false` に変更し、ステータスおよびアサーションを更新
- `modules/phase-state.md`: verify フェーズの Success Signature を `phase/(verify\|done)` から `phase/done` のみに更新（SSoT 同期）

## Implementation Steps

1. `scripts/reconcile-phase-state.sh` line 271-274 を編集:
   - `grep -qE '^phase/(verify|done)$'` → `grep -q '^phase/done$'`
   - line 272 メッセージ `"has phase/verify or phase/done label"` → `"has phase/done label"`
   - line 274 メッセージ `"with no phase/verify or phase/done label"` → `"with no phase/done label"`
   (→ 受入条件 1)

2. `tests/reconcile-phase-state.bats` line 380-396 を編集:
   - テスト名 `"verify completion: issue OPEN + phase/verify label -> matches_expected true"` → `"verify completion: issue OPEN + phase/verify label -> matches_expected false"`
   - `[ "$status" -eq 0 ]` → `[ "$status" -eq 1 ]`
   - `[[ "$output" == *'"matches_expected":true'* ]]` → `[[ "$output" == *'"matches_expected":false'* ]]`
   (→ 受入条件 2, 3)

3. `modules/phase-state.md` line 42 の Phase Table を編集:
   - Success Signature 列: `Issue is CLOSED or has \`phase/(verify\|done)\` label` → `Issue is CLOSED or has \`phase/done\` label`
   (→ SSoT 同期)

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/reconcile-phase-state.sh" "phase/(verify|done)" --> `scripts/reconcile-phase-state.sh` の `_completion_verify` で `phase/verify` を許容する旧パターン `phase/(verify|done)` が削除されている
- <!-- verify: file_not_contains "tests/reconcile-phase-state.bats" "phase/verify label -> matches_expected true" --> `tests/reconcile-phase-state.bats` の「`phase/verify` → `matches_expected true`」を主張する旧テストが削除または変更されている
- <!-- verify: grep "phase/verify.*false" "tests/reconcile-phase-state.bats" --> `tests/reconcile-phase-state.bats` に「`phase/verify` 状態では `matches_expected: false` を返す」テストが追加されている
- <!-- verify: file_not_contains "modules/phase-state.md" "phase/(verify" --> `modules/phase-state.md` の verify 成功署名から `phase/(verify` が削除され SSoT が更新されている

### Post-merge

- Issue #393 と同様のシナリオ（verify が phase/done に到達せず phase/verify で停止）で、reconcile が `matches_expected:false` を返すことを確認

## Notes

- Step 3 の `modules/phase-state.md` 更新はイシュー本文の受入条件には含まれていないが、同ファイルが `reconcile-phase-state.sh` の成功署名の SSoT であるため、スクリプト側の変更と整合させる必要がある。Spec に追加の verify コマンドを設けた（Issue 本文は 3 件、Spec は 4 件）。
- `scripts/reconcile-phase-state.sh` line 404-407 の `_precondition_verify` が `phase/verify` を参照しているのは「verify フェーズ開始条件の確認」であり、今回の修正対象（completion check）とは別。変更不要。
