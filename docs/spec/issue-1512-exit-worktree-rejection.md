# Issue #1512: worktree-lifecycle: fork で動くスキルの ExitWorktree が拒否されると worktree が残り、親セッションが閉じ込められる

## Overview

`context: fork` のスキル (`/code`・`/review`・`/merge`) を対話セッションから実行すると、Claude Code はそれをサブエージェントとして起動する。このサブエージェントの `ExitWorktree` が `cwd override` を理由に拒否されることがあるが、現在の `modules/worktree-lifecycle.md` の Exit 手順は拒否を想定していない (push-and-remove は警告 1 行、merge-to-main は失敗時の分岐なし)。その結果、worktree とチェックアウト中のブランチが残り、親セッションの作業ディレクトリも worktree に入ったままになる。

本 Spec は、Exit 手順に「`ExitWorktree` の結果を検証し、失敗したら 1 回再試行し、`keep` で退出できれば Bash で片付け、それもできなければ worktree を残して定型の報告を出す」という結果ベースの分岐を追加し、fork の 3 スキルがその報告を完了報告に必ず含めるようにする。拒否される条件は未特定のため (調査結果は Notes)、分岐はエラー文ではなく結果に依存させる。

## Reproduction Steps

再現は決定的ではない (同一セッションの `/code` 2 件並行と `/merge` は正常に終了し、`/review` だけが拒否された)。Issue 本文の観測 (2026-10-09、saito/trading、Claude Code 2.1.295、macOS) の流れは次のとおり。

1. 対話セッションから `/wholework:review <PR>` を実行する。`context: fork` のためバックグラウンドのサブエージェントとして動く
2. fork の Worktree Entry が `EnterWorktree(name: "review/pr-<N>")` を呼ぶ。成功し、親セッションの作業ディレクトリも `.claude/worktrees/review+pr-<N>` に移る
3. Worktree Exit で `ExitWorktree(action: "remove", discard_changes: true)` を呼ぶと、`ExitWorktree cannot be called from a subagent with a cwd override ...` で拒否される
4. 現行モジュールは警告 1 行を出して続行するだけなので、worktree (PR ブランチをチェックアウト済み) が残り、Opportunistic Verification はスキップされ、親セッションは worktree に閉じ込められたまま (main への git 操作が isolation guard に拒否される) になる

## Root Cause

**直接原因 (Exit 手順と各スキルの記述の欠落)**:

- `modules/worktree-lifecycle.md` の `### Exit: push-and-remove Section` は、`ExitWorktree` の失敗時に `Warning: Failed to remove worktree. Please remove manually.` の 1 行を出して続行するだけで、残った worktree のパス・チェックアウト中のブランチ・復旧手順を記録も報告もしない
- `### Exit: merge-to-main Section` は `ExitWorktree(action: "keep")` の失敗を想定していない。失敗すると後続の `worktree-merge-push.sh --from` が worktree 内で走るが、このスクリプトは base ブランチをチェックアウトしているディレクトリ (通常は main チェックアウト) から実行する前提で動く。worktree 内では `git fetch . <from>:<base>` が base のチェックアウト先 (main チェックアウト) を理由に拒否され、`current_branch` も base ではないため in-place マージにも入らず、`rebase_from_branch_onto` を経由しても最終的に `ref-fetch ... still failed` で終了する。cleanup も警告 1 行のみで、パスが `.claude/worktrees/$WORKTREE_NAME` (名前の `/` を含む) のため、`/` を `+` に置換する実ディレクトリ名 (`spec/issue-1512` → `spec+issue-1512`) と一致しない
- fork スキルの SKILL.md は「`ExitWorktree` を呼ぶ」としか書かず、失敗時に報告する手順がない。`skills/review/SKILL.md` の Opportunistic Verification 前提条件は、`own` を検出すると「Exit 節を完了させて再実行」と指示するが、Exit が拒否された場合は完了できない行き止まりになる (Issue の観測では節ごとスキップされた)

**拒否の発生条件 (未特定)**: Notes の「拒否条件の調査」を参照。

**修正方針の妥当性**: 拒否の条件が未特定でも、「Exit が効いたかどうか」は `scripts/detect-foreign-worktree.sh` の出力で結果から判定できる。判定を結果に置けば、`cwd override` 以外の失敗 (`EnterWorktree(path:)` で入った worktree は `ExitWorktree` が削除しない等) も同じ分岐で扱える。片付けられない場合の最終手段を「残して報告」に固定すれば、条件が何であっても Purpose (後片付けの完了、または残ったものと復旧手順の確実な報告) を満たす。

## Changed Files

- `modules/worktree-lifecycle.md`: 英語のみ (CJK と半角 `!` を持ち込まない)。コマンドは plain な単発コマンドで書く (`$(...)` と `&&` 連結を使わない — worktree isolation guard に拒否されるため)
  - `## Purpose`: 失敗時の扱いも定めることを 1 文追記
  - Entry step 3: `EnterWorktree` の戻り値から `WORKTREE_PATH` と `WORKTREE_BRANCH` を記録する旨を追記
  - `### Exit: merge-to-main Section`: step 1 に検証と失敗処理への参照を追加、step 2 を整理、step 4 の cleanup を記録値ベースにして警告 1 行を削除
  - `### Exit: push-and-remove Section`: step 2 に検証と失敗処理への参照を追加し、警告 1 行のブロックを削除
  - 新規 `### Exit failure handling: ExitWorktree rejected or ineffective (used by both Exit sections)` を push-and-remove セクションの後・`## Output` の前に追加 (Step A〜D と Leftover worktree report の定型)
  - `## Output`: `WORKTREE_PATH`・`WORKTREE_BRANCH`・`WORKTREE_LEFTOVER` を追加
  - `### Main-repo-only Steps inside a worktree session`: `EnterWorktree(path:)` で再入した worktree は `remove` で削除されない旨を 1 文追記
