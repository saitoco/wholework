# Issue #1066: code: preview ビルドの成功確認を code フェーズの責務にする

## Overview

`capabilities.pr-preview: true` の web 系プロジェクトで、PR 作成後に hosting provider (Amplify / Vercel / Netlify 等) が走らせる preview ビルドの成功確認を `/code` の責務とする。あわせて `scripts/wait-ci-checks.sh` の完了判定にある 2 つの穴 (未完了 state の取りこぼし / check 0 件の誤判定) を塞ぐ。

方針は 2 本立てである。

- **A**: `/code` の pr route に、`HAS_PR_PREVIEW_CAPABILITY=true` のときだけ発火する preview ビルド待ちステップを追加する。失敗時は code フェーズ内で修正コミットを push して再度待つ (上限あり)
- **B**: `wait-ci-checks.sh` の完了判定を `gh pr checks --json` の `bucket` フィールドベースに置き換え、check 0 件時に最低待機時間 + 明示的警告を挟む

`capabilities.pr-preview` 未宣言のプロジェクトでは A のステップ全体を skip し、既存挙動を維持する。B は全 caller (`/review` / `/merge` / 新規 `/code`) に効くが、後方互換 (exit code 0 固定、`ci_wait` イベント形状不変) を保つ。

## Reproduction Steps

### 穴 1: `IN_PROGRESS` 以外の未完了状態を待たない

1. `capabilities.pr-preview: true` のプロジェクトで PR を作成する
2. hosting provider の preview ビルドが CheckRun として登録され、まだ `queued` 段階にある
3. `/review` (または `/merge`) が `scripts/wait-ci-checks.sh <PR>` を呼ぶ
4. `wait-ci-checks.sh:42` の `select(.state == "IN_PROGRESS")` が `QUEUED` にマッチせず `_in_progress=0` となり、43 行目で即座に `break` する
5. ビルド未完了のまま次フェーズへ進む

### 穴 2: check が 1 件も登録されていない状態を完了と判定する

1. PR への push で GitHub Actions の check-suite が作成されず、`gh pr checks` の返り値が空配列 `[]` になる
2. `jq '[.[] | select(.state == "IN_PROGRESS")] | length'` が `0` を返す
3. `_in_progress -eq 0` が成立し、CI を 1 件も待たずに `break` する

### 穴 3 (Purpose 側): `/code` がデプロイビルドの結果を確認しない

1. `capabilities.pr-preview: true` のプロジェクトで `/code 123 --pr` を実行する
2. `skills/code/SKILL.md` Step 11 で PR が作成され、Step 12 の retrospective commit を push した時点で code フェーズが完了する
3. provider 側の preview ビルドが失敗していても `/code` は検知せず、`/review` の CI 待ちに委ねられる

## Root Cause

### 穴 1 の根本原因

`gh pr checks --json state` が返す `state` 値は 14 種類あり、CheckRun の `status`/`conclusion` と StatusContext の `state` の両方にマップされる。`scripts/wait-ci-checks.sh:42` はそのうち `IN_PROGRESS` 1 種類だけを「未完了」とみなしているため、残り 6 種類の未完了 state を取りこぼす。

gh CLI 2.96.0 の `pkg/cmd/pr/checks/aggregate.go` が定義する state → bucket マッピング (全 14 state、**exhaustive**):

| bucket | state |
|--------|-------|
| `pass` | `SUCCESS` |
| `skipping` | `SKIPPED`, `NEUTRAL` |
| `fail` | `ERROR`, `FAILURE`, `TIMED_OUT`, `ACTION_REQUIRED` |
| `cancel` | `CANCELLED` |
| `pending` | `EXPECTED`, `REQUESTED`, `WAITING`, `QUEUED`, `PENDING`, `IN_PROGRESS`, `STALE` |

Issue 本文が「実装時に実機で確認すること」と留保していた点は、この gh CLI の `bucket` フィールドで解決する。Issue 本文が想定していた「未完了 state を列挙する」対応より、`bucket == "pending"` 1 条件で 7 state すべてを吸収するほうが正確かつ将来の state 追加にも耐える。

### 穴 2 の根本原因

