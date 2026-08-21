# Issue #1112: code: Step 3 の precondition 判定結果の説明を実際の判定軸 (phase/ready ラベル) と一致させる

## Overview

`skills/code/SKILL.md` Step 3 は、`reconcile-phase-state.sh --check-precondition` が返す `matches_expected: false` を一律「Spec missing」と説明しているが、実装 (`_precondition_code_common()`) は「`phase/ready` ラベル欠如」と「Spec ファイル欠如 (Size ≠ XS)」を別々の `diagnosis` 文言で区別して返している。この齟齬により、ラベル欠如が原因で `false` が返った場合でも「Spec が無い」と誤って解釈され、誤った原因推定が Auto-Resolve Log に記録される実害が Issue #1053 / #1102 / #1108 で 3 回発生した。3 回とも「Step 4 (ラベル遷移) 後の状態を Step 3 開始時点の状態として遡及的に誤記する」という共通パターンを示しており、SKILL.md の説明修正だけでなく、Step 3 で観測した値をその場でキャプチャして後続の記述に使い回す指示も必要と判断した。

## Reproduction Steps

- `skills/code/SKILL.md` Step 3 (L169-172) を読むと、`matches_expected: false` を一律「Spec missing」として扱い、「Spec が見つかりません。`/spec $NUMBER` を実行してください」という固定文言を出力する設計になっている。
- 一方 `scripts/reconcile-phase-state.sh` の `_precondition_code_common()` (L481-514) は、(1) `phase/ready` ラベル欠如 → `"issue #N does not have phase/ready label (code phase precondition not met)"`、(2) ラベルは有るが Spec ファイル欠如かつ Size ≠ XS → `"Spec missing and Size != XS"` の 2 通りを別々の `diagnosis` として返す。
- Issue #1053 (2026-07-30) では `phase/ready` ラベルが `phase/code` に遷移した直後 (本実行の Step 4 由来) にもかかわらず、SKILL.md の説明に従って「Spec が無い」と誤って解釈され、Auto-Resolve Log に timeline と矛盾する原因推定が記録された。同型の齟齬が #1102 (2026-08-06)、#1108 (2026-08-07) でも再発している。

## Root Cause

- **一次原因**: `skills/code/SKILL.md` Step 3 の説明が `reconcile-phase-state.sh --check-precondition` の実際の判定軸 (ラベル欠如と Spec 欠如を別診断とする実装) と一致していない。
- **二次原因 (3 回の再発パターン)**: Step 3 で実際に観測した値 (ラベルリスト / `diagnosis` 文言) をその場で保持する指示が SKILL.md に無いため、Auto-Resolve Log / Phase Handoff 記述時 (Step 12 相当のタイミング) に GitHub state を再クエリし、その時点で既に Step 4 によってラベルが `phase/code` に遷移した後の状態を「Step 3 時点の状態」として誤記していたと推測される (Issue 本文の「観測タイミングの遡及」分析)。

## Changed Files

- `skills/code/SKILL.md`: Step 3 を書き換え。(a) `reconcile-phase-state.sh --check-precondition` の `matches_expected: false` を `diagnosis` で分岐させ、実際の欠如対象 (ラベル or Spec) を取り違えない出力文言にする。(b) Step 3 で観測した値 (`OBSERVED_LABELS` / `OBSERVED_DIAGNOSIS`) をその場で保持し、Step 12 (Auto-Resolve Log / Phase Handoff 記述時) にその値をそのまま転記する (GitHub state の再クエリによる遡及記述を避ける) ことを明記
- `scripts/reconcile-phase-state.sh`: `_precondition_code_common()` の直上に、`phase/ready` ラベル欠如と Spec ファイル欠如が別々の diagnosis 文言で区別される旨のヘッダコメントを追加。bash 3.2+ 互換 (コメント行のみで実行ロジックへの影響なし)
- [Steering Docs sync candidate] キーワード "reconcile-phase-state.sh" (203 件) と "code" (1174 件) は、いずれも判別力フィルタ (閾値 8 件) を超過したためスキップ。個別列挙なし。

## Implementation Steps

1. `skills/code/SKILL.md` Step 3 を書き換える: `reconcile-phase-state.sh --check-precondition` 実行後、JSON の `diagnosis` を分岐条件として (a) `phase/ready` ラベル欠如時、(b) Spec ファイル欠如時、で異なる出力文言を出すようにする。あわせて、ラベルリストと `diagnosis`/`actual` を `OBSERVED_LABELS` / `OBSERVED_DIAGNOSIS` としてその場で保持し、Step 12 での Auto-Resolve Log / Phase Handoff 記述時にはこれらの値をそのまま転記する (GitHub state を再クエリしない) ことを明記する。(→ acceptance criteria AC1, AC2, AC4)
2. `scripts/reconcile-phase-state.sh` の `_precondition_code_common()` 直上に、2 つの diagnosis 文言が区別される旨のヘッダコメントを追加する。(→ acceptance criteria AC3) (parallel with 1)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md Step 3 の precondition チェック結果の説明が、reconcile-phase-state.sh --check-precondition の実際の判定軸 (phase/ready ラベルの有無、および Spec ファイル存在の有無を別診断として区別すること) と一致している" --> 説明と実装の判定軸が一致している
- <!-- verify: rubric "precondition が false を返した際にユーザ/LLM に提示される文言が、実際の欠如対象 (ラベル or Spec) を取り違えない形になっている" --> 出力文言が実態と一致している
- <!-- verify: rubric "reconcile-phase-state.sh の code-pr / code-patch precondition について、phase/ready ラベル欠如時と Spec ファイル欠如時が別々の diagnosis 文言で区別されることが、スクリプトのヘッダコメントまたは modules/phase-state.md に明記されている (判定条件の列挙だけでは満たさない。診断文言がケースごとに分かれる旨まで明記されている必要がある)" --> diagnosis 文言レベルの区別が文書化されている
- <!-- verify: rubric "skills/code/SKILL.md Step 3 が、precondition チェックで実際に観測した値 (labels または diagnosis) をその場で Auto-Resolve Log / Phase Handoff の記述に用いるよう明記しており、フェーズ終盤に GitHub state を再クエリして遡及的に記述しないことを求めている" --> 観測値のその場キャプチャが明記されている

