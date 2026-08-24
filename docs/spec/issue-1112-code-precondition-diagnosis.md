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

1. `skills/code/SKILL.md` Step 3 を書き換える: 旧 Step 3 の 2 段構成 (`gh issue view` によるアドホックなラベル確認 → 独立した「Spec precondition check」ブロックでの `reconcile-phase-state.sh --check-precondition` 呼び出し) を、単一の `reconcile-phase-state.sh code-patch $NUMBER --check-precondition` 呼び出し (実引数順序をスクリプトの実際の usage に合わせて修正) + `diagnosis` 分岐に統合する。JSON の `diagnosis` を分岐条件として (a) `phase/ready` ラベル欠如時、(b) Spec ファイル欠如時、で異なる出力文言を出すようにする。あわせて、ラベルリストと `diagnosis`/`actual` を `OBSERVED_LABELS` / `OBSERVED_DIAGNOSIS` としてその場で保持し、Step 12 での Auto-Resolve Log / Phase Handoff 記述時にはこれらの値をそのまま転記する (GitHub state を再クエリしない) ことを明記する。(→ acceptance criteria AC1, AC2, AC4)
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

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1112#issuecomment-5369638133
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1112#issuecomment-5369691149
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1112#issuecomment-5378423104
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1112#issuecomment-5379811900
- saito / MEMBER / first-class / <!-- wholework-event: type=batch-verify-dispatch phase=audit issue=1112 --> / https://github.com/saitoco/wholework/issues/1112#issuecomment-5383457825
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1112#issuecomment-5383468221
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1112#issuecomment-5383998201
- saito / MEMBER / first-class / <!-- wholework-event: type=batch-verify-dispatch phase=audit issue=1112 --> / https://github.com/saitoco/wholework/issues/1112#issuecomment-5391603348
## Code Retrospective

### Deviations from Design

- Spec の Implementation Steps は「Step 3 を書き換える」「ヘッダコメントを追加する」の 2 項目のみを列挙していたが、実装時に旧 Step 3 の構造 (ラベル存在をアドホックに `gh issue view` で確認する前段ブロックと、その後で `reconcile-phase-state.sh --check-precondition` を呼ぶ独立した「Spec precondition check」ブロックの 2 段構成) 自体が齟齬の温床と判断し、`reconcile-phase-state.sh` の呼び出しを 1 回に統合して `diagnosis` で分岐する単一フローに再構成した。理由: 旧 2 段構成では、1 段目で `phase/ready` 欠如を検出・処理した後でも 2 段目が独立に再実行され、その 2 段目の説明文が「`matches_expected: false` は常に Spec 欠如」と誤って決め打ちしていた — これは Issue #1112 の Root Cause そのものであり、2 段構成を維持したまま 2 段目の文言だけ直しても、`phase/ready` 欠如がまだ解消されていない状態で 2 段目に到達した場合に同じ齟齬が再現しうる。1 回の呼び出し + `diagnosis` 分岐に統合することで構造的に解消した。
- Step 3 のコマンド例 `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh --check-precondition code-patch $NUMBER` は、実際のスクリプト引数順序 (`<phase> <issue_number> [--check-precondition|--check-completion] ...`、`scripts/reconcile-phase-state.sh` 実行時の usage エラーで確認) と一致しておらず、書かれた通りに実行すると `unknown option: 1112` で失敗する状態だった。本 Issue の対応範囲外だが、同じ行を書き換える機会に `code-patch $NUMBER --check-precondition` へ修正した。Root Cause 分析やレビューでは指摘されていなかった実行時エラーであり、実装時に発見した。

### Design Gaps/Ambiguities

N/A

### Rework

N/A

## Phase Handoff

<!-- phase: code -->

### Key Decisions

- 旧 Step 3 の 2 段構成 (アドホックな `gh issue view` ラベル確認 → 独立した `reconcile-phase-state.sh --check-precondition` 呼び出し) を、1 回の呼び出し + `diagnosis` 分岐へ統合した。2 段構成のままだと 1 段目で `phase/ready` 欠如を検出しても 2 段目が独立に再実行され、2 段目の説明文だけを直しても再発しうる構造的な脆弱性があったため。
- `OBSERVED_LABELS` / `OBSERVED_DIAGNOSIS` という命名で、Step 3 で観測した値を Step 12 まで持ち越して転記する、という指示を Step 3 内に明記した (Step 12 側の書き換えは行っていない — 転記元である Step 3 に「その場でキャプチャして後で使う」ことを書くだけで十分と判断)。
- `_precondition_code_common()` へのヘッダコメント追加は、`code-patch` と `code-pr` 双方の precondition (`_precondition_code_patch()` / `_precondition_code_pr()` がいずれも `_precondition_code_common()` を呼ぶ) に自動的に適用される。個別に 2 箇所へコメントを追加する必要はなかった。

### Deferred Items

- Post-merge の 2 件目 AC (`verify-type: observation event=auto-run session=next`) — 本修正後、次回 `/code` が Auto-Resolve Log / Phase Handoff へ Step 3 の判定結果を記録する際に遡及誤記が再発しないことの確認は、次回発生時まで検証できない。次回の `/code` 実行 (Step 3 で `matches_expected: false` が発生するケース) で観測すること。
- Post-merge の 1 件目 AC (`opportunistic` 検証) — `phase/ready` が無い状態で `/code` を実行した際の出力文言確認は、実運用中の自然発生を待つ opportunistic 検証であり、本フェーズでは未実施。

