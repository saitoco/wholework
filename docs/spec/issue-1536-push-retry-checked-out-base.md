# Issue #1536: worktree-merge-push: base がチェックアウト済みのとき push 再試行の ref-fetch が拒否されて止まる問題を解消

## Overview

`scripts/worktree-merge-push.sh --from <worktree-branch> --base main` の push 再試行の経路 (160〜180 行目) は、ワークツリーで `rebase origin/<base>` したあと `git fetch . "+${FROM_BRANCH}:${BASE_BRANCH}"` だけでローカルの `BASE_BRANCH` を更新する。git は、チェックアウト済みのブランチへの ref の取り込みを force の refspec でも拒否する。`/verify` と `/code` の patch route は本体 (現在のディレクトリ) で `BASE_BRANCH` をチェックアウトしたままこのスクリプトを呼ぶので、別セッションの push と重なって再試行に入ると、必ず `Error: ref-fetch retry after push-rebase failed. Resolve manually.` で止まる。最初の経路には #1076 で同じ場合の代替 (その場でのマージ) があるが、再試行の経路には無い。

本 Spec は、再試行の経路にも最初の経路と同じ判定 (`git rev-parse --abbrev-ref HEAD` が `BASE_BRANCH` に一致) を入れる。一致するときは、ref の取り込みの代わりに `git reset --keep "$FROM_BRANCH" --` で本体の `BASE_BRANCH` をその場で rebase 済みの `FROM_BRANCH` に合わせ、そのまま push を再試行する。最初の経路と同じ `git merge --ff-only` を使えない理由 (再試行では、ローカルの `BASE_BRANCH` が rebase 済みの `FROM_BRANCH` の祖先ではない) と、`reset --keep` を選んだ理由は Notes に記録する。

あわせて、`modules/orchestration-fallbacks.md` の `ff-only-merge-fallback` (Escalation の push 再試行の説明と、Rationale の「Known gap」の記述) を新しい挙動に更新し、`tests/worktree-merge-push.bats` に、修正前の実装に対して FAIL する (欠陥を再現する) テストを追加する。

## Consumed Comments

cutoff: 2026-10-17T15:39:51Z (最新の `phase/issue` ラベル付与時刻)

- saito / MEMBER / first-class / Triage AC audit (注意喚起)。新規テストの検出力を実装後に判定するための依頼で、欠陥を再現する入力を含め現行スクリプトで FAIL することの確認と、rubric AC の追加を求めている / https://github.com/saitoco/wholework/issues/1536#issuecomment-6235931952
- saito / MEMBER / first-class / Issue Retrospective。常時 PASS だった元の AC3 の差し替えと premise マーカーの付与、手段の選定を /spec に委ねる判断を記録。再試行ではローカルの BASE_BRANCH が祖先でなくなり merge --ff-only が通らない点を /spec で扱うよう申し送り / https://github.com/saitoco/wholework/issues/1536#issuecomment-6235935203

## Reproduction Steps

1. 本体で `BASE_BRANCH` (main) をチェックアウトしたまま、`worktree-merge-push.sh --from <worktree-branch>` を呼ぶ。`/verify` は Step 2 で本体の `git checkout "$BASE_BRANCH"` を必ず実行し、`/code` の patch route も `ExitWorktree` で本体に戻るので、この状態は常態である。
2. 別セッションが、ワークツリーのブランチを切ったあとに `origin/main` へ push して先に進める。
3. 最初の経路: `git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"` が拒否され (`BASE_BRANCH` がここでチェックアウト済み)、`git merge "$FROM_BRANCH" --ff-only` (その場でのマージ) が成功する。ローカルの `main` は `FROM_BRANCH` の先頭に進む。
4. `git push origin main` が non-fast-forward で拒否され、`retry 1/3` に入る。ワークツリーでの `rebase origin/main` は成功し、`FROM_BRANCH` は `origin/main` の上に載る。ローカルの `main` は rebase 前の `FROM_BRANCH` のままで、`origin/main` とは分岐している。
5. `git fetch . "+${FROM_BRANCH}:${BASE_BRANCH}"` が `fatal: refusing to fetch into branch 'refs/heads/main' checked out at '<本体のパス>'` で拒否され、`Error: ref-fetch retry after push-rebase failed. Resolve manually.` で `exit 1` する。

