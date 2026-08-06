# Issue #476: review: CI/ランナー環境で決定的に失敗する設定ミスを MUST に分類する基準を明文化

## Consumed Comments

- saito / MEMBER / first-class / 2026-06-14 時点の前回 `/verify 476` 実行結果 (Pre-merge 2 件 PASS、Post-merge observation は event 未発火で SKIPPED) / https://github.com/saitoco/wholework/issues/476#issuecomment-4703192688
- saito / MEMBER / first-class / `/review --light` (PR #1189) 完了に伴い observation event `pr-review-light` が発火した旨の通知 / https://github.com/saitoco/wholework/issues/476#issuecomment-5199934979

### verify フェーズ (2026-08-06 re-run #2, cutoff: 2026-06-14T21:50:38Z)

- saito / MEMBER / first-class / 前回 `/verify 476` (2026-08-06 re-run) 実行結果。Pre-merge 2 件 PASS、Post-merge observation (event=pr-review-light) は PR #1189 の diff に該当欠陥なしのため UNCERTAIN / https://github.com/saitoco/wholework/issues/476#issuecomment-5199963258

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/476#issuecomment-5200100852
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

