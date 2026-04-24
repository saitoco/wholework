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
