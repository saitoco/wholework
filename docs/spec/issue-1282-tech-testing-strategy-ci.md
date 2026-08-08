# Issue #1282: docs: tech.md Testing Strategy に CI の並列/直列切り分けを反映

## Issue Retrospective

### Autonomous Auto-Resolve Log

- **`docs/ja/tech.md` の翻訳同期を Pre-merge AC から除外** — reason: 元の AC4 (`<!-- verify: rubric "docs/ja/tech.md の Testing Strategy 相当セクションにも同内容が反映されている (翻訳同期)" -->`) は `docs/{lang}/` 配下を verify command 対象から除外する `/issue` の Translation document exclusion ルールに抵触していた。加えて #1062 で **同一ファイル** (`docs/tech.md` → `docs/ja/tech.md`) について同じ除外判断が既に記録されており (`docs/translation-workflow.md` の一般 sync procedure より個別 triage 判断を優先)、precedent と rule の双方が同じ結論を指していたため auto-resolve した。
  - Other candidates: AC4 を維持する (rubric + section_contains の組み合わせで機械検証を強化する) — 却下。`docs/ja/tech.md` は `/doc translate` / `translation-workflow.md` の sync procedure が別途担保する対象であり、Issue 個別の AC として重複管理するのは precedent (#1062) と矛盾する。

### Acceptance Criteria の変更理由

- Pre-merge から AC4 (`docs/ja/tech.md` 翻訳反映の rubric) を削除。上記 Auto-Resolve Log の通り。
- Notes セクションに除外理由 (Translation document exclusion ルール + #1062 precedent) を追記し、Related に #1062 を追加した。
- AC1〜AC3 (英語版 `docs/tech.md` 側の内容検証) は変更なし。

### その他の判断

- Background の事実主張 (`.github/workflows/test.yml` の並列/直列切り分け構成) は `.github/workflows/test.yml:28-40` の実装と一致していることを確認済み (警告なし)。
- `docs/tech.md` の Testing Strategy セクション記載も Background の引用内容と一致していることを確認済み。

## Consumed Comments
No new comments since last phase.
