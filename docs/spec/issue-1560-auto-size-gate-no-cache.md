# Issue #1560: auto: 精査直後の Size ゲートがキャッシュの古い空の値を読み XL を取りこぼす

## Overview

`/auto` が `run-issue.sh` (精査) の直後に Size を読む 3 箇所 (Step 3 の精査後の再取得、Count mode の手順 3、List mode の手順 3) は、`get-issue-size.sh` を既定のキャッシュ付き (`gh-graphql.sh --cache`、TTL 300 秒) のまま呼んでいる。精査で Size が付く前に残った「Size 無し」の応答を読むと `$ISSUE_SIZE` が空になる。空は「ゲートに該当しない」と扱われるため、精査で XL と判定された Issue が XL ゲートをすり抜け、分割されないまま実装に進むおそれがある。

この 3 箇所を `get-issue-size.sh --no-cache` に変更し、回帰を検出する bats テストを追加する。精査を経ない Size の読み取り (Step 2 の初期取得、Count mode の候補選定) は対象外で、変更しない。

## Reproduction Steps

1. `phase/*` ラベルの無い Issue (例: #1546) を含めて `/auto --batch N1 N2 ...` (List mode) を実行する。Count mode (`--batch N`) でも同じ。
2. 手順 2 の `run-issue.sh` が精査し、Project の Size フィールドに値 (例: `M`) を書く。
3. 手順 3 の `get-issue-size.sh $NUMBER` が、精査前に同じ Issue の Size を読んで残った (TTL 300 秒以内の) 「Size 無し」のキャッシュを返し、出力が空で exit 1 になる。
4. `scripts/gh-graphql.sh --cache-clear` でキャッシュを消すと、同じ呼び出しが正しい値 (`M`) を返す。

出典: セッション `103482-1792884930` の `docs/sessions/103482-1792884930-2026-10-25/session.md` § Findings (#1546 で実測)。

## Root Cause

`scripts/get-issue-size.sh` は `--no-cache` が無い限り `gh-graphql.sh --cache` で Project フィールドを読む。`gh-graphql.sh` のキャッシュは生の GraphQL 応答を「クエリ + 変数」をキーに TTL 300 秒で保存し、`--no-cache` の呼び出しはキャッシュを読まず、書かず、無効化もしない。精査が Size を書く前に同じ Issue の Size をキャッシュ付きで読んだ呼び出しがあると、その空の応答が精査後も最大 300 秒返り続ける。

`skills/auto/SKILL.md` で Size を読む 6 箇所のうち、`--no-cache` を付けていたのは post-spec の再取得 (Step 3a) の 1 箇所だけで、精査の直後にある 3 箇所は付けていなかった (残る 2 箇所は精査の前の読み取りで、キャッシュ付きのままでよい)。ほかの精査直後の読み取り (`skills/issue/SKILL.md` の完了報告、`modules/project-field-update.md` の書き込み後の確認、`scripts/run-auto-sub.sh`) も #458 以降 `--no-cache` を使っており、今回は同じ系統の症状の再発にあたる。

修正方針は、この 3 箇所の呼び出し側に `--no-cache` を付けること (呼び出し側の修正だけで足り、`scripts/get-issue-size.sh` と `scripts/gh-graphql.sh` は変更しない)。

## Changed Files

- `skills/auto/SKILL.md`: 精査直後の Size 読み取り 3 箇所に `--no-cache` を追加し、理由を 1 句で併記する (行番号は Spec 作成時点のもの)
  - Step 3 の `No phase/* labels` 分岐の `After success, re-fetch Size` (267 行目付近)
  - `### Count mode` の `#### Process Each Issue` 手順 3 (1233 行目付近)
  - `### List mode` の手順 3 (1277 行目付近)。Until mode と Resume mode は List mode の手順 1〜7 を再利用するため、この変更で同時に対象になる
- `tests/auto-batch.bats`: Count mode と List mode の Size ゲートが `get-issue-size.sh --no-cache` を呼ぶことを検査するテストを 2 件追加 (bash 3.2+ 互換)
- `tests/auto.bats`: Step 3 の精査後の Size 再取得が `get-issue-size.sh --no-cache` を呼ぶことを検査するテストを 1 件追加 (bash 3.2+ 互換)

変更しない関連ファイルの判定 (Steering Docs の同期候補を含む) は Notes を参照。

## Implementation Steps

1. `tests/auto-batch.bats` の末尾に、Count mode と List mode の回帰テストを 2 件追加する (→ 受入条件 2)。追加直後に `bats tests/auto-batch.bats --filter 'Issue #1560'` を実行し、2 件とも FAIL する (red) ことを確認する。この時点の SKILL.md は変更前の記述なので FAIL が期待結果で、PASS した場合はテストが空振りしているため、手順 3 に進まずテストを直す。
   ```bash
   # --- Size gate right after refinement reads Size without the cache (Issue #1560) ---
   # run-issue.sh sets Size just before step 3, but get-issue-size.sh caches the GraphQL response
   # for 300 s by default, so the "Size not set" result read before refinement could be returned
   # and an XL Issue would slip through the gate. The gate is the get-issue-size.sh call whose
   # result is retained as $ISSUE_SIZE; the candidate-selection call before refinement is
   # intentionally excluded by this filter.

   @test "Count mode section: step 3 Size gate calls get-issue-size.sh with --no-cache (Issue #1560)" {
       section="$(count_mode_section)"
       [ -n "$section" ]
       gate="$(printf '%s\n' "$section" | grep -F 'get-issue-size.sh' | grep -F 'retain the result as')"
       [ -n "$gate" ]
       [[ "$gate" == *'get-issue-size.sh --no-cache $NUMBER'* ]] || false
   }

   @test "List mode section: step 3 Size gate calls get-issue-size.sh with --no-cache (Issue #1560)" {
       section="$(list_mode_section)"
       [ -n "$section" ]
       gate="$(printf '%s\n' "$section" | grep -F 'get-issue-size.sh' | grep -F 'retain the result as')"
       [ -n "$gate" ]
       [[ "$gate" == *'get-issue-size.sh --no-cache $NUMBER'* ]] || false
   }
   ```
2. `tests/auto.bats` の末尾に、Step 3 の回帰テストを 1 件追加する (→ 受入条件 2) (parallel with 1)。既存の `step3_section` ヘルパー (`### Step 3:` 節を抽出する) を使う。追加直後に `bats tests/auto.bats --filter 'Issue #1560'` を実行し、FAIL する (red) ことを確認する。
   ```bash
   # --- Size re-fetch after run-issue.sh bypasses the cache (Issue #1560) ---

   @test "Step 3 section: Size re-fetch after run-issue.sh calls get-issue-size.sh with --no-cache (Issue #1560)" {
       section="$(step3_section "$SKILL_FILE")"
       [ -n "$section" ]
       refetch="$(printf '%s\n' "$section" | grep -F 'get-issue-size.sh')"
       [ -n "$refetch" ]
       [[ "$refetch" == *'get-issue-size.sh --no-cache $NUMBER'* ]] || false
   }
   ```
3. `skills/auto/SKILL.md` の 3 箇所に `--no-cache` を追加する (→ 受入条件 1) (after 1, 2)。直前のコード文脈で位置を特定する (行番号は目安)。新しい文言は英語で書く (`skills/` 配下は英語のみ)。半角 `!` は使わない。
   - (a) Step 3 の `No phase/* labels` 分岐、`Run run-issue.sh` の次の項目
     - 旧: ``  - After success, re-fetch Size (`${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`). Update route if Size is now set.``
     - 新: ``  - After success, re-fetch Size with `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh --no-cache $NUMBER` (`--no-cache`: read the Size that `run-issue.sh` just set, not the empty result cached before it). Update route if Size is now set.``
   - (b) `### Count mode (--batch N)` の `#### Process Each Issue`、手順 2 (`run-issue.sh`) の次の手順 3
     - 旧: ``3. call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`; retain the result as `$ISSUE_SIZE`; if `$ISSUE_SIZE` is M, L, or XL: ...``
     - 新: ``3. call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh --no-cache $NUMBER` (`--no-cache`: read the Size that step 2's `run-issue.sh` just set, not the empty result cached before it); retain the result as `$ISSUE_SIZE`; if `$ISSUE_SIZE` is M, L, or XL: ...`` (`...` 以降は変更しない)
   - (c) `### List mode (--batch N1 N2 ...)` の `Process each Issue in BATCH_LIST in order:` 配下、手順 2 の次の手順 3
     - 旧: ``3. call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`; retain the result as `$ISSUE_SIZE`; if `$ISSUE_SIZE` is XL: output a warning; ...``
     - 新: ``3. call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh --no-cache $NUMBER` (`--no-cache`: read the Size that step 2's `run-issue.sh` just set, not the empty result cached before it); retain the result as `$ISSUE_SIZE`; if `$ISSUE_SIZE` is XL: output a warning; ...`` (`...` 以降は変更しない)
   - 変更しない読み取り: Step 2 の初期取得 (`get-issue-size.sh "$NUMBER" 2>/dev/null`)、Count mode の `#### Filtering criteria` の候補選定、Step 3a の既存の `--no-cache`。いずれも精査の前か、既に `--no-cache` を使っている。
   - XL ゲートの端のケース (fail-safe に関わるゲートのため明記する。挙動は変更前から変えない):
     - 出力が空 (`get-issue-size.sh` が exit 1: Size 未設定、または GraphQL の失敗後に `size/*` ラベルも無い) のとき、`$ISSUE_SIZE` は空のままで、ゲート (Count mode は M/L/XL を skip、List mode は XL を skip) は発火せず処理が進む (fail-open)。「Size 未設定は pr route を安全側とする」既存方針と、Count mode が Size 未設定の Issue を対象に含める既存方針に合わせるため、fail-closed には変えない。本修正が無くすのは stale キャッシュによる偽の空だけである。
     - GraphQL が一時的に失敗した場合は、`get-issue-size.sh` が Phase 1 の失敗を無視して `size/*` ラベルにフォールバックする (変更なし)。
     - `$NUMBER` は `--batch` の引数または候補一覧の数値で、`get-issue-size.sh` が `^[0-9]+$` で検証する (変更なし)。特殊文字・CRLF・多バイト文字・過大な入力に対する新しい分岐は生じない。
4. 追加した 3 件を含めて `bats tests/auto-batch.bats tests/auto.bats` が PASS (green) し、`python3 scripts/validate-skill-syntax.py skills/` が 0 エラーであることを確認する (→ 受入条件 1, 2, 3) (after 3)。CI の `test.yml` (Run bats tests) は push 後に patch route の `github_check` で確認する (→ 受入条件 3)。既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/auto-batch.bats` に `Count mode section: step 3 Size gate calls get-issue-size.sh with --no-cache (Issue #1560)` と `List mode section: step 3 Size gate calls get-issue-size.sh with --no-cache (Issue #1560)`、`tests/auto.bats` に `Step 3 section: Size re-fetch after run-issue.sh calls get-issue-size.sh with --no-cache (Issue #1560)`) を追加したうえでスイートが PASS すること。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md の中で、run-issue.sh (精査) の直後に Size を読む箇所 (精査後の再取得、Count mode の手順 3、List mode の手順 3) がすべて get-issue-size.sh --no-cache を使っている。精査を経ない Size の読み取りまで --no-cache にする必要はない" --> <!-- verify: file_not_contains "skills/auto/SKILL.md" "get-issue-size.sh $NUMBER`; retain" --> <!-- verify: file_not_contains "skills/auto/SKILL.md" "get-issue-size.sh $NUMBER`)" --> `run-issue.sh` の直後に Size を読む箇所がすべて `--no-cache` を使っている
- <!-- verify: rubric "tests/ 配下の bats テストに、skills/auto/SKILL.md の List mode と Count mode の Size ゲートが get-issue-size.sh --no-cache を呼ぶことを検査するテストがあり、--no-cache の無い現状の記述では FAIL する" --> 回帰を検出する bats テストが追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion,status --jq 'if .[0].status != \"completed\" then \"in_progress\" else .[0].conclusion end'" "success" --> CI の bats テスト (test.yml の Run bats tests) が通る (patch route)

### Post-merge

- なし (Issue に Post-merge 条件は無い。CI の確認は patch route 向けの Pre-merge 3 件目に含まれる)

## Notes

### 判断メモ (非対話モードでの自動判断)

- 本 Issue は Size S のため `SPEC_DEPTH=light`。曖昧さの解消 (clarify) と不確実性の洗い出しは行わない。曖昧点は検出されず、Issue 本文の受入条件をそのまま転記した (Pre-merge 3 件、Issue 本文と一致)。
- 修正方式は呼び出し側の `--no-cache` を採る。代替の「精査直後に `scripts/gh-graphql.sh --cache-clear` を実行する」は採らない。理由: (1) Step 3a の `--no-cache`、`skills/issue/SKILL.md`、`modules/project-field-update.md`、`scripts/run-auto-sub.sh` の既存の対処と同じ手段で、一貫する。(2) `--cache-clear` は `.tmp/gh-graphql-cache` を丸ごと削除するため、無関係なキャッシュ (リポジトリ情報など) まで巻き込む。(3) 手順ごとの 1 箇所の変更で、局所的に意図が読める。
- 精査前の「Size 無し」の応答を誰が (親セッションか、`run-issue.sh` 内の精査セッションか) キャッシュに残したかは特定していない。`--no-cache` は読み取り側でキャッシュを避けるため、どちらであっても修正の要否と内容は変わらない。
- 回帰テストは Issue の受入条件 2 が求める Count mode と List mode の 2 件に加え、Step 3 (単一 Issue 経路) の 1 件を追加する。受入条件 1 の対象 3 箇所のうち Step 3 だけがテストで守られない状態を避けるため。テストの置き場所は、`count_mode_section` / `list_mode_section` を持つ `tests/auto-batch.bats` と、`step3_section` を持つ `tests/auto.bats` とし、新規ファイルは作らない (新規ファイルだと `docs/structure.md` の同期候補が増えるため)。
- 新規ロジックのテスト要件: 今回の変更は SKILL.md の呼び出し形の変更で、スクリプトの新しい分岐は追加しない。回帰テストの追加は受入条件 2 が求めるもので、Implementation Steps の手順 4 に「新規テストケースを追加したうえでスイートが PASS」を明記した。

### Issue 本文と実装の照合 (Conflict 検出)

- 事実関係はすべて一致した。確認結果: `get-issue-size.sh` の既定は `--cache` で、`gh-graphql.sh` の TTL は 300 秒。`skills/auto/SKILL.md` の対象 3 箇所は `--no-cache` なし。Step 3a (318 行目付近)、`skills/issue/SKILL.md` (861 行目付近)、`modules/project-field-update.md` (51・62・71・80 行目)、`scripts/run-auto-sub.sh` (929・961 行目) は `--no-cache` あり。
- premise マーカー (`grep_count "get-issue-size.sh $NUMBER`; retain" "skills/auto/SKILL.md" -eq 2`) は現状で成立する (固定文字列で 1233・1277 行目の 2 行に一致)。実装後は 0 件になるが、`/audit premise` は `phase/verify` 以降の Issue を評価対象から外すため問題ない。
- 軽微な表記のずれ: Issue 本文の「Step 1 の初期取得」は、実装では `### Step 2: Route Detection and Base Branch` 内の初期取得 (160 行目付近) を指す (Step 1 に Size の取得は無い)。対象外であることに変わりはなく、挙動への影響はない。
- AC1 の `file_not_contains` 2 パターンは固定文字列として評価される前提 (`modules/verify-patterns.md` §1)。変更前の一致位置は `get-issue-size.sh $NUMBER`; retain` が 1233・1277 行目、`get-issue-size.sh $NUMBER`)` が 267 行目で、ほかには無い。回帰テストの文言 (`$NUMBER` は単一引用符内の固定文字列) とは別ファイルのため干渉しない。仮に正規表現として評価されると `$` が行末アンカーになり実装前でも PASS し得るが、その場合も rubric が実装前の FAIL を担保する。

### 範囲外として残す読み取り

- Step 2 の初期取得 (`get-issue-size.sh "$NUMBER"`) と Count mode の `#### Filtering criteria` の候補選定は精査の前の読み取りで、キャッシュ付きのままでよい (受入条件 1 の rubric も「精査を経ない Size の読み取りまで `--no-cache` にする必要はない」としている)。
- `scripts/compute-round-order.sh`・`scripts/get-issue-priority.sh`・`scripts/get-issue-type.sh` も `gh-graphql.sh --cache` で読むが、`run-issue.sh` の直後の Size ゲートではないため本 Issue の対象外。
- Until mode は List mode の手順 1〜7、Resume mode は List mode の手順を再利用するため、List mode の手順 3 の修正で同時に対象になる (`### Until mode` / `### Resume mode` に独自の Size 読み取りは無い: `grep -n 'get-issue-size' skills/auto/SKILL.md` は 160・267・318・1217・1233・1277 の呼び出し 6 行と、`allowed-tools` の 1 行の計 7 行)。

### 同期候補の判定 (Steering Docs sync candidate)

測定範囲はいずれも `docs/`・`tests/`・`scripts/`・`modules/` 配下の全ファイルに対する `grep -rl` (除外なし)。

- キーワード `get-issue-size.sh --no-cache` (この Issue が SKILL.md に新しく書く呼び出し形) は 6 ファイル。内訳は過去の使い捨て Spec 5 件 (`docs/spec/issue-{458,501,518,529,1108}-*.md`、履歴のため除外) と `modules/project-field-update.md` (既に 4 箇所とも `--no-cache`、変更不要)。
- キーワード `get-issue-size.sh` は 54 ファイル、`no-cache` は 16 ファイルで、いずれも 8 件を超えるため識別力なしとして対象外 (個別の評価はしない)。
- Listing-side sub-check: ファイルの追加・削除・改名、サブコマンドの追加、ディレクトリ構成の変更がないため対象外。
- Outbound pointer: `skills/auto/SKILL.md` が指す先 (`docs/workflow.md`、`modules/size-workflow-table.md` など) に、今回の変更 (Size 読み取りのキャッシュ指定) を記述した箇所はない。
- 文書への影響 (`modules/doc-checker.md` と `modules/skill-dev-doc-impact.md` の「Skill change」): `README.md`・`docs/workflow.md`・`CLAUDE.md` はスキル一覧・フェーズ説明・開発フローを変えないため変更不要。確認: `README.md` と `CLAUDE.md` に `get-issue-size` の記述はなく、`docs/workflow.md` の言及 (266 行目付近) は reopen 時の Size 保持の説明で無関係。
- `docs/ja/` の同期: トップレベルの `docs/*.md` を変更しないため対象外。
- 既存テストへの影響: `skills/auto/SKILL.md` を読む bats は 9 ファイル。そのうち `tests/auto.bats`・`tests/auto-batch.bats`・`tests/auto-completion-report.bats`・`tests/auto-xl-concurrency.bats`・`tests/assignee-check.bats`・`tests/operate-route.bats`・`tests/check-skill-change-observation-ac.bats`・`tests/ci-failure-classifier.bats` に、変更する 3 行の語句 (`get-issue-size.sh`、`retain the result`、`re-fetch Size`、`Update route if Size`、`ISSUE_SIZE`) を固定する検査はない (`grep -F` で 0 件を確認)。`tests/run-auto-sub.bats` は `get-issue-size.sh` をモックするだけで SKILL.md の文言は検査しない。
- `allowed-tools`: 新しいスクリプトは追加せず、`skills/auto/SKILL.md` の frontmatter に `scripts/get-issue-size.sh:*` が既にあるため変更不要。

### bats テストの入力形式

テストが読む `skills/auto/SKILL.md` の行の形式 (実装後)。

- Count mode / List mode: `### Count mode (--batch N)` / `### List mode (--batch N1 N2 ...)` の節 (次の `###` 以上の見出しの直前まで。`md_section` はコードフェンス内の見出しを無視する) に、番号付きの項目 ``3. call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh --no-cache $NUMBER` (...); retain the result as `$ISSUE_SIZE`; ...`` が 1 行ある。テストは「`get-issue-size.sh` と `retain the result as` を両方含む行」をゲートとして抽出し、`get-issue-size.sh --no-cache $NUMBER` を含むことを確認する。Count mode には `#### Filtering criteria` にも `get-issue-size.sh $NUMBER` を含む行があるが、`retain the result as` を含まないため抽出されず、`--no-cache` を要求しない。
- Step 3: `### Step 3:` 節 (`### Step 3a:` の直前まで) で `get-issue-size.sh` を含む行は、`No phase/* labels` 分岐の精査後の再取得の 1 行だけ。
- テスト名は既存の `(Issue #NNNN)` 末尾の命名に合わせる。ゲート行が見つからない場合や書き換えられた場合は、`[ -n "$gate" ]` で FAIL する (空振りで PASS しない)。

### 試作による事前確認 (Spec 作成時に実施、作業用ファイルは削除済み)

- 現行の `skills/auto/SKILL.md` に対して提案テスト 3 件は 3 件とも FAIL (red)。上記 3 箇所の文言を適用した SKILL.md のコピーに対しては 3 件とも PASS (green)。
- 適用後のコピーで、AC1 の `file_not_contains` 2 パターンはどちらも 0 件に一致 (変更前は 1233・1277 行目と 267 行目)。変更行に半角 `!` と CJK 文字はなく、`python3 scripts/validate-skill-syntax.py` は 0 エラー・0 警告。
- 変更前の `tests/auto.bats` と `tests/auto-batch.bats` は失敗 0 件 (ベースライン)。

### その他

- 監査・調査型の Issue か: いいえ。既存項目を分類する調査ではなく、呼び出しの修正と回帰テストの追加であり、判断根拠を永続成果物に残す性質のものでもないため、識別子の存在確認の追加要件は適用しない (Spec が引用する行・節・ファイルは grep で存在を確認済み)。
- fail-safe に関わるゲートか: はい (XL ゲート。Implementation Steps の手順 3 に端のケースを明記)。
- 認証情報・セキュリティ方針、外部仕様、新規の外部依存パッケージ、Smoke Test: いずれも該当しない。
- 計測: `get-issue-size.sh` の呼び出し行数は `skills/auto/SKILL.md` で 6 行 (`grep -n 'get-issue-size' skills/auto/SKILL.md` から `allowed-tools` の 1 行を除く)。うち `--no-cache` ありは変更前 1 行 (318)、変更後 4 行 (267・318・1233・1277)。

## Consumed Comments
No new comments since last phase.

## Code Retrospective

### Deviations from Design
- なし。Spec の Implementation Steps どおり、`skills/auto/SKILL.md` の 3 箇所に `--no-cache` を追加し、回帰テストを 3 件追加した。

### Design Gaps/Ambiguities
- 全体スイート (`bats --jobs 4 tests/`、2502 件) で `tests/claude-watchdog.bats` の `WATCHDOG_TIMEOUT env var: custom value takes effect` が 1 件 FAIL した。単独で再実行しても FAIL (`elapsed < 30` を満たさない) し、同ファイルの再実行は 300 秒でバックグラウンドへ移ったため止めた。変更ファイルは `skills/auto/SKILL.md` と 2 つの bats だけで `scripts/claude-watchdog.sh` には触れていないため、この環境での時間依存テストの失敗で、本 Issue の差分とは無関係と判断した (未解消。CI の結果で `/verify` が最終確認する)。
- 対象の 2 ファイル (`tests/auto-batch.bats`, `tests/auto.bats`) は全件 PASS (0 件 FAIL)。

### Rework
- なし。新規テスト 3 件は実装前に 3 件とも FAIL (red) し、実装後に PASS (green) することを確認した (Confirmed pre-implementation FAIL for 3 new test(s).)。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 呼び出し側の `--no-cache` 付与で対処した (`get-issue-size.sh` と `gh-graphql.sh` は変更なし)。既存の Step 3a や `modules/project-field-update.md` と同じ手段で、`--cache-clear` のように無関係なキャッシュを巻き込まない。
- 精査より前の Size 読み取り (Step 2 の初期取得、Count mode の候補選定) は対象外のまま。

### Deferred Items
- AC3 (CI の bats テストが通る) は push 後の CI でしか確認できないため未チェックのまま残した。`/verify` が `gh run list` で確認する。
- 全体スイートの `tests/claude-watchdog.bats` の時間依存テスト 1 件が、この環境で FAIL した (差分とは無関係)。CI で再現するか `/verify` で確認する。

### Notes for Next Phase
- AC1 と AC2 は /code で確認済みでチェック済み。AC3 のみ `- [ ]`。
- XL ゲートは Size 空のとき fail-open のまま (Spec の端のケースどおり、挙動は変えていない)。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 起票時の AC3 (`gh pr checks`) を、`/issue` が patch route 向けの `gh run list` 形式に直していた。AC1 には実装前の記述が消えたことを確かめる `file_not_contains` が補助に付き、判定は明確だった

#### design
- 呼び出し側に `--no-cache` を付ける方針で、既存の Step 3a や `modules/project-field-update.md` と手段が揃っている

#### code
- 設計からの逸脱は無い。新規テスト 3 件は実装前に FAIL することを確認している
- 全体スイートで `tests/claude-watchdog.bats` の `WATCHDOG_TIMEOUT env var: custom value takes effect` が FAIL し、「差分とは無関係な時間依存の失敗」と判断されていた。verify で再現したところ、原因は #1546 で wrapper 起動のセッションに `CLAUDE_PLUGIN_ROOT` が export されるようになったこと。`scripts/claude-watchdog.sh` の kill 分岐が本物の `observation-trigger.sh --event watchdog-kill` を呼び、テストが 30 秒の上限を超える (`CLAUDE_PLUGIN_ROOT` 未設定なら PASS、設定すると FAIL を再現)。同じ時刻 (2026-10-25T02:53Z) に #535・#585・#802 へ誤った observation 通知コメントが投稿されており、テストが GitHub に副作用を残している

#### review
- patch route のため review なし

#### merge
- patch route のため main へ直接コミット。CI (8da0ddcf) は success

#### verify
- AC1・AC2 は /code でチェック済み。AC3 は `gh run list` で success を確認して PASS

### Improvement Proposals
- `tests/claude-watchdog.bats` (と、watchdog の kill 分岐を通る他のテスト) が `CLAUDE_PLUGIN_ROOT` を継承すると、本物の `observation-trigger.sh` を呼んで GitHub に誤った通知コメントを投稿し、テストも時間切れで FAIL する。#1546 以降は wrapper 起動の `/code` で毎回起きる。テスト側で `CLAUDE_PLUGIN_ROOT` を外すか stub に向ける (Tier 1: 2026-08-15・08-20・10-25 に同じ形の誤投稿が繰り返されている)