再現確認 (実測): 修正前のスクリプトに対して上記の構成を実 git で組んだテスト (原型) を実行し、Issue 本文のログと同一のメッセージで止まることを確認した (git 2.47.3、bats 1.11.1、2026-10-18)。

## Root Cause

push 再試行の経路 (160〜180 行目) の ref 更新が `git fetch . "+${FROM_BRANCH}:${BASE_BRANCH}"` だけで、`BASE_BRANCH` が本体でチェックアウト済みの場合の分岐を持たない。git は、チェックアウト済みのブランチへの ref の取り込みを force の refspec でも拒否する (`--update-head-ok` を付けない限り)。最初の経路には #1076 で `current_branch == BASE_BRANCH` の代替 (その場でのマージ) があるが、#970 が再試行の経路を checkout に依存しない形に変えたときに、この場合は扱われなかった (#1076 の Deferred Items と Verify Retrospective が、閉じていないギャップとして記録している)。

最初の経路の代替をそのまま移植することもできない。再試行では `FROM_BRANCH` が `origin/<base>` の上に rebase 済みで、ローカルの `BASE_BRANCH` (rebase 前の `FROM_BRANCH`) はその祖先ではなくなっているため、`git merge --ff-only` は通らない。

## Changed Files

- `scripts/worktree-merge-push.sh`: push 再試行の `git fetch . "+${FROM_BRANCH}:${BASE_BRANCH}"` が失敗したとき、`current_branch == BASE_BRANCH` なら `git reset --keep "$FROM_BRANCH" --` でその場で更新する分岐を追加 (それ以外は従来どおり `exit 1`)。force refspec の直前のコメントは、新しい分岐を含む説明に更新する — bash 3.2+ compatible (新規の bashism なし)
- `tests/worktree-merge-push.bats`: 実 git を使うテスト 2 件 (成功、未コミット変更が衝突したときの中断) と、モックを使うテスト 1 件 (他のブランチがチェックアウトされているときは reset しない) を追加。共通の準備は helper 関数にまとめる — bash 3.2+ compatible
- `modules/orchestration-fallbacks.md`: `ff-only-merge-fallback` の Escalation (Push retry loop) に新しい代替を反映し、Rationale の「Known gap」の記述を解消済みの内容に更新、#1536 の項を追加し、See also に #1536 を追加
- `docs/structure.md` (241 行目) と `docs/ja/structure.md` (234 行目): [Steering Docs sync candidate] `worktree-merge-push.sh` の一行説明を確認済み。「push-retry loop (max 3) for parallel session race hardening」の粒度で、再試行内の ref の更新手段には触れていないため変更不要 (`/code` で再確認)
- [Steering Docs sync candidate] キーワード `worktree-merge-push.sh` (116 件)、`orchestration-fallbacks.md` (152 件)、`ff-only-merge-fallback` (34 件) は、`docs/` `tests/` `scripts/` `modules/` での一致ファイル数が 8 件を超え、判別力がないためスキップ。この Issue が導入する語 `reset --keep` は 0 件

## Implementation Steps

