# Issue #41: kanban: Fix option_id mapping and unify automation to label-only

## Issue Retrospective

### Ambiguity Resolution

- **自動化方針**: ユーザーが「ラベル一元化」を選択。Default Workflows を全て OFF にし、kanban-automation.yml のみでカラム移動を制御する。競合の根本解消。
- **option_id の入れ替わり原因**: Projects のカラム追加順序により Review と Verify の option_id が直感と異なる順序になっていた可能性。Projects API で正しい値を確認済み。

### Key Decisions

- Default Workflows の OFF 設定は手動操作（GitHub UI）が必要。Post-merge の manual 条件として記載。
- `Item closed` と `Item reopened` は元々 OFF なので変更不要。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue Retrospective に自動化方針と option_id の正しいマッピングが明確に記載されており、受け入れ条件も具体的なgrep検証コマンドが付いていた。ambiguity resolution が的確。
- Post-merge の manual 条件（Default Workflows OFF）は手動確認前提で正しく分類されている。

#### design
- N/A（Spec ファイル自体がシンプルな fix issue であり、設計セクションなし）

#### code
- 実装は単一コミット (`121063a`) で完了。fixup/amend パターンなし。変更ファイルは `.github/workflows/kanban-automation.yml` のみ。
- シンプルなワークフロー修正であり、リワークなし。

#### review
- PRなし（patch ルート）。コードレビューフェーズはスキップ。

#### merge
- main への直接コミット（patch ルート）。コンフリクトなし。

#### verify
- Pre-merge 全4条件がPASS。grep ベースの検証で確実に自動判定できた。
- Post-merge 条件（opportunistic/manual）は未チェック。`phase/verify` ラベルを付与してユーザー確認待ち状態に移行。

### Improvement Proposals
- N/A