`gh pr checks --json` は check が 0 件でも exporter が空配列 `[]` を書き出す (`pkg/cmd/pr/checks/checks.go`; 併せて `no checks reported on the '<branch>' branch` を返す)。`wait-ci-checks.sh` は「期待する check が存在すること」を前提に持たないため、`[]` を「未完了 0 件 = 完了」と解釈してしまう。

### 穴 3 の根本原因

`skills/code/SKILL.md:386` の設計判断 (`pr route: continue — CI will detect the failure`) を PR 作成後まで延長した結果、code フェーズは「ローカル検証まで」を責務範囲としている。デプロイビルドは hosting provider 上でしか再現できないケースがあるため、ローカル検証だけでは実装の欠陥を検知できない。

## Changed Files

- `scripts/wait-ci-checks.sh`: 完了判定を `bucket == "pending"` ベースへ変更、check 0 件時の grace period + 警告を追加、caller 向け `ci_result:` サマリ行を stdout へ出力 — bash 3.2+ compatible
- `tests/wait-ci-checks.bats`: 全 `gh` モックへ `bucket` フィールドを追加、`QUEUED` / check 0 件 / `ci_result:` 行の新規テストを追加
- `skills/code/SKILL.md`: 新規 Step 13 (Preview Build Verification) を挿入、既存 Step 13 → 14 / Step 14 → 15 へ繰り上げ、内部の Step 番号参照を更新、frontmatter `allowed-tools` に 3 パターン追加、Step 0 の retain 対象に `HAS_PR_PREVIEW_CAPABILITY` を追加、Completion Report に preview 失敗時の prefix を追加
- `docs/tech.md`: Environment Variables 表に `WHOLEWORK_CI_MIN_CHECKS_WAIT_SEC` 行を追加、`HAS_PR_PREVIEW_CAPABILITY` capability flag 行に `/code` の preview ビルド待ちゲートを追記
- `docs/ja/tech.md`: 上記の日本語ミラー (`docs/translation-workflow.md` の sync 手順に従う)
- `docs/workflow.md`: `### 3. /code — Implementation` 節に preview ビルド待ちの段落を追加
- `docs/ja/workflow.md`: 上記の日本語ミラー
- `docs/guide/customization.md`: `capabilities.pr-preview` キー説明行と「Enabling pre-merge-preview」段落に `/code` の preview ビルド待ちを追記
- `docs/ja/guide/customization.md`: 上記の日本語ミラー
- `docs/structure.md`: `scripts/wait-ci-checks.sh` の説明行を新しい責務 (bucket ベース判定 + `/code` からの呼び出し) に更新
- `docs/ja/structure.md`: 上記の日本語ミラー
- `docs/reports/event-log-schema.md`: `ci_wait` イベントの `checks_passed` / `checks_failed` 説明を grep ベース記述から bucket ベース記述へ修正 (ja ミラーなし、`docs/reports/` は translation-workflow の除外対象)

**Steering Docs sync candidate** (`/code` が読んで include/exclude を最終判断する):

- `modules/verify-executor.md`: `github_check` 行の「`gh pr checks` uses `--json name,state` (state values: `SUCCESS`, `FAILURE`, `IN_PROGRESS`)」という記述が実際の 14 state と乖離しており、`in_progress` 検出も穴 1 と同型の取りこぼしを持つ。本 Issue のスコープ外 (Issue 本文は `wait-ci-checks.sh` と `skills/code/SKILL.md` のみを対象と明記) だが、同系統の不整合として記録する
- `tests/issue.bats`: `pr-preview` を含む `@test` が 1 件存在する (`detect-config-markers documents pr-preview capability`)。本 Issue は `modules/detect-config-markers.md` を変更しないため更新不要の見込みだが、`/code` が実際に読んで確認する

**変更不要と判断したファイル** (grep で確認済み):

- `modules/detect-config-markers.md`: `capabilities.pr-preview` → `HAS_PR_PREVIEW_CAPABILITY` の定義行は既に存在し、本 Issue は新しい YAML キーを追加しない (`grep -n "pr-preview" modules/detect-config-markers.md` で 2 箇所ヒット、いずれも既存定義)
- `scripts/run-code.sh`: preview 待ちは skill 内 (Step 13) に置くため wrapper 側の変更なし (`grep -n "wait-ci-checks" scripts/run-code.sh` で 0 件)
- `scripts/validate-skill-syntax.py`: `KNOWN_TOOLS` はベースツール名のみを検証する。追加するのは `Bash(...)` 内のパターン 3 件だけでベースツール名 `Bash` は登録済みのため更新不要
- `scripts/run-review.sh` / `scripts/run-merge.sh`: `wait-ci-checks.sh` の exit code を 0 固定のまま維持するため、`set -euo pipefail` 下の呼び出し行 (それぞれ 102 行目 / 99 行目) は無変更