### Notes for Next Phase

- 本 Issue の変更は SKILL.md の prose 修正とスクリプトへのヘッダコメント追加のみで、`_precondition_code_common()` の分岐ロジック自体 (ラベル欠如/Spec欠如の 2 分岐) は変更していない。挙動を変えたのは「LLM がどちらの分岐かを正しく解釈できるようにする」説明面のみ。
- `/review` は、新しい Step 3 の記述が実際に `reconcile-phase-state.sh` の usage/diagnosis 文言と一致しているか (特にコマンドの引数順序 `code-patch $NUMBER --check-precondition`) を確認すること。
- Post-merge observation AC (次回 `/code` 実行時の遡及誤記チェック) は `/verify` が担当する — 次回発生時まで PASS/FAIL を判定できないことに留意。

## Issue Retrospective

### 実施内容

- Step 1 のコメント消費手続きで、本 Issue に投稿済みの 2 件のコメント (2026-08-06 #1102 再発報告、2026-08-07 #1108 再発報告) を一級ソースとして消費した。いずれも `authorAssociation: MEMBER` (first-class)。
- 実装調査 (`scripts/reconcile-phase-state.sh` `_precondition_code_common()` L481-514) の結果、当初 Background が「Spec ファイルの存在は判定に使われていない」としていた記述は不正確と判明した。実際には `phase/ready` ラベル欠如と Spec ファイル欠如を**別々の診断文言で区別している**実装だった (対応方針の案 C は既に実装済み)。この事実を Background に追記し、対応方針を「SKILL.md 側の説明修正が主軸」という結論に更新した。
- コメントで報告された 2 回目 (#1102) ・3 回目 (#1108) の再発は、いずれも「Step 4 (ラベル遷移) 後の状態を Step 3 開始時点の状態として遡及的に誤記する」という共通パターンを示していた。これは説明・実装の軸ずれ (元々の Issue スコープ) とは別次元の問題であり、SKILL.md の説明を修正するだけでは再発を防げないと判断し、Purpose と Acceptance Criteria に「Step 3 で実際に観測した値をその場で Auto-Resolve Log / Phase Handoff に転記し、フェーズ終盤の再クエリによる遡及記述を避ける」という要件 (案 D) を追加した。3 回連続で同型の記述が観測されている実測を踏まえた判断であり、コメントで「別 Issue は起票せず本 Issue に集約する」と明示されていたため、新規 Issue は起票せず本 Issue の Background / 対応方針 / AC を拡張する形で反映した。
- Pre-merge AC を 3 件から 4 件に拡張 (観測値のその場キャプチャに関する rubric AC を追加)。Post-merge AC に、再発監視用の `verify-type: observation event=auto-run session=next` AC を追加した (skill 自己更新の反映は次回 `/code` 実行セッションでしか観測できないため)。
- タイトルドリフトチェック: Purpose が 2 点に増えたが、いずれも Step 3 の precondition 説明・記録精度という同一スコープ内であり、drift なしと判断してタイトルは変更しなかった。
- 自動起票時チェック (`check-skill-change-observation-ac.sh`, `check-ac-checkbox-format.sh`) はいずれも exit 0 (問題なし)。

### Consumed Comments

| login | authorAssociation | trust tier | 意図の要約 | URL |
|-------|-------------------|-----------|-----------|-----|
| saito | MEMBER | first-class | #1102 での 2 回目の再発を報告し、timeline 実測との矛盾・Phase Handoff への伝播を記録。フェーズ開始時点の値を保持して retrospective に渡す観点を提起 | https://github.com/saitoco/wholework/issues/1112#issuecomment-5205213361 |
| saito | MEMBER | first-class | #1108 での 3 回目の再発を報告し、ラベル読み取り結果自体が記録されていたことから「ラベル付与とラベル読み取りの順序が逆転している」可能性を指摘 | https://github.com/saitoco/wholework/issues/1112#issuecomment-5213033471 |

## Verify Retrospective

### Phase-by-Phase Review

#### verify

- Post-merge observation 条件 (`event=auto-run session=next`) を評価。`auto-run` イベント自体は発火済みだが、修正マージ (a7ecd358, 2026-08-21 21:02 JST) 以降に作成/更新された Spec (#1047, #1435, #1109, #1106, #1107 等) を調査した限り、本 Issue が対象とする「Step 3 の phase/ready 欠如による false-state」シナリオそのものが一度も再現していない。イベント発火 (= 何らかの `/auto` 実行が完了した) と、この観測条件が確認したい「該当シナリオが発生した」は別物であり、後者の母集団がまだ観測されていないため UNCERTAIN と判定した。次回この false-state シナリオが実際に発生した際に再評価が必要
- opportunistic 条件 (phase/ready 無し状態での `/code` 診断文言確認) は、人為的な不完全実行の構築が opportunistic タグの趣旨 (自然発生時の捕捉) にそぐわないため SKIP とした

### Improvement Proposals
- N/A