1. `tests/worktree-merge-push.bats` (テスト先行。→ AC2, AC3, AC6): 既存の `push race with --from: retry ref-fetch succeeds via force refspec despite local base being stale` (本体の `BASE_BRANCH` を別ブランチに切り替えて、チェックアウトを外した構成) の直後に、次の helper とテスト 3 件を追加する。次のコードは、修正前と修正後のスクリプトに対して実行して検証済みの内容で、そのまま追加してよい。
   - helper `setup_checked_out_base_race <other_file>`: origin (bare)、`main` をチェックアウトしたままの本体、`test-branch` のワークツリー (コミット 1 件)、そして `<other_file>` を変更するコミットを先に origin へ push した別セッションを実 git で作る。モックの `git` は `rm -f` で外す (既存の実 git テストと同じ)
   - テスト A (成功): 本体の `notes.txt` に未コミットの編集を加えたまま `--from test-branch` で呼ぶ。`status 0`、`retry 1/3`、origin の `main` に両方のコミットがあり本体の `main` と `test-branch` と一致、本体のチェックアウトが `main` のまま、作業ツリーに別セッションのファイルが現れ、`git status --porcelain` が ` M notes.txt` だけ (未コミットの編集が残り、インデックスも HEAD に追従している)、`git worktree remove` と `git branch -d` が成功する (呼び出し側の後始末が通る) ことを確かめる
   - テスト B (中断): 別セッションが `notes.txt` を変更し、本体の `notes.txt` にも未コミットの編集がある。`reset --keep` が衝突して中断し、スクリプトは `status` 非 0 で、ローカルの `main` と origin の `main` が実行前から動かず、編集が残り、ロックが解放されていることを確かめる
   - テスト C (モック): 再試行の ref-fetch が拒否され、かつ本体で別のブランチ (`some-other-session-branch`) がチェックアウトされているとき、`reset` を一切発行せず `ref-fetch retry after push-rebase failed` で中断することを確かめる (他セッションのブランチを動かさないための安全側のガード)。修正前後とも PASS する
   - アサーションの書き方: `$output` の内容は `[[ ... ]] || false` で書く (bash 3.2 で bare な `[[ ]]` が `set -e` に伝播しない問題、`skills/code/skill-dev-validation.md`)。否定は最終文でない限り `if grep -q ...; then false; fi` の形にする (`modules/test-runner.md` の bats Negation Assertion Pitfall)
   - **修正前の FAIL 確認 (red)**: テストを追加した直後、スクリプトを変更する前に `bats tests/worktree-merge-push.bats` を実行し、A と B が FAIL し (A は `ref-fetch retry after push-rebase failed` で `status` が 0 にならない)、C は PASS することを確認する。Code Retrospective に `Confirmed pre-implementation FAIL for 2 new test(s).` と記録する。`/code` の New Verification-Test Pre-implementation FAIL Check は文字列照合のアサートだけが対象なので、終了コードと出力を見るこのテストにはこの手順で代える

   ```bash
   # Real-git fixture for a push race while BASE_BRANCH (main) is checked out in the shared dir:
   # origin + shared clone on main + worktree branch "test-branch" with one commit + another
   # session that already pushed a commit touching $1 to origin/main. Leaves cwd in $SHARED.
   setup_checked_out_base_race() {
       local other_file="$1"
       rm -f "$MOCK_DIR/git"
       REAL_ORIGIN="$BATS_TEST_TMPDIR/origin.git"
       SHARED="$BATS_TEST_TMPDIR/test-repo"
       WT="$BATS_TEST_TMPDIR/wt-feature"
       OTHER="$BATS_TEST_TMPDIR/other-session"

       git init --bare -q "$REAL_ORIGIN"
       git clone -q "$REAL_ORIGIN" "$SHARED"
       cd "$SHARED"
       git config user.email test@test.com
       git config user.name test
       # Force the branch name regardless of the runner's init.defaultBranch config.
       git checkout -q -B main
       echo base > base.txt
       echo notes > notes.txt
       git add base.txt notes.txt
       git commit -q -m "base"
       git push -q origin main

       git worktree add -q -b test-branch "$WT" main
       cd "$WT"
       echo feature > feature.txt
       git add feature.txt
       git commit -q -m "feature work"

       git clone -q "$REAL_ORIGIN" "$OTHER"
       cd "$OTHER"
       git config user.email test@test.com
       git config user.name test
       git checkout -q main
       echo other >> "$other_file"
       git add "$other_file"
       git commit -q -m "other session work"
       git push -q origin main

       cd "$SHARED"
   }

   @test "push race with --from while base is checked out in the shared dir: retry resets base in place and keeps uncommitted edits" {
       setup_checked_out_base_race other.txt
       echo "local edit" >> notes.txt

       run bash "$SCRIPT" --from test-branch
       [ "$status" -eq 0 ]
       [[ "$output" == *"retry 1/3"* ]] || false
       [[ "$output" == *"resetting it onto test-branch in place"* ]] || false

       # Base moved onto the rebased branch and was pushed; index and worktree follow HEAD.
       [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
       [ "$(git rev-parse main)" = "$(git rev-parse test-branch)" ]
       [ "$(git -C "$REAL_ORIGIN" rev-parse main)" = "$(git rev-parse test-branch)" ]
       run git -C "$REAL_ORIGIN" log --format=%s main
       [[ "$output" == *"feature work"* ]] || false
       [[ "$output" == *"other session work"* ]] || false
       [ -f other.txt ]

       # The unrelated uncommitted edit survived and nothing else is pending.
       grep -q "local edit" notes.txt
       run git status --porcelain
       [ "$output" = " M notes.txt" ]

       # The caller's cleanup (worktree-lifecycle Exit step 4) still succeeds: base == branch tip.
       git worktree remove "$WT"
       git branch -d test-branch
   }

   @test "push race with --from while base is checked out: aborts and leaves local state intact when uncommitted edits conflict with the reset" {
       setup_checked_out_base_race notes.txt
       echo "local edit" >> notes.txt
       pre_from=$(git rev-parse test-branch)
       pre_origin=$(git -C "$REAL_ORIGIN" rev-parse main)

       run bash "$SCRIPT" --from test-branch
       [ "$status" -ne 0 ]
       [[ "$output" == *"git reset --keep of main onto test-branch failed"* ]] || false
       grep -q "local edit" notes.txt
       [ "$(git rev-parse main)" = "$pre_from" ]
       [ "$(git -C "$REAL_ORIGIN" rev-parse main)" = "$pre_origin" ]
       [ ! -d "$SHARED/.tmp/claude-auto-patch-lock" ]
   }

   @test "push race with --from: retry ref-fetch rejected while the shared dir is on another branch does not reset and aborts" {
       WORKTREE_PATH="$BATS_TEST_TMPDIR/fake-worktree"
       mkdir -p "$WORKTREE_PATH"

       cat > "$MOCK_DIR/git" <<MOCK
   #!/bin/bash
   echo "\$@" >> "$GIT_LOG"
   if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
       echo "${BATS_TEST_TMPDIR}/test-repo"
       exit 0
   fi
   if [[ "\$1" == "rev-parse" && "\$2" == "--abbrev-ref" ]]; then
       echo "some-other-session-branch"
       exit 0
   fi
   if [[ "\$1" == "fetch" && "\$2" == "." ]]; then
       COUNT_FILE="${BATS_TEST_TMPDIR}/fetch_count"
       count=0
       [ -f "\$COUNT_FILE" ] && count=\$(cat "\$COUNT_FILE")
       count=\$((count + 1))
       echo "\$count" > "\$COUNT_FILE"
       # 1st: primary ref-fetch rejected; 2nd: succeeds after the ancestry check; 3rd+: retry-scoped ref-fetch rejected
       [ "\$count" -eq 1 ] && exit 1
       [ "\$count" -ge 3 ] && exit 1
       exit 0
   fi
   if [[ "\$1" == "push" ]]; then
       exit 1
   fi
   if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
       printf "worktree ${WORKTREE_PATH}\nbranch refs/heads/test-branch\n\n"
       exit 0
   fi
   if [[ "\$1" == "merge-base" && "\$2" == "--is-ancestor" ]]; then
       exit 0
   fi
   exit 0
   MOCK
       chmod +x "$MOCK_DIR/git"

       run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
       [ "$status" -ne 0 ]
       [[ "$output" == *"ref-fetch retry after push-rebase failed"* ]] || false
       if grep -qE "^reset" "$GIT_LOG"; then false; fi
       push_count=$(grep -c "push origin main" "$GIT_LOG")
       [ "$push_count" -eq 1 ]
   }
   ```

