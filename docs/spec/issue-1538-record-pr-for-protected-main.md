# Issue #1538: worktree-merge-push: main が PR 必須のリポジトリでフェーズ記録の push が拒否され /auto が spec で止まる問題を解消

## Overview

`main` に PR 必須のルールセット (Changes must be made through a pull request) があるリポジトリ (例: saitoco/keio) では、各フェーズがフェーズ記録 (Spec、Consumed Comments、各 Retrospective、Phase Handoff) を `main` へ直接 push する経路がすべて拒否される。`always-pr` は code の route 判定にしか効かないため、`/auto` は spec フェーズの完了判定で止まり、verify・merge・auto の記録は手動 PR か欠落になる。

この Issue では次の方針で解消する (方針 A を採用、判断の経緯は Notes)。

- `main` への push を新しい共通スクリプト `scripts/push-to-base.sh` に集約する。まず従来どおり直接 push を試み、リモート側の拒否 (`[remote rejected]`、ブランチ保護・ルールセット・pre-receive hook) のときだけ、記録用ブランチを push して PR を作り、その場でマージする (フェーズ記録用 PR)
- `scripts/worktree-merge-push.sh` は push をこのスクリプトに委ね、記録用 PR 経由で取り込んだあとはローカル `main` (と worktree ブランチ) を `origin/main` に揃える。取り込めなかったときもローカル `main` を `origin/main` に戻し、原因と記録の置き場所 (ブランチ・PR) を報告して非ゼロ終了する
- 直接 push できるかどうかは設定キーを新設せず、push の拒否の種類から判定する。直接 push できるリポジトリの挙動 (PR もブランチも作らない) は変わらない
- `main` へ直接 push しているスキル側の書き込み箇所 (`/merge` Phase Handoff、`/auto` Step 4b・4a・L3、`/spec` と `/verify` の `ENTERED_WORKTREE=false` 経路) を共通経路に切り替える
- `scripts/reconcile-phase-state.sh` の spec 完了判定は、ローカル作業ツリーに Spec が無くても `origin/main` に取り込まれていれば成功とする

## Reproduction Steps

1. `main` に PR 必須のルールセット (承認数 0) があるリポジトリで、Size S 以上の Issue に `/auto N` を実行する
2. spec フェーズの Worktree Exit で `worktree-merge-push.sh --from worktree-spec+issue-N` が呼ばれる。ローカル `main` へのマージ (ref-fetch か in-place merge) は成功する
3. `git push origin main` がリモートで拒否される (` ! [remote rejected] main -> main (push declined due to repository rule violations)`)
4. push の再試行ループは拒否の種類を区別せず non-fast-forward とみなし、fetch・rebase・ref 更新・push を 3 回繰り返したあと `Manual push required.` で exit 1 になる。ローカル `main` は 1 コミット以上 `origin/main` より先に進んだまま残る
5. `run-spec.sh` の完了判定 (`reconcile-phase-state.sh spec`) が失敗し、`/auto` が止まる。keio#345 では `/spec` が標準の Exit を避けて Spec を PR (keio#349) に載せたため `spec file not found` になった

## Root Cause

- `scripts/worktree-merge-push.sh` の push ループ (`git push origin "$BASE_BRANCH"` の失敗時) は、失敗をすべて non-fast-forward 競合とみなして再試行する。リモート側のポリシー拒否 (`[remote rejected]`) を検出する分岐も、`main` 以外の経路で取り込む分岐も無い。拒否されたときは、push の前にローカル `main` へ取り込んだコミットがそのまま残る
- `/merge` (`git push origin HEAD:main`)、`/auto` Step 4b・4a・L3 (`git push origin main`)、`/spec` Step 14 と `/verify` Step 13 の `ENTERED_WORKTREE=false` 経路 (`git push origin main`) は、ロックも再試行も無い素の push で、拒否されたときの経路が無い
- `scripts/reconcile-phase-state.sh` の `_completion_spec` は CWD の作業ツリーにある `${spec_path}/issue-N-*.md` だけを見る。Spec が `origin/main` に入ったかどうかは見ていない

修正の妥当性: 拒否の種類は git クライアントが ref ごとに出す状態トークンで区別できる (`[rejected]` はクライアント側の non-fast-forward 判定、`[remote rejected]` はサーバー側の拒否)。ローカルの pre-receive hook で再現・確認した (Uncertainty 参照)。keio のルールセットは承認数 0・全マージ方式を許可しているので (Notes の出所参照)、記録用 PR の作成とマージは無人で完了できる。

## Changed Files

- `scripts/push-to-base.sh`: new file — ローカル ref を `origin/<base>` へ push し、`[remote rejected]` のときだけフェーズ記録用 PR (作成とマージ) で取り込む。終了コード 0/1/2 の契約 — bash 3.2+ compatible
- `scripts/worktree-merge-push.sh`: push ループの `git push origin "$BASE_BRANCH"` を `push-to-base.sh` 呼び出しに置き換える。終了コード別の分岐、記録用 PR 経由のあとのローカル `<base>`・`--from` ブランチの整列、取り込めなかったときのローカル `<base>` の巻き戻しを追加する。ヘッダーコメントを更新する — bash 3.2+ compatible
- `scripts/append-consumed-comments-section.sh`: コメントのみ更新。main-tree 経路が `worktree-merge-push.sh` 経由で記録用 PR にフォールバックすることと、失敗時も記録が記録用ブランチ・PR に残ることを明記する (挙動は変えない) — bash 3.2+ compatible
- `scripts/reconcile-phase-state.sh`: `_completion_spec` に、ローカル作業ツリーに Spec が無いときの `refs/remotes/origin/main` のツリー確認を追加する (ネットワークアクセスは行わない) — bash 3.2+ compatible
- `tests/push-to-base.bats`: new file — 実 git (bare origin と pre-receive hook) と `gh` モックで、直接成功・non-fast-forward・リモート拒否から記録用 PR で取り込む・PR がマージできない・`--ref HEAD`・引数エラーを検証する
- `tests/worktree-merge-push.bats`: `setup()` で `push-to-base.sh` を `$MOCK_DIR` にコピーする (`WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` のため)。実 git の新規テスト 3 件を追加する (pre-receive hook で拒否されたら記録用 PR で取り込みローカルを整列、PR がマージできないときは非ゼロ終了しローカル `main` が先に進まない、直接 push できるリポジトリでは PR もブランチも作らない)
- `tests/reconcile-phase-state.bats`: 新規テスト 2 件 (Spec が `origin/main` にだけある → true、どこにも無い → false)
- `skills/merge/SKILL.md`: Step 4 substep 5 の `git push origin HEAD:main` を `${CLAUDE_PLUGIN_ROOT}/scripts/push-to-base.sh --ref HEAD --base main` に置き換え、終了コード別の扱いを書く。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/push-to-base.sh:*` を追加する
- `skills/auto/SKILL.md`: Step 4b substep 4、Step 4a substep 5、Step 5 L3 の not-notable 経路と substep 10 の `git push origin main` (計 4 箇所) を `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh` (lock+push only) に置き換え、非ゼロ終了時の扱いを書く。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh:*` を追加する
- `skills/spec/SKILL.md`: Step 14 の `ENTERED_WORKTREE=false: run git push origin main directly` を `worktree-merge-push.sh` (lock+push only、`--from` なし) に置き換える
- `skills/verify/SKILL.md`: Step 13 の `ENTERED_WORKTREE=false: run git push origin main normally` を同様に置き換える。`<!-- skill-body-lines: N -->` と `<!-- skill-body-sha: H -->` マーカーを再計算して更新する
- `modules/worktree-lifecycle.md`: Exit: merge-to-main に、直接 push が拒否されたときの取り込み経路 (記録用 PR) と判定方法を書く。「Spec file write destination」の伝搬表を更新し (`/spec`・`/verify` の worktree skipped 行、`/merge` 行、`/auto` 親セッション行)、Known gaps を削除する
- `modules/orchestration-fallbacks.md`: 新エントリ `## push-rejected-record-pr` (5 セクション、Rationale に `#1538`) を追加し、`ff-only-merge-fallback` の Escalation (Push retry loop) に「`[remote rejected]` は再試行ループに入らない」旨を追記する
- `modules/phase-state.md`: spec 行の成功シグネチャを「作業ツリー、または `origin/main` に `$SPEC_PATH/issue-N-*.md` がある」に更新する
- `docs/ja/phase-state.md`: `modules/phase-state.md` の日本語ミラー。spec 行を同様に更新する
- `modules/l0-surfaces.md`: § "Bash wrapper fallback" で `/merge` の push を `git push origin HEAD:main` と書いている箇所を `push-to-base.sh --ref HEAD --base main` に更新する
- `docs/structure.md`: Key Files の Process management に `scripts/push-to-base.sh` を追加し、`scripts/worktree-merge-push.sh` の説明に記録用 PR フォールバックを加える [Steering Docs sync candidate / listing-side: Directory Layout tree は `scripts/` を役割で記述しているだけなので変更不要の見込み。`/code` が最終判断する]
- `docs/ja/structure.md`: `docs/structure.md` の日本語ミラー (`docs/translation-workflow.md` の Sync Procedure)。同じ 2 箇所を更新する
- `README.md`: [Steering Docs sync candidate / listing-side] 新規ファイル追加に伴う再確認。README に `scripts/` の個別一覧は無いので (`grep -n "scripts/" README.md` が 0 件) 変更不要の見込み
- [Steering Docs sync candidate] keyword "worktree-merge-push.sh" skipped: matched 117 files (no discriminating power)
- [Steering Docs sync candidate] keyword "append-consumed-comments-section.sh" skipped: matched 52 files (no discriminating power)
- [Steering Docs sync candidate] keyword "reconcile-phase-state.sh" skipped: matched 225 files (no discriminating power)
- [Steering Docs sync candidate] keyword "_completion_spec": 7 files。`docs/spec/` の過去 Spec 5 件 (履歴) と `scripts/reconcile-phase-state.sh` (変更対象) と `modules/orchestration-fallbacks.md:371` (`_completion_spec` の二段階確認パターンへの言及。二段階確認自体は変わらないので変更不要の見込み)
- [Steering Docs sync candidate] keyword "Manual push required": `modules/orchestration-fallbacks.md` (上記で変更対象)、ほかは過去 Spec のみ
- 変更しないファイル (確認済み): `modules/detect-config-markers.md`・`docs/guide/customization.md` (設定キーを新設しないため。AC6 の条件付き部分は発火しない)、`tests/append-consumed-comments-section.bats` (`worktree-merge-push.sh` をモックしているため影響なし)、`docs/migration-notes.md` (既存スクリプトの CLI シグネチャを変えないため対象外)

