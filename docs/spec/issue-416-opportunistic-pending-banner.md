# Issue #416: auto: opportunistic-pending banner で未チェック post-merge 条件を列挙

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec ファイルは Code Retrospective のみで最小構成。Issue body の "Auto-Resolved Ambiguity Points" が実質的に設計決定を担っており、verify コマンドの信頼性（`"post-merge"` → `"and N more"`）・表示形式・AC2 補足の3点が事前解決された。Issue 品質として適切。

#### design
- 専用設計ドキュメントなし（Spec は実装の記録のみ）。Purpose セクションに表示形式（HTML コメント除去・`- [ ]` prefix 除去）が明記され、実装上の曖昧さが解消されていた。

#### code
- Code Retrospective は全 N/A。実装は1コミットで完結し、rework・fixup なし。

#### review
- patch ルート（PR なし）のため正式なコードレビューなし。pre-merge verify コマンドが設計の代替検証として機能した。

#### merge
- patch ルートで main へ直接コミット。コンフリクトなし。

#### verify
- Pre-merge 2 条件ともに PASS。verify コマンドの選定（`"and N more"` による実装後確実マッチ）が効果的に機能した。Post-merge manual 条件 1 件は実行環境依存のため手動確認待ち（期待通り）。

### Improvement Proposals
- N/A