**計測スコープ**: 上記の grep はいずれもリポジトリルートから実行し、`docs/spec/` と `docs/sessions/` を除外した結果である。

## Implementation Steps

1. `scripts/wait-ci-checks.sh` の polling ループの完了判定を bucket ベースへ変更する (→ acceptance criteria 3)
   - `gh pr checks` の `--json name,state` を `--json name,state,bucket` に変更する (3 箇所ある `timeout` / `gtimeout` / 直接実行の分岐すべて)
   - `_in_progress=$(... select(.state == "IN_PROGRESS") ...)` を `_pending=$(echo "$_poll_result" | jq '[.[] | select(.bucket == "pending")] | length' 2>/dev/null || echo "1")` に置き換える。jq 失敗時のフォールバック `1` (= 未完了扱いでループ継続) は現状の保守的挙動を維持する
   - 継続時の stderr メッセージを `CI checks pending: ${_pending} of ${_total} check(s) not yet complete...` に変更する
   - `sleep 60` のポーリング間隔と `TIMEOUT_SEC` による外側の打ち切りは変更しない

2. (after 1) `scripts/wait-ci-checks.sh` に check 0 件時の grace period と `ci_result:` サマリ行を追加する (→ acceptance criteria 4, 1)
   - 新しい環境変数 `MIN_CHECKS_WAIT_SEC="${WHOLEWORK_CI_MIN_CHECKS_WAIT_SEC:-120}"` をファイル冒頭の `TIMEOUT_SEC` 定義の直後に追加する。ヘッダコメントの `Environment variables:` ブロックにも 1 行追記する
   - polling ループ内で `_total=$(echo "$_poll_result" | jq 'length' 2>/dev/null || echo "-1")` を求める。jq 失敗時のフォールバック `-1` は「件数不明」を表し、後述の 0 件分岐に入らない (= 保守的にループ継続)
   - 0 件分岐 (`_total -eq 0`) の挙動を全列挙する:
     - **経過時間 < `MIN_CHECKS_WAIT_SEC`**: stderr に `No CI checks registered yet on PR #${PR_NUMBER}; waiting (grace period ${MIN_CHECKS_WAIT_SEC}s)...` を出力し、`sleep 60` して `continue` する (ループ継続。exit しない)
     - **経過時間 >= `MIN_CHECKS_WAIT_SEC`**: `_zero_checks_seen=true` を立て、stderr に `Warning: no CI checks registered on PR #${PR_NUMBER} after ${MIN_CHECKS_WAIT_SEC}s grace period; proceeding without CI confirmation` を出力して `break` する (ループ終了。exit code は 0 のまま)
   - `_total -gt 0` かつ `_pending -eq 0` のとき `break` する (正常完了)
   - ループ終了後、最終行として **stdout** に `ci_result: total=<N> passed=<N> failed=<N> pending=<N> zero_checks=<true|false>` を 1 行出力する。`passed` は `bucket == "pass"`、`failed` は `bucket == "fail"`、`pending` は `bucket == "pending"` の件数。既存の人間向けメッセージはすべて stderr のままとし、stdout に出るのはこの 1 行だけにする
   - **exit code は全分岐で 0 のままとする**。`scripts/run-review.sh` (102 行目) と `scripts/run-merge.sh` (99 行目) は `set -euo pipefail` 配下で本スクリプトを呼ぶため、非 0 化は既存 2 caller を破壊する
   - `_zero_checks_seen` の初期値 `false` はループ開始前に設定する
   - `ci_wait` イベントの `checks_passed` / `checks_failed` も同じ bucket ベースの値を再利用する (`state == "SUCCESS"` / `state == "FAILURE"` からの置き換え)。イベントのフィールド名・件数・emission 位置は変更しない
   - bash 3.2+ compatible (`mapfile` などの bash 4 構文を使わない)