## Implementation Steps

1. `scripts/push-to-base.sh` を新規作成する (bash 3.2+、`set -uo pipefail`、`SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-...}"` の既存パターン) (→ 受入条件 1, 4)
   - **インターフェース**: `push-to-base.sh [--ref <local-ref>] [--base <branch>]`。`--base` の既定は `main`、`--ref` の既定は `--base` と同じ名前。push の refspec は、`--ref` が `--base` と同じなら `git push origin "<base>"` (既存の `worktree-merge-push.sh` と同じコマンド形。既存 bats の `grep "push origin main"` を壊さない)、異なるなら `git push origin "<ref>:refs/heads/<base>"`。git の出力は `LC_ALL=C` で取得して stderr にそのまま流し、stdout には最後の結果行だけを出す
   - **入力検証 (fail-closed)**: 値の無い `--ref`/`--base`、未知のオプション、`git check-ref-format --branch "<base>"` に失敗する base、`git rev-parse --verify --quiet "<ref>^{commit}"` で解決できない ref は、usage を stderr に出して exit 2
   - **分岐の全列挙 (exhaustive)**:

     | ケース | 条件 | 動作 | 終了コード / stdout |
     |---|---|---|---|
     | D1 直接成功 | 直接 push が exit 0 | なし (PR もブランチも作らない) | 0 / `push-to-base: result=direct` |
     | D2 再試行可能 | 直接 push が非ゼロで、出力に `[remote rejected]` が無い (non-fast-forward・fetch first・ネットワーク・認証など) | なし (PR を作らない) | 1 / なし |
     | R リモート拒否 | 直接 push が非ゼロで、出力に `[remote rejected]` がある | 以下の記録用 PR 経路へ | — |
     | R1 取り込み成功 | 記録用ブランチの push、PR 作成、マージが成功し、PR の state が `MERGED` と確認できた | ローカルの記録用ブランチを削除 (`git branch -D`、残っていれば)、`git fetch origin <base>` (失敗は warning のみ) | 0 / `push-to-base: result=record-pr url=<PR URL>` |
     | R2 記録用ブランチの push 失敗 | 例: secret scanning の push protection | ローカルの記録用ブランチを残す | 2 / なし (stderr に失敗した段階・ローカルブランチ名・復旧手順) |
     | R3 PR 作成失敗 | `gh` が無い (`command -v gh`)・未認証・API エラー | ローカルとリモートの記録用ブランチを残す | 2 / なし (同上) |
     | R4 マージ未完了 | `gh pr merge` が 3 回とも失敗し、state も `MERGED` でない (必須承認・必須チェック・merge queue で auto-merge になった場合を含む) | ローカル・リモートの記録用ブランチと開いた PR を残す | 2 / なし (stderr に PR URL と「手でマージする」復旧手順) |

     タイムアウトやシグナル送出は行わない。待機は `gh pr merge` の再試行 (最大 3 回、間隔 2 秒) と state 確認 (`gh pr view <url> --json state -q .state`、最大 3 回、間隔 2 秒) だけで、上限は固定値。間隔だけは環境変数 `WHOLEWORK_PUSH_RETRY_INTERVAL` (既定 2) で上書きできる (テストで待たないため)。`gh pr create` の stderr は握りつぶさず流す
   - **記録用 PR 経路の手順**: (a) 記録用ブランチ名 `wholework-record/<base の / を - に置換>-<UTC %Y%m%dT%H%M%SZ>-<pid>` を `git check-ref-format --branch` で検証し、ローカルに `git branch <name> <ref>` を作る (以後どの段階で失敗してもコミットはこの ref から辿れる)。(b) `git push origin "refs/heads/<name>:refs/heads/<name>"`。(c) `gh pr create --base <base> --head <name> --title "Phase record: <ref 先端の subject>" --body-file <tmp>`。本文は固定の英語文 (直接 push がリモートで拒否されたため wholework がこの PR で取り込む旨) と `git log --format='- %h %s' "refs/remotes/origin/<base>..<ref>"` の一覧。tmp は `mktemp` で作り EXIT trap で削除する。(d) マージ方式は `"$SCRIPT_DIR/resolve-merge-strategy.sh" --flag` で解決する。失敗・空・`--squash`/`--merge`/`--rebase` 以外の値なら `--squash` にする (リゾルバー自身のフォールバックと同じ)。(e) `gh pr merge <url> <flag> --delete-branch --match-head-commit <記録用ブランチの SHA>`。`--squash` のときだけ `--subject "<PR タイトル>" --body-file <tmp2>` を付け、tmp2 には `git log --format=%B "refs/remotes/origin/<base>..<ref>"` (元のコミットメッセージ全文。`closes #N` と `Signed-off-by:` が squash コミットに残る) を入れる。(f) 成否は `gh pr merge` の終了コードではなく `gh pr view` の state で判定する (`--delete-branch` の後処理だけが失敗するケースを成功と扱うため)
   - **エッジケース (fail-safe critical)**: コミットの subject と本文に含まれる `>`・`"`・改行・CRLF・マルチバイト文字は、ファイル (`--body-file`) か単一の argv 要素でだけ渡し、`eval` しない。タイトルは `%s` (1 行) から CR を `tr -d '\r'` で除く。コミット数が多い場合も本文はファイル経由なので argv 長の制限を受けない。依存コマンドが失敗したときは、成功を名乗らない側 (exit 2) に倒す。ただし `resolve-merge-strategy.sh` の失敗は `--squash` に、マージ後の `git fetch` の失敗は warning に倒す (PR は `MERGED` を確認済み)。拒否の分類がつかない出力は D2 (exit 1) に倒し、意図しない PR を作らない
   - ヘッダーコメントに用途、終了コードの契約、呼び出し元 (`worktree-merge-push.sh`、`skills/merge/SKILL.md`) を書く。`chmod +x` する
