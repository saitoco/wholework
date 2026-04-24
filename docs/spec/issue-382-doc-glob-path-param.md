# Issue #382: skills/doc SKILL.md の Glob `**/*.md` に path パラメータを明示

## Overview

`skills/doc/SKILL.md` の `--deep` フラグ実装ステップ（line 333）に `Search with Glob \`**/*.md\`` という記述があり、`path` パラメータが明示されていない。CWD に依存するため、`modules/filesystem-scope.md` が禁止するパターン（`Glob("**/*.md")` without `path` argument）に該当する。同ファイル内の他 Glob 呼び出しと整合させるため、`path: "."` を明示する形式に書き換える。

## Changed Files

- `skills/doc/SKILL.md`: line 333 の `Search with Glob \`**/*.md\` and skip files...` を `path: "."` 明示形式に書き換え

## Implementation Steps

1. `skills/doc/SKILL.md` line 333 を以下のように変更する（→ 受け入れ基準 1, 2）:
   - 変更前: `Search with Glob \`**/*.md\` and skip files matching these exclusion conditions:`
   - 変更後: `Use Glob \`**/*.md\` with \`path: "."\` and skip files matching these exclusion conditions:`

## Verification

### Pre-merge

- <!-- verify: file_not_contains "skills/doc/SKILL.md" "Search with Glob `**/*.md`" --> 333 行目の `Search with Glob \`**/*.md\`` がパス明示形式（例: `Glob "**/*.md" with path: "."`）に書き換えられている
- <!-- verify: file_contains "skills/doc/SKILL.md" "path" --> 該当 Glob 呼び出しで `path` パラメータが明示されている

### Post-merge

- `/doc --deep` 実行時に該当 Glob の挙動が従来と同等であることを確認 <!-- verify-type: manual -->

## Notes

- Issue body で「305行目、444行目は `docs/**/*.md` のようにベースパスを明示」とあるが、実際の 305 行目・444 行目は `*.md`（root 直下の Markdown）を対象とする Glob であり、`docs/**/*.md` ではない。ただしこの相違は本 Issue の修正対象（line 333）に影響しない。
- `file_contains "skills/doc/SKILL.md" "path"` は既存の他 `path` 出現でも PASS するが、Issue body の verify command を verbatim コピーしているため変更しない。実質的な正確性は criteria 1（`file_not_contains`）が担保する。

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
- Spec は簡潔で明確。Issue 本文と受け入れ基準が一致しており、曖昧さなし。
- Notes セクションで `file_contains "path"` の偽陽性リスクを事前に認識・記録している点は良い設計。

#### design
- 変更対象が1行・1ファイルという最小スコープ。設計と実装の乖離なし。

#### code
- fixup/amend パターンなし、rework なし。1コミットで完結。
- patch route（PR なし、直接 main コミット）が適切に選択されている。

#### review
- PR なし（patch route）のため review フェーズなし。変更が trivial（1行）であることから skip は妥当。

#### merge
- 直接 main へのコミット。コンフリクトなし。

#### verify
- 両 auto-verification 条件が PASS。verify コマンドは適切。
- `file_contains "skills/doc/SKILL.md" "path"` は既存 `path` 出現でも PASS する偽陽性リスクを Spec Notes が指摘済み。`file_not_contains` で実質的な正確性は担保されており問題なし。

### Improvement Proposals
- N/A