3. (after 2) `tests/wait-ci-checks.bats` を更新する (→ acceptance criteria 3, 4)
   - `setup()` のデフォルト `gh` モックを含め、ファイル内の**全ての** `gh` モックが返す JSON に `bucket` フィールドを追加する。`state` と整合させる (`SUCCESS`→`pass`、`IN_PROGRESS`→`pending`、`FAILURE`→`fail`)。bucket 未付与のまま残すと `select(.bucket == "pending")` が常に 0 件となり、既存のタイムアウト系テスト (`success: continues even when timeout exits non-zero`) が意図した経路を通らなくなる
   - 新規 `@test` を追加する (`@test` 名は ASCII のみ):
     - `QUEUED` state (`bucket: pending`) を返すモックで即座に break しないこと (`WHOLEWORK_CI_TIMEOUT_SEC` を小さく設定してタイムアウト経路で終了することを確認)
     - `[]` (check 0 件) を返すモックで `WHOLEWORK_CI_MIN_CHECKS_WAIT_SEC=0` のとき警告メッセージを出して終了すること
     - `[]` を返すモックで `WHOLEWORK_CI_MIN_CHECKS_WAIT_SEC` が経過時間より大きいとき即座に break しないこと
     - stdout に `ci_result:` 行が 1 行出力され、`total=` / `passed=` / `failed=` / `pending=` / `zero_checks=` の 5 キーを含むこと
   - 既存の `ci_wait` イベント系テスト 4 件が引き続き PASS することを確認する (削除・置換したテストが覆っていたシナリオを新テストが引き継いでいるか確認する)

4. `skills/code/SKILL.md` に新規 Step 13 を挿入し、既存ステップを繰り上げる (→ acceptance criteria 1, 2, 5)
   - 挿入位置: `### Step 12: Code Retrospective` の末尾 (pr route の `git push origin HEAD` ブロックの直後) と、既存の `### Step 13: Worktree Exit` 見出しの直前
   - 見出しは `### Step 13: Preview Build Verification (pr route only)` (h3、整数のステップ番号)
   - 冒頭に発火条件を書く: ROUTE が `pr` **かつ** `HAS_PR_PREVIEW_CAPABILITY` が `true` (`.wholework.yml` の `capabilities.pr-preview: true` に由来、Step 0 で retain 済み) のときのみ実行する。いずれかが false の場合は本ステップ全体を skip して Step 14 へ進む。`capabilities.pr-preview` を宣言していないプロジェクトでは既存挙動が変わらない (PR 作成で code フェーズが完了し、CI / preview の失敗検知は `/review` に委ねられる) ことを明記する
   - 待機呼び出しを書く。progress 行を先に出してから Bash で実行する:
     - `echo "progress: Waiting for deploy/preview build on PR #$PR_NUMBER (issue #$NUMBER)..."`
     - `WHOLEWORK_CI_TIMEOUT_SEC=540 ${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh $PR_NUMBER`
     - Bash ツールの `timeout` に `600000` を指定する。`WHOLEWORK_CI_TIMEOUT_SEC=540` は Bash ツールの 10 分上限より内側にスクリプト自身の打ち切りを置くための値であり、変更してはならない旨を注記する
   - 呼び出し結果 (`ci_result:` 行) に対する分岐を全列挙する (**exhaustive**):

     | 条件 | 挙動 |
     |------|------|
     | `pending>0` かつ待機ラウンド数 < 4 | 待機ラウンドを 1 加算して同じコマンドを再実行する |
     | `pending>0` かつ待機ラウンド数 = 4 | 待機打ち切り。未完了 check 名を列挙した警告を出力し、Step 14 へ進む (`/review` 側が引き続き CI を待つ) |
     | `failed>0` | 修正ループ (下記) へ入る |
     | `zero_checks=true` | check が 1 件も登録されなかった旨の警告を出力し、Step 14 へ進む |
     | `total>0` かつ `failed=0` かつ `pending=0` | 成功。Step 14 へ進む |

   - 修正ループの挙動を全列挙する (最大 3 反復。`verify-max-iterations` / `auto-retry-on-fail.max_iterations` の既定値 3 と同じ考え方):
     1. `gh pr checks $PR_NUMBER --json name,state,bucket,link` で失敗した check の名前と link を取得する
     2. 失敗原因を診断する。link が `github.com/.../actions/runs/` を指す GitHub Actions の check であれば `gh run view --log-failed` でログを取得する。link が外部 provider のコンソール URL (Amplify / Vercel / Netlify 等) の場合はログを直接取得できないため、プロジェクトのビルドコマンド (`package.json` の `scripts.build` 等) をローカルで再現できるならそれを実行し、できない場合は check の `description` テキストを手がかりにする
     3. 修正をワークツリー内で適用し、`git add` → `git commit -s -m "Fix preview build failure for issue #$NUMBER"` → `git push origin HEAD` を実行する
     4. 待機ラウンド数を 0 にリセットし、待機呼び出しからやり直す
     5. **上限到達 (3 反復完了しても `failed>0`)、または step 2 で actionable な診断が得られなかった場合**: それ以上の修正を試みず、失敗した check 名と link を明示した失敗レポートを出力して Step 14 へ進む。code フェーズは非 0 exit しない (commit と PR は正当な成果物であり、`/review` が引き続き CI 失敗を検知する)
   - 半角の感嘆符を本文に含めないこと

