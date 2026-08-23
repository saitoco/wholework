# Issue #1454: worktree-lifecycle: cd による isolation guard 回避で git write が main へ誤着地

## Overview

worktree isolation セッション中に単純な `cd /path/to/main/repo` (compound でも `-C` redirect でもない単発 Bash コマンド) を実行すると、`hook-worktree-path-guard.sh` は Edit/Write/NotebookEdit/Read の4ツールしか監視していないため素通りし、その後の CWD 相対コマンド (`git commit` を含む) が main リポジトリの現在ブランチに対して直接実行されてしまう。

本 Spec は、実際にインシデントが発生した `scripts/append-consumed-comments-section.sh` (git write を伴うスクリプト) に、呼び出し契約 (`--no-push` = 「worktree 内で実行され、push は呼び出し元の Exit path が担う」という前提) と実際の CWD 状態 (main tree か isolated worktree か) の不一致を検知して書き込み前に abort する防御チェックを追加する。あわせて `modules/worktree-lifecycle.md` に「worktree セッション中に親リポジトリへ戻る場合は `cd` ではなく `ExitWorktree` を使うこと」を明記する。

## Reproduction Steps

1. `/verify` などの worktree セッション中 (`EnterWorktree` 済み) に、Bash ツールで `cd /path/to/main/repo && bash scripts/append-consumed-comments-section.sh <N> verify --no-push` のような単発コマンドを実行する (誤操作)。
2. `hook-worktree-path-guard.sh` の `PreToolUse` matcher は `Edit|Write|NotebookEdit|Read` のみが対象のため (`hooks/hooks.json`)、Bash 経由の `cd` はブロックされない。
3. `append-consumed-comments-section.sh` 内で `_repo_root="$(git rev-parse --show-toplevel ...)"` が main リポジトリのパスに解決される。スクリプトは「not running inside an isolated worktree」という警告 (line 191) を出すが、処理を継続し `git -C "$_repo_root" commit` を実行する。
4. `--no-push` が指定されているため push はスキップされるが、コミット自体は main リポジトリが現在チェックアウトしているブランチ (通常 `main`) に直接着地する。
5. 後続の (無関係な) `git push` — 例えば同一セッション内の別フェーズの worktree Exit (`worktree-merge-push.sh`、`--from` なしの lock+push のみ) — がこの main ローカルブランチをそのまま origin へ push し、意図しないコミットが `main` に反映される。

## Root Cause

`scripts/append-consumed-comments-section.sh` は「`--no-push` フラグが立っている場合、push は呼び出し元 (worktree セッションの Exit path) の責務」という契約で設計されている (`modules/worktree-lifecycle.md` § "Spec file write destination")。しかしこの契約は「呼び出し時の CWD が実際に isolated worktree 内である」ことを前提としており、スクリプト自身は `_git_dir`/`_git_common_dir` の比較で main tree 実行を検知して**警告こそ出すが、コミット自体は止めない** (line 185-192、line 194 以降)。

`hook-worktree-path-guard.sh` は Edit/Write/NotebookEdit/Read の4ツールのみを対象とする PreToolUse hook であり (`modules/worktree-lifecycle.md` § Enforcement)、Bash 経由の `cd` そのものやその後の CWD 相対プレーンコマンドは監視対象外。この2つのギャップ (hook 側が cd を見ていない、スクリプト側が警告のみで続行する) が重なることで、`--no-push` の前提が崩れた状態でも書き込みが実行されてしまう。

## Changed Files

- `scripts/append-consumed-comments-section.sh`: `--no-push` と「main tree 実行 (isolated worktree でない)」が同時に成立する場合、Spec ファイルへの書き込み・git commit の**前に** abort する防御チェックを追加。既存の worktree 検知ロジック (`_git_dir`/`_git_common_dir` 比較) を早期実行・共通変数化し、警告のみだった既存分岐と push 経路分岐からも再利用する — bash 3.2+ 互換
- `modules/worktree-lifecycle.md`: `## Notes` に新規サブセクション「`cd` で親リポジトリへ戻らないこと」を追加し、`ExitWorktree(action: "keep")` を使うべきことを明記
- `tests/append-consumed-comments-section.bats`: 新規 `@test` を追加し、`--no-push` + main tree の組み合わせで abort (非ゼロ終了・Spec ファイル無変更・commit 未実行) することを検証
- Issue #1454 本文の AC2 verify command: `file_contains` の検索対象を "cd ではなく" (日本語) から実装が実際に導入する英語表現 "instead of `cd`" に修正 (詳細は Notes) — `gh-issue-edit.sh` で本 Spec 作成と同一フェーズ内に反映済み
- [Steering Docs sync candidate] keyword "append-consumed-comments-section.sh" skipped: matched 43 files (no discriminating power)
- [Steering Docs sync candidate] keyword "worktree-lifecycle.md" skipped: matched 73 files (no discriminating power)

## Implementation Steps

