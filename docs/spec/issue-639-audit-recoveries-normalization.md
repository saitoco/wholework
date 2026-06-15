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

## Code Retrospective

### Deviations from Design

- None。Spec のImplementation Steps に記載された2箇所の sed 挿入、fixture 作成、bats テスト追加をすべてそのまま実装した。

### Design Gaps/Ambiguities

- None。Spec Notes の sed パターン (`s/ ([^)]*) *$//`) とその動作説明が明確で、実装中に解釈の迷いは生じなかった。

### Rework

- None。初回実装で全 5 テスト PASS、forbidden expressions チェックも問題なし。

## review retrospective

### Spec vs. Implementation Divergence Patterns

- None. 実装は Spec の Implementation Steps を完全に踏襲。`CURRENT_SYMPTOM` と `sym` への sed 挿入箇所・パターン、fixture 内容（3エントリ）、bats アサーション（line_count=1, カウント=3, trailing context 非存在）すべてが Spec の記述と一致した。Spec 品質が高く、review フェーズで divergence を検出する余地がなかった。

### Recurring Issues

- None. 全4視点（Spec 整合・エッジケース・セキュリティ・ドキュメント整合性）で繰り返しパターンの issue なし。`elif` ブランチ内の `CURRENT_SYMPTOM` リセット（sed 未適用）は pre-existing コードで本 PR スコープ外。

### Acceptance Criteria Verification Difficulty

- None. AC1・AC2 ともに `rubric` + `grep` のデュアル verify command で PASS。UNCERTAINs なし。`rubric` グレーダーが adversarial stance で検証しても問題なし。Post-merge AC は `verify-type: manual` で適切にマーク済みであり、`/verify` 実行時に自動スキップされる。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #659 をスカッシュマージ（`--squash --delete-branch`）で main にマージ
- mergeable=true / CI=success / review=approved — コンフリクトなし、手動解決不要
- Phase Handoff は review フェーズのものを merge フェーズ記録に置換

### Deferred Items
- Post-merge AC: 次回 `/audit recoveries` 実行で `silent-no-op` 系3件が正規化後に同一バケット閾値を満たし候補表示に到達することを手動確認

### Notes for Next Phase
- `/verify 639` で post-merge AC（`verify-type: manual` マーク）の手動確認を実施すること
- pre-merge AC はすべて review フェーズで PASS 済み — verify フェーズでの再実行は任意
- `scripts/collect-recovery-candidates.sh` の sed 正規化が本番データに対して意図通り動作するかを `/audit recoveries` 実行で確認する

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 2 件すべて `rubric` + `grep` のデュアル verify command で自動検証可能。spec で auto-resolve した 3 つの曖昧点（grep ヒントの BRE 問題・`find|xargs` 偽陽性・無効 event 名）はいずれも `/issue` triage で適切に修正済み。
- Size は post-spec で S→M に upgrade。Spec 段階で sed 正規化方針と過剰集約抑止が明示されており、design は不要な詳細化なし。

#### code
- 1 PR (#659) で完了。fixup/amend なし。
- 変更は `scripts/collect-recovery-candidates.sh` の sed 正規化 + bats 回帰テスト + fixture 新規。実装が Spec 推奨案 (案 1) と完全一致。

#### review
- light review。MUST/SHOULD なし。

#### merge
- squash merge `--delete-branch` で main 統合。CI green、conflict なし。

#### verify
- Pre-merge AC 2 件は rubric grader（adversarial stance）で PASS。
- Post-merge manual AC 1 件は次回 `/audit recoveries` 実行確認待ち。Issue は `phase/verify` を維持。
- `/auto --batch` セッション中の uncommitted state（auto-session report + `get-auto-session-report.sh` の差分）が verify 開始時にブロック要因となり、stash + move out で回避した。

### Improvement Proposals
- (HIGH) `check-verify-dirty.sh` の whitelist または `verify-ignore-paths` に `docs/reports/auto-session-*.md`（auto session report の自動生成物）を追加し、batch session 中の verify がブロックされないようにする。
- (MEDIUM) `/auto --batch` の途中で `scripts/get-auto-session-report.sh` 等が unstaged 状態で modify される根本原因を別 Issue で調査。batch run 中に発生したのは事実だが、どの run-auto-sub 経路で書き換えが起きたか不明。

