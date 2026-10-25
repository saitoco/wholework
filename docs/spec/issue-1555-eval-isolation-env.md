# Issue #1555: eval: 再実行を本番の GitHub とローカル状態から切り離す隔離環境を整備

## Overview

#1552 (task-completion eval) の sub-issue 2/4。過去の Issue を再実行しても、本番リポジトリ (saitoco/wholework) の GitHub の状態と、ローカルの本番状態 (イベントログ、セッション記録、メインの作業ツリー) に書き込まないことを、仕組みと自動テストで保証する。

方式 (`/spec` で確定。Issue 本文の「Spec で決めた方式」にも記載):

- GitHub 側は、専用の private な sandbox リポジトリに向ける。読み取りも書き込みも sandbox だけにする
- 4 つの層で止める
  1. 認証情報: 届くのは sandbox だけに権限を持つ fine-grained PAT だけにする
  2. git: 本番の URL への push を URL の書き換えで失敗させ、pre-push hook でも拒否する
  3. `gh`: PATH の先頭の shim が、本番を指す呼び出しを止める
  4. ローカル: 書き込む場所をすべて隔離用のディレクトリ (以下「隔離ルート」) の下に置き、環境変数は空の状態から組み立てる
- Claude 側は MCP だけを止める (`--strict-mcp-config`)
- 既存の skills・scripts・modules は変更しない。隔離は新しいスクリプトを通したときだけ効く

#1556 との分担: sandbox の作業ツリーの用意 (sandbox の clone と base commit の取り出し)、実行ごとの sandbox のリセット、入力本文の本番参照の無害化、sandbox と PAT を実際に作る試運転は #1556 で行う。

## Changed Files

- `scripts/eval-isolation.sh`: new file — サブコマンド `setup` / `check` / `exec`。隔離ルートの組み立て、開始前の確認 (fail-closed)、隔離した環境でのコマンド実行 — bash 3.2+ compatible
- `scripts/eval-gh-guard.sh`: new file — `gh` の shim (隔離ルートの `bin/gh` から呼ばれる) — bash 3.2+ compatible。node ID の復号に `python3 -I` (標準ライブラリだけ) を使う
- `scripts/eval-git-pre-push.sh`: new file — pre-push hook (隔離ルートの `hooks/pre-push` から呼ばれる) — bash 3.2+ compatible
- `scripts/eval-claude-guard.sh`: new file — `claude` の shim (隔離ルートの `bin/claude` から呼ばれる) — bash 3.2+ compatible
- `tests/eval-gh-guard.bats`: new file — gh の shim のテスト
- `tests/eval-isolation.bats`: new file — setup / check / exec、git の 2 つの層、claude の shim のテスト
- `eval/isolation.md`: new file — 隔離の設計と使い方の文書 (English)。脅威 (本番に届く経路)、4 つの層、sandbox と PAT の準備手順、使い方、開始前の確認項目、書き込んでいないことの確認方法、既知の制約
- `SECURITY.md`: Side Effects と Required Tools and Authentication に、eval の隔離 (opt-in) の副作用と認証情報の扱いを追記する。「Wholework does not store or transmit credentials」の文に、sandbox 用トークンはユーザーが用意したファイルから実行時に読んで環境変数で渡すだけで、wholework は保存しない、という例外の説明を足す
- `docs/structure.md`: Directory Layout に `eval/` を、Key Files の `### Scripts` に新しいスクリプト 4 つを追加する — [Steering Docs sync candidate] (新ファイル・新ディレクトリによる listing-side sub-check)。#1554 も `eval/` と `scripts/eval-validate-golden-set.sh` を追加するので、先にマージされた側の記述に合わせて書き足す
- `docs/ja/structure.md`: `docs/structure.md` と同じ変更を日本語で反映する (`docs/translation-workflow.md` の同期対象)
- `docs/tech.md`: [Steering Docs sync candidate] `## Environment Variables` の表に、eval の隔離が使う変数 (`EVAL_ISOLATION_ROOT` など) を `eval/isolation.md` への参照つきで 1 行足すかを判断する。足す場合は `docs/ja/tech.md` も同期する
- `README.md`: [Steering Docs sync candidate] ディレクトリやスクリプトを列挙している箇所がないかを再確認する (現時点の grep では見当たらないので、変更不要の見込み)
- [Steering Docs sync candidate] 新しいスクリプト名・環境変数名は既存の `docs/` `tests/` `scripts/` `modules/` に参照がない (inbound check は該当なし)

## Implementation Steps

