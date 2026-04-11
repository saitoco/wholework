# Issue #54: agents: ネーミング整理

## Overview

investigation 系エージェント 3 ファイルの `-agent` サフィックスを削除し、`{skill}-{aspect}` パターン（`issue-*`）にリネームする。`review-*` 系エージェントとの命名規則統一が目的。

| Before | After |
|--------|-------|
| `scope-agent` | `issue-scope` |
| `risk-agent` | `issue-risk` |
| `precedent-agent` | `issue-precedent` |

## Changed Files

- `agents/scope-agent.md` → `agents/issue-scope.md`: rename + `name:` frontmatter update + line 77 self-reference update
- `agents/risk-agent.md` → `agents/issue-risk.md`: rename + `name:` frontmatter update
- `agents/precedent-agent.md` → `agents/issue-precedent.md`: rename + `name:` frontmatter update
- `skills/issue/SKILL.md`: change `subagent_type` values (lines 309, 312, 315)
- `docs/tech.md`: change inline text (line 49) + matrix entries (lines 80-82)
- `docs/structure.md`: change agent table rows (lines 97-99)
- `docs/ja/tech.md`: change inline text (line 38) + matrix entries (lines 69-71)
- `docs/ja/structure.md`: change agent table rows (lines 89-91)
- `docs/migration-notes.md`: change agent name labels (lines 277-279)
- `docs/ja/migration-notes.md`: change agent name labels (lines 270-272)

## Implementation Steps

1. Rename agent files via `git mv` and update frontmatter `name:` field + internal self-reference in `issue-scope.md` (→ acceptance criteria 1-9)
   - `git mv agents/scope-agent.md agents/issue-scope.md`
   - `git mv agents/risk-agent.md agents/issue-risk.md`
   - `git mv agents/precedent-agent.md agents/issue-precedent.md`
   - Edit each file: `name: scope-agent` → `name: issue-scope` etc.
   - Edit `agents/issue-scope.md` line 77: `agents/scope-agent.md` → `agents/issue-scope.md`
2. Update `skills/issue/SKILL.md` `subagent_type` values (→ acceptance criteria 10-15)
   - Line 309: `subagent_type="scope-agent"` → `subagent_type="issue-scope"`
   - Line 312: `subagent_type="risk-agent"` → `subagent_type="issue-risk"`
   - Line 315: `subagent_type="precedent-agent"` → `subagent_type="issue-precedent"`
3. Update Steering Documents: `docs/tech.md` + `docs/structure.md` (→ acceptance criteria 16-19)
   - `docs/tech.md` line 49: inline agent name references
   - `docs/tech.md` lines 80-82: matrix table Component column
   - `docs/structure.md` lines 97-99: agent table (Agent column + Path column)
4. Update Japanese translations: `docs/ja/tech.md` + `docs/ja/structure.md` (parallel with 3)
   - `docs/ja/tech.md` line 38: inline agent name references
   - `docs/ja/tech.md` lines 69-71: matrix table Component column
   - `docs/ja/structure.md` lines 89-91: agent table
5. Update migration notes: `docs/migration-notes.md` + `docs/ja/migration-notes.md` (parallel with 3, 4)
   - `docs/migration-notes.md` lines 277-279: agent name labels
   - `docs/ja/migration-notes.md` lines 270-272: agent name labels

## Verification

### Pre-merge

- <!-- verify: file_exists "agents/issue-scope.md" --> `agents/issue-scope.md` が存在する
- <!-- verify: file_exists "agents/issue-risk.md" --> `agents/issue-risk.md` が存在する
- <!-- verify: file_exists "agents/issue-precedent.md" --> `agents/issue-precedent.md` が存在する
- <!-- verify: file_not_exists "agents/scope-agent.md" --> `agents/scope-agent.md` が削除されている
- <!-- verify: file_not_exists "agents/risk-agent.md" --> `agents/risk-agent.md` が削除されている
- <!-- verify: file_not_exists "agents/precedent-agent.md" --> `agents/precedent-agent.md` が削除されている
- <!-- verify: file_contains "agents/issue-scope.md" "name: issue-scope" --> `agents/issue-scope.md` のフロントマター `name` が `issue-scope` に更新されている
- <!-- verify: file_contains "agents/issue-risk.md" "name: issue-risk" --> `agents/issue-risk.md` のフロントマター `name` が `issue-risk` に更新されている
- <!-- verify: file_contains "agents/issue-precedent.md" "name: issue-precedent" --> `agents/issue-precedent.md` のフロントマター `name` が `issue-precedent` に更新されている
- <!-- verify: grep "issue-scope" "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` の `subagent_type` が `issue-scope` に更新されている
- <!-- verify: grep "issue-risk" "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` の `subagent_type` が `issue-risk` に更新されている
- <!-- verify: grep "issue-precedent" "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` の `subagent_type` が `issue-precedent` に更新されている
- <!-- verify: file_not_contains "skills/issue/SKILL.md" "scope-agent" --> `skills/issue/SKILL.md` から旧名 `scope-agent` が完全に除去されている
- <!-- verify: file_not_contains "skills/issue/SKILL.md" "risk-agent" --> `skills/issue/SKILL.md` から旧名 `risk-agent` が完全に除去されている
- <!-- verify: file_not_contains "skills/issue/SKILL.md" "precedent-agent" --> `skills/issue/SKILL.md` から旧名 `precedent-agent` が完全に除去されている
- <!-- verify: section_contains "docs/tech.md" "## Architecture Decisions" "issue-scope" --> `docs/tech.md` のモデル・エフォートマトリクスが新名に更新されている
- <!-- verify: section_not_contains "docs/tech.md" "## Architecture Decisions" "scope-agent" --> `docs/tech.md` から旧名 `scope-agent` が除去されている
- <!-- verify: section_contains "docs/structure.md" "### Agents" "issue-scope" --> `docs/structure.md` のエージェント表が新名に更新されている
- <!-- verify: section_not_contains "docs/structure.md" "### Agents" "scope-agent" --> `docs/structure.md` から旧名 `scope-agent` が除去されている

### Post-merge

(なし)

## Notes

- Spec ファイル（`docs/spec/`）は使い捨て方針のため更新対象外。grep ヒットファイル: `issue-108-effort-matrix.md`, `issue-18-agents-migration.md`, `issue-94-acceptance-check-replacement.md`
- `docs/ja/*` は翻訳出力のため verify command 対象外だが、実装では更新する
- `docs/migration-notes.md` は歴史的記録だが、エージェント名ラベルは現在の名前に合わせて更新する（検索性のため）
- 各エージェントの `description` フロントマターフィールドには `-agent` を含む文字列がないため変更不要
- Post-replacement scan: 冠詞変更不要（agent 名は固有名詞的に使用）、複合語の重複なし、日英境界スペースも影響なし

### Grep hit counts

| Old name | Hit count (excl. spec/) |
|----------|----------------------|
| `scope-agent` | 10 files |
| `risk-agent` | 8 files |
| `precedent-agent` | 8 files |

## Code Retrospective

### Deviations from Design

- N/A（Specの実装ステップ通りに実施）

### Design Gaps/Ambiguities

- `docs/spec/`ファイル（`issue-108-effort-matrix.md`等）にも旧名が残っているが、Specは使い捨て方針のため対象外とした。Issue本文のScopeセクションに明記済み。

### Rework

- N/A