5. (after 4) `skills/code/SKILL.md` の付随箇所を更新する (→ acceptance criteria 1, 2)
   - frontmatter `allowed-tools` の `Bash(...)` リストに 3 パターンを追加する: `${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh:*`、`gh pr checks:*`、`gh run view:*`
   - Step 0 の「Retain `ALWAYS_PR` and `SPEC_PATH` for use in route detection below.」に `HAS_PR_PREVIEW_CAPABILITY` を追加する
   - Step 番号の繰り上げに伴う内部参照を更新する (該当行: 313 行目の `proceed to Step 13's L1 branch` → Step 14、524 行目の `Push is done in Step 13 Worktree Exit` と `after Step 13` → Step 14、617 行目の `see Step 12 and Step 13 below` → Step 14、666 行目の `push is done in Step 13 Worktree Exit` → Step 14)。行番号は Step 4 の挿入によりずれるため、実装時は周辺の文脈で位置を特定する
   - 既存の `### Step 13: Worktree Exit` を `### Step 14: Worktree Exit` に、`### Step 14: Opportunistic Verification` を `### Step 15: Opportunistic Verification` に変更する
   - Completion Report の prefix 一覧に preview ビルド失敗時の pr route prefix を追加する: `PR creation complete (preview build FAILED — N check(s) failing after M fix attempts).`

6. `docs/tech.md` と `docs/ja/tech.md` を更新する (parallel with 4, 5) (→ acceptance criteria 5)
   - `## Environment Variables` 表に行を追加する: `| WHOLEWORK_CI_MIN_CHECKS_WAIT_SEC | 120 | Grace period in seconds during which wait-ci-checks.sh keeps polling when gh pr checks reports zero registered checks. After the grace period elapses with still zero checks, the script emits an explicit warning and stops waiting. Set to 0 in tests to skip the grace period. |`
   - `### Capability Flags` 表の `HAS_PR_PREVIEW_CAPABILITY` 行に、`/code` の pr route で PR 作成後のデプロイビルド完了を待つゲートとしても機能すること、および未宣言時は `/code` の挙動が従来どおりであることを追記する
   - `docs/ja/tech.md` の対応する 2 箇所 (Environment Variables 表、Capability Flags 表の `HAS_PR_PREVIEW_CAPABILITY` 行) を日本語で同期する

7. `docs/workflow.md` / `docs/ja/workflow.md` / `docs/guide/customization.md` / `docs/ja/guide/customization.md` を更新する (parallel with 6) (→ acceptance criteria 5)
   - `docs/workflow.md` の `### 3. /code — Implementation` 節、operate route の段落の直後に段落を追加する。内容: `capabilities.pr-preview: true` のとき pr route は PR 作成後にデプロイビルドの完了を待ち、失敗時は code フェーズ内で最大 3 回まで修正コミットを push して再検証する。未宣言のプロジェクトでは PR 作成で完了する従来動作を維持する
   - `docs/guide/customization.md` の `capabilities.pr-preview` キー説明行と「Enabling pre-merge-preview」段落に、同 capability が `/code` の preview ビルド待ちも有効化することを追記する
   - `docs/ja/workflow.md` / `docs/ja/guide/customization.md` の対応箇所を日本語で同期する。`docs/translation-workflow.md` の Sync Procedure step 5 (コードフェンス数の一致確認) を適用する