1. (→ acceptance criteria A) `scripts/append-consumed-comments-section.sh` を修正する。
   - `_repo_root` 解決の直後に `_git_dir`/`_git_common_dir` を解決し、両者が一致する場合に `_in_main_tree=true` とする判定を追加する (既存の line 185-192 相当のロジックを前倒しする)。
   - `NO_PUSH == true && _in_main_tree == true` の場合、`ERROR` メッセージを stderr に出力して `exit 1` する — Spec ファイルの読み込み・書き込みより前に判定すること (中途半端なファイル変更を残さないため)。
   - `git rev-parse --git-dir`/`--git-common-dir` 自体が失敗した場合 (非 git 環境など) は両変数が空文字列になり `_in_main_tree` は `false` のままとなる (fail-open) — 「main tree と確定できたとき」だけ block し、それ以外の失敗はこのスクリプトの既存の best-effort 方針 (常に exit 0 を維持) を壊さない。
   - line 185-192 の既存警告分岐と line 204 相当の push 経路分岐を、`_git_dir`/`_git_common_dir` の再計算ではなく新しい `_in_main_tree` 変数を参照する形にリファクタリングする (git rev-parse の重複呼び出しを削減)。
2. (after 1) (→ acceptance criteria B) `modules/worktree-lifecycle.md` の `## Notes` に、"### Edit/Write path conventions in worktree sessions" と "### Main-repo-only Steps inside a worktree session" の間へ新規サブセクション "### Do not `cd` back to the parent repository" を挿入する。`hook-worktree-path-guard.sh` が Bash `cd` を監視しないこと、Issue #1454 の実インシデント、`ExitWorktree(action: "keep")` を代わりに使うべきことを明記する。
3. (after 1) (→ acceptance criteria C) `tests/append-consumed-comments-section.bats` に新規 `@test` を追加する。既存の "not in worktree" / "main tree execution without --no-push" テストと同じ main-tree 用 `git` モック (git-dir == git-common-dir) を使い、`--no-push` 付きで実行した場合に非ゼロ終了・stderr に "ERROR" を含む・Spec ファイルに `## Consumed Comments` が追加されない・`git.log` に `commit` が記録されないことを検証する。
4. (after 1, 2, 3) (→ acceptance criteria D) `bats tests/` を実行し全件 PASS することを確認する。

## Verification

### Pre-merge

- <!-- verify: rubric "worktree セッション中に cd で親リポジトリへ移動した場合に検知・警告・block のいずれかが行われる機構が実装されている" --> worktree セッション中の `cd` によるセッション外移動を検知する機構が実装されている、または git write を伴うスクリプト側に想定外 CWD の防御的チェックが追加されている
- <!-- verify: rubric "modules/worktree-lifecycle.md に、worktree セッション中に親リポジトリへ戻る場合は cd ではなく ExitWorktree を使うことが明記されている" --> <!-- verify: file_contains "modules/worktree-lifecycle.md" "instead of `cd`" --> `modules/worktree-lifecycle.md` に、worktree セッション中の親リポジトリ復帰には `cd` ではなく `ExitWorktree` を使うことが明記されている
- <!-- verify: rubric "tests/ 配下に本 Issue の検知/防御機構を検証する bats テストが追加されている" --> bats テストが追加され、想定外 CWD での git write 試行が検知されることを検証している
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

なし

## Notes

- **AC2 verify command の言語不整合修正**: Issue 本文の AC2 は `<!-- verify: file_contains "modules/worktree-lifecycle.md" "cd ではなく" -->` (日本語) を指定していたが、`modules/worktree-lifecycle.md` は CLAUDE.md の Language Conventions 表で `Documentation | English` (module docs を含む) と定められており、日本語の地の文は導入できない。`file_contains` は固定文字列検索であり (`modules/verify-executor.md` の定義)、実装が英語で書かれる以上 "cd ではなく" は本文中に一切出現せず、この verify command は恒久的に FAIL する。「Verify command sync rule」(Issue 本文の verify command を逐語的に Spec へ転記する) より、この言語制約の方が優先すると判断し、`file_contains` の検索対象を実装が実際に導入する英語表現 "instead of `cd`" (Implementation Step 2 の新規サブセクション本文に含まれる) に置き換えた。rubric 側の文言 (日本語) はドキュメント内容そのものではなく grader への指示であるため変更していない。Issue 本文側の AC2 verify command も本 Spec 作成と同一フェーズ内で `gh-issue-edit.sh` により同じ表現に修正済み (Spec とのズレを残さないため)。
- **防御チェックの対象範囲を「main tree か否か」に限定した判断**: Issue 本文の Auto-Resolved Ambiguity Points は「`_repo_root` を想定 worktree root と比較する防御チェック」という表現を含むが、`append-consumed-comments-section.sh` は Issue 番号のみを引数に取り (`/review`・`/merge` は PR 番号ベースの worktree 名 `review+pr-N`/`merge+pr-N` を使うため、Issue 番号から期待される worktree パスを一意に逆算できない)、フェーズごとに異なる worktree 命名規則を正確に再構成するのは脆弱と判断した。代わりに「`--no-push` は『isolated worktree 内で実行される』という契約そのものであり、main tree (`_git_dir == _git_common_dir`) で実行されていればこの契約は破られている」という、呼び出し規約と既存の worktree 検知ロジックのみに依拠したチェックを採用した。これは実インシデントのパターン (main tree への完全な離脱) を過不足なく捕捉し、`run-spec.sh`/`run-code.sh` の Secondary layer (`_append_consumed_comments_section()`、`--no-push` を渡さず main tree から意図的に実行される既存の正当な経路、`modules/l0-surfaces.md` § "Bash wrapper fallback") を誤検知しない。
- **スコープを `append-consumed-comments-section.sh` に限定した判断**: Issue 本文の Auto-Resolved Ambiguity Points で既に決定済み。`git -C`/`git add|commit|push` を含む他スクリプトへの横展開は再発時に別 Issue で扱う。
- **block (非ゼロ終了) を採用した判断**: Issue 本文の Auto-Resolved Ambiguity Points で既に決定済み。実インシデントで警告のみでは commit を止められなかったことが実証されているため。
- **新規テストケース要否**: Implementation Step 1 が `append-consumed-comments-section.sh` に新規分岐 (main tree + `--no-push` の abort) を追加するため、Implementation Step 3 で新規 `@test` を追加する (Verification Pre-merge 3件目に対応)。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1–4 were followed as designed with no reordering, omission, or approach change.