1. `scripts/eval-gh-guard.sh` を実装する。判定の規則・順序・終了コードは Notes の「gh の shim の規則」に従う (→ acceptance criteria 1, 2)
2. `scripts/eval-git-pre-push.sh` を実装する。規則は Notes の「git の層」に従う (parallel with 1) (→ acceptance criteria 1, 2)
3. `scripts/eval-claude-guard.sh` を実装する。本物の `claude` に `--strict-mcp-config` を付けて exec する (parallel with 1, 2) (→ acceptance criteria 1)
4. `scripts/eval-isolation.sh` の `setup` / `check` / `exec` を実装する (after 1, 2, 3)。隔離ルートの構成、環境変数、確認項目 C1〜C12、終了コードは Notes の「隔離ルートの構成」「exec が組み立てる環境」「check の確認項目」に従う (→ acceptance criteria 1, 3)
5. `tests/eval-gh-guard.bats` を追加する (after 1)。Notes の「テストの内容」の gh の shim のケースをすべて含める。既存スイートが通るだけでなく、ここに挙げた新規テストケースを追加したうえで通ること (→ acceptance criteria 2, 5)
6. `tests/eval-isolation.bats` を追加する (after 2, 3, 4)。Notes の「テストの内容」の setup / check / exec / git / claude のケースをすべて含める。既存スイートが通るだけでなく、ここに挙げた新規テストケースを追加したうえで通ること (→ acceptance criteria 2, 3, 5)
7. Uncertainty の U1・U2 を確かめる (after 4)。テスト用の隔離ルート (架空の sandbox 名、ダミーのトークン、ローカルの作業ツリー) を作り、`eval-isolation.sh exec` の中で `claude -p` を 1 回起動して、Bash ツールから見える `command -v gh`・`GH_REPO`・`GH_CONFIG_DIR`・`GIT_CONFIG_GLOBAL`・グローバルの git 認証ヘルパーと、`mcp__` で始まるツールの有無を出力させる。想定と違えば Uncertainty に書いた対処を入れて、もう一度確かめる。結果は Code Retrospective に記録する (→ acceptance criteria 1)
8. `eval/isolation.md` を書く (after 4, 7)。Notes の「文書に書くこと」に従う。「書き込んでいないことの確認方法」の節を必ず含める (→ acceptance criteria 1)
9. `SECURITY.md`、`docs/structure.md`、`docs/ja/structure.md` を更新し、`docs/tech.md` (と `docs/ja/tech.md`)・`README.md` の要否を判断する (after 8)
10. 通常の利用に影響しないことを確かめる (after 1〜9)。`git diff --name-status origin/main...HEAD` で、既存の `skills/` `modules/` `scripts/` `agents/` `hooks/` のファイルに変更 (`M` / `D`) がないこと、`bats tests/` 全体が通ることを確認する (→ acceptance criteria 4, 5)

## Alternatives Considered

- **ローカルで GitHub を模擬する** (不採用、ユーザーの判断): 外部の準備は要らないが、wholework が使う `gh` の機能 (Issue・PR・ラベル・CI の結果・GraphQL の名前付きクエリなど 30 種類ほど) を真似る必要があり、本番との挙動のずれが eval の結論を汚す
- **`GH_REPO` の差し替えだけ** (不採用): `git push`、`-R` や URL の明示、node ID の mutation、引数なしの `gh repo view` (下の Notes) を止められない
- **実行ごとに新しい sandbox リポジトリを作る** (不採用): リポジトリを作れる PAT が必要になり、その PAT は本番にも書き込める範囲になりやすい。認証情報の層が弱くなる
- **HOME ごと隔離する** (不採用): `~/.claude` の OAuth 認証情報をコピーすると、トークンの更新で元の認証が失効するおそれがある。ユーザー設定も外れるが、ユーザーは Claude 側では MCP だけを止めると決めた。HOME はそのままにし、`gh` と `git` の設定だけを専用の環境変数 (`GH_CONFIG_DIR`、`GIT_CONFIG_GLOBAL`) で差し替える
- **shim で @mention を止める** (不採用): コードの中の `@test` などと見分けられない。sandbox を private にして、権限のない人には通知が届かないようにする
- **別の OS ユーザーやコンテナで動かす** (不採用): Claude の認証と plugin の読み込みの準備が重い。今回の 4 つの層で足りる

## Verification

### Pre-merge

- <!-- verify: rubric "再実行のとき、本番リポジトリ (saitoco/wholework) の Issue・PR・ラベル・コメント・Project フィールド・blocked-by と sub-issue の関係への書き込み、本番リポジトリへの git push、ローカルの本番状態 (イベントログ、セッション記録、メインの作業ツリー) への書き込みを止める仕組みが実装されている。止める仕組みは 1 つの層だけに頼らない構成になっており、書き込んでいないことを確認する方法が文書化されている" --> 再実行が本番の GitHub とローカルの本番状態に書き込まない仕組みと、その確認方法がある
- <!-- verify: rubric "本番への書き込みを止める仕組みに自動テストが追加されている。テストは、本番リポジトリへの git push、gh api による書き込み (-f や --method や --input を使うもの)、GraphQL の mutation、本番リポジトリを明示した -R や URL の引数のそれぞれについて、書き込みを試みる入力を使い、書き込みが止まることを確認している。書き込みを試みない入力だけで PASS する形や、認証エラーで失敗したことを止まったと見なす形ではない" --> 書き込みを止める仕組みが、経路ごとに書き込みを試みる入力で自動テストされている
- <!-- verify: rubric "再実行を始める前に隔離が効いているかを確認し、効いていなければ再実行を始めない (fail-closed) 仕組みになっている" --> 隔離が効いていないときは、再実行が始まらない
- <!-- verify: rubric "隔離の仕組みを使わない通常の利用では、既存の wholework の skills・scripts の挙動が変わらない" --> 通常の利用では、wholework の既存の挙動が変わらない
- <!-- verify: github_check "gh pr checks --json name,state --jq '.[] | select(.name==\"Run bats tests\") | .state'" "SUCCESS" --> bats テスト (CI の `Run bats tests` ジョブ) が通る

### Post-merge

なし

## Uncertainty

- **U1: Claude の Bash ツールに隔離した環境が届くか**: Claude Code の Bash ツールは、ユーザーのシェル (zsh) の設定から PATH などを取り込むことがある。ユーザーの `~/.zshrc` が PATH を組み直すと、`gh` の shim が先頭でなくなるおそれがある
  - **確かめ方**: Implementation Step 7 の probe (`eval-isolation.sh exec` の中で `claude -p` を 1 回起動し、Bash ツールから見える値を出させる)
  - **想定と違った場合の対処**: `exec` が作る環境に `ZDOTDIR=<root>/shell` を加え、`<root>/shell/.zshenv` で隔離の PATH と変数を設定し直す (bash の場合は `BASH_ENV` で同じことをする)。そのうえでもう一度 probe する
  - **影響する step**: 4, 7, 8
