# Issue #68: doc: /doc translate セクションを translate-phase.md に Progressive Disclosure 分離

## Overview

`skills/doc/SKILL.md` の `## translate — Translation Generation` セクション（746〜873行、128行）を `skills/doc/translate-phase.md` に分離し、SKILL.md 側は薄い委譲形式に差し替える。

既存パターン（`skills/spec/figma-design-phase.md`、`skills/review/external-review-phase.md`、`skills/verify/browser-verify-phase.md`）と同じ Progressive Disclosure 分離を適用する。

分離に際し、Command Routing 側（SKILL.md 行54）が既に `{lang}` 空チェックを行っているため重複する `### Step 0: Validate Language Argument` を削除し、引数検証を Command Routing に一本化する。

## Changed Files

- `skills/doc/translate-phase.md`: 新規作成 — SKILL.md の translate セクション内容（Step 1〜Step 6、BCP 47説明、Relative Link Rewriting Rules）を移設。Step 0（引数検証）は削除
- `skills/doc/SKILL.md`: `## translate — Translation Generation` セクション本体（746〜873行）を薄い委譲形式に差し替え（`### Step 0: Validate Language Argument` も削除）

## Implementation Steps

1. `skills/doc/translate-phase.md` を新規作成する。内容はSKILL.md 748〜873行から以下のように移設:
   - ファイルタイトル: `# Translation Generation Phase`
   - BCP 47 / ISO 639-1 説明（750行）を冒頭に記載
   - `## Steps` セクションを設け、Step 0 を除いた Step 1〜Step 6 を配置
   - Step 番号はそのまま（Step 1〜Step 6）
   (→ 受け入れ基準 A, E, F)

2. `skills/doc/SKILL.md` の `## translate — Translation Generation` セクション（746〜873行）を薄い委譲形式に差し替える:
   ```
   ## translate — Translation Generation

   Execute when ARGUMENTS starts with `translate {lang}`. Generate translations of English documentation to the target language using LLM, place output under `docs/{lang}/` (README → `README.{lang}.md` at project root), commit and push automatically.

   Read `skills/doc/translate-phase.md` and follow its "Steps" section.
   ```
   (→ 受け入れ基準 B)

3. Command Routing セクション（54行付近）の `translate` 分岐は変更不要（既に `{lang}` 空チェック済み）。変更しないことを確認する。
   (→ 受け入れ基準 C)

4. `### Step 0: Validate Language Argument` が SKILL.md に残っていないことを確認する（手順2で削除済みのため）。
   (→ 受け入れ基準 D)

## Verification

### Pre-merge

- <!-- verify: file_exists "skills/doc/translate-phase.md" --> `skills/doc/translate-phase.md` が新規作成されている
- <!-- verify: section_contains "skills/doc/SKILL.md" "## translate" "translate-phase.md" --> `skills/doc/SKILL.md` の `## translate — Translation Generation` セクションが `translate-phase.md` を Read して委譲する形式（薄い委譲）になっている
- <!-- verify: section_contains "skills/doc/SKILL.md" "## Command Routing" "translate" --> `skills/doc/SKILL.md` の Command Routing セクションに `translate` 分岐が残り、ルーティングが維持されている
- <!-- verify: file_not_contains "skills/doc/SKILL.md" "### Step 0: Validate Language Argument" --> 重複する Step 0（引数検証）が SKILL.md から削除されている
- <!-- verify: file_contains "skills/doc/translate-phase.md" "BCP 47" --> `translate-phase.md` に BCP 47 の言語コード説明が移設されている
- <!-- verify: file_contains "skills/doc/translate-phase.md" "Relative Link Rewriting Rules" --> `translate-phase.md` に相対リンク書き換えルール（Step 3 内の固有ルール）が移設されている

### Post-merge

- `/doc translate ja` を実行し、翻訳ファイルが生成されコミット・プッシュされることを確認する（動作変化なし）

## Notes

- `translate-phase.md` は SKILL.md ではないため `validate-skill-syntax.py` の検証対象外
- Command Routing 側（行54）の `{lang}` 空チェックロジックは変更不要（Step 0 削除後も機能維持）
- 参照パス形式は既存パターンに合わせ `skills/doc/translate-phase.md`（`${CLAUDE_PLUGIN_ROOT}` プレフィックスなし）を使用

## Code Retrospective

### Deviations from Design

- 実装コミットのプレフィックスに `feat:` を使用したが、Issue Type が Task のため正しくは `chore:` だった。機能的な影響はないがスタイル上の逸脱。

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A