2. `scripts/worktree-merge-push.sh` の push ループを `push-to-base.sh` 呼び出しに置き換え、`scripts/append-consumed-comments-section.sh` のコメントを更新する (after 1) (→ 受入条件 1, 4, 5)
   - ループ内の `if git push origin "$BASE_BRANCH"; then` を、`"$SCRIPT_DIR/push-to-base.sh" --base "$BASE_BRANCH"` の stdout と終了コードを取得する形にする (`set -e` 下なので `out=$(...) && rc=0 || rc=$?` の形)。分岐の全列挙 (exhaustive):

     | push-to-base.sh | stdout | worktree-merge-push.sh の動作 |
     |---|---|---|
     | 0 | `result=direct` | `break` してそのまま exit 0 (既存挙動と同じ) |
     | 0 | `result=record-pr url=...` | `realign_base_to_origin` を実行。`--from` があれば `--from` ブランチも `origin/<base>` に揃える (worktree があれば `git -C <wt> reset --keep "origin/<base>" --`、無ければ `git fetch . "+refs/remotes/origin/<base>:refs/heads/<from>"`。失敗は warning のみ。呼び出し元の cleanup で `git branch -d` が通るようにするため)。base の整列に失敗したら「PR <url> で取り込み済みだがローカル <base> を揃えられなかった。`git reset --keep origin/<base>` を実行すること」と出して exit 1。成功なら exit 0 |
     | 1 | — | 既存の再試行ロジック (カウント・fetch・rebase・ref 更新) をそのまま使う。メッセージ `Push rejected (non-fast-forward); retry` も維持する |
     | 2 (と想定外の値) | — | `realign_base_to_origin` でローカル `<base>` を `origin/<base>` に戻す (`--from` ブランチには触らない。コミットは `--from` ブランチ、または push-to-base.sh が残した記録用ブランチ・PR にある)。原因と記録の置き場所を出して exit 1。ただし `--from` が無く、`wholework-record/*` ブランチがローカル `<base>` の先端を保持していないときは、コミットを失わないよう巻き戻さずにその旨を出して exit 1。巻き戻しに失敗したら、ローカル `<base>` がまだ先に進んでいることと手順を明記する |

   - `realign_base_to_origin()` を新設する: `git fetch origin "<base>"` (record-pr のあとに失敗したら return 1。exit 2 経路ではスクリプト冒頭で取得済みの `origin/<base>` をそのまま使う) → `git fetch . "+refs/remotes/origin/<base>:refs/heads/<base>"` → 拒否され、かつ `git rev-parse --abbrev-ref HEAD` が `<base>` なら `git reset --keep "origin/<base>" --` (コンフリクトしない未コミット変更は保持し、コンフリクトするなら何も変えずに失敗する。#1536 と同じ選択) → それ以外は return 1
   - ファイル先頭の説明と Usage コメントに、push の委譲と記録用 PR フォールバック、「拒否されたまま終了してもローカル `<base>` は `origin/<base>` より先に進まない」不変条件を追記する。lock の取得と EXIT trap の解放は変えない (記録用 PR 経路もロック内で完結する)
   - `scripts/append-consumed-comments-section.sh`: main-tree 経路 (`"$SCRIPT_DIR/worktree-merge-push.sh" --base "$_current_branch"`) の直前のコメントに、直接 push が拒否されたときは `worktree-merge-push.sh` が記録用 PR で取り込み、失敗しても記録は記録用ブランチ・PR に残ることを追記する (コード変更なし)
3. `scripts/reconcile-phase-state.sh` の `_completion_spec` を拡張する (parallel with 1, 2) (→ 受入条件 3)
   - 既存のローカル確認 (`ls "${spec_path}/issue-${ISSUE_NUMBER}-"*.md`) で見つからないときだけ、`git ls-tree -r --name-only refs/remotes/origin/main -- "$spec_path" 2>/dev/null | grep -E "/issue-${ISSUE_NUMBER}-[^/]*\.md$" | head -1` で `origin/main` を確認する。見つかれば `spec_file` にそのパスを入れ、ラベル判定は既存と同じ。diagnosis は `spec file found on origin/main (not in the local working tree) ...` のように取得元を区別する
   - `git fetch` は行わない (単体テストのネットワーク依存を避ける。push と記録用 PR 経路の fetch が追跡 ref を更新する)。ref が無い・`spec_path` が絶対パス・git が失敗する場合は空として扱い、従来どおり mismatch になる
4. bats テストを追加する: `tests/push-to-base.bats` を新規作成し、`tests/worktree-merge-push.bats` を更新する (after 1, 2) (→ 受入条件 2, 5, 7)
   - フィクスチャの形式: `git init --bare` の origin に `hooks/pre-receive` を置く。hook は stdin の `<old> <new> <ref>` 行を読み、`refs/heads/main` への更新だけを GH013 を模した stderr と exit 1 で拒否する (他のブランチは許可)。初期コミットの push は hook を置く前か許可フラグファイルで通す。`gh` は `$MOCK_DIR/gh` (PATH 先頭) のモックで、argv を `$GH_LOG` に記録する。`pr create` は `--head` の値をファイルに記録して `https://github.com/o/r/pull/1` を出力する。`pr merge` は squash を模して `git --git-dir "$ORIGIN" commit-tree <head>^{tree} -p <main> -m ...` → `update-ref refs/heads/main` → head ref を削除する (失敗ケースでは stderr を出して exit 1)。`pr view` は `MERGED` か `OPEN` を出力する。`resolve-merge-strategy.sh` は置かなくてよい (`--squash` にフォールバックする)
   - `tests/push-to-base.bats` の新規テストケース (`@test` 名の例): `direct push succeeds: result=direct and gh is never called` / `non-fast-forward rejection exits 1 without creating a PR` / `remote rejection lands the commits through a record PR and exits 0` (origin の `main` のツリーに対象ファイルがあり、記録用ブランチがローカルにもリモートにも残らない) / `record PR merge failure exits 2 and keeps the local record branch` (stderr に PR URL、`origin/main` は不変) / `--ref HEAD pushes a worktree branch tip to main` / `missing option value or invalid ref exits 2`
   - `tests/worktree-merge-push.bats`: `setup()` で `cp "<repo>/scripts/push-to-base.sh" "$MOCK_DIR/"` する (既存のモック git テストは、`git push origin main` のコマンド形が変わらないのでそのまま通る)。実 git の新規テスト 3 件を追加する (`rm -f "$MOCK_DIR/git"` の既存パターン):
     - `push rejected by a remote rule: lands via record PR and realigns local base and from-branch to origin` — 共有クローンで `main` をチェックアウトし、worktree ブランチ `test-branch` に 1 コミット。期待: status 0、origin の `main` に feature.txt、`git rev-parse main` が origin の `main` と一致、`git worktree remove` と `git branch -d test-branch` が成功する。修正前の実装では 3 回の再試行のあと exit 1 になるので FAIL する
     - `push rejected by a remote rule and record PR cannot be merged: exits non-zero and local base is not left ahead` — 期待: status 非ゼロ、出力に PR URL、ローカル `main` が origin の `main` と一致、`test-branch` に feature コミットが残る。修正前の実装ではローカル `main` が先に進んだまま残るので FAIL する
     - `direct push allowed: pushes base directly without creating a record PR or branch` — hook なし。期待: status 0、`$GH_LOG` が存在しないか空、`git -C "$ORIGIN" for-each-ref refs/heads` が `main` だけ、origin の `main` が `test-branch` の先端と一致 (受入条件 5)
   - 既存スイートが PASS することだけでなく、上の新規テストケースを追加したうえで `bats tests/push-to-base.bats tests/worktree-merge-push.bats` が PASS すること
5. `tests/reconcile-phase-state.bats` に新規テスト 2 件を追加する (after 3) (→ 受入条件 3, 7)
   - フィクスチャ: bare origin と 2 つのクローン。一方のクローンが `docs/spec/issue-99-x.md` をコミットして push する。テスト対象のクローン (CWD) は `git fetch` だけを行い、作業ツリーには Spec が無い状態にする。`MOCK_SPEC_PATH=docs/spec` (相対)、`gh` モックは `phase/ready` を返す
   - `@test "spec completion: spec only on origin/main (not in local working tree) + phase/ready -> matches_expected true"` (修正前は false になるので FAIL) と `@test "spec completion: spec neither in local working tree nor on origin/main -> mismatch"` (`--strict` で exit 1)
   - 既存スイートが PASS することだけでなく、この 2 件を追加したうえで `bats tests/reconcile-phase-state.bats` が PASS すること
6. スキルの書き込み箇所を共通経路に切り替える (after 1, 2) (→ 受入条件 4)
   - `skills/merge/SKILL.md` Step 4 substep 5: `git push origin HEAD:main` を `${CLAUDE_PLUGIN_ROOT}/scripts/push-to-base.sh --ref HEAD --base main` に置き換える。終了コード別の扱い: 0 は Step 5 へ。1 は `git fetch origin main` → `git rebase origin/main` のあと同じコマンドを 1 回だけ再実行し、まだ非ゼロなら 2 と同じ扱い。2 はスクリプトの stderr (記録用ブランチ・PR URL) を warning として出し、完了報告に含めて Step 5 へ進む (マージ自体は完了しており、記録は記録用ブランチ・PR に残るので捨てない)。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/push-to-base.sh:*` を追加する
   - `skills/auto/SKILL.md`: Step 4b substep 4、Step 4a substep 5、Step 5 L3 の not-notable 経路の commit ブロック、Step 5 L3 substep 10 の `git push origin main` (計 4 箇所) を `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh` (lock+push only、`--from` なし) に置き換える。非ゼロ終了時はスクリプトの stderr (記録の置き場所) を warning として出し、残りの手順は続ける。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh:*` を追加する
   - `skills/spec/SKILL.md` Step 14 と `skills/verify/SKILL.md` Step 13 の `ENTERED_WORKTREE=false` 行を「`${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh` を `--from` なしで実行する (lock+push only。`modules/worktree-lifecycle.md` の "When `ENTERED_WORKTREE=false`" を参照)」に置き換える
   - `skills/verify/SKILL.md` の編集後、`<!-- skill-body-lines: N -->` と `<!-- skill-body-sha: H -->` を再計算して更新し、`bash scripts/check-skill-body-hash.sh` が exit 0 になることを確認する
   - SKILL.md 本文に半角 `!` を入れない (`python3 scripts/validate-skill-syntax.py skills/` で確認)。`bash scripts/check-allowed-tools.sh` で本文と `allowed-tools` の不一致が無いことを確認する
   - 網羅性の機械確認: `grep -rnE "git push origin (main|HEAD:main)" skills/*/SKILL.md` を実行し、フェーズ記録の書き込みで残る素の push が無いことを確認する (残るヒットは、`/review`・`/code` pr route の PR ブランチへの push など対象外のものだけであること)
7. `modules/worktree-lifecycle.md` を更新する (after 2, 6) (→ 受入条件 6)
   - Exit: merge-to-main の step 3 ("The script handles: ...") に、push は `scripts/push-to-base.sh` に委ねることを追記する。新しい h4 小見出し `#### Direct push rejected by the remote: phase-record PR` を step 3 の直後に置き、次を書く: (a) 判定方法: 設定キーは使わず、毎回まず直接 push し、git が出す ref 状態トークンで区別する (`[remote rejected]` はブランチ保護・ルールセット・pre-receive hook によるサーバー側の拒否で記録用 PR 経路へ、`[rejected]` (non-fast-forward / fetch first) やその他の失敗は既存の再試行ループへ)。(b) 取り込み経路: 記録用ブランチ `wholework-record/...` を push し、PR を作成して、リポジトリの `merge-strategy` でその場でマージする。(c) 終了時の不変条件: 成功したらローカル `<base>` と worktree ブランチを `origin/<base>` に揃える (cleanup の `git branch -d` がそのまま通る)。取り込めなければローカル `<base>` を `origin/<base>` に戻し、記録用ブランチ・PR を報告して非ゼロ終了する。この場合、呼び出し元は既存の「On script failure (non-zero exit), abort and skip cleanup」に従う。(d) 対象外: 記録用 PR に承認や必須チェックが要るルールセット (Issue の Out of Scope)
   - "When `ENTERED_WORKTREE=false`" の説明は現状どおり (lock+push only)。Spec file write destination の伝搬表を更新する: `/spec` worktree skipped 行を `worktree-merge-push.sh` (lock+push only) に確定し "see Known gap" を削除する、`/verify` worktree skipped 行を追加する、`/merge` 行を `Step 4 substep 5's push-to-base.sh --ref HEAD --base main` にする、`/auto` 親セッション (Step 4b / 4a / L3) 行を追加する (base branch in the main repository → `worktree-merge-push.sh` lock+push only)。表の直後に「どの行の base への書き込みも `push-to-base.sh` を (直接、または `worktree-merge-push.sh` 経由で) 通るので、記録用 PR フォールバックが全行に効く」と 1 文加える
   - `**Known gaps (not yet migrated):**` ブロックを削除する (Step 6 で移行済みのため)
   - 表は "(exhaustive)" なので、Step 6 の grep 結果と表の行が一致することを確認する
8. 関連ドキュメントを同期する (after 1, 2, 3, 6) (→ 受入条件 6 の補足、SHOULD)
   - `modules/orchestration-fallbacks.md`: `## ff-only-merge-fallback` の直後に `## push-rejected-record-pr` を追加する (h3 で `### Symptom` / `### Applicable Phases` / `### Fallback Steps` / `### Escalation` / `### Rationale` の 5 つ。`tests/orchestration-fallbacks.bats` のスキーマに合わせる)。Symptom は `! [remote rejected] <base> -> <base> (...)`、Applicable Phases は spec / code patch / verify (`worktree-merge-push.sh`)、merge (`push-to-base.sh --ref HEAD`)、auto 親セッション (Step 4b/4a/L3)、`append-consumed-comments-section.sh` の main-tree 経路。Rationale には `#1538` と keio#345 の事例を書く。`ff-only-merge-fallback` の Escalation の Push retry loop 段落に、`push-to-base.sh` が exit 1 (再試行可能) を返したときだけこのループに入り、`[remote rejected]` は `#push-rejected-record-pr` へ進むことを追記する
   - `modules/phase-state.md` の spec 行と `docs/ja/phase-state.md` の対応行: 成功シグネチャを「`$SPEC_PATH/issue-N-*.md` がローカル作業ツリー、または `origin/main` にある」に更新する
   - `modules/l0-surfaces.md` § "Bash wrapper fallback": `/merge` の push の記述 `(git push origin HEAD:main)` を `push-to-base.sh --ref HEAD --base main` に更新する
   - `docs/structure.md` と `docs/ja/structure.md`: Key Files の Process management に `scripts/push-to-base.sh` の説明を追加し、`scripts/worktree-merge-push.sh` の説明に「直接 push がリモートで拒否されたら push-to-base.sh の記録用 PR で取り込み、ローカル base を origin に揃える」を追記する。README.md と Directory Layout tree は再確認のみ

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/worktree-merge-push.sh は、base ブランチへの直接 push がブランチ保護ルールセットにより拒否される場合 (non-fast-forward 以外の拒否) でも、(1) 変更を手動介入なしで base に取り込む経路へ進む (フェーズ記録用 PR の作成とマージなど)、または取り込めない場合は非ゼロ終了で原因を報告し、(2) 終了時にローカル base ブランチが origin の base より先に進んだまま残らない。この 2 点が実装から確認できる" --> `main` への直接 push が拒否されるとき、`worktree-merge-push.sh` が手動介入なしで変更を取り込む経路へ進むか、取り込めない場合は原因を報告して非ゼロ終了し、いずれの場合もローカル `main` が origin より先に進んだまま残らない
- <!-- verify: rubric "tests/worktree-merge-push.bats に、base への直接 push が non-fast-forward 以外の理由で拒否されるケース (例: bare リポジトリの pre-receive hook で拒否) の新規テストが追加されており、そのフィクスチャは拒否を実際に再現し、修正前の実装に対しては FAIL する形になっている (常に成功する入力だけで PASS する形ではない)" --> 直接 push の拒否を再現する新規テストが `tests/worktree-merge-push.bats` に追加され、そのフィクスチャは修正前の実装で FAIL する
- <!-- verify: rubric "Spec が main に取り込まれた状態、または方針で定めた取り込み経路 (Spec PR など) に載っている状態で scripts/reconcile-phase-state.sh の spec 完了判定が matches_expected: true を返し、Spec が main にも取り込み経路にも存在しない状態では従来どおり matches_expected: false を返す。tests/reconcile-phase-state.bats の新規テストがこの両方を検証している" --> `main` が PR 必須のリポジトリで spec フェーズが正常終了したとき、`run-spec.sh` の完了判定が成功になり、Spec が無いときは従来どおり失敗になる (新規テストが両方を検証する)
- <!-- verify: rubric "scripts/append-consumed-comments-section.sh、skills/merge/SKILL.md の Phase Handoff 書き込み、skills/auto/SKILL.md の Step 4a・4b・L3 retrospective の書き込み、および skills/spec/SKILL.md と skills/verify/SKILL.md の ENTERED_WORKTREE=false 経路は、main への直接 push が拒否されても記録が欠落しない (記録用 PR 経由で取り込む、または共通の取り込み経路を呼ぶ)。いずれも拒否されたまま記録を捨てる、または省略する手順になっていない" --> Consumed Comments・各 Retrospective・Phase Handoff の書き込み箇所が、`main` への直接 push が拒否されても記録を欠落させない
- <!-- verify: rubric "main へ直接 push できるリポジトリでは、worktree-merge-push.sh のフェーズ記録 push が従来どおり base へ直接 push され、記録用 PR やブランチを追加で作らない。この既存挙動を検証するテストが tests/worktree-merge-push.bats にある" --> 直接 push できるリポジトリの既存の挙動 (PR を作らず直接 push する) が変わらないことをテストで確認できる
- <!-- verify: rubric "modules/worktree-lifecycle.md に、直接 push が拒否されたときの取り込み経路と、直接 push の可否をどう判定するかが記載されている。新しい .wholework.yml のキーを導入した場合に限り、modules/detect-config-markers.md の Marker Definition Table と docs/guide/customization.md にも記載されている" --> 直接 push 拒否時の取り込み経路と判定方法が `modules/worktree-lifecycle.md` に記載され、設定キーを新設した場合は `modules/detect-config-markers.md` と `docs/guide/customization.md` にも記載されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストの CI が PASS する (PR route)

### Post-merge

- `main` が PR 必須のリポジトリ (例: saitoco/keio) で Size S 以上の Issue を `/auto N` で処理し、手動介入なしに spec から verify まで完了する。処理後に `main` へ Spec・`## Consumed Comments`・各 Retrospective・Phase Handoff が取り込まれていて欠落がなく、ローカル `main` が origin より先に進んだ状態で残っていない <!-- verify-type: manual -->

## Tool Dependencies

### Bash Command Patterns
- `${CLAUDE_PLUGIN_ROOT}/scripts/push-to-base.sh:*`: `skills/merge/SKILL.md` の Step 4 substep 5 で使う (frontmatter `allowed-tools` に追加)
- `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh:*`: `skills/auto/SKILL.md` の Step 4b・4a・L3 で使う (frontmatter `allowed-tools` に追加。`skills/spec/SKILL.md`・`skills/verify/SKILL.md`・`skills/merge/SKILL.md` は登録済み)

### Built-in Tools
- none

### MCP Tools
- none

## Uncertainty

- **GitHub のルールセット・ブランチ保護による拒否で `[remote rejected]` が出るか**: git クライアントはサーバー側で拒否された ref を `[remote rejected]`、クライアント側の non-fast-forward 判定を `[rejected]` と表示する
  - **Verification method**: ローカルで bare リポジトリに pre-receive hook を置いて再現した (git 2.47.3)。hook による拒否は ` ! [remote rejected] main -> main (pre-receive hook declined)`、non-fast-forward は ` ! [rejected] main -> main (fetch first)` になった。`LANG=ja_JP.UTF-8` でもトークンは変わらなかった。GitHub ルールセットの理由文 `(push declined due to repository rule violations)` は公開事例で確認した (出所は Notes)。keio 実機での確認は Post-merge の manual で行う
  - **Impact scope**: Implementation Steps 1, 4
- **`gh pr create` 直後の `gh pr merge` が mergeability の計算待ちで一時的に失敗するか**: 再現は未確認
  - **Verification method**: 最大 3 回 (2 秒間隔) の再試行と `gh pr view` の state 確認で吸収する設計にした。keio の Post-merge 確認で観察する
  - **Impact scope**: Implementation Step 1
- **merge queue が必須のブランチ**: `gh pr merge` はマージせずに auto-merge を有効にする (`gh pr merge --help` で確認)。state が `OPEN` のまま残るので R4 (exit 2) になる。Issue の Out of Scope (無人で満たせない要件) と同じ扱いで、原因を報告して停止する
  - **Verification method**: `gh pr merge --help` (gh 2.101.0) の記述で確認済み
  - **Impact scope**: Implementation Step 1
- **`gh pr merge --delete-branch` の後処理**: ローカルに同名ブランチがある場合は gh がそれも削除する。`delete_branch_on_merge` が有効なリポジトリでは、リモートの削除が重複して gh が非ゼロを返すおそれがある
  - **Verification method**: 成否を終了コードではなく state で判定し、ローカルの記録用ブランチは `git branch -D ... || true` で後始末する設計にした。keio は `delete_branch_on_merge: false` (Notes の出所参照)
  - **Impact scope**: Implementation Step 1
- **`--squash` で `--body-file` に渡した元コミットメッセージが squash コミットに残るか**: 残れば `_completion_code_patch` の `closes #N` 検索と DCO の `Signed-off-by:` が保たれる
  - **Verification method**: `gh pr merge --help` に `-F, --body-file` (Body text for the merge commit) があることは確認済み。実際のコミット内容は Post-merge で観察する
  - **Impact scope**: Implementation Step 1

## Notes

### 方針と判定方法の自動解決 (非対話モード)

- **方針 A を採用** — 理由は下の「方針の比較」のとおり。spec・verify・merge・auto のすべての記録を 1 つの仕組みでまかなえ、`/code` の Spec 読み込みも変えずに済む
- **直接 push の可否は push の拒否から判定し、設定キーは新設しない** — このため受入条件 6 の条件付き部分 (`modules/detect-config-markers.md`・`docs/guide/customization.md` への記載) は発火しない
- **記録用 PR のマージ方式は `resolve-merge-strategy.sh` に従う** — `/merge` が実装 PR のマージに使う方式と同じなので、そのリポジトリで許可されている可能性が最も高い。祖先関係が保たれない方式 (squash / rebase) でも、ローカル `<base>` と `--from` ブランチを `origin/<base>` に揃えるので、呼び出し元の cleanup (`git branch -d`) は変えずに済む
- **記録用 PR のタイトル・本文は固定の英語文** — スクリプト内の文字列リテラル (ソースコード) は英語というプロジェクト規約に従う。配布物でもあり、言語に依存しない文面にする
- 上記の判断は、Issue retrospective コメントとして Auto-Resolve Log に記録する

### 方針の比較 (採用 / 不採用)

Issue が方針の選択を `/spec` に委ねているので、比較を記録する。

- **方針 A (採用)**: 直接 push の拒否を検出して、フェーズ記録用 PR を作ってその場でマージする。1 つの仕組みで spec・code patch・verify・merge・auto のすべての書き込み箇所をまかなえ、`/code` は従来どおり `main` 上の Spec を読める。直接 push できるリポジトリの挙動は変わらない
- **方針 B (不採用)**: Spec を実装 PR に同梱する。spec の記録しか解決せず、verify・merge・auto の記録には効かない。patch route (直接 push) とも両立しない。`/code` の Spec 読み込み、`reconcile-phase-state.sh`、`/review` の差分範囲まで変える必要がある
- **方針 C (不採用、単独では)**: 完了判定だけを直す。開いた Spec PR を完了とみなしても、`/code` は `main` から Spec を読むのでマージの手順が別に要り、他フェーズの記録も救えない。ただし `origin/main` を見るように完了判定を強化する部分は、A の補強として取り込んだ (Step 3)
- **判定方法: 設定キー (不採用)** — `always-pr` とは別の `direct-push: false` のようなキーを新設する案。リモートがすでに強制しているポリシーを設定に二重に書くことになり、設定漏れ・設定ずれの余地が生まれる。`detect-config-markers.md`・`customization.md`・`check-config-schema.sh` の更新も要る。push の拒否から判定すれば設定不要で、ルールセットが後から変わっても追従できる
- **実装の置き場所: `worktree-merge-push.sh` へのインライン実装 (不採用)** — `/merge` は worktree ブランチの `HEAD` を `main` へ push するので、ローカル `main` に取り込んでから push する `worktree-merge-push.sh` には載らない。記録用 PR の処理を独立したスクリプトにして、両方から呼ぶ

### Issue 本文と実装の照合

- 照合した事実 (いずれも実装と一致): `worktree-merge-push.sh` は push の前にローカル `main` へマージする (110〜136 行目)。`/spec` Step 14 と `/verify` Step 13 の `ENTERED_WORKTREE=false` 経路は `git push origin main` を直接実行する。`/auto` の対象は 4 箇所で、Issue の「Step 4a・4b・L3 retrospective」のうち L3 は not-notable 経路 (events.jsonl のみ) と session.md の 2 箇所がある
- 既存の不整合 (この Issue では解消しない): `modules/worktree-lifecycle.md` の Entry section では、`ENTERED_WORKTREE=false` は「自分の worktree の中にいる (`own`)」ときに記録される。一方、伝搬表は「base branch, in the main repository」と記述している。この Issue では SKILL.md 側の push コマンドを module の記述 (lock+push only) に揃えるだけで、意味の整理はしない

### 判断の記録

- **fail-safe critical の判定: はい** (`scripts/push-to-base.sh`) — (c) に該当する。失敗時の既定 (PR を作らない・成功を名乗らない) を選んで返すスクリプトで、`2>/dev/null` や `|| true` を使うため。Implementation Step 1 にエッジケースと依存コマンド失敗時の倒し方を書いた
- **監査・調査型 Issue: いいえ** — 新しい仕組みの実装で、項目の分類表を作る Issue ではない
- **Uncertainty と Implementation Steps の整合 (方向 a: Steps 側に転記)**: Uncertainty で設計に取り込んだ 5 項目は、すべて Implementation Steps に個別に書いた。`[remote rejected]` による分類は Step 1 の分岐表と Step 4 のフィクスチャ、`gh pr merge` の再試行と state 確認は Step 1 の分岐表と手順 (f)、merge queue は Step 1 の R4、`--delete-branch` の後処理は Step 1 の R1 と手順 (f)、squash の本文は Step 1 の手順 (e) にある
- **Size の再評価: L を維持** — Changed Files は 18 件あり、件数だけなら XL に当たる。ただしロジックの変更はスクリプト 3 本・テスト 3 本・スキル 4 本 (計 10 件) に集中し、残りは 1 行程度の記述更新と日本語ミラーの同期である。Issue retrospective でも「書き込み箇所を共通の取り込み経路に集約できる想定」で L とされており、この Spec も共通スクリプト 1 本に集約した。XL にすると無人ではサブ Issue 分割 (High-Stakes) が必要になり `/auto` が止まるので、L のままとする
- **allowed-tools の影響連鎖**: Case 1 (新規 `scripts/push-to-base.sh`) は、本文から直接呼ぶのが `/merge` だけなので `skills/merge/SKILL.md` に追加する。`worktree-merge-push.sh` からの呼び出しはスクリプト間の呼び出しで、`allowed-tools` は関係しない。Case 2 (`modules/worktree-lifecycle.md` の変更) で、追記する `scripts/push-to-base.sh` は `worktree-merge-push.sh` の内部委譲の説明にとどまる。読み手のスキル (spec / code / review / merge / verify) に新しい直接呼び出しは増えないので、Case 2 による追加は無い。`/auto` は `worktree-merge-push.sh` を新たに本文から呼ぶので追加する
- **`WHOLEWORK_SCRIPT_DIR` モックの追加**: `tests/worktree-merge-push.bats` は `WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定しているので、`setup()` で実物の `push-to-base.sh` を `$MOCK_DIR` にコピーする (Step 4)。`tests/append-consumed-comments-section.bats` は `worktree-merge-push.sh` 自体をモックしているので影響なし
- **新規分岐ロジックの新規テストケース (SPEC_DEPTH=full のため spec retrospective にも要約する)**: `push-to-base.sh` の D1/D2/R1/R4/入力検証 → `tests/push-to-base.bats` の 6 件。`worktree-merge-push.sh` の exit 0 record-pr / exit 2 / 直接成功の既存挙動 → `tests/worktree-merge-push.bats` の 3 件。`_completion_spec` の `origin/main` 分岐 → `tests/reconcile-phase-state.bats` の 2 件

### 対象外 (フォローアップ候補)

- `scripts/run-auto-sub.sh`・`scripts/run-spec.sh`・`scripts/run-code.sh` の `_push_with_retry()` (`docs/reports/orchestration-recoveries.md` への回復記録の push) — フェーズ記録ではなく、異常時だけ発火する記録なので、Issue が確定した範囲の外とした。PR 必須のリポジトリでは同じく拒否され、ローカル `main` が先に進む。`worktree-merge-push.sh` (lock+push only) への置き換えが候補
- `/doc` (`modules/doc-commit-push.md` の `git push origin HEAD`)、`/review`・`/code` pr route の PR ブランチへの push (Issue の Out of Scope)
- 記録用 PR に承認や必須チェックが要るリポジトリ (Issue の Out of Scope)。R4 として原因と PR URL を報告して止まる

### 副作用

- 記録用 PR を作るたびに、そのリポジトリの `pull_request` トリガーの CI が走る (マージ後に結果は捨てられる)。直接 push できるリポジトリでは発生しない

### 出所 (実データによる前提確認)

- keio のルールセット: `gh api repos/saitoco/keio/rulesets/6390875` (取得日時: 2026-10-22)。`refs/heads/main` に `pull_request` (required_approving_review_count: 0、allowed_merge_methods: merge / squash / rebase)・`non_fast_forward`・`deletion` の 3 ルールがあり、bypass_actors は空
- keio のリポジトリ設定: `gh api repos/saitoco/keio` (取得日時: 2026-10-22)。allow_squash_merge / allow_merge_commit / allow_rebase_merge はすべて true、delete_branch_on_merge は false。`.wholework.yml` は `always-pr: true` で、`merge-strategy` は未設定 (squash にフォールバック)
- `[remote rejected]` の再現: /spec のセッション内で一時的に作った検証スクリプト (2026-10-22、git 2.47.3。スクリプト自体は残していない)。構成は、bare リポジトリに `refs/heads/main` への更新だけを exit 1 で拒否する pre-receive hook を置き、クローンから `git push origin main` (hook で拒否) と、別クローンが先に push したあとの `git push origin main` (non-fast-forward) を比べるもの。Step 4 のフィクスチャと同じ構成なので、そこで再現できる
- GitHub ルールセット拒否の出力例: https://jira.mongodb.org/browse/JAVA-6032 (取得日時: 2026-10-22。GH013 と "Changes must be made through a pull request" による拒否の事例)

## Consumed Comments

- saito / MEMBER / first-class / Issue retrospective: 方針 A/B/C と判定方法の選択は /spec に委ね、対象範囲を 7 箇所に確定、Size L の根拠 / https://github.com/saitoco/wholework/issues/1538#issuecomment-6341640802

- saito / MEMBER / first-class / <!-- wholework-event: type=pre-merge-ac-gate phase=merge issue=1538 decision=blo / https://github.com/saitoco/wholework/issues/1538#issuecomment-6343567396
- saito / MEMBER / first-class / AC 7 (Run bats tests) re-verified by merge recovery: PR #1539 CI is 17/17 passed / https://github.com/saitoco/wholework/issues/1538#issuecomment-6343606443
## issue retrospective

### 曖昧点の自動解決 (非対話モード)

- **方針 A/B/C は決めない** — 理由: 取り込み経路の選択は How にあたり、`/spec` の責務のため。完了条件は方針に依存しない結果 (取り込み経路への移行または原因報告つきの非ゼロ終了、ローカル `main` が先に進んだまま残らないこと、既存挙動の維持) で書いた
  - 他の候補: 方針 A を前提に AC を書く案 (`/spec` の選択肢を狭めるため不採用)
- **直接 push の可否の検出方法も `/spec` に委ねる** — 設定キーを新設した場合に限り、`modules/detect-config-markers.md` と `docs/guide/customization.md` への記載を求める AC にした
- **「各フェーズの記録」の範囲を確定** — 元の 5 箇所に加え、調査で `skills/spec/SKILL.md` Step 14 と `skills/verify/SKILL.md` Step 13 の `ENTERED_WORKTREE=false` 経路 (`git push origin main` を直接実行) も同じ問題を持つことを確認し、調査の出発点と AC に含めた

### 完了条件の変更理由

- 元の「完了条件の案」4 件を、検証可能な Pre-merge 6 件と Post-merge 1 件に整理した
  - 「`/auto N` が手動介入なしに進む」「記録が欠落しない」は、wholework 本体が `main` へ直接 push できるため pre-merge では再現できない。pre-merge は rubric と bats で部分的に確認し、実リポジトリでの通し確認は Post-merge の manual にした
  - 新規テストの追加を主張する AC には、フィクスチャが修正前の実装で FAIL することを問う rubric AC を併記した (検出力ゼロのテストを防ぐため)
- 記録用 PR に承認が必須のルールセットは無人で満たせないため、Out of Scope に明記した

### 方針に関する判断

- 実行環境の前提として、実リポジトリでの確認に必要な権限 (対象リポジトリへの書き込み、PR のマージ) を Background に記録した。実行アカウントがこの権限を持つかは未確認のオープンクエスチョンとして残した
- Size は L とした (スクリプト 3 本・skill 3 本・modules/docs・テストにまたがるが、書き込み箇所を共通の取り込み経路に集約できる想定)。非対話モードのためサブ Issue 分割 (Step 12) はスキップした。`/spec` で規模が XL に相当すると判断された場合は、対話モードで `/issue 1538` を実行して分割を検討すること

## spec retrospective

### Minor observations

- `/auto` の `allowed-tools` には `git commit`・`git push` が無い。Step 4b・4a・L3 の commit と push は、frontmatter ではなく実行時の権限設定 (auto mode) で通っていた。今回 `worktree-merge-push.sh` を追加すると、push 側だけが frontmatter で明示されることになる
- `/auto` の L3 には push が 2 箇所ある (not-notable 経路の events.jsonl と、session.md の commit)。Issue 本文の「L3 retrospective」は 1 箇所に見えるが、実際は 2 箇所とも対象になる
- `scripts/run-auto-sub.sh`・`run-spec.sh`・`run-code.sh` に同じ `_push_with_retry()` が 3 つ複製されている。回復記録の push も PR 必須のリポジトリでは同じ問題を持つので、フォローアップ候補として Notes に記録した

### Judgment rationale

- 方針は A (記録用 PR) にした。B と C は spec の記録しか救えず、verify・merge・auto の記録には別の仕組みが要る。A なら 1 つのスクリプトに集約できる
- 直接 push の可否は、設定キーではなく push 出力の `[remote rejected]` トークンで判定する。リモートがすでに強制しているポリシーを設定に二重に書かずに済み、直接 push できるリポジトリには追加の API 呼び出しも PR も発生しない
- `worktree-merge-push.sh` へのインライン実装ではなく、新しいスクリプト `push-to-base.sh` にした。`/merge` は worktree ブランチの `HEAD` を push するため、ローカル `main` に取り込んでから push する `worktree-merge-push.sh` の形に載らない
- squash・rebase で祖先関係が切れる問題は、呼び出し元の cleanup (`git branch -d`) を変えずに、スクリプトの中でローカル `<base>` と `--from` ブランチを `origin/<base>` に揃えて解決した。cleanup 側を `-D` に変える案は、LLM が実行する手順に分岐が増えるので採らなかった
- `_completion_spec` の `origin/main` 確認では `git fetch` をしない。既存の単体テストがネットワークに依存しないようにするため。追跡 ref は push と記録用 PR 経路の fetch で更新される
- Size は L のまま (Changed Files は 18 件だが、ロジックの変更は 10 件。XL にすると無人ではサブ Issue 分割ができず止まる)
- 新規分岐ロジックに必要な新規テストケース: `tests/push-to-base.bats` に 6 件 (D1 / D2 / R1 / R4 / `--ref HEAD` / 引数エラー)、`tests/worktree-merge-push.bats` に 3 件 (拒否から記録用 PR で取り込んで整列 / PR マージ失敗でも base が先に進まない / 直接 push の既存挙動)、`tests/reconcile-phase-state.bats` に 2 件 (`origin/main` のみ → true / どこにも無い → false)

### Uncertainty resolution

- `[remote rejected]` と `[rejected]` の区別は、ローカルの bare リポジトリと pre-receive hook で再現して確認した (git 2.47.3、`LANG=ja_JP.UTF-8` でもトークンは不変)。GitHub ルールセットの理由文は公開事例 (MongoDB Jira JAVA-6032) で確認した。keio 実機での確認は Post-merge の manual に残る
- keio のルールセットは承認数 0・全マージ方式許可・bypass なしで、記録用 PR は無人でマージできることを `gh api` で確認した
- merge queue のブランチでは `gh pr merge` が auto-merge の有効化だけで終わることを `gh pr merge --help` で確認し、state 判定で R4 (exit 2) に倒す設計にした
- 未確定のまま残したもの: `gh pr create` 直後の一時的なマージ不可 (再試行で吸収する)、`--squash` の `--body-file` が squash コミットにどう反映されるか (Post-merge で観察する)

## Code Retrospective

### Deviations from Design
- `scripts/push-to-base.sh` に環境変数 `WHOLEWORK_PUSH_RETRY_INTERVAL` (既定 2 秒) を追加した。Spec は間隔を固定値としていたが、R4 (マージ未完了) のテストが 3 回 × 3 回の待機で十数秒かかるため、テストからだけ 0 に上書きできるようにした。本番の既定値は Spec どおり
- `gh pr create` の stderr は握りつぶさず、そのまま流すようにした。Spec は `2>/dev/null` を許容していたが、PR 作成失敗の原因 (認証・API エラー) を呼び出し側のログに残すほうが復旧しやすい。標準出力の最終行だけを URL として使い、`http` で始まらなければ R3 (exit 2) に倒す
- `worktree-merge-push.sh` の exit 2 経路に、Spec に無い安全弁を足した。`--from` が無い (lock+push only) 呼び出しで、`wholework-record/*` ブランチがローカル `<base>` の先端を保持していないときは、ローカル `<base>` を巻き戻さず、その旨を出して exit 1 にする。巻き戻すとコミットが reflog にしか残らなくなるため。入力検証の exit 2 (記録用ブランチを作る前) だけがこの条件に当たる
- Spec の `/merge` 手順は「Step 4 substep 4」を参照している箇所があったが、実際の push は substep 5 だったので、`modules/worktree-lifecycle.md` の伝搬表は substep 5 に直した

### Design Gaps/Ambiguities
- `reconcile-phase-state.bats` の既存 spec テストは `MOCK_SPEC_PATH` に絶対パスを使っている。`_completion_spec` の `origin/main` 確認は相対 `spec_path` のときだけ行うため (絶対パスは git のツリー指定にできない)、既存テストは影響を受けない。新規 2 件は相対パスと実 git のフィクスチャで書いた
- `check-bare-bracket-assertions.sh` は既存の bare `[[ ]]` を大量に報告する (情報のみ)。新規テストは `|| false` を付けて bash 3.2 でも失敗が伝わる形にした
- worktree 隔離ガードは、git を含む文字列を渡す `python3 - <<EOF` や、`;` で連結した複数コマンドを拒否した。編集は Edit ツールに、検証コマンドは単独実行に切り替えて対処した

### Rework
- `skills/verify/SKILL.md` の `skill-body-sha` を一度更新し忘れ、`check-skill-body-hash.sh` が失敗した。行数は変わらず (1003 のまま)、sha のみ再計算した

### Verification Notes
- Confirmed pre-implementation FAIL for 2 new test(s) in `tests/worktree-merge-push.bats` (リモート拒否から記録用 PR で取り込む / PR がマージできないときローカル `main` が先に進まない): 修正前の `worktree-merge-push.sh` と今回のテストで実行して `not ok` を確認した。残る 1 件 (直接 push できるリポジトリでは PR もブランチも作らない) は既存挙動の保持を確認するテストなので、修正前でも PASS する設計
- `tests/push-to-base.bats` 6 件と `tests/reconcile-phase-state.bats` の新規 2 件は、いずれも新規のスクリプト・分岐に対する出力・終了コードの検証で、ファイル内容の文字列照合ではない
- Step 10: Pre-merge の rubric AC 6 件はグレーダーを起動せず (`/review` が PR 上で評価する)、チェックを付けていない。`github_check "gh pr checks"` は pr route の除外対象 (PR 作成前は評価できない)
- Tier 0 の test-failure 回復は発動なし (`bats --jobs 4 tests/` は 2269 件すべて PASS)

## review retrospective

### Spec vs. implementation divergence patterns
- 実装は Spec の分岐表 (D1 / D2 / R1〜R4) と exit code の列挙に沿っており、構造的な乖離はなかった。ただし追跡 ref (`refs/remotes/origin/<base>`) が無い場合の `RANGE` 失敗を Spec が想定しておらず、squash 本文が無警告で空になる穴があった (レビューで `fetch` + fail-closed に修正)
- `resolve-merge-strategy.sh` が CWD 基準で `.wholework.yml` を読む点も Spec に無く、サブディレクトリ実行で設定した `merge-strategy` が黙って `--squash` に落ちた (リポジトリルートで実行するよう修正)

### Recurring issues
- CI でだけ落ちる環境依存のテスト: `gh` モックの `git commit-tree` が committer identity を必要とし、開発機 (global identity あり) では PASS、CI ランナーでは決定的に失敗した。実 git を使うモックの fixture は、identity を自前で設定する必要がある。`GIT_CONFIG_GLOBAL=/dev/null` と `HOME` を空にして実行すると再現できる
- `/code` の完了報告 (全件 PASS) は、開発機の環境でのものだった。pr route の `/code` が CI 相当の無 identity 環境でテストを一度回していれば、レビューより前に見つかった

### Acceptance criteria verification difficulty
- rubric AC 6 件は、グレーダーが PASS を返した (Spec を渡さない構成でも判定できた)。`github_check "gh pr checks" "Run bats tests"` は CI の完了待ちが長く (6 分超)、修正後の再確認が `/review` の中で終わらなかった。AC 7 は未チェックのまま `/merge` に引き継ぐ
- UNCERTAIN はなく、verify command の誤りもなかった

## Phase Handoff

<!-- phase: merge -->

### Key Decisions
- pre-merge AC は全てチェック済み (未チェック 0)、CI は success、review は approved だったため、`--squash` (`resolve-merge-strategy.sh --flag` の結果) でそのままマージした
- review の Notes にあった AC 7 (`Run bats tests`) は、マージ前に CI が success になっていることを確認済み
- コンフリクトは無く、Consumed Comments は `append-consumed-comments-section.sh` のフォールバックで記録した

### Deferred Items
- 実リポジトリ (saitoco/keio など `main` が PR 必須) での `/auto N` 通し確認は、Post-merge の manual AC のまま
- review から引き継いだ CONSIDER (`[remote rejected]` の理由分類、`--base @` の受理、`customization.md` の説明追記) は未対応

### Notes for Next Phase
- verify では Post-merge の manual AC 1 件が残る。`main` が PR 必須のリポジトリでの実機確認が必要
- 記録用 PR は、そのリポジトリの `pull_request` トリガーの CI を走らせる点に注意

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 変更ファイル 18 件で Size L のまま進めた判断は妥当だった。spec 時点で `_push_with_retry()` と `/doc` の push を範囲外として Notes に残しており、フォローアップの起点が明確

#### design
- `[remote rejected]` と `[rejected]` を ref status token で判別する方式は、設定キーを増やさずに既存挙動を保てた。ただし並行 push の競合でも `[remote rejected]` になりうる点は CONSIDER として残っている

#### code
- 開発機 (global identity あり) で全件 PASS としたが、CI ランナー (identity なし) では `gh` モックの `git commit-tree` が決定的に失敗した。pr route の `/code` で無 identity 環境のテストを一度回していればレビュー前に検出できた

#### review
- CI 失敗 (MUST) と SHOULD 2 件を検出・修正し、有効だった。一方、修正 push 後の `Run bats tests` 完了を待たずに終了したため、AC 7 (`github_check "gh pr checks"`) が未チェックのまま `/merge` に渡った

#### merge
- 初回の `/merge` は、CI が 17/17 PASS かつ mergeable だったにもかかわらず、未チェックの AC 7 を理由に非対話モードで停止した (exit 1)。`/auto` の Tier 3 回復 (cause: `ac-unchecked-after-review-fix-push`) で CI 状態を確認したうえで AC 7 にチェックを付け、再実行でマージした

#### verify
- Pre-merge 7 件はすべてチェック済みで SKIPPED。Post-merge の manual AC 1 件 (PR 必須リポジトリでの `/auto` 通し確認) は keio での実行待ち
- このセッションの verify SKILL.md はキャッシュが古く (PR #1539 が Step 13 を変更)、Step 13 はディスク上の版に従った

### Improvement Proposals
- `/merge` (非対話モード) で、未チェックの Pre-merge AC が `github_check "gh pr checks" ...` だけの場合、その場で verify command を実行し PASS ならチェックを付けて続行する。`/review` が修正 push 後の CI 完了前に終了するたびに `/merge` が停止し、Tier 3 回復が必要になるのを防ぐ

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| issue | - | SUCCESS | Size L に判定 |
| spec | - | SUCCESS | `--opus` |
| code | pr | SUCCESS | PR #1539 |
| review | pr (`--full`) | SUCCESS | CI fail 2 件 → 修正済み、SHOULD 2 件修正 |
| merge | pr | SUCCESS (Tier 3 recovery) | 初回 exit 1 (未チェック AC 7 で gate 停止) → AC 7 チェック後に再実行 |
| verify | - | PARTIAL | Post-merge manual AC 1 件待ち (phase/verify) |

### Orchestration Anomalies
- `run-merge.sh 1539` が exit 1。`/review` が修正 push 後の CI 完了前に終了し、AC 7 (`github_check "gh pr checks" "Run bats tests"`) が未チェックのまま残ったため、非対話の `/merge` が pre-merge AC gate で停止した。external kill・CI infra・Tier 2 はいずれも該当せず、Tier 3 の回復計画 (recover) で CI 17/17 PASS を確認して AC 7 をチェックし、再実行でマージした

### Improvement Proposals
- N/A (verify retrospective の提案と同一のため重複を避ける)
