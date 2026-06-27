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

## Auto Retrospective

### Execution Summary

| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| issue | -     | SUCCESS | Size auto-detected as S, then refined to XS post-spec |
| spec  | patch | SUCCESS | run-spec.sh exit 0, Size demoted S → XS |
| code  | patch | SUCCESS (manual recovery) | run-auto-sub.sh killed during code phase. Worktree had uncommitted changes (1 file modified, 1 insertion/1 deletion). Parent-session manual recovery: `git add` + `git commit` + `worktree-merge-push.sh --from worktree-code+issue-780 --base main` |
| verify | - | SUCCESS | this Skill invocation, all ACs PASS |

### Orchestration Anomalies

- **run-auto-sub.sh killed during code phase (before commit)**: 本 batch session 内で 3 度目の同種事例 (#776: after commit before push, #779: after commit before merge-push, #780: before commit). Tier ladder の bottom (commit 前) も観察された。parent session が `git add` + `git commit` + worktree-merge-push.sh の manual recovery で完走。

### Improvement Proposals

1. **#806 (code phase milestone checkpoint) の必要性確認**: 本 batch session 内で run-auto-sub.sh の code phase が複数の異なる milestone で kill された:
   - #780: pre-commit (worktree dirty)
   - #779: post-commit pre-merge-push
   - #776: post-commit post-push pre-PR-create
   - #770/#769/#775: post-PR-create (Tier 3 recovery で対応)
   
   全 milestone を SSoT で persist する設計 (#806) の必要性が更に強化された。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Background が #772 verify retrospective を引用、`/verify` Step 8b の保守的な executability rubric の死角を明確化。AC1/AC2 で section_contains を採用、rubric AC は補強として配置。

#### spec
- "1 file 1 行追記" の最小スコープ実装。Spec Size 自動降格 (S → XS) で patch route が確定。

#### code
- 1 文字列追加 (Executable examples 行末への記述追加)。run-auto-sub.sh kill により Code Retrospective 未記録。parent session manual recovery で完走。

#### verify
- 全 2 pre-merge AC + 1 post-merge AC が PASS。
- **Post-merge AC が本 batch session 内で自己実証**: #780 の Purpose (source code 由来 observation を executable と判定) は本 batch session で実施された複数の verify (#770/#771/#775/#776) で既に使われたパターンと同型。本 #780 verify session 自体も AC1/AC2 を source code 確認で PASS 判定しており、self-referential な実証になっている。
- **Tier ladder 全 milestone での run-auto-sub.sh kill 観察**: 本 batch session で 5 度の kill 観察 (#770/#769/#775: post-PR-create, #776: post-push, #779: post-commit, #780: pre-commit)。各 milestone で parent session manual recovery で完走。

### Improvement Proposals

1. **本 batch session の全 5 milestone kill 観察を #806 (code phase milestone checkpoint) に統合**: 本 batch で観察された kill milestone 全 5 段階を #806 の AC に追加することで設計の網羅性が向上。新規 Issue 不要、#806 の comment で実例追記が candidate。
2. **opportunistic verification の有効性確認**: 本 batch session で #779 の post-merge AC が #780 の `/issue` triage 実行時に opportunistic verify で auto-PASS / phase/done 遷移を実証 (#780 triage output で記録)。`/verify` Step 14 の opportunistic mechanism が batch session の "follow-up Issue が同種チェックを担う" 経路で動作する実例として記録に値する。
