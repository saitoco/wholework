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
- <!-- verify: file_not_contains "tests/reconcile-phase-state.bats" "completion: issue OPEN + phase/verify label -> matches_expected true" --> `tests/reconcile-phase-state.bats` の「`phase/verify` → `matches_expected true`」を主張する旧テストが削除または変更されている
- <!-- verify: grep "phase/verify.*false" "tests/reconcile-phase-state.bats" --> `tests/reconcile-phase-state.bats` に「`phase/verify` 状態では `matches_expected: false` を返す」テストが追加されている
- <!-- verify: file_not_contains "modules/phase-state.md" "phase/(verify" --> `modules/phase-state.md` の verify 成功署名から `phase/(verify` が削除され SSoT が更新されている

### Post-merge

- Issue #393 と同様のシナリオ（verify が phase/done に到達せず phase/verify で停止）で、reconcile が `matches_expected:false` を返すことを確認

## Notes

- Step 3 の `modules/phase-state.md` 更新はイシュー本文の受入条件には含まれていないが、同ファイルが `reconcile-phase-state.sh` の成功署名の SSoT であるため、スクリプト側の変更と整合させる必要がある。Spec に追加の verify コマンドを設けた（Issue 本文は 3 件、Spec は 4 件）。
- `scripts/reconcile-phase-state.sh` line 404-407 の `_precondition_verify` が `phase/verify` を参照しているのは「verify フェーズ開始条件の確認」であり、今回の修正対象（completion check）とは別。変更不要。

## Code Retrospective

### Deviations from Design

- N/A（設計どおりに実装）

### Design Gaps/Ambiguities

- AC2 の verify command `file_not_contains "tests/reconcile-phase-state.bats" "phase/verify label -> matches_expected true"` が miscalibrated であることを実装中に発見。`"phase/verify label -> matches_expected true"` は precondition テスト (line 635: `"verify precondition: issue has phase/verify label -> matches_expected true"`) にもマッチするため FAIL となる。`"completion: issue OPEN + phase/verify label -> matches_expected true"` に修正して Issue body と Spec の両方を更新した。

### Rework

- N/A

## review retrospective

### Spec vs. Implementation Divergence Patterns

Nothing to note. 実装は Spec と完全に一致しており、4ファイルすべての変更が設計書の記述と対応している。

### Recurring Issues

Nothing to note. 本 PR は単一の grep パターン修正とそのテスト・ドキュメント更新のみで、複数の同種 issue は発生していない。

### Acceptance Criteria Verification Difficulty

Nothing to note. 4件の verify command（file_not_contains×3、grep×1）はすべて自動判定可能で UNCERTAIN なし。Forbidden Expressions check CI の FAILURE は PR #413 とは無関係の既存ファイル (`docs/spec/issue-401-detect-dirty-working-tree.md`) 由来であり、本 PR の受入条件検証には影響なし。別 Issue での対応が必要（Issue #401 コンテキストで既にトラッキング済み）。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue body の AC2 verify command が miscalibrated だったことを実装中に発見し、Code Retrospective に記録した上で Issue body と Spec を更新した。verify command の精度検証を Spec 作成時に行う慣行を徹底することで、実装中の修正コストを削減できる。

#### design
- 実装は Spec と完全に一致。Spec に `modules/phase-state.md` の SSoT 同期（受入条件に含まれない追加変更）を Notes セクションで明記しており、意図が明確に記録されている。

#### code
- リワークなし。AC2 の verify command 修正は実装完了前に対処済み。`git log --oneline` でもフィックスアップパターンは見られない（commit: `9a8358f` 1件）。

#### review
- 1回のレビューで承認。レビュー retrospec では実装が Spec と一致していることを確認しており、verify 段階でも FAIL なし（レビューの精度は高い）。

#### merge
- PR #413 が 2026-05-05T01:39:49Z にマージ済み。コンフリクトの痕跡なし。

#### verify
- 4件全て PASS（file_not_contains×3、grep×1）。AC5（opportunistic）は `phase/verify` ラベルで残存。verify command がすべて `always_allow` コマンドのみで構成されており、non-interactive モードでも確認不要で実行完了した。

### Improvement Proposals
- N/A