2. `scripts/worktree-merge-push.sh` (after 1。→ AC1): push 再試行の `git fetch . "+${FROM_BRANCH}:${BASE_BRANCH}"` の失敗時の処理 (現行 177〜180 行目の `if ! ...; then echo "Error: ref-fetch retry after push-rebase failed. Resolve manually." >&2; exit 1; fi`) を、次の内容に置き換える。直前にある `# Force refspec: ...` のコメントは残し、新しい分岐の理由は分岐の先頭のコメントに書く。

   ```bash
       if ! git fetch . "+${FROM_BRANCH}:${BASE_BRANCH}"; then
         # git refuses a ref-fetch into a checked-out branch even with the force refspec.
         # When BASE_BRANCH is checked out here, move it onto the rebased FROM_BRANCH in
         # place. `git merge --ff-only` (used by the primary path) cannot work: after the
         # rebase above, local BASE_BRANCH (the pre-rebase tip of FROM_BRANCH) is no longer
         # an ancestor of FROM_BRANCH. `git reset --keep` keeps uncommitted changes and
         # aborts without touching anything when they conflict with the update.
         current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
         if [[ "$current_branch" == "$BASE_BRANCH" ]]; then
           echo "ref-fetch retry rejected because ${BASE_BRANCH} is checked out here; resetting it onto ${FROM_BRANCH} in place (git reset --keep)..." >&2
           if ! git reset --keep "$FROM_BRANCH" --; then
             echo "Error: git reset --keep of ${BASE_BRANCH} onto ${FROM_BRANCH} failed (uncommitted changes in this checkout may conflict). Resolve manually." >&2
             exit 1
           fi
         else
           echo "Error: ref-fetch retry after push-rebase failed. Resolve manually." >&2
           exit 1
         fi
       fi
   ```

   - 期待動作 (fail-safe critical の観点。Notes 参照): 分岐の先で失敗したときは必ず fail-closed (メッセージを出して `exit 1`、push は試みない、ロックは EXIT trap が解放)。`current_branch` を読めない、または detached HEAD で `HEAD` が返る場合は `BASE_BRANCH` と一致しないので、従来どおり `exit 1` になる。`FROM_BRANCH` と `BASE_BRANCH` は常に二重引用符で単一の引数として渡す (`worktree-spec+issue-N` のように `+` を含む名前でも同じ)。空の値は引数の解析が既に拒否している