- **U2: `--strict-mcp-config` で claude.ai のコネクタと plugin の MCP も止まるか**: ユーザー設定で `slack@claude-plugins-official` などの plugin が有効になっており、claude.ai アカウントのコネクタ (Gmail、Slack など) もある
  - **確かめ方**: Step 7 の probe で、`mcp__` で始まるツールが 1 つもないことを確かめる
  - **想定と違った場合の対処**: 公式の文書で claude.ai のコネクタを無効にする方法 (環境変数 `ENABLE_CLAUDEAI_MCP_SERVERS=false` など) を確かめ、claude の shim に加える
  - **影響する step**: 3, 7, 8
- **U3: PAT が本番に書き込めないことを機械的に確かめられるか**: fine-grained PAT の権限を、本番に書き込みを試みずに問い合わせる方法は確認できていない
  - **扱い**: `check` では確かめない。PAT を作るときの確認項目 (アクセスできるリポジトリは sandbox だけ、Account permissions は付けない) を `eval/isolation.md` に書く。`check --online` では、sandbox に届くことと sandbox が private であることだけを確かめる
  - **影響する step**: 4, 8

## Notes

### 確かめた事実 (出所つき)

いずれも 2026-10-25 に確認した (gh 2.101.0、git 2.47.3)。

- **引数なしの `gh repo view` は `GH_REPO` を無視する**: `GH_REPO=cli/cli gh repo view --json nameWithOwner` は、今いるディレクトリの git remote から `saitoco/wholework` を返した。一方、`GH_REPO=cli/cli gh api 'repos/{owner}/{repo}'` は `cli/cli`、`GH_REPO=cli/cli gh issue view 1` は `cli/cli` の URL を返した。`scripts/gh-graphql.sh` は owner と repo を `gh repo view --json owner,name` で決めているので、shim は引数なしの `gh repo view` に `$GH_REPO` を付け足す
- **グローバルの git 設定の認証ヘルパーは絶対パスで gh を呼ぶ**: `credential.https://github.com.helper` が `!/usr/bin/gh auth git-credential` になっている。PATH の shim では `git push` の認証を止められないので、`GIT_CONFIG_GLOBAL` で git の設定ごと差し替える
- **`GIT_CONFIG_GLOBAL` と `pushInsteadOf` の挙動**: `GIT_CONFIG_GLOBAL` に別のファイルを指定すると、ユーザーの認証ヘルパーは見えなくなる (`git config --global --get-regexp credential` が該当なしで終了コード 1)。`pushInsteadOf` は `git remote get-url --push` の結果に反映され、push はネットワークに出る前にローカルで失敗した (終了コード 128)。書き換えは前方一致なので、`https://github.com/saitoco/wholework` の規則は `https://github.com/saitoco/wholework-eval` などにも当たる。出所: probe スクリプトを `phase-work-dir.sh create 1555 spec` のディレクトリで実行した結果
- **node ID の形式**: `<種類>_` に続く部分は、base64url で符号化した msgpack の配列である。本番の例: `R_kgDOR6v5bg` → `[0, 1202452846]`、`I_kwDOR6v5bs8AAAABZsTkmw` → `[0, 1202452846, 6019146907]` (ラベル `LA_`、PR `PR_`、レビュー `PRR_` も 2 番目の値が同じ)。`PVT_kwDOAT8ukc4BT2qC` → `[0, 20917905, 21981826]`、`PVTI_` と `PVTSSF_` も `[0, 20917905, 21981826, …]`。`gh api repos/saitoco/wholework` の `id` は 1202452846、`owner.id` は 20917905。リポジトリ単位の ID は 2 番目の値がリポジトリ ID で、Project 単位の ID はオーナー ID と Project ID を持つ
- **ユーザー設定の plugin**: `~/.claude/settings.json` の `enabledPlugins` に `slack@claude-plugins-official` などがあり、MCP 経由で外部に書き込む経路がある
- **Project board の workflow**: `.github/workflows/kanban-automation.yml` は `issues: labeled` で動き、`secrets.PROJECT_PAT` を使う。sandbox にこの secret がなければ書き込まずに失敗する。sandbox に Actions の secret を置かないことを、準備の確認項目に入れる
- **イベントログの場所**: `scripts/emit-event.sh` は相対パスの `AUTO_EVENTS_LOG` を、`git worktree list` の最初の項目 (メインの作業ツリー) を基準に解決する。親の環境から本番の絶対パスの `AUTO_EVENTS_LOG` を引き継ぐと、本番のログに書き込む (#1136 の前例と同じ形)。`exec` は環境を空から組み立て、`AUTO_EVENTS_LOG` を隔離ルートの下の絶対パスにする
- **キャッシュの場所**: `scripts/phase-work-dir.sh` は `${XDG_CACHE_HOME:-$HOME/.cache}/wholework/work` を使い、`scripts/gh-graphql.sh` は `.tmp/gh-graphql-cache` (作業ツリーからの相対パス) を使う。`exec` は `XDG_CACHE_HOME` を隔離ルートの下にする
- **`git push` の呼び出し**: `scripts/` の push はすべて `origin` (または既定の remote) に向いている (`push-to-base.sh`、`worktree-merge-push.sh`、`run-*.sh` など)。skill と module の本文も `git push origin HEAD` などである

### 隔離ルートの構成 (`eval-isolation.sh setup`)

- 使い方: `eval-isolation.sh setup --root <dir> --sandbox-repo <owner/name> --production-repo <owner/name> --token-file <path> [--sandbox-push-url <url>] [--extra-blocked-url <url> ...] [--production-info <file>]`
  - `--root` は絶対パスで、どの git の作業ツリーの中にもないこと (ログやトークンのパスを誤ってコミットしないため)。推奨の場所: `${XDG_CACHE_HOME:-~/.cache}/wholework/eval/<name>`
  - `--sandbox-repo` が `--production-repo` と同じか、本番の識別子の規則 (下の P1) に当たる場合は拒否する
  - `--sandbox-push-url` と `--extra-blocked-url` はテスト用 (ローカルの bare リポジトリを sandbox や本番の代わりにする)。既定の sandbox の push URL は `https://github.com/<sandbox>.git`
  - `--production-info` を省くと、隔離の外 (ユーザーの通常の認証) で `gh api repos/<production>` を 1 回だけ読み、リポジトリ ID とオーナー ID を記録する。テストではファイルで渡し、ネットワークを使わない
  - トークンの中身は隔離ルートに書かない。記録するのはパスだけ
- 本物の `gh` と `claude` の場所は、setup の時点の `command -v` で決めて記録する。結果が隔離ルートの中を指す場合は拒否する (shim が自分を呼ぶのを防ぐ)。`push-to-base.sh` と同じく `command -v gh` を使う
- 生成するもの:
  - `isolation.conf`: `KEY=VALUE` 形式。sandbox の名前と push URL、本番の名前・リポジトリ ID・オーナー ID、本物の `gh` と `claude` のパス、トークンファイルのパス
  - `bin/gh` と `bin/claude`: それぞれ `scripts/eval-gh-guard.sh`・`scripts/eval-claude-guard.sh` を絶対パスで exec する小さなラッパー
  - `hooks/pre-push`: `scripts/eval-git-pre-push.sh` を exec する。`hooks/commit-msg`: 作業ツリーに `scripts/git-hooks/commit-msg` があればそれを exec する (DCO の検査を普段どおりに保つ)
  - `gitconfig`: `GIT_CONFIG_GLOBAL` に使う。`user.name` と `user.email` (setup の時点のユーザー設定から写す)、sandbox 用の認証ヘルパー (環境変数 `GH_TOKEN` を返すだけで、ファイルに書かない)、`core.hooksPath=<root>/hooks`、本番の URL の各形 (`https://github.com/<prod>`、`https://github.com/<prod>.git`、`git@github.com:<prod>`、`ssh://git@github.com/<prod>`、`--extra-blocked-url`) から存在しないローカルパスへの `pushInsteadOf`、sandbox の URL から sandbox の URL への `pushInsteadOf` (前方一致で sandbox が書き換えられるのを防ぐ)
  - `gh-config/` (空)、`xdg-config/`、`xdg-cache/`、`logs/`、`tmp/`
- `workspace/` (sandbox の clone) と `plugins/` (構成ごとの wholework の checkout) は #1556 が作る。`check` はそれらが条件を満たすかを確かめる
- 2 回目の setup は、生成するファイルだけを作り直し、`workspace/`・`plugins/`・`logs/` は残す
- 終了コード: 0 = 成功、1 = 失敗 (本番の情報を読めない、本物の `gh` が見つからない、`--root` が作業ツリーの中にある など)、2 = 使い方の誤り

### exec が組み立てる環境 (`eval-isolation.sh exec --root <dir> -- <command...>`)

- `env -i` で空にしてから、次の変数だけを入れる
  - 親から引き継ぐもの: `HOME`、`USER`、`LOGNAME`、`LANG`、`LC_*`、`TERM`、`TZ`、`SHELL`、`ANTHROPIC_*`、`CLAUDE_CODE_*` (Claude の認証と設定のため)。`CLAUDECODE`、`AUTO_SESSION_ID`、`EMIT_PR_NUMBER`、`GITHUB_TOKEN`、`GH_HOST`、`SSH_AUTH_SOCK` などは引き継がない
  - `PATH=<root>/bin:<親の PATH>`
  - `GH_TOKEN` (トークンファイルの中身)、`GH_REPO=<sandbox>`、`GH_CONFIG_DIR=<root>/gh-config`、`GH_PROMPT_DISABLED=1`、`GH_NO_UPDATE_NOTIFIER=1`
  - `GIT_CONFIG_GLOBAL=<root>/gitconfig`、`GIT_CONFIG_NOSYSTEM=1`、`GIT_TERMINAL_PROMPT=0`
  - `XDG_CONFIG_HOME=<root>/xdg-config`、`XDG_CACHE_HOME=<root>/xdg-cache`
  - `AUTO_EVENTS_LOG=<root>/workspace/.tmp/auto-events.jsonl` (絶対パス)
  - `EVAL_ISOLATION_ROOT=<root>`
- 作業ディレクトリは `<root>/workspace`
- 組み立てた環境の中で `check` を実行し、1 つでも FAIL なら `eval-isolation: preflight failed; not running command` を出して終了コード 1 で終わる (コマンドは実行しない)。すべて通れば、組み立てた環境でコマンドを exec する (終了コードはコマンドのもの)
- `eval-isolation.sh check --root <dir> [--online]` は、同じ環境を組み立てて確認だけを行う

### check の確認項目 (fail-closed)

それぞれ `FAIL: C<n> <内容>` を出す。1 つでも FAIL なら終了コード 1、すべて通れば 0、使い方の誤りは 2。確認の途中でコマンドが想定外に失敗した場合も FAIL とする (`|| true` で握りつぶさない)。

- C1: `isolation.conf` があり、必要なキーがすべてある
- C2: sandbox が本番と違い、本番の識別子の規則 (P1) に当たらない
- C3: `GH_REPO` が sandbox、`GH_TOKEN` が空でない、`GH_CONFIG_DIR` が `<root>/gh-config` で `hosts.yml` を含まない、`GIT_CONFIG_GLOBAL` が `<root>/gitconfig`、`GIT_CONFIG_NOSYSTEM=1`、`XDG_CONFIG_HOME` と `XDG_CACHE_HOME` が隔離ルートの下、`EVAL_ISOLATION_ROOT` が隔離ルート
- C4: `command -v gh` が `<root>/bin/gh`、`command -v claude` が `<root>/bin/claude`
- C5: `git config --global --get-regexp '^credential\.'` に、setup が書いた認証ヘルパー以外がない
- C6: 隔離ルートの `tmp/` に作る使い捨てのリポジトリで、本番の URL の各形の `git remote get-url --push` がすべて存在しないパスに書き換わり、sandbox の URL は sandbox のまま
- C7: `<root>/workspace` があり、`git rev-parse --git-common-dir` が隔離ルートの下 (外のリポジトリの worktree ではない)。すべての remote の push URL (書き換え後) が sandbox の push URL。実際に効いている `core.hooksPath` が `<root>/hooks` で、`pre-push` が実行可能
- C8: `<root>/plugins/` の下の各ディレクトリも、`--git-common-dir` が隔離ルートの下 (本番の checkout の worktree だと、ブランチなどの ref が本番のローカルリポジトリに書き込まれるため)。push URL は書き換え後に存在しないパスか sandbox
- C9: `AUTO_EVENTS_LOG` が隔離ルートの下の絶対パス。`AUTO_SESSION_ID` と `EMIT_PR_NUMBER` が空
- C10: shim と hook の自己テスト。`EVAL_GH_GUARD_REAL_GH` を「呼ばれたら印のファイルを作るスタブ」に向けて、本番を指す書き込み (例: `gh issue comment 1 -R <production> --body x`) を `<root>/bin/gh` に渡し、終了コード 97 で止まり、印のファイルができないことを確かめる。`hooks/pre-push` に本番の URL を渡して 0 以外で終わることも確かめる
- C11: トークンファイルがあり、group と other に読み取り権限がなく、どの git の作業ツリーの中にもない
- C12: 本番のリポジトリ ID とオーナー ID が数値で記録されている
- `--online` のときだけ: shim を通した `gh api 'repos/{owner}/{repo}'` の `full_name` が sandbox で、`private` が `true`

### gh の shim の規則 (`scripts/eval-gh-guard.sh`)

上から順に判定し、最初に当たった規則で止める。止めるときは stderr に `eval-gh-guard: BLOCKED (<規則>): <内容>` を出し、終了コード 97 で終わる。通すときは、記録しておいた本物の `gh` (テストでは `EVAL_GH_GUARD_REAL_GH` で差し替える) を元の引数で exec する。判定はすべて `<root>/logs/gh-guard.log` に 1 行ずつ残す (`<時刻>\tALLOW|BLOCK\t<規則>\t<引数>`)。ログに書けなかった場合は stderr に警告を出し、判定は変えない (ログは監査用で、止める仕組みではないため)。

- **S (サブコマンドの許可リスト)**: 通すのは `issue`、`pr`、`label`、`run`、`api`、`repo view`、`auth status`、引数なし、`--version`、`--help`、`help`。それ以外 (`repo` の他の操作、`auth token` / `auth login` / `auth setup-git`、`secret`、`variable`、`workflow`、`project`、`release`、`gist`、`search`、`config`、`alias`、`extension` など) は止める
- **R (リポジトリの指定)**: `-R` / `--repo` (`--repo=X`、`-RX` の形も含む) の値は sandbox でなければ止める。`GH_REPO` が sandbox でなければ止める。引数なしの `gh repo view` は、引数に `$GH_REPO` を付け足してから先に進む (Notes の「確かめた事実」)
- **A (`gh api` のパス)**: 最初の位置引数をパスとする (値を取るフラグ `-X` `--method` `-H` `--header` `-f` `-F` `--field` `--raw-field` `--input` `-q` `--jq` `-t` `--template` `--hostname` `-p` `--preview` `--cache` の値は飛ばす)。`repos/<o>/<r>` で始まるパスは、`{owner}/{repo}` か sandbox でなければ、method を問わず止める。method は `-X` / `--method` の値で、なければ `-f` `-F` `--field` `--raw-field` `--input` のどれかがあれば POST、なければ GET とする。`graphql` 以外でリポジトリを指さないパス (`user`、`rate_limit` など) は、GET なら通し、それ以外は止める
- **P1 (本番の識別子)**: 引数と、引数が指す本文 (`--body-file`、`-F <key>=@<file>`、`--input <file>`) のどこかに、本番の `<owner>/<name>` が含まれていれば止める。大文字と小文字を区別せず、`<name>` の直後が英数字・`.`・`_`・`-` 以外 (または末尾) のときだけ当たる (`saitoco/wholework-eval-sandbox` には当たらない)。URL の形 (`github.com/<owner>/<name>`、`github.com:<owner>/<name>`) と、Issue や PR への参照の形 (`<owner>/<name>#123`) もこの規則で当たる
- **P2 (owner と name の組)**: `-f` / `-F` の値に `owner=<本番の owner>` と `repo=<本番の name>` (または `name=<本番の name>`) が両方あれば止める。GraphQL のクエリ本文に `owner: "<本番の owner>"` と `name: "<本番の name>"` が両方あれば止める (sandbox も同じ owner なので、owner だけでは止めない)
- **P3 (node ID)**: 引数と本文から `[A-Z][A-Z0-9]{0,9}_[A-Za-z0-9_-]{8,}` の形の文字列を取り出し、`_` の後を base64url と msgpack として復号する (`python3 -I`)。配列の 2 番目の値が本番のリポジトリ ID なら止める。種類が `PVT` で始まる ID (Projects V2) は、オーナーを問わず止める (sandbox では Project を使わない。PAT にも Project の権限を付けない)。復号できない文字列は ID ではないとみなす
- **I (内部エラー)**: 本文のファイルを読めない、ID の形の文字列があるのに `python3` が使えないなど、判定ができないときは止める (fail-closed)
- **標準入力の本文**: `--input -`、`--body-file -`、`-F <key>=@-` のときは、標準入力を `<root>/tmp` の一時ファイル (`mktemp`) に読み込んで判定し、通す場合はその内容を本物の `gh` の標準入力に渡す。一時ファイルは終了時に消す (`scripts/gh-pr-review.sh` が `--input -` を使う)
- 引数や本文に引用符・改行・CRLF・マルチバイト文字が入っていても、値をシェルとして評価しない (配列のまま扱い、照合は `grep -E -i` や `python3` に値として渡す)

### git の層

- `pushInsteadOf` (setup が `gitconfig` に書く): 本番の URL への push を、ネットワークに出る前にローカルで失敗させる
- `scripts/eval-git-pre-push.sh`: git から渡される 2 番目の引数 (remote の URL) を正規化して (末尾の `.git`、`https://<user>@` の部分を除き、ホスト名は小文字にする)、sandbox の push URL と一致するときだけ終了コード 0。それ以外は stderr に `eval-pre-push: BLOCKED: <url>` を出して 1。`EVAL_ISOLATION_ROOT` がない、`isolation.conf` を読めないときも 1 (fail-closed)。`pushInsteadOf` が外れていても、この hook だけで止まる (テストで確かめる)

### claude の shim (`scripts/eval-claude-guard.sh`)

- 記録しておいた本物の `claude` を、引数の先頭に `--strict-mcp-config` を足して exec する。`--mcp-config` は付けない (MCP サーバーを 1 つも使わない)
- wrapper (`run-*.sh`) は `claude-watchdog.sh claude -p ...` の形で PATH から `claude` を探すので、PATH の先頭の shim が使われる
- U2 の結果によっては、claude.ai のコネクタを止める環境変数を足す

### 文書に書くこと (`eval/isolation.md`)

- 脅威: 本番に届く経路 (Issue の Background の一覧と、Notes の「確かめた事実」)
- 4 つの層と、それぞれが止める経路の対応表
- sandbox と PAT の準備手順と確認項目: private なリポジトリを作る。名前は本番の名前で始めない (例: `saitoco/eval-sandbox`)。Actions の secret を置かない。fine-grained PAT は Repository access を sandbox だけにし、Repository permissions は Contents・Issues・Pull requests の read and write、Actions・Commit statuses・Metadata の read だけにする。Account permissions は付けない。トークンは権限 600 のファイルに置く (どの作業ツリーの中にも置かない)。ラベルは sandbox に対して `scripts/setup-labels.sh` で作る
- 使い方: `setup` → (#1556 が `workspace/` と `plugins/` を用意) → `check --online` → `exec -- <command>`
- check の確認項目 (C1〜C12) と、FAIL のときの直し方
- **書き込んでいないことの確認方法** (再実行の前後で比べる):
  - GitHub (隔離の外の通常の認証で読み取りだけ行う): `gh api 'repos/<production>/issues?state=all&since=<開始時刻>'` で、再実行の時間内に更新された Issue と PR を一覧にし、再実行によるものがないこと。`git ls-remote https://github.com/<production>.git` の結果が前後で同じこと
  - shim の記録: `<root>/logs/gh-guard.log` の `BLOCK` の行は、止めた書き込みの試みである。止まってはいるが、入力の無害化 (#1556) が足りない手がかりになる
  - ローカル: 本番の作業ツリーで `git status --porcelain` と `git rev-parse HEAD` と `git worktree list` が前後で同じこと、`.tmp/auto-events.jsonl` の行数が変わらず、再実行のセッションの行がないこと、`docs/sessions/` が変わらないこと
- 既知の制約: Claude の会話の記録は `~/.claude/projects/` の下に、作業ツリーのパスごとに作られる (wholework の本番状態ではない)。ユーザーの `CLAUDE.md` と設定は読み込まれる (作業開始時の `git pull` は sandbox から取る)。本番以外の公開リポジトリを `gh api repos/<other>/...` で読むことも止まる

### テストの内容

共通: 各テストは `$BATS_TEST_TMPDIR` だけを使う。本物の `gh` の代わりに、受け取った引数と標準入力をログファイルに書いて 0 で終わるスタブを使う (`EVAL_GH_GUARD_REAL_GH` で指定)。止まったことは「shim の終了コード 97 と `BLOCKED` のメッセージ」と「スタブのログが空」の両方で判定する (認証エラーを止まったと誤認しない)。ネットワークは使わない。テスト用の本番の情報は `--production-info` でファイルから渡す (リポジトリ ID 1202452846、オーナー ID 20917905、名前は実際の `saitoco/wholework`)。node ID の例には Notes の「確かめた事実」の値を使う。

`tests/eval-gh-guard.bats` (新規テストケース):

- 対照: 以下の書き込みの入力を、shim を通さずにスタブへ直接渡すと、スタブのログに記録される (入力が実際に書き込みを試みるものであることの確認)
- `gh api repos/saitoco/wholework/issues/1/comments -f body=x` → 止まる (P1 または A)
- `gh api --method PATCH repos/saitoco/wholework/issues/1` と `gh api -X POST ...`、`--method=DELETE` の形 → 止まる
- `gh api repos/saitoco/wholework/labels --input payload.json` と `--input -` (標準入力) → 止まる
- `gh api graphql -f query='mutation{...}' -F id=I_kwDOR6v5bs8AAAABZsTkmw` (本番の Issue の node ID) → 止まる (P3)
- `gh api graphql` の mutation に `PVT_kwDOAT8ukc4BT2qC` → 止まる (P3)
- `gh api graphql -F owner=saitoco -F repo=wholework -f query=...` と、クエリ本文に `repository(owner:"saitoco", name:"wholework")` → 止まる (P2)
- `gh issue comment 1 -R saitoco/wholework --body x`、`--repo saitoco/wholework`、`--repo=saitoco/wholework`、`-Rsaitoco/wholework` → 止まる (R)
- `gh issue edit https://github.com/saitoco/wholework/issues/1 --add-label x` → 止まる (P1)
- `--body-file` の中身に `saitoco/wholework#12`、`https://github.com/saitoco/wholework/pull/3` がある → 止まる (P1)
- 本番を指す読み取り (`gh issue view 1 -R saitoco/wholework`、`gh api repos/saitoco/wholework`) → 止まる (読み取りも隔離する)
- `gh auth token`、`gh secret set X`、`gh repo delete`、`gh project item-edit` → 止まる (S)
- `GH_REPO` が sandbox でない → 止まる (R)
- 本文のファイルが読めない → 止まる (I)
- 通す例: sandbox を指す書き込み (`gh issue comment 1 --body x`、`gh api 'repos/{owner}/{repo}/issues' -f title=x`、`gh api repos/saitoco/eval-sandbox/labels -f name=x`、sandbox の名前が本番の名前で始まる `saitoco/wholework-eval-sandbox` の場合の `-R`) はスタブに届き、引数が変わっていない。`--input -` で通した場合は、標準入力の中身がそのままスタブに届く
- 引数なしの `gh repo view --json nameWithOwner` は、スタブに `repo view <sandbox> --json nameWithOwner` として届く
- 判定ごとに `logs/gh-guard.log` に `ALLOW` / `BLOCK` の行が残る
- 改行・引用符・マルチバイト文字を含む本文を、通す場合も止める場合も正しく扱う

`tests/eval-isolation.bats` (新規テストケース):

- 準備: ローカルの bare リポジトリ 2 つ (`sandbox.git` と、本番の代わりの `production.git`) を作り、`setup --sandbox-push-url <sandbox.git> --extra-blocked-url <production.git> --production-info <file>` で隔離ルートを作る。`workspace/` は `sandbox.git` の clone、本物の `claude` の代わりは受け取った引数を記録するスタブ
- setup: 生成物 (`isolation.conf`、`bin/gh`、`bin/claude`、`hooks/pre-push`、`gitconfig`、`gh-config/`) がそろう。`isolation.conf` と `gitconfig` にトークンの中身が含まれない。`--sandbox-repo` に本番と同じ名前を渡すと拒否される。`--root` が git の作業ツリーの中だと拒否される
- check の合格: 正しく組み立てた隔離ルートで 0
- check の不合格 (それぞれ 1 で、該当する `FAIL: C<n>` が出る): `gh-config/hosts.yml` がある (C3)、`bin/gh` を消して PATH の `gh` が shim でない (C4)、`gitconfig` に別の認証ヘルパーを足した (C5)、`pushInsteadOf` を消した (C6)、`workspace` の remote を `production.git` に向けた (C7)、`workspace` の `core.hooksPath` を上書きした (C7)、`workspace` がない (C7)、`plugins/` の下に外のリポジトリの worktree がある (C8)、トークンファイルの権限が 644 (C11)、`bin/gh` を素通しのものに差し替えた (C10)
- exec: check が不合格のとき、コマンド (印のファイルを作るもの) は実行されない。合格のときは実行される。親の環境の `AUTO_EVENTS_LOG=<本番のパス>`・`GITHUB_TOKEN`・`AUTO_SESSION_ID` は、exec の中では隔離ルートの値になるか消えている。`GH_TOKEN` はトークンファイルの中身
- git: 対照として、隔離なしで `production.git` への push が成功する (ref ができる)。隔離した環境の `workspace` から `production.git` への push は失敗し、ref ができない。`pushInsteadOf` を外した `gitconfig` でも、pre-push hook だけで止まる。`sandbox.git` への push は成功する
- pre-push hook: `EVAL_ISOLATION_ROOT` がないと 1。URL の正規化 (末尾の `.git`、`https://user@`) を正しく扱う
- claude の shim: スタブに `--strict-mcp-config` が先頭に付いた引数が届き、元の引数は変わっていない

### 判断の記録

- **自動で決めた点** (Q&A の後にユーザーに提示):
  - 本番を指す読み取りも止める。Issue 本文の「読み取りだけ本番に通す構成は成り立たない」に従う
  - `workspace/` と `plugins/` の作成、sandbox のリセット、入力本文の無害化は #1556 に任せる。この Issue は、それらが条件を満たすかを `check` で確かめるところまで
  - 既存のスクリプトは変えない。`gh repo view` の問題も、既存の `gh-graphql.sh` を直さずに shim の側で吸収する
  - 本番を指す文字列は、本文の中のリンク (blob など) も含めて一律に止める。規則を単純に保ち、止めた記録から #1556 で無害化を足せるようにする
- **認証情報の方針との整合**: `SECURITY.md` は「Wholework does not store or transmit credentials」としている。sandbox 用のトークンは、ユーザーが用意したファイルから `exec` の時点で読み、環境変数 (`GH_TOKEN`) と、それを返すだけの git の認証ヘルパーで渡す。隔離ルートにもトークンを書かない。この扱いを `SECURITY.md` に書き足す (Changed Files)
- **fail-safe critical**: 該当する (gh の shim と pre-push hook は書き込みを止める gate、check は受け入れ/拒否を決める validator)。境界の扱いは各節に書いた。判定できないときはどれも止める側に倒す。例外は gh の shim のログ書き込みの失敗で、ログは監査用なので判定は変えない
- **監査・調査型**: 該当しない (新しい仕組みを作る Issue)
- **costly step**: なし。Step 7 の probe は `claude -p` を 1 回起動するが、隔離した環境の中で、短いプロンプトを 1 回だけ実行する (cost=low)。sandbox と PAT を実際に作る作業はこの Issue に含めない
- **`allowed-tools`**: 新しいスクリプトはどの skill からも呼ばれないので変更しない
- **WHOLEWORK_SCRIPT_DIR**: 新しいスクリプトは、隣のスクリプトを `SCRIPT_DIR` (`WHOLEWORK_SCRIPT_DIR` で上書きできる) で探す。既存のテストの規約 (`docs/tech.md` § BATS Mocking Convention) に合わせる
- **Size**: L のまま。新しいファイルが中心で (スクリプト 4、テスト 2、文書 1)、既存のファイルの変更は文書の同期 (`SECURITY.md`、`docs/structure.md` とその翻訳) だけである

## Consumed Comments

No new comments since last phase.

## spec retrospective

### Minor observations
- Issue 本文の調査 (約 72 箇所の直接の `gh` 呼び出し) は「止める場所の多さ」を示していたが、実際に効いたのは「どの経路が設定ファイルや絶対パスで shim を迂回するか」の確認だった。グローバルの git の認証ヘルパーの `/usr/bin/gh` と、`gh repo view` が `GH_REPO` を無視する挙動は、どちらもコードの grep では見つからず、実機での確認で分かった
- `pushInsteadOf` が前方一致であることは、sandbox の名前の付け方 (本番の名前で始めない) と、sandbox への恒等の書き換え規則の両方に効く。#1556 で sandbox を作るときに見落としやすい

### Judgment rationale
- 方式の大きな分かれ目 (sandbox リポジトリかローカルの模擬か、公開範囲、Claude 側の隔離の範囲) はユーザーに確認した。どれも推奨案で決まった
- node ID は文字列の断片で照合せず、復号してリポジトリ ID を比べる方式にした。base64 の境界の位置で断片が変わるため、断片の照合は脆い。復号の形式は本番の 8 種類の ID で確かめた
- 本文の中の本番へのリンクは、cross-reference を作らない blob のリンクも含めて一律に止める。規則を単純に保つことを優先し、止めた記録 (`gh-guard.log`) を #1556 の無害化の手がかりにする
- HOME ごとの隔離は採らなかった。Claude の OAuth の認証情報をコピーすると元の認証が失効するおそれがあり、ユーザー設定を残すというユーザーの判断とも合わない

### Uncertainty resolution
- 解決済み: `gh repo view` と `GH_REPO` の関係、`pushInsteadOf` と `GIT_CONFIG_GLOBAL` の挙動、node ID の形式 (Notes の「確かめた事実」に出所つきで記録)
- 未解決 (U1・U2): Claude の Bash ツールに隔離した環境が届くか、`--strict-mcp-config` で claude.ai のコネクタまで止まるか。どちらも `claude -p` の probe (Implementation Step 7) で確かめる。想定と違った場合の対処も Uncertainty に書いた
- 扱いを決めた (U3): PAT が本番に書き込めないことは機械的には確かめず、PAT を作るときの確認項目にする

### 新しく必要なテストケース
- 新しいスクリプト 4 つは、どれも分岐を持つ新規ファイルである。必要なテストケースは Notes の「テストの内容」に列挙した。要点は、経路ごとの「止まる」ケースが、スタブのログが空であることと shim 自身の終了コード (97) の両方で判定されること、同じ入力をスタブに直接渡すと記録される対照のケースがあること、git の 2 つの層がそれぞれ単独で止めることを確かめるケースがあること

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- GitHub 側は private な sandbox リポジトリに向け、4 つの層 (認証情報・git・gh の shim・ローカル) で止める。既存の skills・scripts・modules は変更しない
- gh の shim は本番を指す読み取りも止める。判定の規則は S → R → A → P1 → P2 → P3 → I の順で、止めるときは終了コード 97
- `gh repo view` が `GH_REPO` を無視するので、shim が引数なしの `gh repo view` に `$GH_REPO` を付け足す
- node ID は復号してリポジトリ ID を比べる。`PVT` で始まる Projects V2 の ID はすべて止める

### Deferred Items
- `workspace/` と `plugins/` の作成、sandbox のリセット、入力本文の無害化、sandbox と PAT を実際に作る試運転は #1556
- PAT が本番に書き込めないことの機械的な確認 (U3) は行わず、文書の確認項目にする

### Notes for Next Phase
- Implementation Step 7 の probe (U1・U2) の結果で、`exec` の環境 (`ZDOTDIR` / `BASH_ENV`) と claude の shim (claude.ai のコネクタを止める環境変数) に追加が要るかが決まる。結果を Code Retrospective に残す
- テストでは、止まったことを「shim の終了コード 97 と `BLOCKED` のメッセージ」と「スタブのログが空」の両方で判定する。認証エラーを止まったと誤認しない
- `docs/structure.md` の `eval/` と Scripts の追記は #1554 と重なる。先にマージされた側の記述に合わせて書き足す
- `SECURITY.md` の「Wholework does not store or transmit credentials」との整合を、文書の更新で取る
