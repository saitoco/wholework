# Issue #198: docs: tech.md Fork table の triage 記載を修正

## Overview

`docs/tech.md` の Fork context 判断表で `triage` 行が `No (removed)` と記載されているが、`skills/triage/SKILL.md` は現役で `/auto` からも呼び出されている。`(removed)` は triage スキル自体が削除されたと誤読される可能性がある。実際には `run-triage.sh` ラッパーは存在せずインライン呼び出しのみで、fork context を使用しない設計になっている。`No (removed)` を他の非 fork スキル行（`No` のみ）と同様の表記に統一する。

日本語ミラーファイル `docs/ja/tech.md` にも同じ誤記（`不要（削除済み）`）が存在するため、同時に修正する。

## Reproduction Steps

1. `docs/tech.md` の Fork context 判断表を参照する
2. `triage | No (removed)` 行を確認する
3. 他の `No` のみの行（`issue/spec/code/review/merge/verify`）と比較すると、`(removed)` という注記が triage スキルが削除されたかのように見える

## Root Cause

`run-triage.sh` が廃止されてインライン呼び出しに変わった際に `(removed)` 注記が追加されたが、その後も `/auto` 等から呼び出され続けたにもかかわらず注記が残存した。スキル本体の削除と実行ラッパーの削除が混同されている。

## Changed Files

- `docs/tech.md`: `triage | No (removed)` → `triage | No`（Fork context 判断表 triage 行）
- `docs/ja/tech.md`: `triage | 不要（削除済み）` → `triage | 不要`（同表の日本語版）

## Implementation Steps

1. `docs/tech.md` の `| triage | No (removed) |` を `| triage | No |` に変更する (→ 受入条件 1)
2. `docs/ja/tech.md` の `| triage | 不要（削除済み） |` を `| triage | 不要 |` に変更する (→ 受入条件 2)

## Verification

### Pre-merge

- <!-- verify: file_not_contains "docs/tech.md" "No (removed)" --> `docs/tech.md` の Fork context 判断表から "No (removed)" 記述が削除されている
- <!-- verify: file_not_contains "docs/ja/tech.md" "削除済み" --> `docs/ja/tech.md` の Fork context 判断表から "削除済み" 記述が削除されている

### Post-merge

- Fork context 判断表の全行を目視確認し、同様の誤注記（過去の経緯が残った注記など）がないことを確認する

## Notes

- `docs/ja/tech.md` はミラーファイルのため、英語版 `docs/tech.md` と同時に修正する
- `削除済み` は `docs/ja/tech.md` line 29 に1箇所のみ存在（`grep -n "削除済み" docs/ja/tech.md` で確認済み）
- 変更は機械的なテキスト置換のみで、ロジックへの影響なし

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec は簡潔かつ正確で、実装と完全に一致した。変更対象ファイルと変更内容が明示されており、曖昧点なし。
- `/audit` による drift 検出から Issue 化までの流れが機能しており、Spec の品質も適切だった。

#### design
- 設計は機械的なテキスト置換のみで複雑さなし。`docs/tech.md` と `docs/ja/tech.md` の両方を同時修正する判断も正しい。

#### code
- 実装は単一コミット（`91440e5`）で完結、2ファイル・2行変更のみ。rework（fixup/amend）なし。
- パッチルート（main 直コミット）が適切に選択されており、PR を経由しない小規模修正の典型例。

#### review
- パッチルートのため PR レビューなし。変更が機械的テキスト置換で影響範囲が明確なため、レビュー省略は妥当。

#### merge
- パッチルートで main 直コミット。コンフリクトなし、CI への影響なし。

#### verify
- 全条件（Pre-merge 2件）が PASS。verify コマンド（`file_not_contains`）が適切に機能した。
- Post-merge 条件は `verify-type: manual` で正しくユーザー確認に委譲。

### Improvement Proposals
- N/A
