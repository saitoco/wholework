# Issue #971: worktree-lifecycle: 絶対パス誤参照 (worktree セグメント欠落) の防止策を追加

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 2026-07-10T18:25:24Z
  - 要旨: `/issue 971 --non-interactive` の Issue Retrospective。Proposal A ( `hook-worktree-path-guard.sh` を Read ツールにも拡張) の採用理由、Read 誤参照時はブロック (exit 2、警告のみは不採用) とする判断、`modules/worktree-lifecycle.md` の Scope limit 記述更新をスコープに含める判断、AC を 4 件に具体化した経緯を記録。Blocked-by なし (exit 0) も確認済み。
  - URL: https://github.com/saitoco/wholework/issues/971#issuecomment-4938325985

## Overview

worktree セッション中、絶対パスでファイルを参照する際に worktree セグメント (`.claude/worktrees/{name}/`) を欠落させ、共有メインリポジトリ側を誤って参照・編集する事象が Issue #961 の code / review 両フェーズで独立に再発した。既存の `scripts/hook-worktree-path-guard.sh` (PreToolUse hook) は Edit/Write/NotebookEdit の絶対パス誤用を機械的にブロックしているが、Read ツールでの誤参照はガード対象外だった。本 Issue は `hook-worktree-path-guard.sh` を Read ツールにも拡張し、既存の Edit/Write と同じ exit 2 ブロック挙動を適用する (Proposal A、Issue Retrospective コメントで採用確定済み)。

Codebase Investigation で、Issue 本文が言及していなかった追加の必須変更点が判明した。`hooks/hooks.json` の `PreToolUse` エントリの `matcher` (`"Edit|Write|NotebookEdit"`) は、Claude Code がこの hook を起動するかどうかを決めるツール名フィルタそのものであり、これを Read 対応させない限り、script 内の `TOOL_NAME` case 文を拡張しても Read ツール呼び出し自体がフックに到達しない。この発見を Issue 本文の Pre-merge Acceptance Criteria (5 件目) と本 Spec に反映済み。

## Changed Files

- `hooks/hooks.json`: `PreToolUse` エントリの `matcher` を `"Edit|Write|NotebookEdit"` → `"Edit|Write|NotebookEdit|Read"` に変更 (Codebase Investigation で判明した追加必須変更。Issue 本文の Proposal 記述には元々含まれていなかった)
- `scripts/hook-worktree-path-guard.sh`: `TOOL_NAME` の case 文を `Edit|Write|NotebookEdit)` → `Edit|Write|NotebookEdit|Read)` に変更 — bash 3.2+ compatible (既存 case 文パターンへの追加のみ)
- `tests/hook-worktree-path-guard.bats`: Read ツール向けの block (parent-repo 絶対パス → exit 2) / allow (worktree 絶対パス → exit 0) テストケースを追加
- `modules/worktree-lifecycle.md`: § Notes の Enforcement/Scope limit 段落 (133 行目) を Read 対応を反映して更新 ( `only the Edit/Write/NotebookEdit tools` の文言を除去)
- `docs/structure.md`: [Steering Docs sync candidate] 172 行目の `hook-worktree-path-guard.sh` 一行要約 ("blocks Edit/Write calls") を確認 — grep 済み、NotebookEdit 言及も省略した既存の簡略表現のため今回は変更不要と判断 ( `/code` で再確認望ましい)
- `docs/ja/structure.md`: [Steering Docs sync candidate] 165 行目、同上 (ja mirror)

## Implementation Steps

