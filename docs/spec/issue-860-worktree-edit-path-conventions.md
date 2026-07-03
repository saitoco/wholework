# Issue #860: docs/skills: worktree session 中の Edit/Write 規律を明文化 (parent main path 誤使用を防止)

## Overview

**Revised design (2026-07-03)**: 初回実装 (2026-06-30 merge) は `modules/worktree-lifecycle.md` の prose 注記追加のみで完了したが、2026-07-03 の #876 code phase で **prose 注記が LLM に読み飛ばされ絶対 main-repo path 誤用の rework が実発生** した (verify FAIL 判定済) 。

本 Spec は **PreToolUse hook による structural enforcement** を追加する: `scripts/hook-worktree-path-guard.sh` を新規作成し、`hooks/hooks.json` の `PreToolUse` エントリで Edit / Write / NotebookEdit tool にマッチさせる。 Hook は cwd (worktree 配下か) と `tool_input.file_path` (parent-repo absolute か worktree 配下か) を照合し、worktree session 中の parent-repo absolute path 呼び出しを exit 2 + stderr message で block する。

既存の prose 注記 (`modules/worktree-lifecycle.md § Edit/Write path conventions in worktree sessions`) は documentation として維持し、hook 参照の 1 行を追加する。 初回実装で更新した `skills/*/SKILL.md` (verify / spec / review) の cross-reference も維持 (変更なし) 。

## Changed Files

- `scripts/hook-worktree-path-guard.sh`: 新規。 PreToolUse hook 本体、bash 3.2+ 互換、`INPUT=$(cat)` → jq で `tool_name` / `tool_input.file_path` を parse → cwd 判定 → block/allow 判定 → exit 2 + stderr で block、exit 0 で allow
- `hooks/hooks.json`: 編集。 既存 `UserPromptSubmit` エントリの隣に `PreToolUse` エントリを追加。 matcher: `Edit|Write|NotebookEdit`、command: `${CLAUDE_PLUGIN_ROOT}/scripts/hook-worktree-path-guard.sh`、timeout: 5000
- `tests/hook-worktree-path-guard.bats`: 新規。 bats テスト、4 シナリオ (inside worktree + parent-repo absolute → block、inside worktree + worktree absolute → allow、inside worktree + relative → allow、outside worktree + any → allow)
- `modules/worktree-lifecycle.md`: 編集。 既存 `### Edit/Write path conventions in worktree sessions` サブセクション末尾に「本規約は `scripts/hook-worktree-path-guard.sh` によって PreToolUse hook で機械的に enforce される」旨の 1 行を追加
- `docs/structure.md`: 編集。 `### Scripts` セクションの Phase banner group に `scripts/hook-worktree-path-guard.sh` を追加 (structure.md maintenance rule に従う)

**Steering Docs sync candidates:**
- `docs/ja/structure.md`: [Steering Docs sync candidate] `docs/structure.md` の変更を日本語 mirror にも反映

## Implementation Steps

1. `scripts/hook-worktree-path-guard.sh` を新規作成 (bash 3.2+ 互換、実行可能パーミッション付与) 。 `scripts/hook-rename-on-auto.sh` の入力 parse パターンを踏襲。 ロジック (→ AC1):
   - `INPUT=$(cat)` で stdin JSON を読む
   - `TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')` で tool_name を抽出
   - `FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')` で file_path を抽出
   - case で `Edit|Write|NotebookEdit` 以外は `exit 0`
   - `FILE_PATH` が空なら `exit 0` (defensive)
   - `CWD=$(pwd)` を取り `[[ "$CWD" != *".claude/worktrees/"* ]]` なら `exit 0`
   - `WORKTREE_ROOT` 抽出: `sed -E 's|(\.claude/worktrees/[^/]+).*|\1|'`
   - `PARENT_REPO` 抽出: `WORKTREE_ROOT` から `/.claude/worktrees/...` を strip
   - `FILE_PATH` が `/` で始まらない (relative) なら `exit 0`
   - `FILE_PATH` が `$WORKTREE_ROOT/` prefix なら `exit 0`
   - `FILE_PATH` が `$PARENT_REPO/` prefix で worktree 外なら stderr に規約メッセージを書いて `exit 2`
   - それ以外 (例: `/tmp` や他 repo path) は `exit 0`