- `skills/code/SKILL.md`: `### Step 14: Worktree Exit` (失敗処理への参照と `WORKTREE_LEFTOVER=true` 時の分岐)、`### Step 15: Opportunistic Verification` (スキップ条件)、`## Completion Report` (報告の出力) — frontmatter は変更不要 (`ExitWorktree`・`git worktree`・`git branch`・`detect-foreign-worktree.sh` は allowed-tools に既存)。`tests/code.bats` の Step 14 構造テスト (特に最初の出現行の前後関係を見る順序検査) を壊さないこと
- `skills/review/SKILL.md`: `## Worktree Exit (push-and-remove)` (失敗処理への参照)、`## Opportunistic Verification` の前提条件 (Leftover check の追加、`own` の記述補正)、`## Completion Report` (報告の出力)。見出し `## Worktree Exit (push-and-remove)` の文言と、Opportunistic Verification 節内の `detect-foreign-worktree.sh`・`none`・`own`・`foreign` は `tests/review.bats` が検査するため維持する
- `skills/merge/SKILL.md`: `### Step 7: Worktree Exit (push-and-remove)` (失敗処理への参照)、`## Completion Report` (報告の出力)
- `tests/worktree-lifecycle.bats`: 新規ファイル — モジュールと 3 スキルの構造テスト。bash 3.2+ 互換 (`mapfile`・連想配列・裸の `[[ ]]` アサーションを使わない)
- [Steering Docs sync candidate] `docs/structure.md`: 新規ファイルの追加 (Listing 側の確認が発火) と doc-checker の Change Type「Project structure changes」に該当。再確認する列挙は 3 つ — Directory Layout の `tests/` 行 (ファイル単位の列挙はないため変更不要の見込み)、Key Files の `modules/worktree-lifecycle.md` 行 (失敗処理を含む旨を追記するか判断)、Key Files の `scripts/detect-foreign-worktree.sh` 行 (使用箇所の列挙に「Exit failure handling の Step A」を追加)。最終判断は `/code`
- [Steering Docs sync candidate] `docs/ja/structure.md`: `docs/structure.md` を更新した場合のみ、`docs/translation-workflow.md` に従って対応箇所 (233 行目付近の `detect-foreign-worktree.sh` 行など) を同期する
- `README.md`: Listing 側の確認の対象だが、ファイル単位の列挙がなく (`docs/structure.md` へのリンクのみ) 変更不要
- [Steering Docs sync candidate] keyword "worktree-lifecycle.md" skipped: matched 81 files (no discriminating power; `grep -rl "worktree-lifecycle.md" docs/ tests/ scripts/ modules/ | wc -l`、履歴の `docs/spec/` と `docs/sessions/` を含む、2026-10-09 計測)
- [Steering Docs sync candidate] keyword "detect-foreign-worktree" skipped: matched 19 files (no discriminating power; 同コマンド・同日。上記の `docs/structure.md` は個々のヒットではなく Change Type と Listing 側の確認から候補にした)
- [Steering Docs sync candidate] keyword "ExitWorktree" skipped: matched 19 files (no discriminating power; 同コマンド・同日)

## Implementation Steps

AC の番号は `## Verification > Pre-merge` の並び順 (AC1〜AC5)。

