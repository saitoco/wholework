# Issue #425: Add manual-AC-automatable reminder in spec

## Overview

`/spec` Step 10 の `verify-type tag check` ステップおよび `modules/verify-patterns.md` を拡張し、`manual` タグ付き AC について automatable/rubric への置換機会を見直す仕組みを導入する。

採用 Proposal: **D + A**（Issue body の Auto-Resolved Ambiguity Points に記録済み）
- **Proposal D**: `modules/verify-patterns.md` に §11「Manual AC Quick Reference」セクション（早見表）を追加
- **Proposal A**: `skills/spec/SKILL.md` の `**verify-type tag check:**` ブロックに `manual` タグ付き条件の automatable/rubric 代替検討サブステップを追加

## Changed Files

- `modules/verify-patterns.md`: `## Output` セクション直前に `### 11. Manual AC Quick Reference` セクションを追加（manual パターン → 置換候補 verify command 早見表）
- `skills/spec/SKILL.md`: `**verify-type tag check:**` ブロックの末尾に `manual`-tagged conditions サブステップを追加

## Implementation Steps

1. `modules/verify-patterns.md` の `## Output` セクション直前（line 318 付近）に `### 11. Manual AC Quick Reference` セクションを追加する（→ AC1, 2）
   - セクション見出し: `### 11. Manual AC Quick Reference — Replace with automatable/rubric`
   - 早見表カラム: `manual に書きがちなパターン` / `置換候補 verify command` / `使用例`
   - 含めるべき行（最低限）:
     - コマンド成否 → `command` / `build_success "CMD"`
     - URL 応答確認 → `http_status "URL" "200"` / `html_check` / `api_check`
     - コンポーネント整合性・意味検証 → `rubric "..."`
     - 出力ファイル生成 → `file_exists "path"`
   - 早見表の後に注記: 「置換可能と判断できる場合は Spec および Issue body の AC の verify command を更新すること。`rubric` と `file_contains`/`section_contains` の併用も有効（§9 参照）」

2. `skills/spec/SKILL.md` の `**verify-type tag check:**` ブロック（line 331 付近）で `opportunistic`-tagged conditions の確認行の後に、`manual`-tagged conditions サブステップを追加する（→ AC3, 4）
   - 追加するテキスト（例）: `` - `manual`-tagged conditions — for each, consult `${CLAUDE_PLUGIN_ROOT}/modules/verify-patterns.md §11` quick reference and check if it can be replaced with `file_exists` / `file_contains` / `http_status` / `rubric`. If replaceable, update the verify command in both the spec and issue body AC. ``
   - 注意: SKILL.md 内では半角 `!` 禁止（Forbidden Expressions 準拠）

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-patterns.md に manual verify-type AC を automatable または rubric に置き換えるためのクイックリファレンステーブルが追加されている" --> `modules/verify-patterns.md` に manual AC の automatable/rubric 置換候補早見表が追加されている
- <!-- verify: grep "build_success" "modules/verify-patterns.md" --> 早見表にコマンド置換候補（`build_success` 等）が含まれている
- <!-- verify: file_contains "skills/spec/SKILL.md" "manual" --> `/spec` SKILL.md の `verify-type tag check` ブロックに `manual` タグ付き条件の見直し記述が追加されている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/spec/SKILL.md" --> `/spec` SKILL.md が構文チェックを通過する

### Post-merge

- CI（bats tests + skill syntax validation + forbidden expressions check）が green であることを確認する

## Notes

**Auto-resolve（non-interactive mode）:**

AC3 の verify command を Issue body の `section_contains "skills/spec/SKILL.md" "verify-type tag check" "manual"` から `file_contains "skills/spec/SKILL.md" "manual"` に修正した。

理由: SKILL.md において "verify-type tag check" はマークダウン見出し行（`#` プレフィックス）ではなく太字段落（`**verify-type tag check:**`）として記述されているため、`section_contains` は UNCERTAIN を返す。`file_contains "skills/spec/SKILL.md" "manual"` は単純かつ確実な代替（"manual" は現時点で SKILL.md に 0 件、実装後に verify-type tag check ブロックへ導入される）。Issue body を同様に更新した。
