# Issue #639: audit/recoveries: collect-recovery-candidates.sh symptom-short normalization

## Overview

`scripts/collect-recovery-candidates.sh` は symptom-short バケット鍵に **完全一致** を使用しているため、末尾に括弧付き文脈（例: `(#576, 2nd in session)`, `(#523, #526)`）が付いたエントリが別バケットに分裂し、`/audit recoveries` のデフォルト閾値 (3) に到達しない問題がある。

2026-06-14 に観測された `silent-no-op` 系 3 件はセマンティックに同一だが、リテラル差異により候補ゼロを返した。

symptom-short を抽出する際に末尾の `(...)` を sed で strip して正規化することで、概念的に同一のリカバリーパターンを正しく集約し、`/audit recoveries` の候補検出感度を改善する。

## Changed Files

- `scripts/collect-recovery-candidates.sh`: symptom-short 抽出の 2 箇所に `sed 's/ ([^)]*) *$//'` による末尾括弧 strip を追加 — bash 3.2+ compatible
- `tests/audit-recoveries.bats`: 末尾文脈のみ異なる複数エントリが 1 バケットに集約されることを assert する回帰テスト (`normalize:` カテゴリ) と `FIXTURE_TRAILING` 変数宣言を追加
- `tests/fixtures/orchestration-recoveries-trailing.md`: 末尾文脈バリアント 3 件（`"X"`, `"X (#576, 2nd in session)"`, `"X (#523, #526)"`）を含む新規テスト fixture

## Implementation Steps

1. `scripts/collect-recovery-candidates.sh`: symptom-short を変数に代入する 2 箇所を正規化する (→ AC1)
   - **箇所 1** (line ~88): `CURRENT_SYMPTOM="${line#*UTC: }"` の直後に `CURRENT_SYMPTOM="$(echo "$CURRENT_SYMPTOM" | sed 's/ ([^)]*) *$//')"` を追加
   - **箇所 2** (line ~103): `sym="${line#*UTC: }"` の直後に `sym="$(echo "$sym" | sed 's/ ([^)]*) *$//')"` を追加
   - strip 対象は末尾の `(...)` **1 つのみ**（`$` アンカーにより最末尾の `(...)` だけが対象）

2. `tests/fixtures/orchestration-recoveries-trailing.md`: 以下の 3 エントリを持つ fixture を新規作成する (→ AC2)
   - `## 2026-06-01 10:00 UTC: silent-no-op recovered via wrapper-anomaly Tier 2 retry`
   - `## 2026-06-02 11:00 UTC: silent-no-op recovered via wrapper-anomaly Tier 2 retry (#576, 2nd in session)`
   - `## 2026-06-03 12:00 UTC: silent-no-op recovered via wrapper-anomaly Tier 2 retry (#523, #526)`
   - 全エントリの `Improvement Candidate` は `未起票`（除外なし）
   - 正規化後 3 件とも同一バケット → threshold=3 で count=3 が出力される

3. `tests/audit-recoveries.bats`: ファイル先頭付近に `FIXTURE_TRAILING` 変数宣言を追加し、`@test "normalize: trailing context stripped and aggregated to same bucket"` を追加する (after 2) (→ AC2)
   - `run bash "$SCRIPT" "$FIXTURE_TRAILING" --threshold 3` で実行
   - 出力が 1 行であることを assert (`line_count -eq 1`)
   - 出力に `silent-no-op recovered via wrapper-anomaly Tier 2 retry\t3` が含まれることを assert (正規化後の base 症状とカウント)
   - 出力に `(#576` や `(#523` が含まれないことを assert（trailing context が strip されている）

## Verification

### Pre-merge
- <!-- verify: rubric "scripts/collect-recovery-candidates.sh が symptom-short バケット時に末尾の括弧付き文脈（例: (#576, 2nd in session), (#523, #526)）を strip した正規化文字列を鍵として使用する実装になっており、末尾文脈のみ異なる複数エントリが同一バケットに集約される" --> <!-- verify: grep "sed" "scripts/collect-recovery-candidates.sh" --> `scripts/collect-recovery-candidates.sh` で symptom-short の末尾括弧付き文脈を strip した正規化バケット鍵が使用される
- <!-- verify: rubric "tests/audit-recoveries.bats に、末尾文脈のみ異なる複数エントリ（例: 'X' と 'X (#N, ...)' の組み合わせ）を含む fixture を使用し、それらが 1 バケットとして集約されることを assert する回帰テストが追加されている" --> <!-- verify: grep "trailing\|normalize" "tests/audit-recoveries.bats" --> 末尾差分のみ異なる複数エントリが 1 バケットに集約される回帰テストが `tests/audit-recoveries.bats` に追加される

### Post-merge
- 次回以降の `/audit recoveries` 実行で、本 Issue 起票時点に存在する `silent-no-op` 系エントリ群が正規化後に同一バケットとして threshold を満たし、候補表示またはユーザー判断待ちに到達することを確認する <!-- verify-type: manual -->

## Notes

### 正規化の設計方針

- strip 対象は **末尾の `(...)` 1 つのみ** (Issue Notes §1 推奨案を採用)
- sed パターン: `s/ ([^)]*) *$//`
  - `(` と `)` は BRE でリテラル扱い（エスケープ不要）
  - `[^)]*` は `)` 以外の任意文字の繰り返し（括弧内の `,` や `#` も含む）
  - `$` アンカーにより最末尾の `(...)` のみ対象（複数 `(...)` があっても最後だけ strip）
  - BSD sed (macOS) / GNU sed 両対応 — bash 3.2+ compatible
- `false-positive silent-no-op on patch route (#523, #526)` は先頭 5 語が異なるため、正規化後も別バケット扱い（過剰集約を防ぐ）

### docs/structure.md 変更不要

`collect-recovery-candidates.sh` の説明文「count symptom-short frequency」は高レベルの動作を記述しており、正規化後も正確性を保つ（`grep "symptom-short frequency" "docs/structure.md"` で確認済み）

### 変数代入の方向

CURRENT_SYMPTOM と sym の両方を正規化することで、EXCLUDED_LIST と SYMPTOM_LIST の比較が `grep -qxF` の exact match で一致するよう保つ。
