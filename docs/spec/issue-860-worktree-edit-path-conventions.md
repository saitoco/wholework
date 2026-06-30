# Issue #860: docs/skills: worktree session 中の Edit/Write 規律を明文化 (parent main path 誤使用を防止)

## Overview

並列セッション環境で LLM が worktree 内ファイルを編集する際、worktree 配下の path ではなく
parent main repo の absolute path を誤って指定してしまうケースが複数回観察された。
これにより parent main が汚染され、他セッションがその dirty state を見てエラーになる。

本 Issue は**規約の明文化のみ**で対応する最小侵襲アプローチ:
- `modules/worktree-lifecycle.md` の Notes セクションに Edit/Write path 規約サブセクションを追加
- `skills/verify/SKILL.md` / `skills/spec/SKILL.md` / `skills/review/SKILL.md` の retrospective 追記ステップに worktree-lifecycle.md への cross-reference を追加

`skills/code/SKILL.md` (lines 136-138) と `skills/merge/SKILL.md` (line 211) は既存の
path 規約記述が充分なため変更不要。

## Changed Files

- `modules/worktree-lifecycle.md`: `## Notes` 配下に `### Edit/Write path conventions in worktree sessions` サブセクションを追加 — `ENTERED_WORKTREE=true` 状態での Edit/Write path 規約 (✅/❌ 例付き)
- `skills/verify/SKILL.md`: Step 12 retrospective 追記ステップ (line 699) に worktree-lifecycle.md cross-reference を追加
- `skills/spec/SKILL.md`: Step 13 retrospective 追記ステップ (lines 805-806) に worktree-lifecycle.md cross-reference を追加
- `skills/review/SKILL.md`: retrospective Write ステップ (line 765) に worktree-lifecycle.md cross-reference を追加
- `docs/workflow.md`: [Steering Docs sync candidate] verify that description of `verify` / `spec` / `review` is up to date; update if needed (behavioral change なし → update 不要の可能性大)

## Implementation Steps

1. `modules/worktree-lifecycle.md` の `## Notes` 配下、既存 `### Editing .claude/ files inside worktrees` の直後 (末尾の `## Callers` セクションの前) に以下のサブセクションを追加 (→ AC1):

   ```markdown
   ### Edit/Write path conventions in worktree sessions

   After calling `EnterWorktree` (`ENTERED_WORKTREE=true`), when editing files inside the
   worktree, **always use the worktree-local path** with the Edit or Write tool:

   - ✅ Absolute worktree path: `Edit .claude/worktrees/{NAME}/docs/spec/issue-N-foo.md`
   - ✅ CWD-relative path (when CWD is inside the worktree): `Edit docs/spec/issue-N-foo.md`
   - ❌ Absolute parent-repo path during a worktree session: `Edit /path/to/repo/docs/spec/issue-N-foo.md`

   **Why**: Using an absolute parent-repo path calls Edit on the parent repo's file instead
   of the worktree copy. In parallel-session environments, other sessions observing the
   resulting dirty state of the parent repo file may fail unexpectedly.

   **How to verify CWD**: Run `pwd` to confirm you are inside the worktree, or confirm that
   the return value from `EnterWorktree` points to the worktree path before calling Edit.
   ```

2. `skills/verify/SKILL.md` line 699 の retrospective append 記述を更新 (→ AC2):

   変更前: `- Append section at end of Spec with Edit tool`

   変更後: `- Append section at end of Spec with Edit tool (use CWD-relative path in worktree sessions — see \`modules/worktree-lifecycle.md\` § Notes for Edit/Write conventions)`

3. `skills/spec/SKILL.md` lines 805-806 の retrospective append 記述を更新 (→ AC2):

   変更前:
   ```
   2. If issue retrospective found, transfer it first (Edit tool to prepend to Spec)
   3. Edit tool to append spec retrospective to Spec end
   ```

   変更後:
   ```
   2. If issue retrospective found, transfer it first (Edit tool to prepend to Spec; use CWD-relative path in worktree sessions)
   3. Edit tool to append spec retrospective to Spec end (use CWD-relative path — see `modules/worktree-lifecycle.md` § Notes for worktree Edit/Write conventions)
   ```

