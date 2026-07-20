# Issue #1024: issue: コード変更を伴わない運用系 Issue への implementation-type: metadata-only マーカー付与を追加

## Issue Retrospective

`/issue 1024 --non-interactive` 実行時の判断記録。

### Triage 結果

Type=Feature, Size=XS (対象は skills/issue/SKILL.md 1ファイル), Value=2 (Impact=0: 他 Issue からの blocking/mention なし, Alignment=3: product.md Vision「verifies that the delivered artifact matches the acceptance criteria after merge」に直接関連する verification harness の正確性改善)。Priority は本文/タイトルから未検出のため未設定。重複候補・停滞パターン・未解決 blocked-by なし。

### Ambiguity 自動解決 (3件)

Size XS のため検出上限3件。すべて自動解決 (根拠: 既存コードベースパターンから一意に推測可能、かつ選択によって AC 文言が変わらない)。

1. **付与基準の具体的定義**: `modules/size-workflow-table.md` §「Diff-less Axis (operate route)」が既に「リポジトリファイル変更なし・外部ツール操作のみ」という同種の判定条件を Spec レベルで定義済み。これを `/issue` 時点 (Spec 未作成) で参照可能な情報 — Post-merge 全 AC が `verify-type: manual`/`opportunistic` で外部サービス/GitHub メタデータ操作を記述し、かつ Pre-merge にリポジトリファイル対象の verify command が皆無 — に翻案する形で解決。Issue #645 の Spec retrospective (`docs/spec/issue-645-rollup-trigger-design.md`) に記録された「Size XS かつ AC が manual 中心」という過去提案とも整合する。
2. **付与方法 (自動 vs 提案)**: Purpose 原文の「付与する (または付与を提案する)」という二択を「付与する」(自動付与、AskUserQuestion 確認なし) に確定。理由: Issue 本文への HTML コメント追加は低リスク・冪等・可逆であり、既存の pre-merge/post-merge 分類や verify-type タグ付けも同様に確認なしで自動適用されている既存パターンと整合するため。
3. **適用範囲**: New Issue Creation / Existing Issue Refinement の両フローに適用と判断。Existing Issue Refinement の AC 分類ステップは既に New Issue Creation 側の手続きを全面参照する構造のため、実装時に判断基準を一箇所追加すれば両フローに自然に反映される設計が可能。

### Issue 本文の変更

- Acceptance Criteria を `### Pre-merge (auto-verified)` / `### Post-merge` に区分 (両 AC とも grep/rubric によるファイル内容検証のため Pre-merge に分類、Post-merge は「なし」)。AC の内容自体は変更なし。
- Purpose 文中の「(または付与を提案する)」を削除し、上記 Ambiguity 解決 #2 の決定を反映。
- Background に Issue #645 の先行提案への参照を追加 (実装時の参考情報として)。
- 上記 3 点の自動解決内容を Issue 本文に「## Auto-Resolved Ambiguity Points」として記録。

### Note

本 Issue 自体は `skills/issue/SKILL.md` の実装変更を要求するものだが、`/issue` skill の責務は Issue のリファインメントに限られ、実装は `/spec` → `/code` の責務。今回の Retrospective に記録した設計方針 (付与基準・適用範囲) は次フェーズでの参考情報として残す。

## Consumed Comments

No new comments since last phase.
