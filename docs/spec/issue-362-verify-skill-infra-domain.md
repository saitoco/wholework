# Issue #362: .wholework/domains/verify/skill-infra-classify.md を新設し verify Step 13 分類語彙を退避 (Core/Domain 分離 Phase 4 Sub 4B)

## Overview

`skills/verify/SKILL.md` Step 13 の "Skill infrastructure improvement" 定義 bullet 群と classification note を、新設の `.wholework/domains/verify/skill-infra-classify.md` へ退避する。`HAS_SKILL_PROPOSALS` gate・Code improvement 分岐・重複チェック・freshness check・Issue 起票フローは Core に残す。これにより `/verify` skill の Domain loader メカニズムが初めて実運用され、他プロジェクトへの移植ガイドとなる `.wholework/domains/verify/` の実例が整備される。

## Changed Files

- `.wholework/domains/verify/skill-infra-classify.md`: 新規作成（frontmatter `type: domain`, `skill: verify`, `load_when: marker: skill-proposals` ＋ 分類語彙 bullet 群 + classification note）
- `skills/verify/SKILL.md`: Step 4 に domain-loader 呼び出し追加; Step 13 の "Skill infrastructure improvement" bullet 群（行 598–602）を削除し Domain file への委任参照に置換
- `docs/environment-adaptation.md`: Layer 3 Domain Files 表の project-local 行に `/verify` を追記; 「`/spec`、`/code`、`/review` から呼び出される」説明文に `/verify` を追加
- `docs/ja/environment-adaptation.md`: 上記の翻訳同期
- `docs/structure.md`: `.wholework/domains/` 配下に `verify/` エントリ追加
- `docs/ja/structure.md`: 翻訳同期

## Implementation Steps

1. `.wholework/domains/verify/skill-infra-classify.md` を新規作成する。frontmatter: `type: domain`, `skill: verify`, `load_when: marker: skill-proposals`。本文に "Skill infrastructure improvement" 定義 — `/spec`・`/verify`・`/review` 等 skill 変更提案、`~/.claude/` 配下ファイル参照、`SKILL.md`・`modules/*.md`・`agents/*.md` への言及、`scripts/`/`docs/` の classification note（skill infrastructure context 内のみ該当） — を移植する（→ 受け入れ条件 1–5）

2. `skills/verify/SKILL.md` を 2 箇所修正する（→ 受け入れ条件 6）:
   - **Step 4** の `detect-config-markers.md` 読み込み行の直後に追記: `Read ${CLAUDE_PLUGIN_ROOT}/modules/domain-loader.md and follow the "Processing Steps" section with SKILL_NAME=verify. Domain file content provides Skill infrastructure improvement classification criteria for Step 13.`
   - **Step 13** の "Skill infrastructure improvement" bullet 群（行 598–602 の 5 行）を削除し、`**If HAS_SKILL_PROPOSALS=true**:` 行（行 596）の後半を次のように置換: 「classify each improvement proposal using the criteria from the Domain file loaded in Step 4 (`.wholework/domains/verify/`). If no Domain file was loaded, treat all proposals as Code improvements.」。`Code improvement` bullet（行 603）はそのまま残す

3. `docs/environment-adaptation.md` を修正する（step 2 の後）:
   - Domain Files 表の project-local 行 (`| .wholework/domains/{skill}/*.md | ...`) の Skills 列を `/spec`, `/code`, `/review`, `/verify` に変更
   - 表直後の説明文 "invoked by `/spec`, `/code`, and `/review` skills" を "invoked by `/spec`, `/code`, `/review`, and `/verify` skills" に変更

4. `docs/ja/environment-adaptation.md` を翻訳同期する（step 3 の後）:
   - Domain Files 表の project-local 行に `/verify` を追加
   - 説明文 「`/spec`、`/code`、`/review` スキルから呼び出されます」を「`/spec`、`/code`、`/review`、`/verify` スキルから呼び出されます」に変更

5. `docs/structure.md` と `docs/ja/structure.md` を修正する（step 1 と並列可）:
   - `.wholework/domains/` の `└── review/` を `├── review/` に変更し、直後に `└── verify/ # Domain files for /verify`（日本語版は `└── verify/ # /verify の Domain files`）を追加

## Verification

### Pre-merge

- <!-- verify: file_exists ".wholework/domains/verify/skill-infra-classify.md" --> Domain file が作成されている
- <!-- verify: file_contains ".wholework/domains/verify/skill-infra-classify.md" "type: domain" --> frontmatter に `type: domain` が宣言されている
- <!-- verify: file_contains ".wholework/domains/verify/skill-infra-classify.md" "skill: verify" --> frontmatter で `skill: verify` が宣言されている
- <!-- verify: rubric "the Domain file declares load_when conditions conforming to the Phase 2 Sub 2A frontmatter schema (typed keys such as file_exists_any, marker, capability, arg_starts_with, spec_depth) — not a free-form bash expression" --> load_when が Phase 2 frontmatter スキーマに従って宣言されている
- <!-- verify: rubric "the Domain file contains the Skill infrastructure improvement classification vocabulary: references to ${CLAUDE_PLUGIN_ROOT}/modules/, SKILL.md, modules/*.md, agents/*.md as classification criteria, plus the generic scripts/docs/ classification note" --> 退避された分類語彙 (bullet 群 + classification note) が Domain file に含まれている
- <!-- verify: rubric "skills/verify/SKILL.md Step 13 no longer contains the inline Skill infrastructure improvement classification vocabulary bullet list; the file delegates to the Domain file instead. The HAS_SKILL_PROPOSALS gate, Code improvement branching, duplicate check, freshness check, and Issue creation flow all remain in Core" --> verify/SKILL.md から分類語彙 bullet 群が退避され、HAS_SKILL_PROPOSALS gate と Issue 起票フロー本体は Core に残る

### Post-merge

- wholework 自身で `/verify` を実行し、skill-infra 分類が Domain file 経由で従来通り発動する (project-local Domain loader が `.wholework/domains/verify/` を load する) ことを手動確認 <!-- verify-type: manual -->

## Notes

**非インタラクティブモードでの自動解決:**

1. **`load_when` キー選択**: `skill-infra-classify.md` は `skill-proposals: true` が設定されたプロジェクトでのみ意味を持つため、`load_when: marker: skill-proposals` が最適。現状、project-local Domain files は `load_when` の評価なしに無条件でロードされる（`environment-adaptation.md` 記載の仕様）が、frontmatter 宣言は Phase 2 スキーマへの準拠と将来の評価実装のための metadata として記載する。

2. **domain-loader 挿入位置**: Step 4 の `detect-config-markers.md` 読み込み直後（`{{base_url}}` セクションより前）に挿入。他スキル（`/spec` Step 5、`/code` Step 6、`/review` Step 6）と同様に、早期ロードで Step 13 での参照可能性を確保する。

3. **Step 13 の Core 残存範囲**: `HAS_SKILL_PROPOSALS` の早期 gate（行 594）、「If `HAS_SKILL_PROPOSALS=true`」の分岐（行 596）、Code improvement 定義（行 603）、重複チェック・freshness check・Issue 起票フロー（行 606–638）はすべて Core に残す。