8. `docs/structure.md` / `docs/ja/structure.md` / `docs/reports/event-log-schema.md` を更新する (parallel with 6, 7) (→ acceptance criteria 3, 4)
   - `docs/structure.md:212` の `scripts/wait-ci-checks.sh` 説明行を、bucket ベースの pending 判定と check 0 件 grace period、および `/review` / `/merge` に加えて `/code` (pr route + pr-preview capability) からも呼ばれることを含む記述へ更新する
   - `docs/ja/structure.md:204` の対応行を日本語で同期する
   - `docs/reports/event-log-schema.md` の `ci_wait` セクションで、`checks_passed` / `checks_failed` のフィールド説明と末尾の Note にある「grep-based」という記述を、`gh pr checks --json bucket` ベースである旨に修正する

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md の pr route に、capabilities.pr-preview: true の場合に PR 作成後のデプロイビルド完了を待ち、失敗時は code フェーズ内で修正するステップが追加されている" --> `/code` が preview ビルドの成功を確認してから完了する
- <!-- verify: grep "pr-preview" "skills/code/SKILL.md" --> `skills/code/SKILL.md` が `pr-preview` capability を参照している
- <!-- verify: rubric "scripts/wait-ci-checks.sh の完了判定が IN_PROGRESS 以外の未完了状態 (queued 等) も未完了として扱うようになっている" --> `wait-ci-checks.sh` が未完了状態を取りこぼさない
- <!-- verify: rubric "wait-ci-checks.sh が check 0 件の状態を完了と誤判定しないための対策 (期待 check の宣言、最低待機時間、明示的な警告のいずれか) が実装されている" --> check 未登録時の誤判定対策がある
- <!-- verify: rubric "capabilities.pr-preview が未宣言のプロジェクトでは /code の既存挙動が変わらないことが明記されている" --> 後方互換が保たれている

### Post-merge

