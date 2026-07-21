# Issue #1031: skills/issue: Step 12a の parallel subagent が pane に残る (自動停止未実装)

## Issue Retrospective

### 曖昧性解消の判断根拠

非対話モード (`--non-interactive`) で自動解決した 3 点:

1. **スコープ**: 本 Issue は `/issue` (skills/issue/SKILL.md) の Step 12a/12b に限定した。同一の `SendMessage(to="main")` 型 parallel-investigation pattern は調査時点で `skills/issue/SKILL.md` 以外に存在しないことを確認したため、Related に記載されていた「他 skill への横展開」は本 Issue のスコープ外として明記し、follow-up 候補として保留した。
2. **TaskStop 呼び出しタイミング**: AC は「Step 12a または Step 12b」と両論併記されていたが、各 subagent の結果受信直後 (3体を待たず個別に停止) を推奨方針として Auto-Resolved セクションに記録した。全体を待って一括停止するより pane 残留時間を最小化できるため。
3. **技術的前提の明記**: `TaskStop` ツールのスキーマを確認したところ、`task_id` は agent 名または `name@team` 形式の ID を受け付ける仕様だが、現状の Step 12a の `Agent()` 呼び出しには `name:` パラメータが指定されていない。このままでは main 側が個別の subagent を指し示して停止できないため、実装時に `name:` の明示が必要という技術的前提を Background に追記した。

### Q&A で決まった主要な方針

なし (AskUserQuestion は非対話モードのため未使用。上記はすべてモデル判断による自動解決)。

### Acceptance Criteria 変更理由

- Pre-merge AC に `file_contains "skills/issue/SKILL.md" "TaskStop"` を追加。既存 2 件の `rubric` AC の意味的判定を補助する機械的チェックとして、`docs/environment-adaptation.md` の rubric + supplementary パターンに従った。AC のテキスト自体 (rubric の内容) は変更していない。

### Scope Assessment

Size=XS のため sub-issue 分割の対象外。非対話モードのため該当ステップ自体もスキップ (High-Stakes Decision)。

## Consumed Comments
No new comments since last phase.