1. `hooks/hooks.json` の `PreToolUse` エントリの `matcher` に `Read` を追加する ( `"Edit|Write|NotebookEdit"` → `"Edit|Write|NotebookEdit|Read"` ) (→ acceptance criteria AC5)
2. `scripts/hook-worktree-path-guard.sh` の `TOOL_NAME` case 文に `Read` を追加する ( `Edit|Write|NotebookEdit)` → `Edit|Write|NotebookEdit|Read)` )。`FILE_PATH` 抽出行 ( `.tool_input.file_path // .tool_input.notebook_path // empty` ) は Read ツールも `file_path` を使うため変更不要 (parallel with 1) (→ acceptance criteria AC1, AC2)
3. `tests/hook-worktree-path-guard.bats` に、既存の Edit 向けテスト ( `"inside worktree + parent-repo absolute path -> exit 2 (block)"` 等) と同じパターンで Read 向けテストケースを 2 件追加する: (a) parent-repo 絶対パス → exit 2 (block)、(b) worktree 絶対パス → exit 0 (allow) (parallel with 1, 2) (→ acceptance criteria AC3)
4. `modules/worktree-lifecycle.md` の Enforcement/Scope limit 段落 (133 行目) を更新し、"blocks Edit/Write calls" → "blocks Edit/Write/Read calls"、"the hook matches only the Edit/Write/NotebookEdit tools" → "the hook matches the Edit/Write/NotebookEdit/Read tools" に変更する (parallel with 1-3) (→ acceptance criteria AC4)

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/hook-worktree-path-guard.sh" "Read" --> `hook-worktree-path-guard.sh` の対象ツール判定 (`TOOL_NAME` の case 文) に `Read` が追加され、既存の `Edit|Write|NotebookEdit` と同様に扱われる
- <!-- verify: rubric "hook-worktree-path-guard.sh が worktree セッション中に Read ツールで parent-repo 側の絶対パス (worktree セグメント欠落) を参照した場合、既存の Edit/Write と同じ exit 2 ブロック挙動で防止する" --> Read ツールでの絶対パス誤参照が Edit/Write と同様にブロックされる
- <!-- verify: grep "Read" "tests/hook-worktree-path-guard.bats" --> 既存の bats テストファイルに Read ツール向けのテストケースが追加されている
- <!-- verify: file_not_contains "modules/worktree-lifecycle.md" "only the Edit/Write/NotebookEdit tools" --> `modules/worktree-lifecycle.md` の Enforcement/Scope limit 記述が Read 対応を反映して更新されている (Edit/Write のみという記述が残っていない)
- <!-- verify: file_contains "hooks/hooks.json" "Read" --> `hooks/hooks.json` の `PreToolUse` フック登録の `matcher` (`"Edit|Write|NotebookEdit"`) に `Read` が追加されている

### Post-merge

なし

## Notes

- **Auto-Resolve Log は Issue Retrospective コメントを参照**: Proposal A 採用理由、Read 誤参照時のブロック挙動 (exit 2、警告のみ不採用)、`modules/worktree-lifecycle.md` 更新をスコープに含める判断は、いずれも `/issue --non-interactive` の Issue Retrospective コメントに記録済み。本 Spec では重複記載しない。
- **`hooks/hooks.json` matcher の発見経緯**: Issue 本文・Retrospective コメントいずれも `scripts/hook-worktree-path-guard.sh` 内部の `TOOL_NAME` case 文の拡張にのみ言及していたが、Codebase Investigation で `hooks/hooks.json` の `PreToolUse` エントリの `matcher` フィールドが Claude Code 側のツール名フィルタそのものであることが判明した。これを更新しない限り、script 側だけをいくら拡張しても Read ツール呼び出しがそもそも hook に到達せず、AC2 の rubric ("Read ツールでの絶対パス誤参照が Edit/Write と同様にブロックされる") が実際には満たされない。この判断は非対話モードでの自動解決 (AskUserQuestion 不使用) として、Issue 本文の Pre-merge AC に 5 件目 (`file_contains "hooks/hooks.json" "Read"`) を追加する形で反映し、本 Spec の Verification 節にも同一の verify command をコピーした (Issue 本文が SSoT、`modules/verify-patterns.md` §18 準拠)。
- **`docs/structure.md` / `docs/ja/structure.md` 一行要約のリネームは見送り**: `hook-worktree-path-guard.sh` を grep した結果、両ファイルとも "blocks Edit/Write calls" という一行要約 (NotebookEdit 言及も元々省略された簡略表現) がヒットした。今回の変更に伴い "blocks Edit/Write/Read calls" 等へ更新することも検討したが、AC4 が要求するスコープは `modules/worktree-lifecycle.md` の Scope limit 文言の是正のみであり、`docs/structure.md` の一行要約は既存の簡略化された表現の範囲内 (NotebookEdit 追加時も更新されていない) と判断し、今回は Changed Files に Steering Docs sync candidate として残すに留めた。
- **`modules/worktree-lifecycle.md` のセクション見出し ( `### Edit/Write path conventions in worktree sessions` ) のリネームも見送り**: 見出し名自体を "Edit/Write/Read path conventions" 等に変更すると、`docs/structure.md`・`docs/ja/structure.md`・`scripts/hook-worktree-path-guard.sh` の echo メッセージ内の cross-reference 文字列 (`§ Edit/Write path conventions in worktree sessions`) や過去の disposable Spec ( `docs/spec/issue-860-*.md` 等) への波及確認が必要になり、AC4 が要求するスコープ (Scope limit 文言の是正) を超える。AC4 の `file_not_contains` は見出し名ではなく Enforcement 段落内の特定フレーズのみを対象としているため、見出し名は変更せず据え置く。
- **関連 Issue #888 (CLOSED / phase/done) の確認**: `hook: claude -p サブプロセスセッションでの hook-worktree-path-guard.sh 発火を検証` は解決済み。hook 自体の起動メカニズム (`--plugin-dir` 経由のプラグインロード) は実行環境で健全であることが既に確認されており、本 Issue の実装を妨げる要因はない。