- `capabilities.pr-preview: true` のプロジェクトで意図的にビルドを失敗させ、`/code` がその失敗を検知して完了しないことを確認する
- <!-- verify: command "bats tests/wait-ci-checks.bats" --> キュー段階の check (`bucket: pending`) に対して `wait-ci-checks.sh` が即座に break せず待機を継続することを bats テストで確認する

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh:*`: Step 13 が preview / CI ビルドの完了待ちに使用する (`skills/code/SKILL.md` の `allowed-tools` に未登録 — 追加が必要)
- `gh pr checks:*`: Step 13 の修正ループが失敗した check の名前と link を取得するために使用する (`skills/code/SKILL.md` の `allowed-tools` に未登録 — 追加が必要)
- `gh run view:*`: Step 13 の修正ループが GitHub Actions の失敗ログを取得するために使用する (`skills/code/SKILL.md` の `allowed-tools` に未登録 — 追加が必要)

### Built-in Tools

- なし (既存の `Read` / `Write` / `Edit` / `Grep` / `Glob` で足りる)

### MCP Tools

- なし

## Uncertainty

- **Bash ツールの単一呼び出し 10 分上限が headless `claude -p` 内でも適用されるか**: `docs/spec/issue-875-abolish-data-layer-md.md` の Code Retrospective に、`skills/auto/SKILL.md` が `timeout: 600000` を指定して `run-code.sh` を呼んだ際、約 660–720 秒で外部から kill された記録がある。ただしこれは `/auto` (対話セッション) からの Bash 呼び出しであり、headless `claude -p` 内の Bash 呼び出しで同じ上限が効くことの直接的な実測ではない。
  - **検証方法**: Step 13 の実装後、`capabilities.pr-preview: true` の実プロジェクトで `run-code.sh` 経由の pr route を実行し、待機呼び出しが 540 秒付近で正常に自走終了するか (外部 kill されないか) を観察する
  - **影響範囲**: Implementation Steps 4 の待機呼び出し設定。`WHOLEWORK_CI_TIMEOUT_SEC=540` は上限 600 秒より内側にスクリプト自身の打ち切りを置く緩和策であり、上限が存在しない環境でも安全側に働く (待機が 4 ラウンドに分割されるだけ)

- **外部 provider (Amplify / Vercel / Netlify) のビルド失敗ログを code フェーズが取得できるか**: `gh pr checks --json link` が返すのは provider コンソールの外部 URL であり、`gh run view` では読めない。ローカルでビルドコマンドを再現できないプロジェクト (Issue 本文が挙げる「環境変数不足でローカルビルドが失敗する」ケース) では、`description` テキスト以上の情報が得られない可能性がある
  - **検証方法**: post-merge の 1 件目の受入条件 (実プロジェクトで意図的にビルドを失敗させる) で観察する
  - **影響範囲**: Implementation Steps 4 の修正ループ step 2。診断できない場合は step 5 のエスケープハッチ (失敗レポートを出して Step 14 へ進む) に落ちるため、無限ループにはならない

- **`gh pr checks --json state` の queued 時の実値** (Issue 本文が実機確認を求めていた点): **解決済み**。gh CLI 2.96.0 の `pkg/cmd/pr/checks/aggregate.go` が 14 の `state` 値を 5 つの `bucket` に正規化しており、`QUEUED` を含む 7 state が `bucket: pending` に入る。`state` を列挙する代わりに `bucket == "pending"` を判定条件とすることで、この不確実性そのものを設計から取り除いた (Root Cause 節の表を参照)。実機の `gh pr checks 1077 --json name,state,bucket` でも `bucket` フィールドが返ることを確認済み

## Notes

### 自動解決した曖昧点 (Auto-Resolve Log)

`--non-interactive` モードのため、以下 3 件をモデル判断で自動解決した。

1. **preview ビルド待ちの配置と Bash ツール 10 分上限との整合** — wrapper (`run-code.sh`) ではなく skill 内の新規 Step 13 に置き、1 回の呼び出しを `WHOLEWORK_CI_TIMEOUT_SEC=540` に制限したうえで最大 4 ラウンド繰り返す。
   - 根拠: 「失敗時は code フェーズ内で修正する」という Issue の要件は、claude セッションが生きている間でなければ満たせない。wrapper 側で待つと claude 終了後になり修正できない。一方、Bash ツールの単一呼び出しには 10 分上限があるため (#875 の外部 kill 記録)、`WHOLEWORK_CI_TIMEOUT_SEC` の既定値 1200 秒をそのまま使うと呼び出しが途中で切られる。540 秒 × 4 ラウンド (最大 36 分) で `WATCHDOG_TIMEOUT_CODE_DEFAULT` (4680 秒 = 78 分) の内側に収まる
   - 却下した選択肢: `run-code.sh` に待機を追加する案 (却下 — claude 終了後の待機では修正ループを回せない)、`WHOLEWORK_CI_TIMEOUT_SEC` を既定値のまま単発で呼ぶ案 (却下 — Bash ツール上限に抵触する)

2. **修正上限に到達したとき code フェーズを非 0 exit させるか** — させない。失敗レポートを出力して Step 14 (Worktree Exit) へ進む。
   - 根拠: `skills/code/SKILL.md:386` の既存 pr route 規約 (`continue — CI will detect the failure; report remaining failures in the completion message`) と整合する。commit と PR は正当な成果物として既に push 済みであり、非 0 exit させると `/auto` の silent no-op 検知および code-side auto-retry が、実際には完了しているフェーズに対して誤発火する
   - 却下した選択肢: 非 0 exit する案 (却下 — 上記のとおり orchestration recovery の誤発火を招く。Issue が求める「無限ループさせず停止して失敗を報告する」は、明示的な失敗 prefix 付き Completion Report で満たされる)

3. **穴 2 の対策として 3 案のどれを採るか** — 「最低待機時間 (grace period) + 明示的な警告」を採用し、`.wholework.yml` への `expected-checks` 宣言は採用しない。
   - 根拠: 受入条件 4 が「期待 check の宣言、最低待機時間、明示的な警告のいずれか」と明示的に 3 択を許している。`expected-checks` の宣言は新しい YAML キー 1 個に加えて `modules/detect-config-markers.md` + `docs/guide/customization.md` (英日) + `docs/tech.md` (英日) の同期を要求する一方、Issue 本文自身が「check 名は hosting provider やリージョンに依存する」と宣言必須化を避けている。設定ゼロで全プロジェクトに効く grace period のほうが費用対効果が高い
   - 却下した選択肢: `expected-checks` を `.wholework.yml` に追加する案 (却下 — 上記のとおり同期コストが大きく、Issue 本文自身も宣言必須化を否定している)

### 設計上の判断

- **`bucket` フィールドの採用**: Issue 本文は「未完了とみなす state を網羅する (`QUEUED` / `PENDING` / `WAITING` 等)」という対応を提案していたが、gh CLI が既に `bucket` として正規化を提供しているため、state の列挙ではなく `bucket == "pending"` 1 条件で実装する。将来 gh 側に state が追加されても bucket マッピング側で吸収されるため、Wholework 側の追随が不要になる
- **exit code を 0 のまま維持する理由**: `scripts/run-review.sh` (102 行目) と `scripts/run-merge.sh` (99 行目) は `set -euo pipefail` 配下で `wait-ci-checks.sh` を呼ぶ。CI 失敗時に非 0 を返すようにすると、これら 2 caller が review / merge フェーズ開始前に abort する破壊的変更になる。呼び出し側への結果伝達は stdout の `ci_result:` 行で行い、exit code の意味は変えない
- **`ci_wait` イベントのフィールド形状を変えない理由**: `docs/reports/event-log-schema.md` に定義済みのスキーマ (`wait_sec` / `checks_passed` / `checks_failed` の 3 フィールド) を維持し、内部の集計方法だけを bucket ベースに揃える。`checks_failed` は `FAILURE` のみから `bucket == "fail"` (`ERROR` / `TIMED_OUT` / `ACTION_REQUIRED` を含む) へ広がるが、これはフィールドの意味により忠実な変更であり、スキーマ互換性は保たれる
- **`#1050` との関係**: 本 Issue は「code がビルド成功を保証する」上流の対策、`#1050` は「それでも review 時に未完了だった場合に silent no-op にしない」下流の対策。本 Issue の Step 13 は `/review` を待たずに失敗を検知するが、修正上限到達時や外部 provider の診断不能時には `/review` に流れるため、`#1050` の下流防御は引き続き必要である (どちらも独立に価値がある)