3. `modules/orchestration-fallbacks.md` (parallel with 2。→ AC4, AC5): `## ff-only-merge-fallback` を次のとおり更新する。文面は英語。新しい `scripts/*.sh` の参照は追加しない (Notes の allowed-tools を参照)。
   - a. Escalation の `Push retry loop (max 3)` の項で、force refspec の説明 (`...not a bypass of the ff-only guarantee the primary path relies on.` の文) と、`When <from-branch> is unset ...` の文の間に、次の趣旨の文を追加する: 「この ref-fetch が `<base-branch>` が共有ディレクトリでチェックアウト済みであるために拒否された場合 (`git rev-parse --abbrev-ref HEAD` が `<base-branch>` に一致。git は force の refspec でも拒否する、exit 128)、ループは ref-fetch を繰り返さず、その場で `git reset --keep <from-branch> --` を実行する。これはチェックアウト済みの `<base-branch>` を rebase 済みの先頭へ動かし、インデックスと作業ツリーも合わせ、重ならない未コミットの変更は残す。未コミットの変更または未追跡のファイルが上書きされる場合、reset は何も変えずに中断し、ループは "resolve manually" のメッセージで exit 1 する (復旧: 衝突する変更をコミットまたは退避し、`git reset --keep <from-branch>` を実行して `git push origin <base-branch>`)。共有ディレクトリで別のブランチがチェックアウトされている場合は、従来どおり exit 1 で中断し、共有ディレクトリには触れない」
   - b. Rationale の `Step 2's true-side rebase fallback added in #1076:` で始まる項の末尾にある `**Known gap, not closed by this fallback**: ...` から `not addressed here` までの文を、解消済みの内容に置き換える。趣旨: 「push 再試行の ref-to-ref 更新 (`git fetch . "+<from-branch>:<base-branch>"`) は、`<base-branch>` が共有ディレクトリでチェックアウト済みの間は、force の refspec でも git に拒否され (exit 128)、true 側の実行中に重なった push の競合でスクリプトが止まっていた。#1536 がその場での `git reset --keep` の代替で解消した (Escalation の Push retry loop と、下の #1536 の項を参照)」。`Known gap, not closed by this fallback` の語句は残さない (AC5 の `file_not_contains`)
   - c. Rationale の `Push retry loop aligned with the checkout-less design in #970` の項の直後に、`Push retry loop's checked-out <base-branch> alternative added in #1536` の項を追加する。含める事実: (1) 観測された事象 (downstream の `/verify` の Worktree Exit が `ref-fetch retry after push-rebase failed` で止まり、本体の rebase で手動復旧、2026-10-17)。(2) `git reset --keep` を選び、次を退けた理由: `git merge --ff-only` (step 2 と同じ) は、再試行ではローカルの `<base-branch>` が rebase 済みの先頭の祖先でないので通らない。`git fetch --update-head-ok` や `git update-ref` は ref だけが動いてインデックスと作業ツリーが古いコミットのまま残り、差分が staged な変更に見える。`git reset --hard` は未コミットの変更を捨てる。その場での `git rebase origin/<base-branch>` (手動復旧) は未コミットの変更があると開始できず、`<from-branch>` と別のコミットになるため、呼び出し側の `git worktree remove` に続く `git branch -d` が not fully merged で失敗しうる (downstream の手動復旧は `git branch -D` を使った)。(3) ローカルの `<base-branch>` から外れるコミットは、`<from-branch>` 自身のコミットの rebase 前の複製だけで、再試行の rebase で `origin/<base-branch>` の上に再適用済み、reflog にも残る。`<base-branch>` がチェックアウトされていないときに force refspec が行う上書きと同じ意味である
   - d. 末尾の `See also:` の行に、`#1536 (the in-place git reset --keep alternative for the push retry loop when <base-branch> is checked out in the shared directory, closing the gap #1076 recorded)` を追加する

