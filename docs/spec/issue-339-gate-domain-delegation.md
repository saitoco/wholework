# Issue #339: code/doc: Phase 1 gate 5 箇所を Domain file 委譲に置き換え (Phase 2 Sub 2G)

## Overview

Phase 1 (#292) で `skills/code/SKILL.md` および `skills/doc/SKILL.md` に挿入した 5 箇所の existence gate を、Phase 2 Sub 2A/2B で整備した frontmatter 駆動 Domain file 委譲に置き換える。Core 側には「条件付き Read instruction」のみを残し、処理本体は Domain file へ移すことで、非 skill-dev プロジェクトでの不要な処理の混入を構造的に防ぐ。

対象 gate（5 箇所）:
- `skills/code/SKILL.md` Sub 1A: `validate-skill-syntax.py` 呼び出し gate
- `skills/code/SKILL.md` Sub 1C: Stale Test Assertion Check gate
- `skills/doc/SKILL.md` Sub 1B: skill scan gate
- `skills/doc/SKILL.md` cross-skill consistency gate
- `skills/doc/SKILL.md` terms consistency gate

## Changed Files

- `skills/code/skill-dev-validation.md`: new file — Sub 1A の処理本体 (validate-skill-syntax.py 実行) を格納する Domain file。bash 3.2+ 互換
- `skills/code/stale-test-check.md`: new file — Sub 1C の処理本体 (stale test assertion check) を格納する Domain file。bash 3.2+ 互換
- `skills/doc/skill-dev-sync.md`: new file — Sub 1B・cross-skill consistency・terms consistency の処理本体を格納する Domain file。bash 3.2+ 互換
- `skills/code/SKILL.md`: Step 8 "Stale Test Assertion Check" の inline gate+body を条件付き Read instruction に置き換え; Step 9 "Additional validation" の inline gate+body を条件付き Read instruction に置き換え
- `skills/doc/SKILL.md`: sync Step 6 "Scan implementation code"・"Cross-skill consistency check"・"Terms consistency check" の 3 つの inline gate+body を 1 つの条件付き Read instruction に統合置き換え

## Implementation Steps

1. `skills/code/skill-dev-validation.md` を新規作成する (→ 検証条件 1)
   - frontmatter: `type: domain`, `skill: code`, `load_when: file_exists_any: [scripts/validate-skill-syntax.py]`
   - Processing Steps: `python3 scripts/validate-skill-syntax.py skills/` を実行し、失敗した場合はテスト失敗と同様に修正してから継続する旨を記述

2. `skills/code/stale-test-check.md` を新規作成する (→ 検証条件 2)
   - frontmatter: `type: domain`, `skill: code`, `load_when: file_exists_any: [scripts/validate-skill-syntax.py]`
   - Processing Steps: `scripts/validate-skill-syntax.py` の存在を前提とする stale test assertion check の処理本体を記述。内部ガードとして `tests/` ディレクトリが存在しない場合 or `scripts/`・`modules/`・`skills/` のいずれも存在しない場合はスキップする旨を冒頭に明示する

3. `skills/doc/skill-dev-sync.md` を新規作成する (→ 検証条件 3, 4, 5)
   - frontmatter: `type: domain`, `skill: doc`, `load_when: file_exists_any: [scripts/validate-skill-syntax.py, skills/]`
   - Processing Steps: 以下を順に実行する
     a. skill-dev ファイルスキャン (Sub 1B): `skills/*/SKILL.md`, `modules/*.md`, `agents/*.md`, `scripts/*.sh` を Glob+Read でロード
     b. Cross-skill consistency check: `${CLAUDE_PLUGIN_ROOT}/modules/skill-dev-checks.md` の "Cross-Skill Consistency Checks" セクションを Read して実行
     c. Terms consistency check: `--deep` フラグが有効な場合のみ実行 (内部条件チェックとして記述)
   - `load_when` の `file_exists_any` が OR 評価のため、`scripts/validate-skill-syntax.py` が存在しない場合でも `skills/` が存在すれば読み込まれる。その場合、Cross-skill consistency check は `validate-skill-syntax.py` が存在する時のみ実行する内部ガードを含める

4. `skills/code/SKILL.md` を修正する (→ 検証条件 1, 2)
   - Step 8 "Stale Test Assertion Check" サブセクション: 現在の gate (`**Existence gate**: ...`) と処理本体（steps 1–3、Warning）をすべて削除し、以下の 1 行に置き換える:
     「`scripts/validate-skill-syntax.py` が存在する場合、`${CLAUDE_PLUGIN_ROOT}/skills/code/stale-test-check.md` を Read して "Processing Steps" セクションに従う。」
   - Step 9 "Additional validation" サブセクション: 現在の gate (`If scripts/validate-skill-syntax.py does not exist, skip this subsection entirely.`) と処理本体（python3 実行、説明文）をすべて削除し、以下の 1 行に置き換える:
     「`scripts/validate-skill-syntax.py` が存在する場合、`${CLAUDE_PLUGIN_ROOT}/skills/code/skill-dev-validation.md` を Read して "Processing Steps" セクションに従う。」

5. `skills/doc/SKILL.md` を修正する (→ 検証条件 3, 4, 5)
   - sync → Step 6 "Content Classification" 内の以下 3 ブロックをすべて削除する:
     - "Scan implementation code" ブロック（`if scripts/validate-skill-syntax.py exists or skills/ directory exists` の条件 + ファイルロード処理 + "If neither condition is met, skip this block entirely."）
     - "Cross-skill consistency check" ブロック（`if scripts/validate-skill-syntax.py exists` の条件 + `skill-dev-checks.md` Read）
     - "Terms consistency check" ブロック（`This check runs only when the --deep flag is enabled and ...` 条件 + 全処理本体）
   - 削除箇所を以下の 1 段落に置き換える:
     「`scripts/validate-skill-syntax.py` が存在するか `skills/` ディレクトリが存在する場合、`${CLAUDE_PLUGIN_ROOT}/skills/doc/skill-dev-sync.md` を Read して "Processing Steps" セクションに従う。」

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md no longer contains inline gate logic for validate-skill-syntax.py — replaced by a conditional Read instruction to a Domain file" --> code/SKILL.md の validate gate が Domain 委譲に置き換わっている
- <!-- verify: rubric "skills/code/SKILL.md no longer contains inline gate logic for Stale Test Assertion Check — replaced by a conditional Read instruction to a Domain file" --> code/SKILL.md の Stale Test gate が Domain 委譲に置き換わっている
- <!-- verify: rubric "skills/doc/SKILL.md no longer contains inline gate logic for skill scan — replaced by a conditional Read instruction to a Domain file" --> doc/SKILL.md の skill scan gate が Domain 委譲に置き換わっている
- <!-- verify: rubric "skills/doc/SKILL.md no longer contains inline gate logic for cross-skill consistency — replaced by a conditional Read instruction to a Domain file" --> doc/SKILL.md の cross-skill consistency gate が Domain 委譲に置き換わっている
- <!-- verify: rubric "skills/doc/SKILL.md no longer contains inline gate logic for terms consistency — replaced by a conditional Read instruction to a Domain file" --> doc/SKILL.md の terms consistency gate が Domain 委譲に置き換わっている
- <!-- verify: rubric "All Domain files used by the gate replacements declare type: domain + skill + load_when frontmatter aligned with the Sub 2A schema" --> 追加/流用した Domain file が Sub 2A スキーマに準拠している

### Post-merge

- 非 skill-dev プロジェクトで `/code` 実行時に validate 関連エラー / Stale Test エラーが出ないことを手動確認 <!-- verify-type: manual -->
- 非 skill-dev プロジェクトで `/doc sync --deep` が skill scan / cross-skill / terms 関連のノイズなく完了することを手動確認 <!-- verify-type: manual -->

## Notes

- `skills/doc/SKILL.md` は現在 `domain-loader.md` を呼び出していないため、`skills/doc/skill-dev-sync.md` は domain-loader 経由ではなく Core の直接 Read instruction で読み込まれる。`load_when` frontmatter は Sub 2A スキーマ準拠および将来の domain-loader 対応のために含める。
- Sub 1C (stale-test-check) の `load_when` 条件として `scripts/validate-skill-syntax.py` を使用するのは、元の gate の `tests/` + `scripts/modules/skills/` 条件と厳密には異なるが、`validate-skill-syntax.py` は skill-dev プロジェクトの最も強い識別子であるため proxy として採用する。domain file 内部で `tests/` directory の存在チェックを追加ガードとして記述することで、非 skill-dev プロジェクトでの誤実行を防ぐ。
- `skills/doc/skill-dev-sync.md` の `load_when` は `file_exists_any: [scripts/validate-skill-syntax.py, skills/]` (OR 評価)。`validate-skill-syntax.py` が存在しない環境で `skills/` のみ存在する場合、Cross-skill consistency check は domain file 内の内部ガードでスキップする。
- Pre-merge 検証条件が 6 件で SPEC_DEPTH=light の 5 件制限を超えているが、Issue body からの verbatim コピーを優先して全件記載する。

