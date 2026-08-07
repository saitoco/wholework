# Issue #476: review: CI/ランナー環境で決定的に失敗する設定ミスを MUST に分類する基準を明文化

## Consumed Comments

- saito / MEMBER / first-class / 2026-06-14 時点の前回 `/verify 476` 実行結果 (Pre-merge 2 件 PASS、Post-merge observation は event 未発火で SKIPPED) / https://github.com/saitoco/wholework/issues/476#issuecomment-4703192688
- saito / MEMBER / first-class / `/review --light` (PR #1189) 完了に伴い observation event `pr-review-light` が発火した旨の通知 / https://github.com/saitoco/wholework/issues/476#issuecomment-5199934979

### verify フェーズ (2026-08-06 re-run #2, cutoff: 2026-06-14T21:50:38Z)

- saito / MEMBER / first-class / 前回 `/verify 476` (2026-08-06 re-run) 実行結果。Pre-merge 2 件 PASS、Post-merge observation (event=pr-review-light) は PR #1189 の diff に該当欠陥なしのため UNCERTAIN / https://github.com/saitoco/wholework/issues/476#issuecomment-5199963258

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/476#issuecomment-5200100852

### verify フェーズ (2026-08-06 re-run #4, cutoff: 2026-06-14T21:50:38Z)

- saito / MEMBER / first-class / 前回 `/verify 476` (2026-08-06 re-run #3) 実行結果。Pre-merge 2 件 SKIPPED (already checked)、Post-merge observation (event=pr-review-light) は PR #1193 の diff に該当欠陥なしのため UNCERTAIN。3回連続の再現により起票水準に達したと記録 / https://github.com/saitoco/wholework/issues/476#issuecomment-5200610461
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/476#issuecomment-5201684724
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=4 / https://github.com/saitoco/wholework/issues/476#issuecomment-5210084188

### verify フェーズ (2026-08-06 re-run #6, cutoff: 2026-06-14T21:50:38Z)

- saito / MEMBER / first-class / 前回 `/verify 476` (2026-08-06 re-run #5) 実行結果。Pre-merge 2 件 SKIPPED (already checked)、Post-merge observation (event=pr-review-light) は PR #1218 (Issue #1082) の diff に該当欠陥なしのため UNCERTAIN。`keyword=workflow` ゲートがファイル名 `docs/workflow.md` の部分一致で誤発火した新規欠陥を発見 / https://github.com/saitoco/wholework/issues/476#issuecomment-5210100264
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=476 event=pr-review-light --> observation event 再発火通知 (`/review --light` PR #1217, Issue #1206 完了) / https://github.com/saitoco/wholework/issues/476#issuecomment-5210084188

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/476#issuecomment-5210233540
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/476#issuecomment-5212707587
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/476#issuecomment-5212862164
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/476#issuecomment-5213280537

### verify フェーズ (2026-08-07 re-run #11, cutoff: 2026-06-14T21:50:38Z)

- saito / MEMBER / first-class / 前回 `/verify 476` (2026-08-07 re-run #10) 実行結果。Pre-merge 2 件 SKIPPED (already checked)、Post-merge observation (event=pr-review-light) は PR #1244 (Issue #1117) の diff に該当欠陥なしのため UNCERTAIN。`keyword=workflow` ゲートの誤発火が10件目として再現 / https://github.com/saitoco/wholework/issues/476#issuecomment-5213746899
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/476#issuecomment-5215472710
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/476#issuecomment-5215741886
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/476#issuecomment-5216205088
## 背景

`/review` の MUST/SHOULD 分類基準に「対象実行環境で決定的に失敗する欠陥は MUST」というルールを明文化する。Spec フェーズなしで直接実装（Issue 本文から要件を読み取り）。

## 実装ステップ

1. `modules/review-output-format.md` に `## Severity Classification Criteria` セクションを追加
   - MUST（決定的失敗）、SHOULD（条件付き失敗）、CONSIDER（改善提案）の分類基準を定義
   - MUST 例：sudo なし root パス書き込み、sudo なし apt、存在しない action バージョン、未設定 secret、構文エラー、未定義変数参照
2. `agents/review-bug.md` に `## Severity Classification` セクションを追加（review-output-format.md への参照）
3. `agents/review-light.md` に `## Severity Classification` セクションを追加（同上）
4. `docs/structure.md` の review-output-format.md 説明を更新

## Code Retrospective

### Deviations from Design

- Spec なし（`phase/ready` ラベルはあったが Spec ファイル未作成）で実装。Issue 本文のスコープ（案）に候補ファイルが明示されていたため問題なく実装できた。

### Design Gaps/Ambiguities

- None

### Rework

- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 分類基準の追加先として `modules/review-output-format.md` を選択（既に `Severity: MUST / SHOULD / CONSIDER` が登場するため自然な配置）
- review-bug と review-light の両エージェントに同一の参照セクション `## Severity Classification` を追加（DRY: 定義は module 側に集約）
- MUST の判定基準は「対象環境で常に再現するか」と簡潔に定式化し、SHOULD との差を明確にした

### Deferred Items
- `review-spec` エージェントへの参照追加は未実施（Issue 本文のスコープ外）。必要であれば follow-up Issue で対応

### Notes for Next Phase
- 変更は docs/structure.md, modules/review-output-format.md, agents/review-bug.md, agents/review-light.md の 4 ファイル
- post-merge AC は `verify-type: observation event=pr-review-light` — 次回 `/review --light` 完了時に観測評価される

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 2 rubric AC で意味検証を主軸とする設計。`MUST 基準` と `例示` の双方を別 AC として独立検証する構成が機能。

#### design
- modules + agents の双方に同一 "Key rule" を配置することで review-bug と review-light の両エージェントが同じ基準を共有する設計。SSoT 重複だが意図的（agent-specific text として）。

#### code
- 4 ファイル変更で完了、rework なし。docs/structure.md 同時更新でドキュメント整合性も保全。

#### review
- patch route のため非実行 (N/A)。

#### merge
- patch route のため非実行。worktree-merge-push.sh で main 直マージ成功。

#### verify
- Pre-merge 全 2 件 PASS。Post-merge observation は次回 `/review --light` 完了時に自動評価で `phase/verify` 維持。

### Improvement Proposals
- N/A

## Verify Retrospective (2026-08-06 re-run)

### Phase-by-Phase Review

#### verify
- Post-merge observation (`verify-type: observation event=pr-review-light`) は `/review --light` (PR #1189, Issue #1156) 完了時に発火したことを確認した。ただし発火元 PR の diff (`skills/issue/SKILL.md`, `scripts/check-ac-checkbox-format.sh`, テスト, `docs/structure.md`) には CI ランナー環境で決定的に失敗する設定ミス自体が含まれておらず、review-light エージェントが実際に MUST 分類を行う場面が今回は発生しなかった。基準の存在 (Pre-merge 2 件 PASS) は裏付けられたが、「決定的失敗が実際に MUST 判定される」挙動そのものの実地確認はできず UNCERTAIN 判定とした

### Improvement Proposals
- 本 Issue の post-merge observation event (`event=pr-review-light`) は「`/review --light` が完了した」ことのみを検知し、レビュー対象 PR に決定的失敗パターンの欠陥が実在したかまでは絞り込んでいない。このため任意の `/review --light` 完了で event が発火し、対象 PR にたまたま該当欠陥がなければ `/verify` は UNCERTAIN 止まりになる — かつ fired 状態は Issue コメント全履歴から検出するため一度発火すると恒久的に「fired」のままとなり、以後の `/verify` 再実行でも同じ (証拠不十分な) fired 状態を毎回再評価することになる。observation-trigger の event 定義に「diff 内容が特定パターンにマッチする場合のみ発火」という絞り込み条件を持たせるか、この post-merge AC 自体を「該当欠陥を含む PR が review された際に限り評価する」形に見直すことを検討する価値がある

## Verify Retrospective (2026-08-06 re-run #2)

### Phase-by-Phase Review

#### verify
- 本 Issue の `/verify` は `/review --light` (PR #1190, Issue #1186) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は前回判定から内容変更なく再度 PASS。Post-merge observation は fired 状態を再確認したが、今回の発火元 PR #1190 の diff (`docs/spec/issue-1186-*.md`, `skills/verify/SKILL.md`, `tests/verify.bats`) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず、前回 (2026-08-06 re-run) と同じ UNCERTAIN 判定に帰着した。上記「re-run」で既に記録済みの Improvement Proposal (fired 状態の恒久化・観測条件の絞り込み不足) がまさに想定どおり再現した事例であり、新規の観測事項はない

### Improvement Proposals
- N/A (上記「re-run」の Improvement Proposals を参照。新規提案なし — 再発の実測として記録するに留める)

## Verify Retrospective (2026-08-06 re-run #3)

### Phase-by-Phase Review

#### verify
- 本 Issue の `/verify` は `/review --light` (PR #1193, Issue #1185) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は既に `[x]` 済みのため already-checked skip rule により SKIPPED (再検証なし)。Post-merge observation は fired 状態を再確認したが、今回の発火元 PR #1193 の diff (`docs/spec/issue-1185-*.md`, `skills/issue/SKILL.md`, `skills/triage/skill-dev-verify-audit.md`, `tests/issue.bats`, および review 中の SHOULD fix `docs/tech.md`) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず、re-run / re-run #2 と同じ UNCERTAIN 判定に帰着した。同一の Improvement Proposal (fired 状態の恒久化・観測条件の絞り込み不足) が3回連続で再現しており、単発の偶発事象ではなく構造的な観測条件の設計不足であることが実測で裏付けられた

### Improvement Proposals
- 3回連続の再現により、「observation event の fired 状態が一度確定すると恒久化し、無関係な PR の `/review --light` 完了のたびに証拠不十分な UNCERTAIN 判定が繰り返される」問題は偶発ではなく構造的パターンと判断する。observation-trigger の event 定義に「diff 内容が特定パターン (CI/ワークフロー変更など) にマッチする場合のみ発火」という絞り込み条件を追加するか、この post-merge AC 自体を「該当欠陥を含む PR が review された際に限り評価する」形に見直すことを follow-up Issue として起票する価値がある水準に達した。判断は Step 16 (retro-proposals) に委ねる

## Verify Retrospective (2026-08-06 re-run #4)

### Phase-by-Phase Review

#### verify
- 本 Issue の `/verify` は `/review --light` (PR #1195, Issue #1076) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は既に `[x]` 済みのため already-checked skip rule により SKIPPED (再検証なし)。Post-merge observation は fired 状態を再確認したが、今回の発火元 PR #1195 の diff (`scripts/worktree-merge-push.sh`, `modules/orchestration-fallbacks.md`, `docs/spec/issue-1076-*.md`, `tests/worktree-merge-push.bats` — git merge/rebase fallback ロジックの変更) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず、re-run〜re-run #3 と同じ UNCERTAIN 判定に帰着した。**4回連続**の再現であり、`event=pr-review-light` が診断対象の PR diff 内容を一切問わず発火する設計であることが確定的に裏付けられた

### Improvement Proposals
- 4回連続の再現 (re-run〜re-run #3 に続く4件目) を受け、re-run #3 で「起票水準に達した」と判定した follow-up Issue を本 `/verify` の Step 16 (retro-proposals) で起票する方針だったが、Tier 1 分類後の freshness check (`modules/retro-proposals.md` Step 10) で `modules/observation-trigger.md` § Condition Check Gate (`keyword=`) を確認したところ、Issue #794 が同種の問題 (`event=pr-review-full` の無条件発火) 向けに導入済みの軽量プリフィルタ機構 (`--context-file` の内容に対する `keyword=` 大文字小文字非区別部分一致) がそのまま適用可能と判明した。新規の絞り込み機構を実装する必要はなく、本 Issue 自身の post-merge AC に `keyword=workflow` を追加するだけで解決するため、**新規 Issue は起票せず**、本 Issue の AC を直接更新した (Auto-Resolved Ambiguity Points 参照)。関連 Issue #1118 は route/mode/recovery-tier 系の実行文脈フィルタが scope であり、今回発見した `keyword=` (diff/Spec 内容ベースのフィルタ) とは別軸で共存する — 参考のため記録は残すが対応不要

## Verify Retrospective (2026-08-06 re-run #5)

### Phase-by-Phase Review

#### verify
- 本 `/verify` は `/review --light` (PR #1218、Issue #1082) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は既に `[x]` 済みのため already-checked skip rule により SKIPPED。Post-merge observation は fired 状態を再確認 (`pr-review-light` detected マーカーあり) したが、今回の発火元 PR #1218 の diff (`scripts/reconcile-phase-state.sh`, `modules/phase-state.md`, `tests/reconcile-phase-state.bats`, `docs/spec/issue-1082-*.md` — worktree の完了判定シグナル追加) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず UNCERTAIN 判定に帰着した。ここまでは re-run〜re-run #4 と同型の再現だが、本 re-run では新たな観測がある: re-run #4 で導入した `keyword=workflow` ゲートが、実際には Issue #1082 の Spec 本文中の "`docs/workflow.md`" というファイル名参照 (`docs/product.md` / `docs/tech.md` / `docs/workflow.md` / `docs/structure.md` を列挙した一文) に大文字小文字非区別で部分一致しただけで発火していたことを確認した。GitHub Actions ワークフローの内容とは無関係な誤発火であり、re-run #4 で「起票水準に達した問題を解決した」と判断した `keyword=` フィルタ自体が、ファイル名の部分文字列に反応する粗いマッチングであるという新しい構造的欠陥を持つことが判明した

### Improvement Proposals
- re-run #4 で追加した `keyword=workflow` ゲートは、`.github/workflows/` 配下のワークフロー内容ではなく「diff/Spec テキスト中に 'workflow' という文字列が (ファイル名の一部としてであっても) 出現するか」という表層一致でしか判定していない。本 Issue の Spec のようにドキュメントファイル名の列挙 (`docs/workflow.md`) に反応して誤発火するケースが実測で確認できたため、`keyword=` フィルタの設計そのもの (単純な部分文字列マッチ vs. ファイルパス変更を対象とした構造化マッチ、例えば `.github/workflows/*.yml` の変更有無を見る) を見直す価値があると考えられる。ただし本件は `keyword=workflow` 導入後の初回発生であり、re-run〜re-run #3 で適用した「3回連続再現で起票水準」の閾値には未到達 — Step 16 (retro-proposals) の Tier 1 分類・freshness check に判断を委ねる

## Verify Retrospective (2026-08-06 re-run #6)

### Phase-by-Phase Review

#### verify
- 本 `/verify` は `/review --light` (PR #1217、Issue #1206) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は既に `[x]` 済みのため already-checked skip rule により SKIPPED。Post-merge observation は fired 状態を再確認 (`pr-review-light` detected マーカー計6件) したが、今回の発火元 PR #1217 の diff (`scripts/run-merge.sh`, `skills/auto/SKILL.md`, `tests/auto.bats`, `tests/run-merge.bats`, `docs/spec/issue-1206-*.md` — pr route merge 後のローカル main 未追従検出・防止) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず UNCERTAIN 判定に帰着した。re-run #5 で確認した `keyword=workflow` ゲートの誤発火パターン (Spec 内 `docs/workflow.md` ファイル名参照への部分一致) が、本 Issue #1206 の Spec でも同じ列挙文 ("`docs/tech.md` / `docs/workflow.md`") に反応して**2件目**として再現した。1件のみだった re-run #5 と異なり、異なる Issue (#1082 → #1206) の Spec で同一の誤発火経路 (steering document 列挙文脈での `docs/workflow.md` 言及) が再現したことで、この経路が偶発ではなく反復可能なパターンであることが裏付けられた

### Improvement Proposals
- re-run #5 で発見した `keyword=workflow` ゲートの誤発火が、本 re-run #6 で異なる発火元 Issue (#1082 → #1206) においても**同一の経路** (Spec の「steering document に該当記述なし」を確認する列挙文中の `docs/workflow.md` ファイル名言及) で再現した。2件はいずれも `docs/tech.md` / `docs/workflow.md` 等の steering document パス列挙という共通パターンから発生しており、単発の偶然ではなく `keyword=` の部分文字列マッチ設計に起因する構造的な誤検知経路である可能性が高い。re-run #3 で採用した「3回連続再現で起票水準」の閾値には未到達 (2/3) だが、発火元が異なる Issue にわたって再現している点は re-run #2〜#4 (同一 event の無条件発火という単一パターンの反復) より一段階進んだ証拠強度を持つ。次回同型の誤発火が確認された場合は、閾値を待たずに起票を検討する価値がある — Step 16 (retro-proposals) の Tier 1 分類・freshness check に判断を委ねる

## Verify Retrospective (2026-08-06 re-run #7)

### Phase-by-Phase Review

#### verify
- 本 `/verify` は `/review --light` (PR #1232、Issue #1164) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は既に `[x]` 済みのため already-checked skip rule により SKIPPED。Post-merge observation は fired 状態を再確認 (`pr-review-light` detected マーカーあり) したが、今回の発火元 PR #1232 の diff (`docs/reports/manual-ac-retype-d2.md` 新規追加、`docs/spec/issue-1164-*.md` retrospective/handoff 追記のみ — ドキュメントのみの変更) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず UNCERTAIN 判定に帰着した。`keyword=workflow` ゲートの誤発火パターン (re-run #5: `docs/workflow.md`／Issue #1082、re-run #6: `docs/workflow.md`／Issue #1206) が、本 Issue #1164 の Spec 内 `docs/translation-workflow.md` というファイル名参照への部分一致で**3件目**として再現した。re-run #6 で「次回同型の誤発火が確認された場合は、閾値を待たずに起票を検討する価値がある」とした条件に該当する

### Improvement Proposals
- `keyword=workflow` ゲートの誤発火が異なる発火元 Issue (#1082 → #1206 → #1164) にわたって**3件連続**で再現した。いずれも `docs/workflow.md` / `docs/translation-workflow.md` のような、GitHub Actions ワークフローとは無関係なファイルパス文字列への部分一致が原因であり、単純な部分文字列マッチ設計 (`modules/observation-trigger.md` § Condition Check Gate) の構造的欠陥であることが確定的に裏付けられた。re-run #3 で採用した「3回連続再現で起票水準」の閾値を満たしたため、Step 16 (retro-proposals) で follow-up Issue の起票を検討する。改善方向性の候補: `keyword=` を単純な部分文字列マッチから `.github/workflows/*.yml` 等の実際のファイルパス変更を対象とした構造化マッチへ置き換える、または `keyword=` に単語境界 (word boundary) を要求する

## Verify Retrospective (2026-08-07 re-run #8)

### Phase-by-Phase Review

#### verify
- 本 `/verify` は `/review --light` (PR #1235、Issue #1108) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は既に `[x]` 済みのため already-checked skip rule により SKIPPED。Post-merge observation は fired 状態を再確認 (`pr-review-light` detected マーカーあり) したが、今回の発火元 PR #1235 の diff (`scripts/run-auto-sub.sh`, `skills/auto/SKILL.md`, `skills/issue/SKILL.md`, `tests/run-auto-sub.bats`, `docs/spec/issue-1108-*.md` — batch/XL 経路の spec dispatch を Size 判定込みで Step 3 と一致させる修正) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず UNCERTAIN 判定に帰着した。`keyword=workflow` ゲートの誤発火パターン (re-run #5: `docs/workflow.md`／Issue #1082、re-run #6: `docs/workflow.md`／Issue #1206、re-run #7: `docs/translation-workflow.md`／Issue #1164) が、本 Issue #1108 の Spec 内 `docs/workflow.md:52,113` というファイルパス参照への部分一致で**4件目**として再現した。follow-up Issue #1220 (`observation-trigger: keyword= フィルタのファイル名部分一致誤検知を解消`) が既に起票済み (OPEN) であることを確認したため、本 re-run では重複起票を行わない

### Improvement Proposals
- N/A — re-run #7 で「起票水準に達した」問題は follow-up Issue #1220 として既に起票済み (確認済み)。本 re-run はその後に発生した4件目の再現事例として記録するに留め、新規提案は行わない。Issue #1220 の解決後、本 post-merge observation AC が実際に「決定的失敗が MUST 判定される」挙動を実地確認できるかは引き続き未検証のまま — #1220 のクローズ後に改めて `/review --light` が CI/ワークフロー変更を含む PR で完了するタイミングで再評価される見込み

## Verify Retrospective (2026-08-07 re-run #9)

### Phase-by-Phase Review

#### verify
- 本 `/verify` は `/review --light` (PR #1237、Issue #1167) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は既に `[x]` 済みのため already-checked skip rule により SKIPPED。Post-merge observation は fired 状態を再確認 (`pr-review-light` detected マーカーあり) したが、今回の発火元 PR #1237 の diff (`docs/reports/manual-ac-retype-c-d1.md`, `docs/spec/issue-1167-manual-ac-retype-c-d1.md`, `tests/wait-ci-checks.bats`, `tests/check-pre-merge-ac.bats` — manual AC 区分 C の bats テスト化) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず UNCERTAIN 判定に帰着した。`keyword=workflow` ゲートの誤発火パターンが、本 Issue #1167 の Spec 内 `docs/translation-workflow.md` / `modules/size-workflow-table.md` というファイルパス参照への部分一致で **9件目** として再現した。follow-up Issue #1220 が既に起票済み (OPEN) であることを確認したため、本 re-run でも重複起票を行わない

### Improvement Proposals
- N/A — re-run #7 で既に起票水準に達し follow-up Issue #1220 が対応済み。本 re-run はその後の9件目の再現事例として記録するに留める

## Verify Retrospective (2026-08-07 re-run #10)

### Phase-by-Phase Review

#### verify
- 本 `/verify` は `/review --light` (PR #1244、Issue #1117) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は既に `[x]` 済みのため already-checked skip rule により SKIPPED。Post-merge observation は fired 状態を再確認 (`pr-review-light` detected マーカーあり) したが、今回の発火元 PR #1244 の diff (`scripts/reconcile-phase-state.sh`, `modules/phase-state.md`, `tests/reconcile-phase-state.bats`, `docs/spec/issue-1117-*.md` — `_completion_issue()` の成功シグネチャ修正) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず UNCERTAIN 判定に帰着した。`keyword=workflow` ゲートの誤発火パターンが、本 Issue #1117 の Spec 内 `docs/workflow.md` というファイルパス参照 (Steering Docs sync candidate 確認の一文) への部分一致で **10件目** として再現した。follow-up Issue #1220 が依然 OPEN であることを確認したため、本 re-run でも重複起票を行わない

### Improvement Proposals
- N/A — re-run #7 で既に起票水準に達し follow-up Issue #1220 が対応済み (未クローズ)。本 re-run はその後の10件目の再現事例として記録するに留める

## Verify Retrospective (2026-08-07 re-run #11)

### Phase-by-Phase Review

#### verify
- 本 `/verify` は `/review --light` (PR #1253、Issue #1221) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は既に `[x]` 済みのため already-checked skip rule により SKIPPED。Post-merge observation は fired 状態を再確認 (`pr-review-light` detected マーカーあり) したが、今回の発火元 PR #1253 の diff (`scripts/detect-wrapper-anomaly.sh`, `modules/orchestration-fallbacks.md`, `skills/auto/SKILL.md`, `tests/detect-wrapper-anomaly.bats` — CI 待機由来の watchdog kill を独立パターンとして切り出す変更) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず UNCERTAIN 判定に帰着した。`keyword=workflow` ゲートの誤発火パターンが、本 Issue #1221 の Spec 内 `.github/workflows/test.yml` というファイルパス参照 (CI ジョブ名確認の一文) への部分一致で **11件目** として再現した。follow-up Issue #1220 が依然 OPEN であることを確認したため、本 re-run でも重複起票を行わない

### Improvement Proposals
- N/A — re-run #7 で既に起票水準に達し follow-up Issue #1220 が対応済み (未クローズ)。本 re-run はその後の11件目の再現事例として記録するに留める

## Verify Retrospective (2026-08-07 re-run #12)

### Phase-by-Phase Review

#### verify
- 本 `/verify` は `/review --light` (PR #1254、Issue #1064) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は既に `[x]` 済みのため already-checked skip rule により SKIPPED。Post-merge observation は fired 状態を再確認 (`pr-review-light` detected マーカーあり) したが、今回の発火元 PR #1254 の diff (`docs/reports/opus-5-effort-recalibration-spec.md` 新規、`docs/tech.md`/`docs/ja/tech.md`/`docs/spec/issue-1064-*.md` 更新 — ドキュメントのみの変更) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず UNCERTAIN 判定に帰着した。`keyword=workflow` ゲートの誤発火パターンが、本 Issue #1064 の Spec 内 `docs/translation-workflow.md` というファイル名参照 (翻訳ミラー除外規約の一文) への部分一致で **12件目** として再現した。follow-up Issue #1220 が依然 OPEN であることを確認したため、本 re-run でも重複起票を行わない
- worktree セッション中に `source` 経由の `emit-event.sh` 呼び出し (Step 11 の `phase_complete` イベント発行) が worktree isolation guard によりブロックされた。`modules/worktree-lifecycle.md` § "source-based shell function calls are blocked by the worktree isolation guard" に記載済みの既知制約どおり、自然な exit 境界 (Step 13 Worktree Exit) がまだ先だったため best-effort でスキップし、その旨を明示的に記録した

### Improvement Proposals
- N/A — re-run #7 で既に起票水準に達し follow-up Issue #1220 が対応済み (未クローズ)。本 re-run はその後の12件目の再現事例として記録するに留める

## Verify Retrospective (2026-08-07 re-run #13)

### Phase-by-Phase Review

#### verify
- 本 `/verify` は `/review --light` (PR #1258、**Issue #1220 自身**) の Event-based observation scan から dispatch された再実行。Pre-merge 2 件は既に `[x]` 済みのため already-checked skip rule により SKIPPED。Post-merge observation は fired 状態を再確認 (`pr-review-light` detected マーカーあり) したが、今回の発火元 PR #1258 の diff (`scripts/opportunistic-search.sh`, `modules/observation-trigger.md`, `tests/opportunistic-search.bats` — `keyword=` ゲート自体のパス様トークン除外修正) にも CI/ランナー環境で決定的に失敗する設定ミスは含まれておらず UNCERTAIN 判定に帰着した。`keyword=workflow` ゲートの誤発火パターンが **13件目** として再現したが、今回は発火源が Issue #1220 自身の Spec (`docs/spec/issue-1220-keyword-gate-path-fp-fix.md`) であり、内容の大半がパス様トークン (`docs/workflow.md`, `.github/workflows/ci.yml`) であることに加え、`keyword=workflow` という**属性構文そのもの** (スラッシュを含まないため #1220 のパス様トークン除外の対象外) も一致要因に含まれる点で過去12件と異なる。follow-up Issue #1220 は本 PR #1258 でパス様トークン除外を実装済み (pre-merge AC 全3件 PASS、CI 全SUCCESS) だが、まだ main に merge されていないため、今回発火に使われた `opportunistic-search.sh`/`observation-trigger.sh` は main 上の旧実装 (修正前) のまま実行された

### Improvement Proposals
- 13件目の再現は、#1220 のパス様トークン除外だけでは解消しない新しい亜種 (`keyword=<value>` のような、スラッシュを含まない属性構文自体への一致) を示している。ただし本件は Issue #1220 自身の Spec という特殊事例 (#1220 が merge されれば当該 Spec ファイルが `--context-file` として再利用される機会は事実上ない) であり、一般的な PR で `keyword=workflow` という文字列がスラッシュなしで地の文に出現するケースは稀 (実際に過去12件はすべて `docs/*.md` 等のパス様トークンが原因だった)。#1220 merge 後、次回以降の `/review --light` でパス様トークン起因の誤発火 (13件中12件のパターン) が解消するかどうかが本 post-merge AC の主眼であり、この観測は #1220 の post-merge AC (`docs/workflow.md` 等の無関係パスのみを参照する PR での誤発火なし観察) 側で追跡する。新規 follow-up Issue の起票は不要と判断する

