# Issue #1554: eval: task-completion eval の設計とゴールデンセットを定義

## Overview

#1552 (task-completion eval) の sub-issue 1/4。再実行の仕組み (#1555 隔離環境、#1556 ランナー) が従う前提を先に決める。成果物は次の 3 つ。

- 人が読める設計文書: ゴールデンセットの選定基準、一覧の形式、材料の取り出し方、採点項目の算出方法、集計方法、実行ごとに残す構成情報
- 仕組みが読み込める一覧: 10〜15 件のタスクと、各タスクの再実行の起点 (base commit)、MUST 例の指摘時点のコミット・PR 番号・既知の不具合の要約、再実行に入力する Issue 本文の凍結コピー
- 一覧の検証スクリプトと、条件を満たさない一覧を不合格にすることを確かめる bats テスト

配置は新しいトップレベルディレクトリ `eval/` に置く (理由は Notes)。

## Changed Files

- `eval/README.md`: new file — task-completion eval の設計文書 (English)。選定基準、`golden-set.json` のスキーマ、材料の取り出し手順 (base commit / 指摘時点のコミット / 入力本文)、採点項目 5 つの算出方法、集計方法、実行ごとの記録項目を書く
- `eval/golden-set.json`: new file — ゴールデンセットの一覧 (10〜15 件、スキーマは Notes)
- `eval/inputs/issue-<N>.md`: new files (タスク数と同数、同じ形式のデータファイル) — 各タスクの、元の実行で spec (spec を飛ばした Issue は code) が始まった時点の Issue 本文の凍結コピー。チェック済みの checkbox は未チェックに戻す
- `scripts/eval-validate-golden-set.sh`: new file — 一覧の検証スクリプト (bash 3.2+ compatible、依存は `jq` と `git` のみ)
- `tests/eval-validate-golden-set.bats`: new file — 検証スクリプトの bats テスト
- `docs/structure.md`: Directory Layout に `eval/` を追加し、Key Files の `### Scripts` に `scripts/eval-validate-golden-set.sh` を追加する — [Steering Docs sync candidate] (新ディレクトリと新ファイルの追加による listing-side sub-check)
- `docs/ja/structure.md`: `docs/structure.md` と同じ変更を日本語で反映する (`docs/translation-workflow.md` の同期対象)
- `README.md`: [Steering Docs sync candidate] ディレクトリやスクリプトを列挙している箇所がないかを再確認する (現時点の grep では列挙は見当たらないので、変更不要の見込み)
- [Steering Docs sync candidate] keyword `eval-validate-golden-set.sh` は新規の名前で、`docs/` `tests/` `scripts/` `modules/` に既存の参照はない (inbound check は該当なし)

## Implementation Steps

1. `eval/README.md` を書く。内容は Notes の「設計の内容」に従う (選定基準、一覧のスキーマ、材料の取り出し手順、採点項目、集計方法、実行ごとの記録項目) (→ acceptance criteria 1, 2)
2. ゴールデンセットを選び、`eval/golden-set.json` と `eval/inputs/issue-<N>.md` を作る (after 1)。手順は Notes の「材料の取り出し手順」に従う。MUST 例の指摘時点のコミットは、`git fetch origin pull/<PR>/head` で手元に取り込んでから記録する。一覧に書く識別子 (Issue 番号、PR 番号、コミット SHA、レビューの URL) は、書く前に `gh issue view` / `gh pr view` / `git cat-file -e` で実在を確かめる (記憶や推測で書かない) (→ acceptance criteria 1)
3. `scripts/eval-validate-golden-set.sh` を実装する (parallel with 1, 2)。検査項目と終了コードは Notes の「検証スクリプトの仕様」に従う (→ acceptance criteria 3)
4. `tests/eval-validate-golden-set.bats` を追加する (after 3)。Notes の「bats テストの内容」の不合格ケースをすべて含める。条件を満たす一覧が PASS するケースだけで終わらせない。追加後に `bats tests/eval-validate-golden-set.bats` が通ること、手元で `scripts/eval-validate-golden-set.sh eval/golden-set.json` (git の検査あり) が通ることを確かめる (after 2) (→ acceptance criteria 3, 4)
5. `docs/structure.md` と `docs/ja/structure.md` を更新する (Directory Layout の `eval/` と、Key Files の Scripts の項目)。`README.md` に列挙の箇所がないかを確かめる (after 1, 3)

## Verification

### Pre-merge