### Post-merge

- `phase/ready` が無い状態で `/code` を実行し、出力される診断文言が実際の欠如対象と一致することを確認する <!-- verify-type: opportunistic -->
- 本修正後に `/code` が Auto-Resolve Log / Phase Handoff へ Step 3 の判定結果を記録する際、Step 4 以降の状態を遡及的に誤記する事例が再発しないことを次回発生時に確認する <!-- verify-type: observation event=auto-run session=next --> <!-- verify: rubric "Auto-Resolve Log または Phase Handoff の Step 3 関連記述が、Step 3 実行時点で観測した値 (ラベルリストまたは diagnosis 文言) と整合しており、Step 4 のラベル遷移後の状態を Step 3 開始時点の状態として誤って記述していない" -->

## Notes

- **Issue 本文の自動修正 (Comment Consumption Procedure 経由)**: 消費した「AC Verify Command Integrity Audit」コメント (2026-08-21T11:27:49Z, MEMBER, first-class) が、Pre-merge AC3 の rubric 文言が `modules/phase-state.md` L40-41 の既存記述 (「`phase/ready` label on issue, Spec exists OR Size=XS」) で字義通り満たされてしまい、本 Issue の実装を待たずに常時 PASS する懸念を指摘していた。実際に `modules/phase-state.md` を確認したところ、この懸念は妥当と判断 (composite な判定条件は既に文書化済みだが、diagnosis 文言がケースごとに分かれる旨は未文書化)。SPEC_DEPTH=light のため確認は行わず、rubric 文言を「diagnosis 文言レベルで区別されている」という、現状まだ非文書化の主張に絞り込む形で Issue 本文と Spec を同時に更新した (AC1/AC2 への統合・AC3 削除という代替案は、判定軸の文書化という独立した検証観点を失うため採用しなかった)。
- **Post-merge observation AC の rubric 追加**: `modules/verify-classifier.md` の "observation-tagged conditions" 手順 (観測イベントと期待される出力構造を分離する) に基づき、Post-merge 2 件目の `verify-type: observation` AC に rubric verify command を追加した (Option B: 既存の 1 行構造を維持しつつ検証基準を明確化)。Issue 本文も同時に更新済み。
- **案 D の実装粒度**: 観測値のその場キャプチャは SKILL.md への instruction 追加のみで対応し、`.tmp/` への一時ファイル書き出し等の新規永続化機構は導入しない。Issue の Purpose が「その場で保持し記述に用いるよう明記する」ことを求めており、3 回の再発はいずれも instruction 不在 (自然にそうなるはずという暗黙の期待のみで明示的な指示が無かったこと) が原因と分析されているため、prose 修正が適切な粒度と判断した。
- **新規テストケース不要の判断**: 本 Issue の変更は SKILL.md の prose 修正とスクリプトへのヘッダコメント追加のみで、`_precondition_code_common()` の分岐ロジック自体は変更しない (ラベル欠如/Spec欠如の 2 分岐は変更前から存在)。既存テスト `tests/reconcile-phase-state.bats` の `code-patch precondition: no phase/ready label -> mismatch` / `code-patch precondition: Spec missing and Size != XS -> mismatch` 等が両分岐を既にカバーしているため、新規 bats テストケースの追加は不要と判断した。
- **Steering Docs sync candidate check**: 抽出キーワード "reconcile-phase-state.sh" (203 件ヒット) と "code" (1174 件ヒット、バレースキル名) はいずれも判別力フィルタ (閾値 8 件) でスキップ。個別列挙なし。

## Consumed Comments

| login | authorAssociation | trust tier | 意図の要約 | URL |
|-------|-------------------|-----------|-----------|-----|
| saito | MEMBER | first-class | `/issue` フェーズの Issue Retrospective。実装調査 (`_precondition_code_common()`) の結果、当初 Background の「Spec ファイル存在は判定に使われていない」という記述が不正確と判明し対応方針を更新したこと、および 2 回目・3 回目の再発から Purpose/AC に案 D (観測値のその場キャプチャ) を追加したことを報告 | https://github.com/saitoco/wholework/issues/1112#issuecomment-5369204332 |
| saito | MEMBER | first-class | AC Verify Command Integrity Audit — Pre-merge AC3 の rubric が `modules/phase-state.md` の既存記述で常時 PASS してしまう懸念を指摘し、絞り込みまたは AC1/AC2 への統合を提案 | https://github.com/saitoco/wholework/issues/1112#issuecomment-5369246125 |