### Design Gaps/Ambiguities
- **Moving the main-tree detection earlier broke a pre-existing test's implicit assumption**: Implementation Step 1 moved `_git_dir`/`_git_common_dir` resolution to immediately after `_repo_root`, per the Spec's design. This is a read-only `git rev-parse` call, but it now runs unconditionally, including on the "section already exists, nothing new to add" fast-exit path. `tests/run-verify.bats`'s "section exists: skip and exit 0 without adding another section" test asserted `[ ! -f "$GIT_LOG" ]` (no git call at all on that path), which the Spec did not anticipate as an impacted file (it only listed `tests/append-consumed-comments-section.bats` in Changed Files). Fixed by narrowing the assertion to "no write/commit call happened" rather than "no git call happened at all", which is what the test actually intends to verify. Takeaway: a Spec's Changed Files list for a shared-helper function's refactor may not exhaustively predict every test file the change touches; the Stale Test Assertion Check module only scans for removed literal strings, not for behavior-based assertions like "call count" that a code-motion refactor can invalidate without removing any string.

### Rework
- One rework cycle: the new `--no-push` + main-tree bats test initially used a bare `[[ "$output" == *"ERROR"* ]]` assertion (copying the surrounding file's existing style), caught by `skills/code/skill-dev-validation.md`'s bash-3.2 bare-bracket-assertion pitfall during the Additional validation pass (Step 9) — not by `check-bare-bracket-assertions.sh` itself, which is informational-only and does not block. Rewrote to `echo "$output" | grep -q "ERROR"` before committing.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Chose a script-side defensive check (abort in `append-consumed-comments-section.sh`) over hook-side `cd` parsing in `hook-worktree-path-guard.sh`, per the Spec's rationale: no existing hook in this repo parses Bash `tool_input.command`, and reliable parsing of compound commands/subshells/aliases is fragile there, while the script already resolves `_repo_root` and reuses that pattern.
- Positioned the `NO_PUSH && _in_main_tree` abort check immediately after `_repo_root`/`_git_dir`/`_git_common_dir` resolution — before any Spec file read or write — so a blocked run never leaves a partial file edit behind.
- Scoped the defensive check to `append-consumed-comments-section.sh` only, matching the Issue's Auto-Resolved Ambiguity Points; other git-write scripts (`apply-fallback.sh`, `worktree-merge-push.sh`, etc.) are explicitly out of scope for this Issue.

### Deferred Items
- Extending the same main-tree defensive check to other git-write scripts is deferred to a follow-up Issue if the same failure mode recurs there (Issue body Auto-Resolved Ambiguity Points, "スコープを `append-consumed-comments-section.sh` に限定した判断").
- hook-side `cd` detection in `hook-worktree-path-guard.sh` was considered and explicitly not implemented (AC1's "検知・警告・block のいずれか" wording permits the script-side-only approach chosen here).

### Notes for Next Phase
- Confirm the new `### Do not \`cd\` back to the parent repository` subsection in `modules/worktree-lifecycle.md` reads cleanly in its inserted position (between "Edit/Write path conventions in worktree sessions" and "Main-repo-only Steps inside a worktree session").
- The script's abort message cites `modules/worktree-lifecycle.md § "Do not \`cd\` back to the parent repository"` by heading text — if the heading is renamed, update the message to match.
- `tests/run-verify.bats`'s "section exists" test assertion was narrowed during this phase (see Code Retrospective's Design Gaps/Ambiguities) — worth a second look to confirm the narrowed assertion still captures the property it's meant to guard.
- Full suite verified locally: `bats --jobs 18 tests/` → 2012/2012 PASS.

## Consumed Comments
No new comments since last phase.