- <!-- verify: rubric "ゴールデンセットの選定基準と対象 Issue の一覧が文書化されている。一覧には Size XS・S・M・L がそれぞれ含まれ、さらに review で MUST 指摘が出た例、verify が FAIL した例、costly step (spec-approval-needed) を含む例がそれぞれ 1 件以上含まれている。各 Issue について再実行の起点 (マージ前の base commit) が記録され、MUST 指摘が出た例では指摘を受けた時点のコミット、PR 番号、既知の不具合の要約も記録されている。一覧は人が読める文書とは別に、仕組みが読み込める形式でも用意されている" --> ゴールデンセットの選定基準と、再実行の起点となるコミットを含む対象 Issue の一覧が用意されている
- <!-- verify: rubric "採点項目 (AC の pass 率、既知の不具合の検出率、所要時間、出力トークン、介入回数) それぞれの算出方法が定義されている。既知の不具合の検出率は、MUST 指摘を受けた時点のコミットに対して review だけを再実行し、元の MUST 指摘を再び検出できたかで算出すると定義されている。介入回数は、数える対象のイベントの種類が列挙されている。集計方法として、構成間で結果が反転したタスク (各構成の中では結果が一致するもの) と、同じ構成の実行間で結果が分かれたタスクを分けて一覧にする方法が定義されている。実行ごとに wholework の commit SHA、model ID、effort を記録することが定められている" --> 採点項目の算出方法、反転したタスクの集計方法、実行ごとに残す構成情報が定義されている
- <!-- verify: rubric "ゴールデンセットの一覧を機械的に検証する仕組みがあり、自動テストが、存在しない起点コミットを含む一覧や、Size・分類の条件を満たさない一覧を不合格にすることを確認している (条件を満たす一覧だけで PASS する形ではない)" --> ゴールデンセットの一覧を検証する仕組みがあり、条件を満たさない一覧を不合格にすることが自動テストで確認されている
- <!-- verify: github_check "gh pr checks --json name,state --jq '.[] | select(.name==\"Run bats tests\") | .state'" "SUCCESS" --> bats テスト (CI の `Run bats tests` ジョブ) が通る

### Post-merge

なし

## Notes

### 配置と形式の判断

- **置き場所はトップレベルの `eval/`**: 入力本文の凍結コピーは過去の Issue 本文をそのまま保存するため、現在は使わない用語 (例: `docs/product.md § Terms` の旧称) を含むことがある。`scripts/check-forbidden-expressions.sh` の検査対象 (`SCAN_DIRS="skills/ modules/ agents/ tests/ docs/ scripts/"`) に置くと CI が落ちるので、検査対象外の `eval/` に置く。設計文書も同じディレクトリに置き、#1556 が実行手順を書き足す先にもする。`docs/` の外なので `docs/ja/` の翻訳同期の対象にもならない
- **一覧は JSON**: 既存のスクリプトは `jq` で JSON を扱っており (`docs/tech.md` の Key Dependencies)、YAML のパーサーは依存にない
- **入力本文は凍結コピーを持つ**: #1555 の隔離環境では読み取りも隔離側に向けるため、再実行の時点で本番の Issue の編集履歴を読みに行く形は取りにくい。一覧を作る時点で取り出してコミットしておけば、再実行はネットワークに依存せず、取り出した本文を PR で確かめられる

### 設計の内容 (`eval/README.md` に書くこと)

**選定基準**