### 実装上の注意

- `tests/wait-ci-checks.bats` の `gh` モックに `bucket` を付け忘れると、`select(.bucket == "pending")` が常に 0 件を返し、`success: continues even when timeout exits non-zero` テストが「タイムアウト経路を通らずに即 break する」経路へ静かにすり替わる。テスト自体はアサーション上 PASS してしまうため、モック更新の漏れは検知されない。Implementation Steps 3 でモック全件の更新を明示している理由がこれである
- `skills/code/SKILL.md` は `scripts/validate-skill-syntax.py` の検証対象であり、本文中の半角感嘆符・小数点付きステップ番号 (`Step 13.5` 等)・本文中の 3 連バッククォートはいずれも禁止される。Step 13 の追加テキストと Step 番号の繰り上げの両方でこれらに抵触しないこと
- Step 13 の分岐表とループ挙動は「同様に処理」「適切にハンドル」「必要に応じて」といった曖昧表現を使わず、条件と挙動を全列挙する (`skills/spec/skill-dev-constraints.md` § ブランチ分岐ロジックの挙動全列挙)

## Consumed Comments

| login | authorAssociation | 信頼層 | 意図の要約 | URL |
|-------|-------------------|--------|-----------|-----|
| saito | MEMBER | first-class | `/issue 1066 --non-interactive` の Issue Retrospective。曖昧点 1 件 (プレビュービルド修正ループの再試行上限とエスケープハッチ) を自動解決し Issue 本文へ追記した旨、AC は変更なしである旨、および Background の事実記述 (`skills/code/SKILL.md` の pr route 記述、`wait-ci-checks.sh` の完了判定ロジック) がコードベースと一致することを確認済みである旨を報告 | https://github.com/saitoco/wholework/issues/1066#issuecomment-5113593972 |

cutoff: `2026-07-29T05:20:59Z` (直近の `phase/*` ラベル付与時刻)。上記 1 件のみが cutoff 以降のコメント。`wholework-event: type=verify-fail` / `type=preview-ac-unverified` マーカーを持つコメントは存在しない。
