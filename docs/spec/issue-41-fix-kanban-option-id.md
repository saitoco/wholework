# Issue #41: kanban: Fix option_id mapping and unify automation to label-only

## Issue Retrospective

### Ambiguity Resolution

- **自動化方針**: ユーザーが「ラベル一元化」を選択。Default Workflows を全て OFF にし、kanban-automation.yml のみでカラム移動を制御する。競合の根本解消。
- **option_id の入れ替わり原因**: Projects のカラム追加順序により Review と Verify の option_id が直感と異なる順序になっていた可能性。Projects API で正しい値を確認済み。

### Key Decisions

- Default Workflows の OFF 設定は手動操作（GitHub UI）が必要。Post-merge の manual 条件として記載。
- `Item closed` と `Item reopened` は元々 OFF なので変更不要。