- 対象: 完了した Issue で、変更が main に入っているもの。Size は完了時点の XS〜L (XL の親と、追跡専用の Issue は除く)
- 除外: AC が本番の GitHub の状態や外部サービスに依存するもの (本番の Issue を読む `github_check`、`http_*`、`mcp_call`、`browser_*`)、operate route (差分のない Issue)、GitHub の状態を変えること自体が目的の Issue
- 優先: `/auto` で処理され、`docs/sessions/*/events.jsonl` に元の実行のイベントが残っているもの (元の所要時間やトークンを参考値として比べられる)。base commit が新しいもの (古いほど、現行の wholework と作業対象の checkout の差が大きくなる)
- 構成: 10〜15 件。Size XS・S・M・L をそれぞれ 1 件以上 (推奨 2 件以上)。分類 `must_finding` (review で MUST 指摘)・`verify_fail` (verify で FAIL)・`costly_step` (`spec-approval-needed` の step を含む) をそれぞれ 1 件以上。1 件が複数の分類に入ってよい。`must_finding` は検出率の刻みを細かくするため 3 件以上を推奨
- 候補の手がかり (#1552 の前例調査): `verify_fail` は #1355、#1206 (events 上の `verify_reopen_cycle` はこの 2 件だけ)。`costly_step` は #1134、#1229、#1413、#1477、#1503 など。`must_finding` は PR のレビューにしか残っていないので、`gh api repos/{owner}/{repo}/pulls/<PR>/reviews` で、MUST を含むレビュー (`scripts/gh-pr-review.sh` は MUST があると `REQUEST_CHANGES` で投稿し、自分の PR では `COMMENT` に切り替えて本文に `instead of REQUEST_CHANGES` を残す) を探す

**一覧のスキーマ (`eval/golden-set.json`)**

```json
{
  "schema_version": 1,
  "repository": "saitoco/wholework",
  "tasks": [
    {
      "issue": 1234,
      "title": "...",
      "size": "M",
      "categories": ["must_finding", "costly_step"],
      "pr": 1240,
      "spec_started_at": "2026-08-01T12:00:00Z",
      "base_commit": "<40 桁の SHA>",
      "input_body": "inputs/issue-1234.md",
      "review_replay": {
        "reviewed_commit": "<40 桁の SHA>",
        "known_defects": [
          { "summary": "...", "source_url": "https://github.com/saitoco/wholework/pull/1240#discussion_r..." }
        ]
      }
    }
  ]
}
```

- `pr`: マージされた PR の番号。patch route (PR なし) は `null`。`must_finding` の件では必須
- `categories`: `must_finding` / `verify_fail` / `costly_step` の部分集合。どれにも当たらない件は `[]`
- `review_replay`: `must_finding` の件では必須。それ以外では省く
- `input_body`: `golden-set.json` があるディレクトリからの相対パス

**材料の取り出し手順**

- `spec_started_at`: Issue の timeline で、最初に `phase/spec` か `phase/code` のラベルが付いた時刻 (spec を飛ばした XS/S は `phase/code`)。`gh api "repos/{owner}/{repo}/issues/<N>/timeline" --paginate --jq '[.[] | select(.event=="labeled" and (.label.name=="phase/spec" or .label.name=="phase/code")) | .created_at] | first'`
- `base_commit` (全フェーズ再実行の起点): main の first-parent 履歴で、その Issue に属する最初のコミット (pr route なら `Add design for issue #N`、patch route なら `Issue #N: ...` など) の親。squash commit の親ではない (Notes の「Issue 本文との食い違い」)。取り出した base の committer date が `spec_started_at` より前であることを確かめる
- `reviewed_commit` (review だけの再実行の起点): MUST を含むレビューの `commit_id` (`gh api repos/{owner}/{repo}/pulls/<PR>/reviews`)。PR のブランチはマージ時に削除されているので、`git fetch origin pull/<PR>/head` で取り込む (force-push されていなければ、指摘時点のコミットは最終の head の祖先として取り込まれる)
- `known_defects[].summary`: MUST 指摘が指していた不具合の要約 (どのファイルの何が、どの条件で必ず失敗するか)。`source_url` は指摘のコメントの URL
- 入力本文: GraphQL の `userContentEdits` から、`editedAt` が `spec_started_at` 以前で最も新しい版の `diff` を取る (`diff` は差分ではなく、その版の本文全体が入っている)。編集履歴がない (`totalCount` が 0) なら現在の本文が元の本文である。取り出した本文の `- [x]` / `- [X]` を `- [ ]` に戻して `eval/inputs/issue-<N>.md` に保存する

**採点項目の算出方法**

- **AC の pass 率 (全フェーズ再実行)**: 対象は、入力本文 (凍結コピー) の Pre-merge と Post-merge の AC のうち、verify command があり、`verify-type` が `manual` / `observation` / `opportunistic` でないもの。実行が終わった後に、隔離環境のリポジトリの最終状態 (マージ後の default branch) に対して、採点側が verify command を full mode で実行し直して判定する。実行の中の `/review` や `/verify` が付けた checkbox の状態は使わない (自己申告に頼らない)。pass 率 = PASS / (PASS + FAIL + UNCERTAIN)。SKIPPED は分母から除く。タスクの成否 = 実行が完了し、かつ対象の AC がすべて PASS
- **既知の不具合の検出率 (review だけの再実行)**: `must_finding` の件の `reviewed_commit` に対して review だけを再実行し、`known_defects` の各項目について、再実行の review が同じ不具合 (同じファイル・同じ失敗の仕組み) を MUST で指摘したかを判定する。判定は、不具合の要約と再実行の指摘一覧を材料にした LLM の grader (rubric と同じ形) が行い、対応する指摘を引用して残す。検出率 = 検出した不具合の数 / 不具合の総数。MUST 以外の重大度で指摘した場合は、副次の列 (重大度を問わない検出率) にだけ数える
- **所要時間**: 1 回の実行の開始から終了までの実時間 (秒)。あわせて、実行のイベントログの `phase_start` から `phase_complete` までをフェーズごとに記録する
- **出力トークン**: 実行のイベントログの `token_usage` イベントの `output_tokens` の合計。`token_usage` が出ないフェーズがあった場合は、値を `partial` と記録し、欠けたフェーズを列挙する (欠けたまま合計を小さく出さない)
- **介入回数**: 実行のイベントログにある、次の種類のイベントの件数。`manual_intervention`、`recovery`、`watchdog_kill`、`code_retry_fire`、`verify_retry_fire`、`verify_reopen_cycle`。合計と種類ごとの内訳を出す。イベントの定義は `modules/event-emission.md` と `scripts/emit-event.sh`
- どの採点項目も、その実行の隔離環境のイベントログだけを材料にする (本番の `.tmp/auto-events.jsonl` は使わない)

**集計方法**

- 各タスクを、各構成で 2 回以上実行する
- 1 回の実行の結果は `success` / `failure` / `incomplete` のどれか。`incomplete` は kill・時間切れ・中断などで完了しなかった実行で、`failure` とは分けて数える
- 構成の中で、完了した実行 (`incomplete` 以外) の結果がすべて一致すればその構成での結果は「安定」、一致しなければ「実行間で分かれた (unstable)」
- 両方の構成で安定していて、結果が違うタスクを「構成間で反転した (flipped)」とし、向き (候補構成で良くなったか悪くなったか) を付けて一覧にする
- どちらかの構成で完了した実行が 2 回未満のタスクは「判定不能 (insufficient)」として別に一覧にし、反転にも unstable にも数えない
- review だけの再実行は、既知の不具合ごとに「検出した / しなかった」を結果として同じ分類を行う
- 集計の出力: 構成ごとの平均 pass 率、タスクの成功率、検出率、所要時間の中央値、出力トークンの合計、介入回数の合計と、反転・unstable・判定不能の 3 つの一覧

**実行ごとに残す構成情報**

- `run_id`、`task` (Issue 番号)、`kind` (`full` / `review`)、`config` (構成の名前)
- `wholework_sha`: 使った wholework の checkout の commit SHA (40 桁)。作業ツリーに未コミットの変更があった場合はそれも記録する
- `config_overrides`: 構成の設定の違い (例: `.wholework.yml` の差分)
- フェーズごとの `model_id` と `effort`。`model_id` は alias (`opus` など) ではなく、実行が実際に使った正式な ID (例: `claude-opus-5-5`)。alias は途中で指す先が変わることがあるため (#1064)
- `started_at`、`ended_at`、`status` (`completed` / `incomplete`)、`incomplete` の理由

### 検証スクリプトの仕様 (`scripts/eval-validate-golden-set.sh`)

- 使い方: `eval-validate-golden-set.sh [--repo <dir>] [--no-git] [<golden-set.json>]`。既定は `--repo .`、一覧は `eval/golden-set.json`
- 終了コード: 0 = 合格、1 = 条件違反がある (違反をすべて `ERROR: issue #<N>: <内容>` または `ERROR: <内容>` の形で stderr に出してから終了する)、2 = 使い方の誤り・JSON として読めない・`jq` がない・`--repo` が git リポジトリでない
- 検査項目:
  - `schema_version` が 1、`tasks` が配列
  - タスク数が 10〜15
  - `issue` が正の整数で重複がない
  - `size` が `XS` / `S` / `M` / `L` のどれか
  - `categories` が配列で、要素が `must_finding` / `verify_fail` / `costly_step` のどれか
  - `spec_started_at` が `YYYY-MM-DDTHH:MM:SSZ` の形
  - `base_commit` が 40 桁の 16 進数で、`--repo` の中にコミットとして存在する (`git cat-file -e <sha>^{commit}`)
  - `input_body` が相対パスで `..` を含まず、ファイルが存在し、チェック済みの checkbox (`- [x]` / `- [X]`) を含まない
  - `must_finding` の件: `pr` が正の整数、`review_replay.reviewed_commit` が 40 桁でコミットとして存在し、`base_commit` がその祖先 (`git merge-base --is-ancestor`)、`review_replay.known_defects` が 1 件以上で各 `summary` が空でない
  - 網羅: Size `XS`・`S`・`M`・`L` がそれぞれ 1 件以上、分類 `must_finding`・`verify_fail`・`costly_step` がそれぞれ 1 件以上
- `--no-git`: コミットの実在と祖先関係の検査だけを飛ばす。CI の checkout は浅いため、bats から本物の一覧の形式と網羅を確かめるときに使う
- 境界の扱い (fail-closed の validator として):
  - 空のファイル・JSON として読めないファイル → 2
  - `summary` などに引用符・改行・CRLF・マルチバイト文字を含んでも、値は `jq` で扱い、シェルの文字列として評価しない
  - `git` や `jq` が想定外に失敗したときは合格にせず、0 以外で終了する (`|| true` で握りつぶさない)
- bash 3.2 互換 (`mapfile` や連想配列を使わない)

### bats テストの内容 (`tests/eval-validate-golden-set.bats`)

- 入力データの形式: 各テストが `$BATS_TEST_TMPDIR` に `git init` したリポジトリを作り、コミットをいくつか積む (git の user は `push-to-base.bats` と同じく `git config user.email test@test.com` / `user.name test` で設定する)。そのコミットの SHA を使って、上のスキーマの `golden-set.json` (10 件、網羅を満たす) と `inputs/issue-<N>.md` を作る。テストごとの一時ディレクトリだけを使う (並列の CI で競合させない)
- 新しく追加するテストケース (すべて必須):
  - 条件を満たす一覧 → 0
  - 存在しない `base_commit` を含む → 1
  - 存在しない `reviewed_commit` を含む → 1
  - `base_commit` が `reviewed_commit` の祖先でない → 1
  - Size `L` の件がない → 1
  - 分類 `verify_fail` の件がない → 1
  - 9 件 / 16 件 → 1
  - `must_finding` の件に `known_defects` がない → 1
  - 入力本文にチェック済みの checkbox がある → 1
  - `size` が不正な値 / `issue` が重複 → 1
  - JSON として読めない → 2
  - 本物の `eval/golden-set.json` を `--no-git` で検証 → 0 (コミットした一覧が形式と網羅の条件を保っていることを CI で確かめる)

### Issue 本文との食い違い

- Issue 本文の Background に「base commit は、マージ時の squash commit の親から取れる」とあるが、pr route では squash commit の親は、その Issue の `Add design for issue #N` コミットを含む。例: #1551 の squash commit `1b9cdeb0` の親は `94217047` (`Add design for issue #1551`)。この状態から全フェーズ再実行を始めると、元の実行の Spec が作業ツリーに入ったまま `/spec` が走ることになる。そのため、全フェーズ再実行の起点は「その Issue に属する最初のコミットの親」と定義した。一方、review だけの再実行の起点 (`reviewed_commit`) は PR のブランチ上のコミットで、Spec を含む状態が正しい

### 不確かな点の確認結果

- **`userContentEdits.diff` の中身**: 差分ではなく、その版の本文全体が入っていることを確かめた。#1552 の 3 つの版のうち、最新の版の `diff` の長さ (2765) が現在の本文の長さと一致し、最も古い版の `editedAt` は Issue の `createdAt` と一致した。版は新しい順に並ぶ。出所: `gh api graphql` で `repository(owner:"saitoco",name:"wholework").issue(number:1552).userContentEdits` (取得日時: 2026-10-25)
- **model ID の取り出し元**: 既存の `token_usage` イベントの `model` は `unknown` のことがある (例: #880 の `code-patch`)。正式な model ID をどこから取るか (Claude Code の JSON 出力など) は、記録する仕組みを作る #1556 で決める。この Issue では「alias ではなく正式な ID を記録する」という要件だけを定める

### その他

- 監査・調査型の判断: 該当する。既存の Issue を分類して一覧にし、後の仕組み (#1556 のランナー) がその一覧を読む。そのため Implementation Step 2 で、一覧に書く識別子の実在を書く前に確かめることを求めた
- fail-safe critical の判断: 該当する (受け入れ/拒否を決める validator)。境界の扱いを「検証スクリプトの仕様」に書いた
- 新しいスクリプトはどの skill からも呼ばれないので、`allowed-tools` の変更は不要
- 新しい分岐を持つ既存ファイルの変更はない (新規ファイルだけ)。新規スクリプトのテストケースは上の「bats テストの内容」に列挙した
- costly step: なし (Claude の起動や本番への書き込みを伴う step はない。`git fetch` と GitHub の読み取りだけ)
- Size の再評価: 中心のファイルは 5 つ (`eval/README.md`、`eval/golden-set.json`、`eval/inputs/` の同じ形式のデータファイル群、検証スクリプト、bats)。これに `docs/structure.md` とその翻訳の小さな同期が加わる。既存のパターン (jq と git を使う検証スクリプト) の延長なので、M のままとする

## Consumed Comments

No new comments since last phase.