2. `hooks/hooks.json` を編集 (after 1) 。 既存 `UserPromptSubmit` エントリを保持しつつ `PreToolUse` エントリを追加 (→ AC2):
   ```json
   {
     "hooks": {
       "UserPromptSubmit": [ ... 既存のまま ... ],
       "PreToolUse": [
         {
           "matcher": "Edit|Write|NotebookEdit",
           "hooks": [
             {
               "type": "command",
               "command": "${CLAUDE_PLUGIN_ROOT}/scripts/hook-worktree-path-guard.sh",
               "timeout": 5000
             }
           ]
         }
       ]
     }
   }
   ```

3. `tests/hook-worktree-path-guard.bats` を新規作成 (parallel with 1) 。 4 シナリオを検証 (→ AC3):
   - `@test "inside worktree + parent-repo absolute path → exit 2 (block)"`: cd `$FIXTURE_WORKTREE`; hook に `{"tool_name":"Edit","tool_input":{"file_path":"/fixture/parent/docs/foo.md"}}` を渡し、exit 2 かつ stderr に "hook-worktree-path-guard" キーワードが出ることを確認
   - `@test "inside worktree + worktree absolute path → exit 0 (allow)"`: cd `$FIXTURE_WORKTREE`; `file_path` を `$FIXTURE_WORKTREE/docs/foo.md` にして exit 0
   - `@test "inside worktree + relative path → exit 0 (allow)"`: cd `$FIXTURE_WORKTREE`; `file_path` を `docs/foo.md` にして exit 0
   - `@test "outside worktree + any path → exit 0 (allow)"`: cd parent main; `file_path` を parent-repo absolute にして exit 0
   - setup で `$FIXTURE_PARENT/.claude/worktrees/test-issue` ディレクトリ構造を作成、teardown でクリーンアップ

4. `modules/worktree-lifecycle.md` の既存 `### Edit/Write path conventions in worktree sessions` サブセクション末尾 (`How to verify CWD` bullet の直後) に 1 行を追加 (parallel with 1) (→ AC4):
   ```markdown
   **Enforcement**: This convention is mechanically enforced by `scripts/hook-worktree-path-guard.sh` (registered as a PreToolUse hook in `hooks/hooks.json`), which blocks Edit/Write calls whose `file_path` is an absolute parent-repo path while the session is inside a worktree.
   ```

5. `docs/structure.md` の `### Scripts` セクション、`**Phase banner:**` グループ末尾に `scripts/hook-worktree-path-guard.sh` の 1 行を追加 (parallel with 1) (→ AC5):
   ```markdown
   - `scripts/hook-worktree-path-guard.sh` — PreToolUse hook: blocks Edit/Write calls with parent-repo absolute file_path while inside a worktree session (structural enforcement of `modules/worktree-lifecycle.md § Edit/Write path conventions in worktree sessions`)
   ```
   `docs/ja/structure.md` にも同等の日本語エントリを追加 (translation-workflow.md sync)

## Verification

### Pre-merge

- <!-- verify: file_exists "scripts/hook-worktree-path-guard.sh" --> `scripts/hook-worktree-path-guard.sh` が新規作成され、bash 3.2+ 互換で PreToolUse hook として動作する (AC1)
- <!-- verify: file_contains "hooks/hooks.json" "PreToolUse" --> <!-- verify: file_contains "hooks/hooks.json" "hook-worktree-path-guard.sh" --> `hooks/hooks.json` に `PreToolUse` エントリが追加され Edit / Write / NotebookEdit tool を対象に `${CLAUDE_PLUGIN_ROOT}/scripts/hook-worktree-path-guard.sh` を呼び出す (AC2)
- <!-- verify: file_exists "tests/hook-worktree-path-guard.bats" --> <!-- verify: command "bats tests/hook-worktree-path-guard.bats" --> `tests/hook-worktree-path-guard.bats` が新規作成され 4 シナリオを検証している (AC3)
- <!-- verify: section_contains "modules/worktree-lifecycle.md" "## Notes" "hook-worktree-path-guard" --> `modules/worktree-lifecycle.md § Edit/Write path conventions in worktree sessions` の末尾に hook による自動 enforce の言及が追加されている (AC4)
- <!-- verify: file_contains "docs/structure.md" "hook-worktree-path-guard.sh" --> `docs/structure.md` の scripts リストに `hook-worktree-path-guard.sh` が追加されている (AC5)

### Post-merge

- 次回 verify/spec/code session で worktree Entry 後に LLM が誤って parent-repo absolute path で Edit/Write を呼んだ場合、hook で block されて stderr に規約メッセージが表示されることを観察 <!-- verify-type: observation event=worktree-path-block -->

## Consumed Comments

