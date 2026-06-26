# Issue #749: Domain Files: 7 ファイルの type: domain frontmatter 欠落で silently skip されている

## Overview

`/audit drift` が検出した Domain File frontmatter の silent skip リスク (severity: high)。
`modules/domain-loader.md` は `skills/{skill}/*.md` を Glob し `type: domain` を持つファイルのみを Domain file として処理するが、以下 7 ファイルのうち 4 ファイルが frontmatter を持たないため、domain-loader ベースの読み込みが発生した際に silently skip される。
残り 3 ファイルは調査時点でも frontmatter が存在しており、Issue body との乖離がある。

対象 7 ファイル:
| File | Status |
|------|--------|
| `skills/audit/auto-session-narrative-prompts.md` | ❌ frontmatter なし → 追加 |
| `skills/doc/product-template.md` | ❌ frontmatter なし → 追加 |
| `skills/doc/structure-template.md` | ❌ frontmatter なし → 追加 |
| `skills/doc/tech-template.md` | ❌ frontmatter なし → 追加 |
| `skills/spec/external-spec.md` | ✅ すでに frontmatter あり |
| `skills/spec/figma-design-phase.md` | ✅ すでに frontmatter あり |
| `skills/triage/skill-dev-verify-audit.md` | ✅ すでに frontmatter あり |

## Reproduction Steps

1. `domain-loader.md` の Processing Steps (Phase 1) に従い `skills/audit/*.md` を Glob
2. `auto-session-narrative-prompts.md` の frontmatter を確認 → `type: domain` なし
3. domain-loader はこのファイルを skip する

## Root Cause

4 ファイルが Domain file として設計・使用されているにもかかわらず、`type: domain` frontmatter の付与が漏れていた。また、`docs/environment-adaptation.md` の Domain Files 網羅表にこれら 7 ファイル全てが未掲載のため、`/audit drift` の **table-missing** / **file-or-frontmatter-missing** 両方のドリフトが発生している。

## Changed Files

- `skills/audit/auto-session-narrative-prompts.md`: add `type: domain` frontmatter (skill: audit, load_when: arg_starts_with: auto-session)
- `skills/doc/product-template.md`: add `type: domain` frontmatter (skill: doc)
- `skills/doc/structure-template.md`: add `type: domain` frontmatter (skill: doc)
- `skills/doc/tech-template.md`: add `type: domain` frontmatter (skill: doc)
- `docs/environment-adaptation.md`: add 7 rows to "Domain Files (exhaustive)" table
- `docs/ja/environment-adaptation.md`: Japanese mirror sync

## Implementation Steps

1. Add frontmatter to `skills/audit/auto-session-narrative-prompts.md` (→ AC1)
   - Prepend to the top of the file:
     ```
     ---
     type: domain
     skill: audit
     load_when:
       arg_starts_with: auto-session
     ---
     ```
   - bash 3.2+ compatible (no shell script involved)

2. Add frontmatter to 3 doc templates (→ AC2, AC3, AC4) — parallel with step 1
   - `skills/doc/product-template.md`, `structure-template.md`, `tech-template.md`:
     - Prepend to each file:
       ```
       ---
       type: domain
       skill: doc
       ---
       ```
   - Note: no `load_when:` for doc templates — they are used by multiple subcommands (init, product, tech, structure) so unconditional loading is correct

3. Update `docs/environment-adaptation.md` Domain Files table (→ AC8 rubric context)
   - First confirm which files are already in the table: `grep "external-spec\|figma-design-phase\|skill-dev-verify-audit\|auto-session-narrative\|product-template\|structure-template\|tech-template" docs/environment-adaptation.md`
   - `skills/spec/external-spec.md` and `skills/spec/figma-design-phase.md` are already listed — do NOT add again
   - Add 5 new rows after the existing `skills/doc/skill-dev-sync.md` row and before the project-local row:
     ```
     | `skills/audit/auto-session-narrative-prompts.md` | `/audit` | `auto-session` subcommand | `arg_starts_with: auto-session` | Auto-session narrative prompt templates |
     | `skills/doc/product-template.md` | `/doc` | init/product subcommands | _(none — multiple subcommands)_ | product.md template |
     | `skills/doc/structure-template.md` | `/doc` | init/structure subcommands | _(none — multiple subcommands)_ | structure.md template |
     | `skills/doc/tech-template.md` | `/doc` | init/tech subcommands | _(none — multiple subcommands)_ | tech.md template |
     | `skills/triage/skill-dev-verify-audit.md` | `/triage` | always (unconditional) | _(none)_ | AC verify command integrity audit |
     ```

4. Sync `docs/ja/environment-adaptation.md` (after step 3) — add corresponding Japanese rows

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/audit/auto-session-narrative-prompts.md" "type: domain" --> auto-session-narrative-prompts.md に frontmatter 追加
- <!-- verify: file_contains "skills/doc/product-template.md" "type: domain" --> product-template.md に追加
- <!-- verify: file_contains "skills/doc/structure-template.md" "type: domain" --> structure-template.md に追加
- <!-- verify: file_contains "skills/doc/tech-template.md" "type: domain" --> tech-template.md に追加
- <!-- verify: file_contains "skills/spec/external-spec.md" "type: domain" --> external-spec.md に追加
- <!-- verify: file_contains "skills/spec/figma-design-phase.md" "type: domain" --> figma-design-phase.md に追加
- <!-- verify: file_contains "skills/triage/skill-dev-verify-audit.md" "type: domain" --> skill-dev-verify-audit.md に追加
- <!-- verify: rubric "全 7 ファイルの frontmatter に load_when 等の必須フィールドが正しく設定されている (silently skip されない)" --> frontmatter が syntactically valid

### Post-merge

- 次回 /skill 実行時に対応する domain file が意図通り load されることを観察

## Notes

**Issue body との乖離 (conflict detection):**
- Issue body は 7 ファイル全てが frontmatter を欠くと述べているが、調査時点で `skills/spec/external-spec.md`、`skills/spec/figma-design-phase.md`、`skills/triage/skill-dev-verify-audit.md` の 3 ファイルはすでに `type: domain` frontmatter を持つ
- これらは `/audit drift` 実行後に別の作業で修正されたと推測される
- 対処: 3 ファイルへの frontmatter 追加はスキップし、未修正の 4 ファイルのみ変更する
- verify command は 7 ファイル全てに `file_contains` があるが、すでに通過しているため問題なし

**environment-adaptation.md の重複確認:**
- `skills/spec/external-spec.md` と `skills/spec/figma-design-phase.md` は既にテーブルに掲載済み
- 実装時は grep で確認してから追加する: `grep "external-spec\|figma-design-phase" docs/environment-adaptation.md`

**audit/doc スキルは domain-loader を使わない:**
- `audit` と `doc` SKILL.md は `domain-loader.md` を呼ばずに直接 Read でファイルを参照している
- したがって frontmatter 追加は実行時の動作を変えないが、`/audit drift` の誤検知を防ぎ、将来 domain-loader に移行した際の準備になる

## Consumed Comments

No new comments since last phase.