## Code Retrospective

### Deviations from Design
- Implementation Steps に明記されていなかった軽微な追加として、`scripts/hook-worktree-path-guard.sh` 冒頭のヘッダーコメント (`# PreToolUse hook: block Edit/Write/NotebookEdit calls ...`) も `Read` を含む記述に更新した。同じファイル・同じ行が対象とする `TOOL_NAME` case 文の直近にあり、更新しないと case 文の変更内容とヘッダーコメントの記述が食い違うため、ドキュメント整合性維持の一環として実施した。AC・Verification には影響しない。

### Design Gaps/Ambiguities
- N/A — Spec の Codebase Investigation (`hooks/hooks.json` matcher の発見) により、実装時に新たな設計ギャップは見つからなかった。

### Rework
- N/A — Implementation Steps 1-4 を計画通り実装し、bats テスト (9/9 PASS) と5件の pre-merge verify command が初回実行で全て PASS した。

## review retrospective

### Spec vs. implementation divergence patterns
- Nothing to note — Implementation Steps 1-4 と PR diff は 1:1 対応しており、構造的な乖離は検出されなかった (review-light Perspective 1 で確認済み)。

### Recurring issues
- Nothing to note — MUST/SHOULD/CONSIDER いずれの指摘も発生しなかった。

### Acceptance criteria verification difficulty
- Nothing to note — 5件の verify command (file_contains ×2, grep, file_not_contains, rubric) はいずれも曖昧さなく機械的に判定でき、UNCERTAIN は発生しなかった。code フェーズで既に PASS 済みだった内容を review フェーズで独立に再検証し、同じ結果 (全PASS) を得た。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #985 は mergeable=true (clean, CI success, review approved) であったため、conflict resolution はスキップし squash merge を直接実行。
- squash merge 後、worktree ブランチを `origin/main` に ff-only で追従させ、同一 commit 上で Phase Handoff を書き込む通常フローに従った。

### Deferred Items
- Nothing to note — merge フェーズでの追加対応は発生しなかった。

### Notes for Next Phase
- Pre-merge verify command 5件は code/review 両フェーズで PASS 済み。Post-merge verify command はなし (Spec Verification § Post-merge = 「なし」)。
- `/verify 971` は post-merge 確認事項がないため、label transition のみで完了する見込み。

## Auto Retrospective

### Manual recovery (review)
- **Date**: 2026-07-10 19:31 UTC
- **Issue**: #971, phase: review
- **Source**: parent session manual recovery
- **Recovery type**: review-rerun
- **Outcome**: success
