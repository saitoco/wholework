# Issue #780: verify: Step 8b executability rubric に source code 由来の observation を executable 例として追加

## Overview

`/verify` Step 8b (Claude Executability Judgment) の rubric に、「default 挙動が source code から決まる observation」を executable 例として追加する。

現状の rubric には以下の例しか記載されていない:
- Executable: `curl`, `gh`, file/dir 存在確認, `git log`/`git status`, `ps`/`pgrep`
- Non-executable: browser visual, user action, UI/UX, dashboard

「次回観察」と書かれた post-merge AC でも、script の default 挙動が source code から静的に決まるケース (OUTPUT_PATH ハードコード、デフォルト変数代入など) は `grep` で in-session 検証可能。これを rubric に明示することで、保守的な "Manual/SKIP" 判定を防ぐ。

## Changed Files

- `skills/verify/SKILL.md`: Step 8b `**Executable examples**` 行に「source code から default 挙動が決まる observation」の例を追加 (bash 3.2+ compatible — shell script ではないため考慮不要)

## Implementation Steps

1. `skills/verify/SKILL.md` の `#### Step 8b: Manual Post-merge Conditions` セクション、`**Executable examples**` の行末に追加する (→ AC1, AC2):

   現行:
   ```
   - **Executable examples**: `curl` URL reachability check, `gh` command result judgment, file/directory existence check (`test -f`, `test -d`), `git log`/`git status` result inspection, process listing (`ps`, `pgrep`)
   ```

   変更後 (行末に追加):
   ```
   - **Executable examples**: `curl` URL reachability check, `gh` command result judgment, file/directory existence check (`test -f`, `test -d`), `git log`/`git status` result inspection, process listing (`ps`, `pgrep`), observation whose default behavior is statically determined from source code (e.g., `grep` for hardcoded default path, constant, or variable assignment — confirms expected behavior without waiting for future execution)
   ```

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/verify/SKILL.md" "#### Step 8b: Manual Post-merge Conditions" "source code" --> `skills/verify/SKILL.md` の Step 8b "Claude Executability Judgment" rubric セクションに「default 挙動が source code から決まる observation」を executable 例として追加
- <!-- verify: rubric "/verify SKILL.md Step 8b の executability rubric に、script の default 挙動を source code から判定して PASS 判定する具体例が記述されている" --> <!-- verify: section_contains "skills/verify/SKILL.md" "#### Step 8b: Manual Post-merge Conditions" "default" --> 具体例 (script default path / hardcoded behavior の grep ベース判定) が記述されている

### Post-merge

- 次回 post-merge "次回観察" 系 manual AC を含む Issue の `/verify` 実行で、source code 確認で executable 判定されるケースが観察される

## Consumed Comments

- saito / MEMBER / first-class / issue retrospective: verify command を `grep -iE` → `section_contains` に変更、rubric + `section_contains` 補助チェック追加の自動解決記録 / https://github.com/saitoco/wholework/issues/780#issuecomment-4821587342