1. (→ AC1, AC2, AC3) `modules/worktree-lifecycle.md` を編集する。サブステップは同一ファイル内で順に行う。
   1. `## Purpose` に「`ExitWorktree` が拒否されたり効かなかったりした場合の扱い (`Exit failure handling`) も定める」旨を 1 文追記する。
   2. Entry step 3 を「`EnterWorktree` を呼び、戻り値 (`Created worktree at <path> on branch <branch>`) から `WORKTREE_PATH` (絶対パス) と `WORKTREE_BRANCH` を記録する」に拡張する。`path:` 形式 (step 2 の stale 再利用) では渡したパスを `WORKTREE_PATH` とし、`WORKTREE_BRANCH` は worktree 内で `git branch --show-current` を実行して得る。`EnterWorktree` は名前の `/` を `+` に置換する (`review/pr-5` → `.claude/worktrees/review+pr-5`、ブランチ `worktree-review+pr-5`) こと、以降の Exit 手順は `$WORKTREE_NAME` から再導出せずこの 2 値を使うこと、値が手元にない場合は `git worktree list --porcelain` の `branch refs/heads/worktree-<名前の / を + に置換したもの>` の組から読み戻せることを書く。`/review` は Entry の後で PR ブランチへ checkout するが、`WORKTREE_BRANCH` は Entry 直後に記録した `EnterWorktree` 作成ブランチのままとする。
   3. `### Exit: merge-to-main Section` (見出しは変更しない) を直す。
      - step 1: `ExitWorktree(action: "keep")` の直後に「`### Exit failure handling` の Step A で退出を検証し、失敗なら同節に従う。`WORKTREE_LEFTOVER=true` で終わった場合は step 3 と step 4 を実行しない (base ブランチへのマージは main チェックアウトで実行する必要があり、このセッションからは届かない)」を追記する。
      - step 2: Entry で記録済みの `WORKTREE_BRANCH` を以降で使う旨に簡素化する。
      - step 3: 変更なし (`worktree-merge-push.sh --from "$WORKTREE_BRANCH" [--base "$BASE_BRANCH"]`)。
      - step 4: cleanup を `git worktree remove "$WORKTREE_PATH"` と `git branch -d "$WORKTREE_BRANCH"` の plain な 2 コマンドにし (記録値をそのまま代入する)、`Warning: Failed to remove worktree directory...`・`Warning: Failed to delete branch...` の警告 1 行を削除する。実行後に `git worktree list --porcelain` と `git branch --list "$WORKTREE_BRANCH"` で消えたことを確認し、残っていたら警告で止めず `Exit failure handling` の Step D へ進む (マージは着地済みなので復旧手順の (b) は含めない)。
   4. `### Exit: push-and-remove Section` (見出しは変更しない) の step 2 を直す。`ExitWorktree(action: "remove", discard_changes: true)` の直後に「`### Exit failure handling` の Step A で退出と削除を検証し、失敗なら同節に従う」を追記し、`If deletion fails: ... Warning: Failed to remove worktree. Please remove manually.` のブロックを削除して、「この節は警告 1 行だけで終わらない。worktree とブランチが消えているか、`WORKTREE_LEFTOVER=true` で呼び出し元スキルが完了報告に Leftover worktree report を載せるかのどちらかになる」旨の 1 文に置き換える。
   5. push-and-remove セクションの後・`## Output` の前に、新規 `### Exit failure handling: ExitWorktree rejected or ineffective (used by both Exit sections)` を追加する (見出しレベル h3)。構成と必須要素は次のとおり (文言は英語、下記は意図する内容の草案)。
      - **Background (Issue #1512)**: `context: fork` のスキルは対話セッションから起動するとサブエージェントとして動く (`modules/execution-context.md` の「fork context」= headless の `run-*.sh` とは別物と 1 文で区別する)。`EnterWorktree` は通り、親セッションの作業ディレクトリごと worktree に移るが、`ExitWorktree` は次のエラーで拒否されうる。このエラー文を原文のままコードブロックで引用する (AC2 の `cwd override` を満たす): `ExitWorktree cannot be called from a subagent with a cwd override (isolation: "worktree" or explicit cwd) — it would mutate the parent session's process-wide working directory. This agent is already isolated; use Bash with `cd` for directory changes within it.` 拒否後は worktree がブランチをチェックアウトしたまま残り、親セッションの作業ディレクトリも worktree 内に残るため、親が自分で `ExitWorktree(action: "keep")` を呼ぶまで main への git 操作が isolation guard に拒否される。拒否条件は未特定であり、`cwd override` だけが失敗の形でもない (`EnterWorktree(path: ...)` で入った worktree は `ExitWorktree` が削除しない)。よって以降の分岐は **エラー文ではなく結果** に基づき、検証が完了できない・想定外の出力のときは「退出できていない」とみなして削除側ではなく Step D (残して報告) に倒す (fail-closed)。
      - **Step A — verify**: `ExitWorktree` の後に、返り値を問わず `${CLAUDE_PLUGIN_ROOT}/scripts/detect-foreign-worktree.sh "$WORKTREE_NAME"` を単独の plain コマンドで実行する。`none` なら退出済み (`action: "remove"` の場合はさらに `git worktree list --porcelain` と `git branch --list "$WORKTREE_BRANCH"` で worktree とブランチが消えたことを確認し、残っていれば Step C の 2 コマンドを直接実行する)。`none` 以外 (`own`、または `foreign <path>`。`/review` は PR ブランチへ checkout するため自分の worktree でも `foreign` になりうる) は、`cwd override` のエラー・「no worktree session is active」の no-op・その他のメッセージのいずれであっても失敗とみなして Step B へ進む。
      - **Step B — retry once**: 同じ `ExitWorktree` 呼び出しを 1 回だけ繰り返して Step A をやり直す (同じエラー文が断続的に誤報されたとの上流報告がある: anthropics/claude-code#52538)。2 回以上は繰り返さない。
      - **Step C — alternative cleanup (push-and-remove only)**: 失敗した呼び出しが `action: "remove"` なら `ExitWorktree(action: "keep")` を呼んで Step A をやり直す。`none` になれば (`path:` で入った worktree では通常こうなる) main リポジトリに戻っているので、この節の step 1 で push 済みと確認した前提で、記録値を代入した plain コマンドを 1 つずつ実行する: `git worktree remove --force "$WORKTREE_PATH"`、`git branch -D "$WORKTREE_BRANCH"` (ブランチが既に無いのは可)。locked を理由に git が拒否したら `git worktree unlock "$WORKTREE_PATH"` を実行して削除を 1 回だけやり直す。`--force` と `-D` は `discard_changes: true` と同じ契約 (push 済み) を反映したもの。両方成功すれば Exit 完了。`keep` も拒否される、またはコマンドが失敗したら Step D。
      - **Step D — leave and report**: (1) 自分が立っている worktree を削除しない・そのために `cd` や `git -C` で抜けない (削除すると、作業ディレクトリを共有する親セッションが削除済みパスに取り残される。親リポジトリへの `cd` は "Do not `cd` back to the parent repository" の失敗経路そのもの。isolation guard もリダイレクトされた git を拒否する)。(2) `WORKTREE_LEFTOVER=true` にし、worktree にチェックアウト中のブランチを読む。セッションが worktree 内に残っている場合は `git branch --show-current` (plain コマンド)、すでに main に戻っている場合 (merge-to-main の cleanup 失敗) は `git worktree list --porcelain` で `WORKTREE_PATH` の組に記録されたブランチを読む。`/review`・`/merge` では `WORKTREE_BRANCH` ではなく PR ブランチ等になりうる。(3) merge-to-main で失敗した呼び出しが `keep` だった場合は、そのセクションの step 3 と step 4 を実行せず (worktree 内のコミットは base ブランチに未マージ)、報告の復旧手順に (b) のマージを含める。あわせて、成果物が base ブランチに着地していることを前提とする呼び出し元スキルの手順 (例: `/spec` の Spec リンク付き Issue コメントと `ready` への label 遷移、`/code` patch route の Implementation Complete コメントと `verify` への label 遷移、`/verify` の完了報告) も実行せず、(b) の後に完了させる保留事項として報告に書く。退出は成功し cleanup だけ失敗した場合はマージ済みなので、(b) も保留も不要。(4) 呼び出し元スキルの残りの手順のうち main チェックアウトを要せず、かつ上記の保留に当たらないものは続行するが、ネストしたスキルを dispatch する手順 (Opportunistic Verification・Event-based observation scan) はスキップする (残存 worktree のセッションを継承してしまう)。(5) 下記の Leftover worktree report を、呼び出し元スキルが最後に返すメッセージ (完了報告) に含める。サブエージェントの途中出力は親セッションに表示されないため。
      - **Leftover worktree report (fixed format)**: 次の 3 項目を、プレースホルダを実値に置き換えて出力する。項目の番号は維持し、文面はセッションの言語に訳してよく、1 行の警告に縮めてはならない。項目は (1) パス、(2) チェックアウト中のブランチ、(3) 親セッションでの復旧手順の 3 点に限る (理由・未マージ状態などは見出し行と (3) の中に含める)。
        ```
        Worktree left behind: ExitWorktree could not clean up (<one-line reason>). The parent session's working directory may still be inside it.

        1. Path: <WORKTREE_PATH>
        2. Checked-out branch: <output of git branch --show-current> (worktree branch created by EnterWorktree: <WORKTREE_BRANCH>)
        3. Recovery (run in the parent session, in this order):
           a. If the working directory is still inside the worktree (check with pwd, or git commands on the main checkout are refused as "isolated in the worktree"), call ExitWorktree(action: "keep") to return to the main repository.
           b. Only when the base-branch merge did not run (merge-to-main): from the main repository, run <plugin path>/scripts/worktree-merge-push.sh --from "<WORKTREE_BRANCH>" [--base "<BASE_BRANCH>"], then finish the calling skill's steps that follow the push (for /code patch route: the Implementation Complete comment and the verify label transition).
           c. git worktree remove "<WORKTREE_PATH>"   (if git reports the worktree is locked, run git worktree unlock "<WORKTREE_PATH>" first)
           d. git branch -D "<WORKTREE_BRANCH>"   (git branch -d is enough after a merge-to-main merge)
        ```
      - 末尾に 1 文: 直ちに復旧されなかった残骸は、Issue が CLOSED または PR が MERGED になった後で `scripts/reclaim-stale-worktrees.sh` (既定は dry-run) でも回収できる (Notes の "Broader stale worktree/branch reclaim" を参照)。
   6. `## Output` に `WORKTREE_PATH`・`WORKTREE_BRANCH` (Entry で記録)、`WORKTREE_LEFTOVER` (`true` = `Exit failure handling` で worktree を片付けられなかった。既定 `false`) を追加する。
   7. `### Main-repo-only Steps inside a worktree session` に 1 文追記する: `EnterWorktree(path: ...)` で再入した worktree は `ExitWorktree(action: "remove")` では削除されないため、push-and-remove で終わる場合は `Exit failure handling` の Step C で片付く。
2. (after 1) (→ AC4) fork の 3 スキルの SKILL.md を編集する。3 ファイルは互いに独立で並行可。全て英語で書き、半角 `!` を本文に置かない (`scripts/validate-skill-syntax.py` が検出する)。下記の文言は意図する内容の草案。
   1. `skills/code/SKILL.md`: `### Step 14: Worktree Exit` の冒頭 (「Read ... and follow the Exit section appropriate for the route.」の直後) に追加する — 「`/code` は `context: fork` のスキルなので、対話セッションから起動するとサブエージェントとして動き、`ExitWorktree` が `cwd override` で拒否されうる。どちらの Exit セクションでもモジュールの `Exit failure handling` に従い、この Step を警告 1 行だけで終えない。`WORKTREE_LEFTOVER=true` で終わった場合: patch / operate route は push されていないので、deferred bats AC の CI 確認ブロック・Implementation Complete コメント・label transition をスキップし、作業が `$WORKTREE_BRANCH` にコミット済みだが `$BASE_BRANCH` に未マージであることを完了報告に書く。pr route は Step 12 で PR を push 済みなので成果物は損なわれない。どの route でも Step 15 をスキップし、モジュールの Leftover worktree report (パス・チェックアウト中のブランチ・復旧手順) を Completion Report に載せる」。`### Step 15: Opportunistic Verification` の末尾に「Step 14 が `WORKTREE_LEFTOVER=true` で終わった場合もスキップする」を追記する。`## Completion Report` では、route 別 prefix の後・next-action-guide の前に Leftover worktree report を出す旨と、patch / operate route では「Direct commit and push to main complete.」の代わりに「コミット済みだが base ブランチに未マージ」を示す旨を追記する。**注意**: `tests/code.bats` は Step 14 節内で `CI-based bats AC confirmation` と `Implementation Complete comment (patch route, before label transition)` の最初の出現行の前後関係を検査する。挿入する段落にはこの 2 つの文字列を含めない (含めると検査対象の行がずれて、順序検査が意味を失う)。
   2. `skills/review/SKILL.md`: `## Worktree Exit (push-and-remove)` の 2 つ目の段落の後に追加する — 「`/review` は `context: fork` のスキルなので、対話セッションから起動するとサブエージェントとして動き、この呼び出しが `cwd override` で拒否されたり効かなかったりしうる。呼び出しの後はモジュールの `Exit failure handling` (`detect-foreign-worktree.sh` で検証、1 回再試行、代替片付け、できなければ残して報告) に従う。この節を警告 1 行だけで終えない。worktree を片付けられなかった場合は `WORKTREE_LEFTOVER=true` とし、下の Completion Report にモジュールの Leftover worktree report (パス・チェックアウト中のブランチ — ここでは PR ブランチ・復旧手順) を載せる」。`## Opportunistic Verification` の `Precondition` の冒頭に **Leftover check** を追加する — 「Worktree Exit 節が `WORKTREE_LEFTOVER=true` で終わった場合は、この節全体 (Opportunistic Verification と Event-based observation scan の両方) をスキップし、`Skipping Opportunistic Verification — the worktree could not be removed (see the leftover worktree report).` を出力する。ネストした `Skill(skill="wholework:verify", ...)` が残存 worktree のセッションを継承するため。`ExitWorktree` が拒否された後は下の `own` の『Exit 節を完了させる』を完了できない」。`own` の箇条書きには「(その節が `WORKTREE_LEFTOVER=true` で終わった場合は再試行せず、上の Leftover check に従う)」を括弧書きで追記する。`## Completion Report` では、既存のコードブロックの後・next-action-guide の前に「`WORKTREE_LEFTOVER=true` なら Leftover worktree report を出し、`Opportunistic Verification: skipped (worktree not removed)` の 1 行を添える」を追記する。
   3. `skills/merge/SKILL.md`: `### Step 7: Worktree Exit (push-and-remove)` の 2 つ目の段落の後に追加する — 「`/merge` は `context: fork` のスキルなので、対話セッションから起動するとサブエージェントとして動き、この呼び出しが `cwd override` で拒否されたり効かなかったりしうる。呼び出しの後はモジュールの `Exit failure handling` に従う。マージ自体は完了済みなので、ここでの失敗を結果の失敗にはしない。この Step を警告 1 行だけで終えない。worktree を片付けられなかった場合は `WORKTREE_LEFTOVER=true` とし、Completion Report にモジュールの Leftover worktree report (パス・チェックアウト中のブランチ・復旧手順) を載せる」。`## Completion Report` では、固定 prefix「Merge complete.」の直後・next-action-guide の前に Leftover worktree report を出す旨を追記する。
3. (after 1, 2) (→ AC1〜AC4 の回帰、AC5) `tests/worktree-lifecycle.bats` を新規作成する。既存の構造テスト (`tests/phase-handoff.bats`・`tests/review.bats`) の流儀に合わせ、`PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` から各ファイルのパスを組み立て、節の抽出は見出しの先頭一致の `awk` で行う (見出し末尾の括弧書きに依存しない)。既存スイートの PASS だけでなく、新規ロジックを検証する次の新規 `@test` を追加したうえでスイートが PASS することを要求する (AC5 の CI `Run bats tests` job は `tests/` 全体を実行するため新規ファイルを含む)。否定の確認は `run` と `[ "$status" -ne 0 ]` / `[ "$output" = "0" ]` で行う (裸の `! grep` は errexit 下でテストを失敗させない)。
   - `Exit failure handling` 節が存在し、Step A・B・C・D を含む
   - `cwd override` のエラー文を引用している
   - merge-to-main セクションと push-and-remove セクションの両方が `Exit failure handling` を参照している
   - 警告 1 行だけの文言 (`Please remove manually`) がモジュールに残っていない
   - Step A が `detect-foreign-worktree.sh` で検証し、`none` 以外を失敗として扱う
   - Step B が再試行を 1 回に限る
   - Step C が `ExitWorktree(action: "keep")` の後に `git worktree remove` と `git branch -D` を使う
   - Step D が `WORKTREE_LEFTOVER` を設定し、自分の worktree を削除しない
   - Leftover worktree report が Path・Checked-out branch・Recovery の 3 項目を持ち、復旧手順の順序が `ExitWorktree(action: "keep")` → `git worktree remove` → `git branch -D` である (行番号の大小で比較)
   - `## Output` に `WORKTREE_LEFTOVER` がある
   - `skills/code/SKILL.md` の Step 14、`skills/review/SKILL.md` の `## Worktree Exit (push-and-remove)`、`skills/merge/SKILL.md` の Step 7 が `Exit failure handling` と `Leftover worktree report` を参照している
   - 3 スキルの `## Completion Report` が `Leftover worktree report` を参照している
   - `skills/review/SKILL.md` の `## Opportunistic Verification` が `WORKTREE_LEFTOVER` でスキップする
4. (after 1) (→ ドキュメント整合) `docs/structure.md` の Key Files を、Changed Files の候補どおりに再確認する。`scripts/detect-foreign-worktree.sh` 行の「used by」に `modules/worktree-lifecycle.md` Exit failure handling (Step A) を足し、`modules/worktree-lifecycle.md` 行に失敗処理を含む旨を足す必要があれば更新する。更新した場合は `docs/ja/structure.md` の対応箇所も `docs/translation-workflow.md` に従って同期する。更新不要と判断した場合は理由をコミットメッセージか Code Retrospective に残す。
5. (after 1, 2, 3, 4) (→ AC5) 検証を実行する: `bats tests/worktree-lifecycle.bats tests/review.bats tests/code.bats` の後に `bats tests/` 全件 (CI と同じく並列実行する場合は `bats --jobs <N> tests/`。`$(nproc)` は worktree isolation guard に拒否されるので先に `nproc` を単独で実行して値を代入する)、`python3 scripts/validate-skill-syntax.py skills/code/SKILL.md skills/review/SKILL.md skills/merge/SKILL.md`、`bash scripts/check-forbidden-expressions.sh`、`scripts/check-language-convention.py` (CJK が英語限定パスに混入していないこと)、`bash scripts/check-translation-sync.sh` (`docs/structure.md` を更新した場合)。

## Verification

### Pre-merge

- <!-- verify: rubric "modules/worktree-lifecycle.md の Exit 手順 (merge-to-main と push-and-remove の両方) が、ExitWorktree がサブエージェントの cwd override を理由に拒否された場合の扱いを定めている。拒否の理由がエラー文と異なる場合を含め、ExitWorktree の呼び出しが失敗したときに、代替手段で worktree を片付けるか、片付けられなかった worktree を残したまま完了報告で知らせるかのどちらかに分岐することが明記されている。現状の push-and-remove にある『Failed to remove worktree. Please remove manually.』という警告 1 行だけの記述は、この条件を満たさない" --> Exit 手順が ExitWorktree の拒否 (cwd override) を扱っている
- <!-- verify: file_contains "modules/worktree-lifecycle.md" "cwd override" --> Exit 手順の説明に、拒否の原因となったエラー (`cwd override`) の語が含まれている
- <!-- verify: rubric "modules/worktree-lifecycle.md が、ExitWorktree の拒否で worktree を片付けられなかった場合に完了報告へ必ず含める項目を定めている。含める項目は (1) 残った worktree のパス、(2) その worktree でチェックアウト中のブランチ、(3) 親セッションで実行する復旧手順、の 3 点である。(3) には、親セッションの作業ディレクトリが worktree に入ったままの場合に main へ戻す操作から始まり、worktree の削除とローカルブランチの削除までの順序が示されている" --> 片付けられなかった場合の完了報告に、パス・ブランチ・親セッションでの復旧手順 (main への復帰を含む) が定型で含まれる
- <!-- verify: rubric "context: fork のスキル (skills/code/SKILL.md・skills/review/SKILL.md・skills/merge/SKILL.md) のうち worktree を push-and-remove で終了するスキルの Worktree Exit が、ExitWorktree を拒否されて worktree を残したまま完了する場合に、modules/worktree-lifecycle.md の定める 3 項目 (パス・ブランチ・親セッションでの復旧手順) を各スキルの完了報告に出す手順になっている。拒否を報告せずに終了する経路や、警告 1 行だけで終える経路が残っていない" --> fork のスキル (code・review・merge) が拒否を黙って見過ごさず、完了報告に復旧情報を出す
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> All bats tests pass (PR route)

### Post-merge

- 対話セッションから `/review N` を実行して完了したあと、`.claude/worktrees/review+pr-N` が残っていない。または、残った場合に完了報告に復旧手順が出ている <!-- verify-type: manual -->
- 上の実行のあと、親セッションが worktree に閉じ込められたままになっていない (main のチェックアウトに対する git コマンドが拒否されない) <!-- verify-type: manual -->

## Notes

### 拒否条件の調査 (Issue 対応方針 4)

結論: **条件は特定できなかった**。本 Issue の実装は条件に依存しない結果ベースの分岐とし、条件の特定は後続調査に回す。以下は調査で得た根拠と仮説。

- **公式仕様** (2026-10-09 取得、Claude Code 2.1.295)
  - `context: fork` のスキルは `agent` で指定した型のサブエージェントを起動し、**既定でバックグラウンド**で実行する。待機 (前景) になるのは `background: false`、非対話モード (`-p`)、`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`、**同一スキルの先行実行が残っているとき**、スケジュール実行のとき。出典: https://code.claude.com/docs/en/skills § "Run skills in a subagent"
  - サブエージェントは親会話の作業ディレクトリで起動し、サブエージェント内の `cd` は Bash 呼び出し間で保持されず親の作業ディレクトリに影響しない。`EnterWorktree`・`ExitWorktree` はバックグラウンドサブエージェントの組み込みツール一覧に含まれる。出典: https://code.claude.com/docs/en/sub-agents § "Write subagent files"・"Available tools"
  - 隔離中のセッションは親リポジトリ側への git を isolation guard が拒否する。Claude Code が作る worktree は `git worktree lock` され (本セッションで `git worktree list --porcelain` に `locked claude session spec/issue-1512 (pid ... start ...)` を確認)、`git worktree remove` が locked で拒否されたら `git worktree unlock` を先に実行する。出典: https://code.claude.com/docs/en/worktrees § "How Claude Code enforces isolation"・"Clean up worktrees"・"Clean up subagent and background-session worktrees"
  - `EnterWorktree` のツール説明 (本セッションで提示): `path:` で入った worktree は `ExitWorktree` が削除しない (`action: "keep"` で戻る)。ピン留めされた cwd のエージェントからでも `path:` 形式の切り替えは可能で、親セッションには影響しない
- **上流 issue** (anthropics/claude-code、`gh api` で本文を確認)
  - #52538 (closed 2026-05-27): 同一のエラー文が **メインセッションからの `EnterWorktree` でも断続的に誤報された**。同じ呼び出しが 2 回失敗した後 3 回目で成功した (2.1.118)。→ Step B の再試行の根拠
  - #82737 (closed 2026-10-06): ピン留め cwd のサブエージェントからの `EnterWorktree` が拒否される。解決内容は未確認
  - #93676 (open): `--worktree` や `path:` 由来の worktree は `ExitWorktree` が追跡せず削除できない。→ Step C の根拠
  - #78355 (open): squash マージ済みの worktree は `discard_changes: true` なしでは `remove` が拒否される。本モジュールは常に `discard_changes: true` を渡すため非該当
- **仮説** (いずれも未検証)
  - H1: `/review` は Entry と Exit の間に Step 10 で `Task(...)`/Workflow による自前のサブエージェントを起動する唯一のスキル (`skills/code/SKILL.md`・`skills/merge/SKILL.md` には `Task(`・`Agent(` の起動がない — `grep -n "Task(\|Agent(" skills/code/SKILL.md skills/merge/SKILL.md` で確認)。サブエージェントの起動が fork の cwd の扱いを変える可能性
  - H2: 上流 #52538 と同種の断続的な誤報
  - H3: 起動形態の差 (バックグラウンドか前景強制か。`/code` の 2 件並行は後発が「同一スキルの先行実行あり」で前景強制になりうる)
- **後続の検証方法**: 対話セッションで小さな PR に `/review` を fork 実行し、Step 10 のサブエージェント起動の有無 (`--light` / `--full`)・単独実行か並行実行かを変えて `ExitWorktree` の結果を比較する。条件が特定できたら、Entry 側で回避する設計 (下記の不採用案 1) を再検討する価値がある。

### 採用しなかった代替案

1. **fork 内で `EnterWorktree` を使わず `git worktree add` + `cd` にする** (Issue 対応方針 2): 親セッションの作業ディレクトリを動かさないので閉じ込め自体は起きなくなるが、3 スキルの Entry/Exit 全体と isolation guard (#1454 の `cd` 経路) に波及する設計変更で、AC も要求していない。Entry 時点でピン留め cwd かを判別する手段もない。拒否条件が特定された後の別 Issue で検討する
2. **fork 内から自分の worktree を `git worktree remove` で削除する** (対応方針 1(a) の素朴な形): 自分が立っているディレクトリ (fork が親と共有する作業ディレクトリ) を消すと、親セッションが削除済みパスに取り残される。`cd` で抜ける案は #1454 の経路そのものなので不採用。代わりに、`ExitWorktree(action: "keep")` で正規に退出できた後の Bash 削除 (Step C) だけを採用した
3. **`reclaim-stale-worktrees.sh` を完了報告の主復旧手順にする** (対応方針 3): 同スクリプトは Issue CLOSED / PR MERGED・CLOSED の worktree だけが対象で、`/review` 直後 (PR は OPEN) の残骸は回収しない。主手順にはせず、モジュール新節の末尾で後続の一括回収経路として参照するにとどめた

### 設計判断

- **報告項目は 3 点に限定**: AC3 の「含める項目は 3 点」に合わせ、理由や未マージ状態は見出し行と復旧手順 (3) の中に収める
- **fail-closed**: `detect-foreign-worktree.sh`・`git worktree list`・`git branch --list` が失敗または想定外の出力のときは「退出できていない」とみなし、削除側ではなく Step D に倒す。削除コマンドは Step C の「`ExitWorktree(action: "keep")` で退出を確認した後」だけに限る。worktree のパスとブランチは常に二重引用符で囲む (`+`・`.`・空白を含みうる)
- **再試行は 1 回**: #52538 の断続性に基づく低コストの緩和策。構造的な拒否には効かず、効果は未検証 (Uncertainty)
- **`/code` patch / operate route (merge-to-main)**: 失敗すると push されないため、Implementation Complete コメント・label transition・CI bats AC 確認をスキップする。親セッション側が復旧手順 (b) のマージを行った後に残りを完了させる
- **`/spec`・`/verify` (非 fork の merge-to-main 呼び出し元) は SKILL.md を変更しない**: 失敗処理はモジュール側の Step D (3) の「着地を前提とする手順は保留する」規則を参照で受ける。AC4 の対象外であり、SKILL.md 側に個別の記述は置かない (変更ファイルを 5 つに抑え Size M を保つため)。この 2 スキルで拒否が観測された場合は、各 SKILL.md に保留手順を明記する後続 Issue の候補とする
- **`detect-foreign-worktree.sh` の限界**: ブランチ名で own / foreign を判定するため、PR ブランチへ checkout する `/review` では自分の worktree でも `foreign` を返す。新規 Step A は `none` 以外をすべて失敗扱いにし、own / foreign の区別に依存しない (スクリプトは変更しない)

### 用語の注意

本 Issue の「fork」は Claude Code の `context: fork` (対話セッションから起動されるサブエージェント) で、`modules/execution-context.md` の「fork context」(`run-*.sh` が起動する headless の `claude -p`) とは別物。モジュールの新節ではこの区別を 1 文で明記する。`/auto` 経由の headless 実行は `run-*.sh` が `claude -p` を起動するため、この拒否の対象は主に対話セッションの fork である (`skills/review/SKILL.md` の Autonomous Mode の Note も同様の区別を述べている)。

### 既存の観察 (本 Issue のスコープ外・後続候補)

- Entry step 2 の stale check とモジュール Notes の `git -C ".claude/worktrees/$WORKTREE_NAME"` は、`/` を含む名前を `+` に置換しない文字列でパスを組み立てている (実ディレクトリは `.claude/worktrees/spec+issue-1512`、`scripts/run-code.sh` は `code+issue-N` を使う)。新規記述は Entry で記録した `WORKTREE_PATH` を使うため影響しないが、既存箇所は未修正。merge-to-main の cleanup も同じ不整合を持っていたため、Step 1 のサブステップ 3 で記録値ベースに直す
- `skills/review/SKILL.md` の XS/S 早期終了と review-only の完了報告は、`## Worktree Exit (push-and-remove)` に到達しない構成に読める (Exit 自体が呼ばれる経路ではなく、`ExitWorktree` の拒否でもないため本 Issue の対象外)
- 「関連しうる観察」の `/code`・`/verify` の worktree 7 つの残存は、上記の cleanup パス不整合と、`path:` 再入後の `remove` 無効化 (`Main-repo-only Steps` の往復) の両方が原因候補になりうる。本 Issue の対応で再発の入口は塞がるが、因果は未検証

### Uncertainty

- **Step B (1 回の再試行) の効果**: 上流の誤報報告に基づく緩和策で、構造的な拒否には効かない。効果は未検証。検証方法: 対話セッションの fork で拒否が再現したときに、再試行の成否を記録する
- **Step C (`keep` → Bash 削除) の実機動作**: `path:` で入った worktree で `ExitWorktree(action: "keep")` が通ることはツール説明に基づく。`keep` 後に Claude Code が worktree のロックを外すかは未確認 (外さない場合は `git worktree unlock` の分岐で扱う)。検証方法: `Main-repo-only Steps` の往復をした `/code` で push-and-remove を実行して確認する
- **fork の最終メッセージだけが親に届く点**: 公式ドキュメントは「結果が会話に届く」とだけ述べる。途中出力が親に見えない前提で、報告を最終メッセージ (完了報告) に含める設計にした

### verify command の確認

- AC2 の `file_contains "modules/worktree-lifecycle.md" "cwd override"`: 現状 0 件 (Issue 本文の premise マーカーと一致)。Step 1 の新節が原文のエラー文を引用するため PASS する。AC1・AC3・AC4 は rubric。AC4 の対象は 3 つの SKILL.md だが Exit の実体はモジュールに委譲されているため、各 SKILL.md に「失敗処理への参照」「完了報告への出力」「(code・review) Opportunistic Verification のスキップ」を明記し、SKILL.md 単体で rubric が判断できるようにした
- AC5 は PR route (Size M、`ALWAYS_PR=false`) の `github_check "gh pr checks" "Run bats tests"`。patch route 用の書き換えは不要
- Pre-merge は Issue 本文と同数の 5 件で、verify command は逐語で転記した

### 新規テストケースの要否と bats の入力形式

- Step 1・2 は既存のモジュールとスキルに新規の分岐 (結果の検証・再試行・代替片付け・残骸報告・Opportunistic Verification のスキップ) を追加するため、Step 3 で `tests/worktree-lifecycle.bats` に新規 `@test` を追加する。AC5 は既存スイートの PASS に加え、この新規テストを含むスイートの PASS を要求する
- テストの入力は対象の markdown 自体 (`modules/worktree-lifecycle.md`・`skills/{code,review,merge}/SKILL.md`)。節の抽出に使う見出しの先頭一致の文字列: `### Exit: merge-to-main`、`### Exit: push-and-remove`、`### Exit failure handling`、`## Output`、review の `## Worktree Exit (push-and-remove)`・`## Opportunistic Verification`・`## Completion Report`、code の `### Step 14: Worktree Exit`・`## Completion Report`、merge の `### Step 7: Worktree Exit`・`## Completion Report`

### その他の確認結果

- **監査・調査型 Issue か**: no。分類した結果を後続処理が根拠として読む成果物ではなく、仕様変更の修正であるため。引用する識別子 (`WORKTREE_PATH`・`WORKTREE_BRANCH`・見出し名・スクリプト名・上流 issue 番号) は実在を確認済み (`grep -rn` / `gh api`)
- **fail-safe critical か**: スクリプトではなく LLM 実行の手順だが、失敗時の既定動作を定める点で fail-safe の性格を持つため、依存コマンドの失敗時 (fail-closed、削除側に倒さない)・特殊文字 (パスとブランチを二重引用符で囲む)・空入力 (記録値が手元にない場合は `git worktree list --porcelain` から読み戻す) の挙動を Step 1 に明記した
- **allowed-tools impact chain check**: モジュールが参照する `scripts/*.sh` は既存の `detect-foreign-worktree.sh`・`worktree-merge-push.sh`・`reclaim-stale-worktrees.sh` (参照のみ) で、新規スクリプトはない。モジュールの reader (`spec`・`code`・`review`・`merge`・`verify` の SKILL.md) は全て `detect-foreign-worktree.sh:*`・`worktree-merge-push.sh:*`・`git worktree:*`・`git branch:*` を allowed-tools に持つことを確認済み (`grep -c` / `grep -o`)。frontmatter の変更は不要
- **Feature deletion impact chain**: 削除する警告 1 行 (`Failed to remove worktree` 系) の参照は `modules/worktree-lifecycle.md` の 2 箇所のみ (他は `scripts/run-code.sh` の別メッセージ `Failed to remove stale worktree` と履歴の `docs/spec/`)。削除の確認はテスト (`Please remove manually` が残っていないこと) で行う
- **変数 `WORKTREE_BRANCH` の利用箇所**: モジュールの merge-to-main の step 2〜4 と、Notes の "Manual recovery worktree reuse" (`$WORKTREE_BRANCH` を fetch/log に使う)。意味 (EnterWorktree が作ったブランチ) は変わらない。`WORKTREE_PATH` は他に定義がなく、`tests/worktree-merge-push.bats` の同名変数はテスト内のローカル変数で衝突しない
- **言語規約**: `modules/` と `skills/` は英語のみ (CI の `language-convention` job が CJK の混入を検出する)。報告の定型文も英語で書き、セッションの言語への翻訳は実行時に任せる
- **測定範囲**: Changed Files の一致ファイル数は `grep -rl "<keyword>" docs/ tests/ scripts/ modules/ | wc -l` (リポジトリルートから、履歴の `docs/spec/`・`docs/sessions/` を含む、2026-10-09)

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (AC の対象を ExitWorktree の失敗全般にしたこと、完了報告の 3 項目への具体化、対応方針 2〜4 を AC に含めない判断の記録。`/spec` への追加要求はなし) / https://github.com/saitoco/wholework/issues/1512#issuecomment-6073274423

## Code Retrospective

### Deviations from Design
- Spec の Implementation Steps どおりに実装した。Step 1 (モジュール) → Step 2 (3 スキル) → Step 3 (bats) → Step 4 (`docs/structure.md`・`docs/ja/structure.md`) の順で、構成の変更はない
- Step 4 の判断: `docs/structure.md` の Key Files 2 行 (`modules/worktree-lifecycle.md`・`scripts/detect-foreign-worktree.sh`) を更新し、`docs/ja/structure.md` を同期した。Directory Layout の `tests/` 行はファイル単位の列挙がないため変更しなかった

### Design Gaps/Ambiguities
- 環境に bats がなかったため、`tests/worktree-lifecycle.bats` を bats では実行できなかった。`@test` を関数に変換する plain bash の再現ハーネス (一時ファイル、コミットしていない) で 17 件の PASS を確認した。bats 固有の挙動 (`run` の status 取り扱いなど) は CI の `Run bats tests` で確認する。既存の `tests/code.bats`・`tests/review.bats` もローカルでは実行できていない (Step 14 の順序検査は、挿入した段落に検査対象の 2 文字列を含めないことで影響を避けた)
- 新規テストの「実装前 FAIL 確認」は、追加した assert が新節・新文言のみを対象とする (節単位に抽出して検査する) ため、実装前の状態では FAIL することをコードの読み取りで確認した。実行による確認は bats がないため行っていない
- `scripts/check-translation-sync.sh` は `docs/guide/xl-decomposition.md` を OUTDATED と報告するが、今回の変更とは無関係 (既存の状態)

### Rework
- Comment Consumption を Step 4 のラベル遷移 (`phase/code`) より後に実施したため、cutoff を `phase/code` ではなく直前の `phase/ready` のタイムスタンプで解決した。新しいコメントはなかった (最新のコメントは `phase/ready` の 5 秒前)

## review retrospective

### Spec vs. implementation divergence patterns
- Spec の Implementation Steps 1〜4 と PR の差分に構造的な乖離はなかった。AC1〜AC4 (rubric・`file_contains`) は PASS と判定した

### Recurring issues
- 構造テストの `section()` ヘルパー (見出しの先頭一致で節を切り出す awk) がコードフェンス内の `## ...` 行を見出しと誤認し、`/review` の Completion Report を途中で打ち切って CI の `Run bats tests` が FAIL した。`/code` の再現ハーネスは、テスト本体だけを plain bash に写していたため、この種の不具合は検出できなかった。Markdown の節抽出ヘルパーは「フェンス内を見出しとして扱わない」ことを前提にすべき
- `section "$CODE_SKILL" "### Step 14:" 3` も同じ原因で途中打ち切りになっていたが、追記位置が前にあるため偶然 PASS していた

### Acceptance criteria verification difficulty
- AC5 (`github_check "gh pr checks" "Run bats tests"`) は CI の実行結果に依存し、`/code` 時点では未確認になる。bats がローカルにない環境では、テストが初回に CI で FAIL するリスクが残る。UNCERTAIN は発生しなかった

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- pre-merge AC は全件チェック済み、review の完了も fallback 起源ではなかったため、ゲートは通過した
- マージ戦略は `resolve-merge-strategy.sh` の結果 (`--squash`) を使い、競合なし・CI success で `gh pr merge` を実行した

### Deferred Items
- Post-merge の 2 件 (対話セッションから `/review N` を実行した後の worktree 残存の有無、親セッションの閉じ込めの有無) は manual 確認のまま
- `/spec`・`/verify` への Leftover worktree report の組み込みは、拒否が観測された場合の後続 Issue 候補

### Notes for Next Phase
- `/verify` では、対話セッションから `/review N` を実行して `.claude/worktrees/review+pr-N` が残らないか、残った場合に完了報告へ復旧手順が出るかを確認する
- 拒否の発生条件は未特定のため、再現しない場合は観測待ちとして扱う
