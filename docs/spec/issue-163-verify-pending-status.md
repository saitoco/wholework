# Issue #163: verify: CI in_progress 時の UNCERTAIN/reopen を pending 扱いに変更

## Overview

`/verify` 実行時に CI が in_progress で `github_check "gh run list"` が判定保留になると、現状は UNCERTAIN として reopen + fix-cycle を誘発する。これを UNCERTAIN と区別する **PENDING** ステータスに分離し、PENDING のみの場合は reopen せず `phase/verify` を維持する挙動に変更する。FAIL/UNCERTAIN 混在時は従来通り reopen を優先（本物の失敗を見逃さない）。

## Changed Files

- `modules/verify-executor.md`: PENDING ステータス定義追加、`github_check` の PENDING 検出ロジック追記、CI Reference Fallback の incomplete を UNCERTAIN → PENDING に変更
- `skills/verify/SKILL.md`: 結果集約の分類テーブル拡張（3 値 → 4 値）、reopen 判定に PENDING 分岐追加、PENDING 時のユーザー案内メッセージ追加

## Implementation Steps

1. **`modules/verify-executor.md` に PENDING ステータス追加** (→ AC1, AC2):
   - Step 4 の結果分類（`PASS`/`FAIL`/`UNCERTAIN`/`SKIPPED`）に `PENDING` を追加:
     > **PENDING**: CI execution in progress (github_check output matches `in_progress`/`queued`/`pending`/empty/`null`). Distinct from UNCERTAIN — will be auto-determined after CI completes. Does not trigger reopen/fix-cycle.
   - `github_check` 行（テーブル内）に PENDING 検出条件を追記: safe mode allowlist 実行後、出力が `""` / `null` / `in_progress` / `queued` / `pending` のいずれかに一致する場合は PENDING を返す（expected_value が指定されていて出力が空/null の場合も同様）
   - CI Reference Fallback セクションの「Related job is incomplete (PENDING, etc.) → UNCERTAIN」を「→ PENDING」に修正

2. **`skills/verify/SKILL.md` の判定ロジックを 4 値化** (→ AC3, AC4):
   - 結果集約テーブル（`Condition 3 | ⚠️ UNCERTAIN` 付近）を拡張し、PENDING 行を追加（例: `Condition 4 | ⏳ PENDING | CI in progress`）
   - Issue Reopen Judgment セクション（`When Issue is CLOSED` / `When Issue is OPEN` の両方）の判定ロジックを以下に変更:
     - 全 PASS/SKIPPED → 現状通り close or phase/verify
     - **新規**: PENDING を含む、かつ FAIL/UNCERTAIN なし → reopen せず `phase/verify` を付与、ユーザー案内メッセージを出力
     - FAIL または UNCERTAIN を含む → 現状通り reopen + fix-cycle（PENDING が混在していても FAIL/UNCERTAIN を優先）
   - セクション見出しに「Issue Reopen Judgment」相当の明示的な見出しがない場合は、判定ロジックの導入箇所に `### Issue Reopen Judgment` 見出しを追加（AC4 の `section_contains` 検証が通るよう）

3. **PENDING 時のユーザー案内メッセージ実装** (→ AC5):
   - 完了メッセージセクションに PENDING ケースを追加:
     > CI がまだ実行中です。CI 完了後に `/verify $NUMBER` を再実行してください。
     > PENDING 件数: N / 総件数: M
   - メッセージには必ず「CI 完了後」のリテラルを含める（AC5 verify command が `file_contains "CI 完了後"` のため）

## Verification

### Pre-merge
- <!-- verify: file_contains "modules/verify-executor.md" "PENDING" --> `verify-executor.md` に PENDING ステータスが定義されている
- <!-- verify: file_contains "modules/verify-executor.md" "in_progress" --> `verify-executor.md` で `github_check` の in_progress 検出が記載されている
- <!-- verify: file_contains "skills/verify/SKILL.md" "PENDING" --> `verify/SKILL.md` に PENDING 用の reopen 回避分岐が追加されている
- <!-- verify: section_contains "skills/verify/SKILL.md" "Issue Reopen Judgment" "PENDING" --> 再オープン判定セクションに PENDING ケースが明記されている
- <!-- verify: file_contains "skills/verify/SKILL.md" "CI 完了後" --> PENDING 時のユーザー案内メッセージが実装されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI が PASS する

### Post-merge
- CI in_progress 状態で `/verify N` を実行し、Issue が reopen されず `phase/verify` に留まることを確認
- CI 完了後に `/verify N` を再実行し、正しく PASS 判定されて Issue クローズされることを確認
- FAIL/UNCERTAIN と PENDING が混在する場合、FAIL/UNCERTAIN が優先されて従来通り reopen されることを確認

## Notes

- **既存 `tests/verify-executor.bats` は存在しない**: verify-executor は LLM 駆動のドキュメントモジュールで bats 対象外。Issue body の bats テスト記述は削除せず Follow-up として残す（ユーザー向けに分かりやすさ優先）が、本 Issue のスコープには含めない。動作検証は post-merge の手動確認で担保
- **PENDING 判定の 5 パターン**: `in_progress` / `queued` / `pending` / 空文字列 `""` / `null`。GitHub Actions API が返す未完了シグナルの標準値
- **優先規則の根拠**: FAIL/UNCERTAIN 混在時に PENDING を優先すると本物の失敗が「時間で解決」と誤認され見逃される。保守的に FAIL/UNCERTAIN を優先
- **AC4 の section_contains 対応**: `skills/verify/SKILL.md` に「Issue Reopen Judgment」セクション見出しが存在することを確認（現状は `When Issue is CLOSED` / `When Issue is OPEN` のサブ見出しのみ）。verify command が通るよう親見出しとして `### Issue Reopen Judgment` の追加が必要
- **AC5 のリテラル「CI 完了後」**: 日本語リテラル。英語版 SKILL.md 本文に日本語混入は許容される（既存 `verify/SKILL.md` には日本語完了メッセージが多数存在。line 493 の「Issue #$NUMBER has been reopened」などと整合性を保つ）
- **Simplicity rule**: light 上限 5 ステップ / 5 pre-merge に対し、ステップ 3 件は OK。pre-merge は 6 件で 1 件超過だが Issue body の AC と 1:1 対応を優先して全量コピー
