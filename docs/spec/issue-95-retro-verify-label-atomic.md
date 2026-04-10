# Issue #95: verify: retro/verify ラベルを gh issue create --label で付与に変更

## Issue Retrospective

### Judgment Rationale
- Pre-merge 条件 2 の acceptance check を修正: `section_not_contains` は固定文字列マッチングのため、`.*` を含むパターンは常に PASS してしまう。実際の SKILL.md テキスト `gh issue edit {issue_number} --add-label` に合わせた `file_not_contains` に変更
- `gh label create` の事前チェックは維持する判断: `gh issue create --label` はラベル未存在時にエラーになるため、削除対象は `gh issue edit --add-label` のみ

### Key Decisions
- Nothing to note

### Acceptance Criteria Changes
- Pre-merge 条件 2: `section_not_contains` + regex-like pattern → `file_not_contains` + 固定文字列に修正（false positive 防止）
- Purpose に `gh label create` 維持の方針を明記