4. `skills/review/SKILL.md` line 765 の retrospective append 記述を更新 (→ AC2):

   変更前: `- Append \`## review retrospective\` section to the end of \`$SPEC_PATH/issue-$ISSUE_NUMBER-*.md\` using Edit tool`

   変更後: `- Append \`## review retrospective\` section to the end of \`$SPEC_PATH/issue-$ISSUE_NUMBER-*.md\` using Edit tool (use CWD-relative path in worktree sessions — see \`modules/worktree-lifecycle.md\` § Notes for Edit/Write conventions)`

## Verification

### Pre-merge

- `modules/worktree-lifecycle.md` の Notes セクションに「Worktree session 中の Edit/Write 規律」サブセクションが追加され、worktree path 必須の規約と例 (✅/❌) が明記されている <!-- verify: rubric "modules/worktree-lifecycle.md の Notes セクションに、worktree session 中の Edit/Write 呼び出しでは worktree 配下 path を使うべき旨の規約と、absolute parent main path の使用を避ける旨が明文化されている" --> <!-- verify: section_contains "modules/worktree-lifecycle.md" "## Notes" "ENTERED_WORKTREE" -->
- 各 SKILL.md (`skills/verify/SKILL.md` / `skills/spec/SKILL.md` / `skills/code/SKILL.md` / `skills/review/SKILL.md` / `skills/merge/SKILL.md`) の Edit 呼び出し記述で、worktree session 内の path 規約への参照が含まれている <!-- verify: rubric "各 SKILL.md の Edit 呼び出し記述セクション (retrospective 追記等) で modules/worktree-lifecycle.md の path 規律への参照またはインライン注意書きが含まれている、もしくは relative path で統一されており absolute parent main path の例示が削除されている" --> <!-- verify: file_contains "skills/code/SKILL.md" "CWD-relative" -->
- 変更対象 SKILL.md (`skills/verify/SKILL.md` / `skills/spec/SKILL.md` / `skills/review/SKILL.md`) が validate-skill-syntax.py の構文チェックを通過する <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/verify/SKILL.md skills/spec/SKILL.md skills/review/SKILL.md" -->

### Post-merge

- 次回 verify/spec/code session で LLM が worktree session 中の Edit を呼ぶ際、worktree path で正しく動作することを観察 <!-- verify-type: manual -->

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: auto-resolved 3 ambiguity points (SKILL.md change scope, Proposal C skip, subsection placement) / https://github.com/saitoco/wholework/issues/860#issuecomment-4840963708

## Notes

- 本 Issue は**規約の明文化のみ**。LLM 強制機構は追加しない
- absolute parent main path での Edit を「禁止」とは書かない (config 変更などの正当 use case がある)
- `skills/code/SKILL.md` と `skills/merge/SKILL.md` は既存記述が充分なため変更不要 (auto-resolved)
- Proposal C (verify-patterns.md への検出 pattern 追加) は本 Issue スコープ外でスキップ (auto-resolved)
- `worktree-lifecycle.md` の新サブセクションは `### Editing .claude/ files inside worktrees` と同列 (`###` level、sibling) に配置 (auto-resolved)
- 本 Issue の Changed Files は `modules/` と `skills/` のみ。`docs/*.md` の変更はなく `docs/ja/` の translation sync 不要

## Code Retrospective

### Deviations from Design
- 実装を 4 ステップ別コミット (modules/worktree-lifecycle.md → verify → spec → review) に分割した。Spec の「実装 step 1-4」に対応する個別コミットであり意図的。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `modules/worktree-lifecycle.md` の `## Notes` 配下に `### Edit/Write path conventions in worktree sessions` サブセクションを追加。`ENTERED_WORKTREE=true` 状態での ✅/❌ 例付きで規約を明文化した。
- `skills/verify/SKILL.md`, `skills/spec/SKILL.md`, `skills/review/SKILL.md` の retrospective 追記ステップに `modules/worktree-lifecycle.md § Notes` への cross-reference を追加。
- `skills/code/SKILL.md` と `skills/merge/SKILL.md` は既存記述が充分 (auto-resolved) のため変更不要と判断した。

### Deferred Items
- Post-merge AC: 次回 verify/spec/code session での動作観察 (manual check)。
- Proposal C (verify-patterns.md への検出 pattern 追加) は本 Issue スコープ外でスキップ。

### Notes for Next Phase
- 変更はドキュメントのみ (4 files)。動作変更なし。CI は bats (1041 PASS) と validate-skill-syntax を通過済み。
- verify コマンドは全 PASS (section_contains, file_contains, command, rubric)。
- `/verify` は Post-merge AC (manual) のみ残っている。観察確認後に Close。
