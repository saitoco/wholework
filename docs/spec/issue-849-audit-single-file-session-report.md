# Issue #849: audit/auto: session data-layer.md の bilingual 生成を廃止 (single-file 化)

## Overview

`/audit auto-session` が生成する session report の bilingual sibling 生成 (data-layer-ja.md) を廃止し、single-file 化する。session report は内部開発者向け artifact であり、言語選択はリポジトリの既存の規約 (CLAUDE.md / memory) に委ねる。

変更スコープ:
- `skills/audit/SKILL.md` の Step 3 (Japanese sibling generation) と `--no-ja` フラグを削除
- frontmatter description 内の sibling 言及を削除
- `docs/sessions/*/data-layer-ja.md` 既存 5 件を削除
- 関連ドキュメント (structure.md, workflow.md, ja mirrror) から sibling 言及を削除

## Consumed Comments

- saito (MEMBER / first-class) — Issue Retrospective: `find` で 5 件確認、Auto-Resolve Log 記録、AC verify command 追加。[コメント](https://github.com/saitoco/wholework/issues/849#issuecomment-4828627261)

## Changed Files

- `skills/audit/SKILL.md`: (1) frontmatter description から "Also generates a Japanese-translated sibling file at `{report-path-without-ext}-ja.md` by default; pass `--no-ja` to skip." を削除。(2) line 23 の auto-session routing 例から `auto-session <id> --no-ja` を削除。(3) line 27 の usage 文字列から `[--no-ja]` を削除。(4) Argument Parsing の `--no-ja` 項目 (line 873) を削除。(5) Step 3 "Generate Japanese Sibling" 全体 (lines 966–980) を削除 — bash 3.2+ compat N/A (SKILL.md は LLM が解釈)
- `docs/sessions/58975-1781511640-2026-06-16/data-layer-ja.md`: delete
- `docs/sessions/3480-1782440098-2026-06-27/data-layer-ja.md`: delete
- `docs/sessions/98315-1782515143-2026-06-27/data-layer-ja.md`: delete
- `docs/sessions/13998-1782562514-2026-06-27/data-layer-ja.md`: delete
- `docs/sessions/22753-1782519060-2026-06-27/data-layer-ja.md`: delete
- `docs/sessions/13998-1782562514-2026-06-27/session.md`: line 105 の `data-layer-ja.md` cross-link を削除
- `docs/structure.md`: line 69 の `│           data-layer-ja.md # Japanese translation sibling` 行を削除
- `docs/ja/structure.md`: line 62 の `│           data-layer-ja.md # 日本語翻訳 sibling` 行を削除
- `docs/workflow.md`: line 166 の `; \`--no-ja\` to skip Japanese sibling generation` 部分を削除
- `docs/ja/workflow.md`: line 159 の `` `--no-ja` を付与すると日本語 sibling ファイルの生成をスキップします。`` 文を削除

## Implementation Steps

1. `skills/audit/SKILL.md` を編集:
   (a) frontmatter description (line 3) から "Also generates a Japanese-translated sibling file at `{report-path-without-ext}-ja.md` by default; pass `--no-ja` to skip." を削除
   (b) line 23 の auto-session 例から `, auto-session <id> --no-ja` を削除
   (c) line 27 の usage 文字列から ` [--no-ja]` を削除
   (d) line 873 の `--no-ja` 引数説明行を削除
   (e) lines 966–980 の "### Step 3: Generate Japanese Sibling" セクション全体を削除
   (→ 受け入れ基準 AC1, AC2)

2. 既存 data-layer-ja.md を 5 件削除:
   ```bash
   rm docs/sessions/58975-1781511640-2026-06-16/data-layer-ja.md
   rm docs/sessions/3480-1782440098-2026-06-27/data-layer-ja.md
   rm docs/sessions/98315-1782515143-2026-06-27/data-layer-ja.md
   rm docs/sessions/13998-1782562514-2026-06-27/data-layer-ja.md
   rm docs/sessions/22753-1782519060-2026-06-27/data-layer-ja.md
   ```
   (→ 受け入れ基準 AC3)

3. `docs/sessions/13998-1782562514-2026-06-27/session.md` の cross-link を削除:
   line 105: `- [Data layer report (日本語)](docs/sessions/13998-1782562514-2026-06-27/data-layer-ja.md)` を削除
   (→ 受け入れ基準 AC3)

4. ドキュメント更新 (after 1, parallel):
   (a) `docs/structure.md`: line 69 の `│           data-layer-ja.md # Japanese translation sibling` を削除
   (b) `docs/ja/structure.md`: line 62 の `│           data-layer-ja.md # 日本語翻訳 sibling` を削除
   (c) `docs/workflow.md`: `; \`--no-ja\` to skip Japanese sibling generation` を削除
   (d) `docs/ja/workflow.md`: `` `--no-ja` を付与すると日本語 sibling ファイルの生成をスキップします。`` を削除
   (→ 受け入れ基準 AC1, AC4)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/audit/SKILL.md に -ja.md sibling 生成の Step 3 / --no-ja フラグが残っていない" --> SKILL.md から Step 3 と --no-ja が削除されている
- <!-- verify: file_not_contains "skills/audit/SKILL.md" "data-layer-ja.md" --> SKILL.md に data-layer-ja.md の言及がない
- <!-- verify: file_not_contains "skills/audit/SKILL.md" "Japanese-translated sibling" --> SKILL.md に Japanese-translated sibling の言及がない
- <!-- verify: file_not_contains "skills/audit/SKILL.md" "--no-ja" --> --no-ja フラグが削除されている
- <!-- verify: rubric "docs/sessions/ 配下に data-layer-ja.md が存在しない" --> 既存の sibling ファイルが削除されている
- <!-- verify: file_not_exists "docs/sessions/13998-1782562514-2026-06-27/data-layer-ja.md" --> 代表ファイルが削除されている
- <!-- verify: rubric "skills/audit/SKILL.md の data-layer.md 生成パスが Step 3 削除後も intact" --> data-layer.md の生成パス (Step 1-2) が健全

### Post-merge

- 次回 `/audit auto-session <id>` 実行で `data-layer.md` のみ生成され `-ja.md` sibling が作られないことを確認 <!-- verify-type: observation event=auto-run -->

## Notes

- **スコープ除外**: `docs/spec/` 配下の既存 Spec (issue-752, issue-772, issue-776) は historical record として変更しない。これらに残る `--no-ja` / `data-layer-ja.md` 言及は過去の Spec の文脈に属する。
- **Session.md の cross-link 削除**: `docs/sessions/13998-1782562514-2026-06-27/session.md` line 105 に data-layer-ja.md への cross-link が存在する。既存 sibling 削除と同時に broken link になるため削除対象とする。
- **docs/ja/ sync**: `docs/structure.md` と `docs/workflow.md` の変更に対して `docs/ja/` mirror ファイルの対応箇所を同時に更新する (translation-workflow.md の sync 規則に従い)。
- **SKILL.md の Step 3 削除後の continuity**: Step 3 削除後、auto-session サブコマンドは Step 1 (display/generate) → Step 2 (display result) で完結する。"Period aggregate mode stops at Step 2." の記述 (line 964) は整合している。

## spec retrospective

### Minor observations

- Issue body と Issue retrospective コメントの組み合わせで変更範囲が明確だった。grep-based impact chain discovery の実行で 9 ファイルを網羅的に特定できた。

### Judgment rationale

- `docs/spec/` 配下の既存 Spec を historical record として除外した。機械的に全て変更すると Spec の文脈が壊れるため除外が適切。
- `session.md` の cross-link は SHOULD レベルだが、削除した sibling へのリンクは broken link になるため削除をスコープに含めた。

### Uncertainty resolution

- Nothing to note — codebase investigation で全ての変更対象を特定できた。

## Code Retrospective

### Deviations from Design

- None. All Spec implementation steps were followed exactly as designed.

### Design Gaps/Ambiguities

- The Spec referenced line numbers (e.g., "lines 966-980") which had already shifted slightly; actual lines were approximately 966-977. Content-based editing handled this transparently.

### Rework

- None. The implementation proceeded cleanly in a single pass.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Deleted all 5 existing `data-layer-ja.md` sibling files as specified; none were kept for historical reference
- Removed the `--no-ja` flag from routing example, usage string, and argument parsing section — the flag is fully deprecated
- Updated `docs/ja/` mirror files in the same commit to keep translation sync current

### Deferred Items
- Post-merge verification: confirm that the next `/audit auto-session` run produces only `data-layer.md` and no `-ja.md` sibling (observation event=auto-run, AC4)

### Notes for Next Phase
- All pre-merge verify commands passed locally; CI should confirm `file_not_contains` checks pass against the PR branch
- The auto-session Subcommand now stops at Step 2 (Display Result) — the Step 3 heading no longer exists, which is correct
- No forbidden expressions violations were found; the check passed cleanly