- saito / MEMBER / first-class / verify FAIL iteration 1: 2026-07-03 の #876 code phase で prose 注記が読み飛ばされ絶対 main-repo path 誤用の rework が発生 → structural fix (hook) が必要 / https://github.com/saitoco/wholework/issues/860#issuecomment-4872092896
- saito / MEMBER / first-class / verify-fail marker: 未 check の manual AC を FAIL 判定、phase/* labels 除去、hook による structural enforce を次期実装で / https://github.com/saitoco/wholework/issues/860#issuecomment-4872093551

## Notes

- **Revised design**: 初回の "prose 注記のみ" 実装 (2026-06-30 merge) は verify FAIL となったため、本 Spec は **PreToolUse hook による structural enforcement** を追加する
- 既存の prose 注記 (`modules/worktree-lifecycle.md § Edit/Write path conventions in worktree sessions` および `skills/verify/SKILL.md` / `skills/spec/SKILL.md` / `skills/review/SKILL.md` の cross-reference) は削除せず維持。 documentation として引き続き有用、hook との併用で defense-in-depth
- Hook の block 動作は exit 2 + stderr message。 Claude Code hooks API の standard block 動作に従い、stderr message は次の tool call で Claude に返される (先例: `scripts/hook-rename-on-auto.sh` の bash 3.2+ 互換パターン)
- Edit/Write の合法的な parent-repo path 使用 (worktree 外の parent main 直接編集) は cwd 判定で自動的に allow (cwd が `.claude/worktrees/` を含まない場合は無条件 allow)
- `PreToolUse` matcher は `Edit|Write|NotebookEdit` の 3 tool。 `Bash` は対象外 (bash script 経由の parent-repo file 書き込みは合法 use case の方が多い、例: `gh-issue-edit.sh` の `.tmp/` 書き込み)
- **Uncertainty**: Claude Code の PreToolUse hook 出力仕様として exit 2 + stderr が block を意味することは `scripts/hook-rename-on-auto.sh` の UserPromptSubmit 実装から類推。 PreToolUse では要検証。 検証方法: bats test の block シナリオで exit 2 を assert し、実運用時に Claude Code が block message を Claude に返すかを observe (post-merge AC)
- 本 Issue の初回 Spec が light 5-item 上限で書かれていたが、AC 数は 5 のまま維持 (impl steps も 5 で fit)

## Code Retrospective

### Deviations from Design
- 実装を 4 ステップ別コミット (modules/worktree-lifecycle.md → verify → spec → review) に分割した。Spec の「実装 step 1-4」に対応する個別コミットであり意図的。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- **Revised design**: 初回実装 (prose 注記のみ) が verify FAIL となったため、本 Spec で PreToolUse hook による structural enforcement を追加する
- Hook script は `scripts/hook-rename-on-auto.sh` のパターン (bash 3.2+ 、jq JSON parse、`INPUT=$(cat)`) を踏襲。 exit 2 + stderr message で block、exit 0 で allow
- Matcher は `Edit|Write|NotebookEdit` の 3 tool。 Bash tool は対象外 (bash script 経由の parent-repo write は合法 use case が多いため)
- 既存の prose 注記 (`modules/worktree-lifecycle.md`) は削除せず、hook 参照の 1 行を追加する形で維持 (defense-in-depth)

### Deferred Items
- Post-merge AC は observation type: 次回 verify/spec/code session で hook block が発火することを実運用で確認
- Claude Code の PreToolUse hook exit 2 + stderr の block API 仕様は Notes の Uncertainty で記録。 bats test で exit 2 を assert しつつ、実運用時の Claude 側の応答 (block message を受けて次 tool call を修正) は observe 段階で確認

### Notes for Next Phase
- **前回の実装 (prose 注記のみ) は既に main に merge 済み**。 本 Spec は「その上に hook を追加」する additive 変更。 既存 prose 注記および `skills/*/SKILL.md` の cross-reference は削除しないこと
- Changed Files 5 個。 Axis 1 は M (3-5 files) に該当し、CI-sensitive (hook が全 Edit/Write に発火) なので M 最低ライン。 patch route → pr route に bump される (Post-Spec Size Refresh で自動判定される想定)
- Test data 形式: bats test は stdin JSON payload を `bash -c "cat << EOF"` heredoc または `printf` で hook に渡す。 詳細は Implementation Step 3 参照
- Hook 実装後、実際の Claude Code session で block が発火するかは実行時観察のみで確認可能 (bats は hook スクリプト単体の unit test)
