# Issue #39: verify: Fix phase/done label transition reliability in patch route

## Issue Retrospective

### Ambiguity Resolution

- **根本原因の特定**: タイムライン分析で verify スキルの Step 9 ロジック自体は正しいことを確認（#34 が正常動作）。問題は verify 実行の中断またはラベル遷移コマンドの失敗。
- **kanban-automation vs verify スキル**: kanban-automation.yml はラベルイベントでカラムを移動するだけで、ラベル付与自体は verify スキルの責務。問題は kanban 側ではなく verify 側にある。

### Key Decisions

- 暫定対処として #33 に `phase/done`（`phase/verify` を除去）、#35 に `phase/done` を手動付与
- #37（permission プロンプト）が verify 中断の原因である可能性が高い。#37 の解決で本問題も解消する可能性がある

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue Retrospective に根本原因の分析が詳細に記録されており、問題の切り分けが明確（#33/#35 の複合問題を2つに分解している）。
- Acceptance criteria の `--when="test -f tests/gh-label-transition.bats"` 条件で bats ファイルの存在を前提にした柔軟な設計になっている。

#### design
- Spec ファイルに Spec Retrospective セクションなし（パッチルートでの簡略実装）。
- 変更スコープが明確：`scripts/gh-label-transition.sh` の冪等性確保と対応 bats テストの追加のみ。

#### code
- 1コミット (`bbfea69`) でパッチルート実装。`gh-label-transition.sh` に38行の変更、`tests/gh-label-transition.bats` に46行追加（75行合計で十分な規模）。
- 実装が clean で rework なし（fixup/amend なし）。

#### review
- パッチルートのためコードレビューなし。bats テスト12件（正常系・エラー系・冪等性テスト）によってコード品質を担保。

#### merge
- パッチルート（直接 main へコミット）。コンフリクトなし。

#### verify
- Pre-merge の全3条件が PASS。特に bats テスト #11/#12 で冪等性を直接検証している。
- Post-merge の2条件（opportunistic/manual）はユーザー検証待ち。

### Improvement Proposals
- N/A
