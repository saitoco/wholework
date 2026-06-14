# Issue #476: review: CI/ランナー環境で決定的に失敗する設定ミスを MUST に分類する基準を明文化

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

