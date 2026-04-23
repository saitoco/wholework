# Issue #95: verify: retro/verify ラベルを gh issue create --label で付与に変更

## Issue Retrospective

### Judgment Rationale
- Pre-merge 条件 2 の verify command を修正: `section_not_contains` は固定文字列マッチングのため、`.*` を含むパターンは常に PASS してしまう。実際の SKILL.md テキスト `gh issue edit {issue_number} --add-label` に合わせた `file_not_contains` に変更
- `gh label create` の事前チェックは維持する判断: `gh issue create --label` はラベル未存在時にエラーになるため、削除対象は `gh issue edit --add-label` のみ

### Key Decisions
- Nothing to note

### Acceptance Criteria Changes
- Pre-merge 条件 2: `section_not_contains` + regex-like pattern → `file_not_contains` + 固定文字列に修正（false positive 防止）
- Purpose に `gh label create` 維持の方針を明記

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec は作成されていないが、Issue Retrospective で verify command の `section_not_contains` から `file_not_contains` への修正を事前に実施済み。検証精度の向上につながった。

#### design
- N/A（このIssueは設計フェーズなし）

#### code
- コミット `45c3610` の単一コミットで完結。fixup/amend なし。変更は `skills/verify/SKILL.md` のみで、8 行追加・17 行削除とコンパクト。`gh issue create --label` への統合と `gh issue edit --add-label` の削除が正確に実施されている。

#### review
- PR なし（patch ルートで直接 main へコミット）。レビューは省略。小さな変更で影響範囲が明確なため適切な判断。

#### merge
- 直接 main へのコミット。コンフリクトなし、CI 問題なし。

#### verify
- 条件 1・2（Pre-merge）はどちらも PASS。条件 3（Post-merge opportunistic）はユーザー検証項目として提示。
- Post-merge の opportunistic 条件が残っているため `phase/verify` ラベルを付与した。

### Improvement Proposals
- N/A