4. 検証 (after 2, 3。→ AC3, AC4, AC5): `bats tests/worktree-merge-push.bats` (全件。既存 21 件と新規 3 件)、`bats tests/orchestration-fallbacks.bats` (カタログの構造テスト)、`python3 scripts/validate-skill-syntax.py skills/`、`bash scripts/check-forbidden-expressions.sh` を実行する。既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/worktree-merge-push.bats` に手順 1 の 3 件) を追加したうえでスイートが PASS すること

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/worktree-merge-push.sh の push の再試行の経路で、git fetch . +FROM:BASE が拒否され、かつ BASE_BRANCH が本体 (現在のディレクトリ) でチェックアウト済みのとき、ローカルの BASE_BRANCH を rebase 済みの FROM_BRANCH に合わせる代替 (最初の経路と同じ考え方で、作業ツリーを壊さない方法) に切り替え、push を再試行する" --> push の再試行の経路に、`BASE_BRANCH` がチェックアウト済みのときの代替がある
- <!-- verify: rubric "tests/ に、BASE_BRANCH を本体でチェックアウトしたまま --from で呼び、最初の push が non-fast-forward で拒否される (origin が先に進む) 状況を作り、再試行で push が成功することを確かめるテストがある" --> 本体で `BASE_BRANCH` をチェックアウトしたまま push が競合する場合のテストがある
- <!-- verify: command "bats tests/worktree-merge-push.bats" --> `tests/worktree-merge-push.bats` が全件成功する (既存のテストファイルに追加する前提。別ファイルに追加する場合は、そのファイルも成功する)
- <!-- verify: rubric "modules/orchestration-fallbacks.md の ff-only-merge-fallback の Escalation 節 (push 再試行の説明) が、BASE_BRANCH が本体でチェックアウト済みのときの代替 (ref の取り込みではなく、作業ツリーを壊さない形でローカルの BASE_BRANCH を更新する) を反映している" --> `modules/orchestration-fallbacks.md` の `ff-only-merge-fallback` の Escalation 節 (push の再試行の説明) が、新しい代替を反映している
- <!-- verify: file_not_contains "modules/orchestration-fallbacks.md" "Known gap, not closed by this fallback" --> 同ファイルの Rationale にある「Known gap」の記述が、解消済みの内容に更新されている
- <!-- verify: rubric "tests/worktree-merge-push.bats に追加された新規テストが、BASE_BRANCH を本体でチェックアウトしたまま push が競合する構成を使用しており、修正前の実装 (push 再試行で git fetch . +FROM:BASE が拒否されて止まる) に対して FAIL する形になっている (BASE_BRANCH がチェックアウトされていない構成だけで PASS する形ではない)" --> 追加された新規テストが、修正前の実装に対して FAIL する (欠陥を再現する構成を使っている)

### Post-merge

- 本体で main をチェックアウトしたまま並行するセッションが push する状況で、`/verify` の Worktree Exit が手での復旧なしに終わる <!-- verify-type: opportunistic -->

## Notes

- **手段の選定 (Issue から /spec に委ねられた論点)**: `git reset --keep "$FROM_BRANCH" --` を採用した。AC1 の「最初の経路と同じ考え方」は、最初の経路が行う「チェックアウト済みの `BASE_BRANCH` を、その場で、作業ツリーを壊さずに更新する」ことを指す。最初の経路は `git merge --ff-only` でそれを実現するが、再試行では `FROM_BRANCH` が `origin/<base>` の上に rebase 済みで、ローカルの `BASE_BRANCH` (rebase 前の `FROM_BRANCH`) はその祖先ではなく、`--ff-only` のマージが通らない (Issue Retrospective の申し送りと一致)。そこで同じ「その場で更新」を `reset --keep` で行う。
  - 退けた案: (a) `git fetch --update-head-ok` / `git update-ref`: ref だけが動き、インデックスと作業ツリーが古いコミットのまま残って、差分が staged な変更に見える。(b) `git reset --hard`: 未コミットの変更を捨てる。(c) 本体での `git rebase origin/<base>` (今回の手動復旧): 未コミットの変更があると開始できず、`FROM_BRANCH` と `BASE_BRANCH` が別のコミットになり、呼び出し側の `git branch -d` が失敗しうる。(d) 先に `git reset --keep origin/<base>` してから `git merge --ff-only`: 同じ結果に 2 段で至るだけで、失敗点が増える。
  - 失われるコミット: ローカルの `BASE_BRANCH` から外れるのは、`FROM_BRANCH` 自身のコミットの rebase 前の複製だけである。最初の経路が終わった時点でローカルの `BASE_BRANCH` は `FROM_BRANCH` と同一で、再試行の rebase がそれを `origin/<base>` の上に再適用するため、内容は失われない (reflog にも残る)。`BASE_BRANCH` がチェックアウトされていないときの force refspec の上書きと同じ意味である。
- **`reset --keep` の挙動 (実測。出所: 使い捨ての原型テスト `.tmp/proto-1536/`、git 2.47.3、2026-10-18。構成は Implementation Steps 1 のコードと同一)**: 重ならない未コミットの変更は保持される (`git status --porcelain` が ` M notes.txt` のまま)。追跡ファイルの変更が重なると `error: Entry 'notes.txt' not uptodate. Cannot merge.`、未追跡のファイルが衝突すると `error: Untracked working tree file 'other.txt' would be overwritten by merge.` で、どちらも何も変えずに中断する (`main` も origin も不変で、ローカルの変更も残る)。末尾の `--` は、ブランチ名と同名のファイルがあるときの曖昧さを避けるためで、この git で動作する。
- **fail-safe critical の判定**: このスクリプトは `|| true` / `2>/dev/null` を含み (`grep -nF` で 12 行を確認)、push の可否を決めるため fail-safe critical として扱った。追加した分岐の期待動作は Implementation Steps 2 に記載のとおり、dependent command の失敗はすべて fail-closed (`reset --keep` の失敗は `exit 1`、`current_branch` を読めない場合や detached HEAD は従来の `exit 1`)。空の引数は解析が拒否済みで、ブランチ名は常に二重引用符で渡す。巨大な入力や改行・CRLF を含む入力は、ファイルを解析しない経路なので該当しない。
- **既存テストとの整合 (実測)**: 修正案のスクリプトに対して既存 21 件がすべて PASS し、追加 3 件を含む 24 件がすべて PASS した。修正前のスクリプトに対しては、新規の実 git テスト A・B が FAIL し、C だけが PASS する (C は他セッションのブランチを動かさないための安全側のガードで、修正前後とも PASS するのが正しい)。
- **Issue 本文と既存実装の照合**: 矛盾は検出されなかった。最初の経路が 110〜136 行目、push 再試行の経路が 160〜180 行目という記述はコードと一致し、`premise` マーカーの `Known gap, not closed by this fallback` は `modules/orchestration-fallbacks.md` に 1 件 (実測) である。
- **検出力 AC の追加 (Triage AC audit の申し送り)**: `skills/triage/skill-dev-verify-audit.md` の "Repair handoff for self-generated AC" に従い、Issue 本文の Pre-merge に、新規テストの検出力を問う rubric AC (AC6) を追加した (注意喚起コメントの提案をそのまま採用)。Pre-merge は 6 件になり、light の目安 (5 件) を 1 件超えるが、追加分は監査の申し送りで必須のため許容した。fixture の要件 (欠陥を再現する構成を使い、修正前に FAIL する) は Implementation Steps 1 に記載した。
- **新規テスト要件 (新規分岐ロジック)**: 再試行の ref-fetch 失敗時に `current_branch == BASE_BRANCH` の新しい分岐が加わる。既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/worktree-merge-push.bats` に、一致して reset する A、reset が失敗して中断する B、一致せず reset しない C) を追加したうえでスイートが PASS すること。
- **Steering Docs sync candidate check**: 判別力フィルタ (`grep -rl` の件数。測定範囲は `docs/` `tests/` `scripts/` `modules/` 全体で、`docs/spec/` と `docs/sessions/` を含む) で 3 つのキーワードがスキップとなったため、`docs/structure.md` と `docs/ja/structure.md` は Step 6 の文面調査で見つけた候補である。listing 側の確認は非該当 (サブコマンドの追加・削除、ファイルの追加・削除・改名、ディレクトリ構造の変更のいずれもない)。Outbound pointer は、`scripts/worktree-merge-push.sh` のポインタコメントの先が `modules/orchestration-fallbacks.md` で、既に Changed Files に含まれる。`docs/migration-notes.md` は CLI シグネチャ・フラグ・引数順の変更がないため対象外。`docs/ja/` の同期義務 (`docs/translation-workflow.md`) は top-level の `docs/*.md` を変更する場合のみで、今回は該当しない。
- **allowed-tools**: 新規の `scripts/*.sh` はなく、`modules/orchestration-fallbacks.md` に追加する文面にも新しい `scripts/*.sh` の参照を入れない。`worktree-merge-push.sh` は spec / code / merge / review / verify の SKILL.md の `allowed-tools` に既にあるため、frontmatter の変更は不要。
- **その他の判定 (すべて非該当)**: UI Design (UI を含まない)。audit / investigation 型 (複数項目の分類ではなく、1 つの欠陥の修正)。Tag/enum の意味拡張 (consumer sweep)。高コストまたは不可逆な手順 (spec-approval-needed)。外部サービスへのログイン (external-auth-required)。Smoke Test (MCP や外部サービスの呼び出しなし)。
- **範囲外 (記録のみ)**: (1) `BASE_BRANCH` が本体ではなく別のワークツリーでチェックアウトされている場合は、最初の経路と同様に未対応のまま (従来どおり `exit 1`)。(2) `modules/worktree-lifecycle.md` の Exit: merge-to-main の説明にある `git pull --rebase` の再試行という記述は、#961 で ref-fetch に置き換わった実装より古い。今回の変更で悪化しないため触れない。
- **Route**: 変更ファイルは 3 件で、Axis 1 は M (3〜5 件)。Axis 2 は、スクリプトの分岐追加 (+1) と、原因が明確なバグ修正 (-1) が相殺して調整なし。トリアージ時の Size S から **M に更新**し (Project の Size フィールド。read-back で M を確認)、pr route とする。同じ構成 (スクリプト + モジュール + テスト) の #1076 も M だった。pr route では `/review` の Step 8 が AC6 (新規テストの検出力) を判定する。`always-pr` は未設定。
