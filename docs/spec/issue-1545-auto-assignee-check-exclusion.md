# Issue #1545: auto: 開始時に他メンバーの担当を確認し、--batch の自動選定から他メンバーの担当 Issue を除外

## Overview

#1542 (XL 親) の sub-issue ③。#1543 で用意した担当状況の判定・付け替えの共通処理 (`scripts/gh-issue-assignee.sh`) を使い、`/auto` が他のメンバーの担当している Issue を、本人の確認なしに進めないようにする。

要点:

- **`/auto N` (と `/auto --resume N`)**: 新設の Step 1a で、子フェーズを起動する前に 1 回、`gh-issue-assignee.sh status` で担当状況を読む。実行ユーザー以外がアサイン済み (`other`) のとき、対話実行では `自分に付け替えて続ける` / `付け替えずに続ける` / `中止` の 3 択で確認する (付け替えは親が `reassign` で行い、中止は子フェーズを起動せずラベルも変えずに終了する)。`--non-interactive` では assignee を変えずに警告して続ける
- **List mode (`--batch N1 N2 ...`) と Resume mode (`--batch --resume`)**: 開始時に、実行ユーザー以外がアサイン済みの Issue を 1 回の警告で一覧する。除外はしない
- **Count mode (`--batch N`) と Until mode (`--batch --until <query>`)**: 候補から、実行ユーザー以外がアサインされている Issue を除く (未アサインの Issue と、実行ユーザーだけがアサインされている Issue は残す)。判定は新規スクリプト `scripts/filter-other-assignees.sh` に集約する (SKILL.md の散文に足すだけでは bats で検証できないため。#1457 の教訓)。Count mode は `gh issue list ... | filter-other-assignees.sh`、Until mode は `scripts/resolve-batch-query.sh` の内部から呼ぶ。実行ユーザーを特定できないときは fail-closed (誰かがアサイン済みの Issue はすべて除外する)
- **XL**: 確認は XL 親だけに行う。子 Issue は扇形展開の前に警告だけを出す (確認も除外もしない)
- 他のメンバーの担当の確認・警告・除外は、人が手で付けた assignee を尊重するためのもので、`auto-assign` 設定と autonomy tier のどちらにも依存しない (#1542 の方針 9・10)
- `docs/workflow.md` の `/auto` の説明、構造ドキュメント (`docs/structure.md`)、L0 surface の SSoT (`modules/l0-surfaces.md`)、各日本語ミラーを更新する

## Consumed Comments

No new comments since last phase.

## Changed Files

- `skills/auto/SKILL.md`: 次の 8 点を変更する。追記する文字列は英語のみ (日本語は `` `自分に付け替えて続ける` `` のような inline code の中だけ。`scripts/check-language-convention.py` が散文の CJK を検出する)。本文に半角 `!` を書かない、bash ブロックに `for VAR in $SCALAR` を書かない (`scripts/validate-skill-syntax.py`)
  - (a) frontmatter `allowed-tools`: `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-batch-query.sh:*` の直後に `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh:*` と `${CLAUDE_PLUGIN_ROOT}/scripts/filter-other-assignees.sh:*` を追加 (本文が参照するスクリプトは `allowed-tools` に載せる必要がある)
  - (b) Step 1: `--resume` 検出の「Proceed to Step 2 as normal」を Step 1a 経由の記述に直す。`--batch` 分岐の 4 か所の `skip Steps 2–6` と、`## Batch Mode (--batch)` 冒頭の 1 か所 (計 5 か所) を `skip Steps 1a–6` に直す
  - (c) 新規 `### Step 1a: Assignee Check (single-Issue path)` を Step 1 と Step 2 の間に追加
  - (d) Step 4 の XL route: 項目 1 (`get-sub-issue-graph.sh` の結果の解析) の直後に、子 Issue の警告を追記 (`awk` で `**XL route:` から最初の `---` 行までを切り出す `tests/auto-xl-concurrency.bats` があるため、`---` 行より前に収める)
  - (e) Count mode: 冒頭の後方互換の 1 文 (「既存の `--batch N` の挙動は変更せず後方互換で維持する。」) を、担当による除外という例外を明記した英語の 1 文に書き換える。Fetch Batch Candidates のコマンドを `--json number,title,labels,createdAt,assignees` にして `filter-other-assignees.sh` へパイプし、その説明を追記する
  - (f) List mode: 「Load stop-at setting (List mode only)」ブロックの直後、「Process each Issue in `BATCH_LIST` in order:」の直前に、「Assignee warning」ブロックを追加
  - (g) Until mode: 冒頭 (「Condition-driven loop」の段落の後) に担当による除外の説明を追加。step 4 に、スクリプトの標準エラー出力の扱いを追記
  - (h) Resume mode: step 5 に、List mode の「Assignee warning」ブロックを `REMAINING` に対して実行する旨を追記
- `scripts/filter-other-assignees.sh`: 新規ファイル。`gh issue list --json number,...,assignees` の JSON 配列を標準入力から読み、実行ユーザー以外がアサインされている Issue を除いた同じ形の配列を標準出力に出す。実行ユーザーを特定できないときは fail-closed。作成後に `chmod +x` を実行する (隣接スクリプトは git mode 100755) — bash 3.2+ 互換 (連想配列・`mapfile` を使わない)。追記する文字列は英語のみ (`scripts/` への CJK 混入を検出される)
- `scripts/resolve-batch-query.sh`: `gh issue list` の `--json` に `assignees` を足し、ラベル一致の後・Status の GraphQL 照会の前に `filter-other-assignees.sh` で除外する。ヘッダーコメントに除外規則・実行ユーザー不明時の扱い・終了コードの規約 (0 / 1 / 2 は不変) を追記 — bash 3.2+ 互換。追記する文字列は英語のみ
- `tests/filter-other-assignees.bats`: 新規ファイル。判定・実行ユーザーの特定・入力の境界値・使い方の各ケース
- `tests/resolve-batch-query.bats`: `gh` mock に `api user` の分岐を足し、担当による除外の @test を追加 (既存の @test と fixture は変更しない)
- `tests/auto-batch.bats`: Count mode・List mode・Until mode・Resume mode の担当まわりの構造テストを追加 (既存の @test は変更しない)
- `tests/auto.bats`: Step 1a・`skip Steps 1a–6`・XL route の警告・`allowed-tools` の構造テストを追加 (既存の @test は変更しない)
- `docs/workflow.md`: Orchestration の `/auto` の説明に、開始時の確認 (`/auto 123` の段落)、`--batch N` と `--batch --until` の項の候補除外、`--batch N1 N2 ...` と `--batch --resume` の項の開始時警告を追記
- `docs/ja/workflow.md`: [translation sync] 上記の日本語ミラーを同期 (`docs/translation-workflow.md` の Sync Procedure に従う。コードフェンス数の一致を確認する)
- `docs/structure.md`: [Steering Docs sync candidate: listing-side sub-check] Key Files の「Process management」で、`scripts/resolve-batch-query.sh` の行に担当による除外を追記し、直後に `scripts/filter-other-assignees.sh` の行を追加 (`ssot_for: directory-layout` を frontmatter で確認済み。Directory Layout の木構造には個別スクリプトもファイル数も載っていないため、木構造は変更不要)
- `docs/ja/structure.md`: [translation sync] 上記の日本語ミラーを同期
- `modules/l0-surfaces.md`: L0 Surface SSoT 表の `Assignees` 行の Primary callers 列に `/auto` を追記する (#1543 の申し送り: スキル名を足すのは #1544・#1545 の側)。スクリプト名は `${CLAUDE_PLUGIN_ROOT}/scripts/` 付きの形では書かない (`validate-skill-syntax.py` の `validate_modules_scripts_in_allowed_tools` の検出対象にしないため)。追記する文字列は英語のみ
- [Steering Docs sync candidate] `docs/guide/workflow.md`: 「`/auto` — Full Automation」の例 (`/auto --batch 5` など) の近くに、他のメンバーがアサイン済みの Issue は開始時に確認され (`/auto N`)、`--batch N` と `--batch --until` では候補から除かれる旨を 1〜2 文足すかどうかを `/code` が読んで判断する (推奨: 追加。追加する場合は `docs/ja/guide/workflow.md` も同期)

**変更不要 (grep・Read で確認済み。測定範囲は `docs/`・`modules/`・`skills/`・`scripts/`・`README.md`・`SECURITY.md`、`docs/spec/`・`docs/reports/`・`docs/sessions/` を除く。main の ca1b5b31 時点):**

- `docs/guide/customization.md` と `docs/ja/guide/customization.md`: `auto-assign` の行が「他のメンバーの担当の確認・警告と `/auto` の候補除外は、値に関係なく動く」と既に書いている (`grep -n "candidate exclusion" docs/guide/customization.md` で確認)
- `modules/detect-config-markers.md`: `auto-assign` の箇条書きが「`status` は `/auto` の候補除外に使う」と既に書いている。`modules/autonomy-tier.md`: assignee の付与の例外の節は `status` を L0 read としてゲートしないと既に書いている
- `modules/round-ordering.md`: `resolve-batch-query.sh` の出力を並べ替える手順だけで、候補の選定規則には触れない (`grep -n -i "assign\|candidate\|exclud" modules/round-ordering.md` の一致は無関係な 1 件のみ)
- `README.md`: スクリプト・サブコマンドの列挙がない。`SECURITY.md`: 13 行目の GitHub 操作の一覧が「edit (title, body, labels, assignees)」を既に含み、60 行目の許可パターンに `gh api` が既にある
- `.claude/settings.json.template`: ワイルドカードが全スクリプトを覆う (#1543 の Spec で確認済み)。`.claude/` 配下のファイルは変更しないので `git add -f` は不要
- `docs/migration-notes.md`・`docs/ja/migration-notes.md`: 既存スクリプトの CLI の署名・引数順を変えないので対象外 (`resolve-batch-query.sh` の引数と終了コードの規約は不変)
- `docs/product.md` の Terms の `/auto` の行: `--batch N` の説明は「XS/S Issue を一括処理」のままで正しい。除外の詳細は `docs/workflow.md` が持つ
- WHOLEWORK_SCRIPT_DIR の mock 追加: `grep -ln "resolve-batch-query" tests/*.bats` は `tests/resolve-batch-query.bats` と `tests/auto-batch.bats` だけで、どちらも `WHOLEWORK_SCRIPT_DIR` を設定しない (新スクリプトは実物が呼ばれる)。`tests/resolve-batch-query.bats` の「assignee 評価の失敗は exit 2」の @test だけ、その @test の中で `WHOLEWORK_SCRIPT_DIR` を別ディレクトリに向ける

**同期候補の探索結果** (測定範囲: `grep -rl "<keyword>" docs/ tests/ scripts/ modules/`、`docs/spec/`・`docs/reports/`・`docs/sessions/` を含む全ファイル。main の ca1b5b31 時点):

- キーワード `filter-other-assignees` (新規の識別子): 既存ファイルへの一致は 0 件
- [Steering Docs sync candidate] keyword "resolve-batch-query.sh" skipped: matched 13 files (no discriminating power)。ただし実体を持つ一致 8 件 (`docs/workflow.md`・`docs/ja/workflow.md`・`docs/structure.md`・`docs/ja/structure.md`・`modules/round-ordering.md`・`tests/auto-batch.bats`・`tests/resolve-batch-query.bats`・`scripts/resolve-batch-query.sh`) は手で確認済みで、`modules/round-ordering.md` を除く 7 件は上の Changed Files に入っている
- [Steering Docs sync candidate] keyword "auto" (skills/auto/SKILL.md の裸のスキル名) skipped: no discriminating power
- 既存の `assignee` への言及は `/triage --assignee` (読み取りのみ) と #1543 が追加した記述だけで、今回の変更と矛盾しない

## Implementation Steps

1. `scripts/filter-other-assignees.sh` を新規作成する (→ acceptance criteria 3, 4, 5)

   **呼び出し規約** (スクリプトのヘッダーコメントと `--help` に英語で書く):

   ```
   gh issue list --state open --json number,...,assignees ... | scripts/filter-other-assignees.sh
   ```

   | 項目 | 内容 |
   |---|---|
   | 標準入力 | 各要素が数値の `number` を持つオブジェクトの JSON 配列。`assignees` は `{login}` を持つオブジェクトの配列 (`null`・キー欠落・`[]` は未アサイン) |
   | 標準出力 | 入力と同じ形 (順序・全フィールドを保つ) のコンパクトな JSON 配列 (`jq -c`)。実行ユーザー以外がアサインされている Issue を除く。全件除外なら `[]` |
   | 標準エラー出力 | 人間向けの `Info:` / `Warning:` / `Error:` で始まる行だけ。機械処理は標準出力だけを見る |
   | 終了コード | 0: 成功 (標準出力は常に JSON 配列)。1: 使い方の誤り (引数あり・標準入力が端末)、または入力が不正 (標準出力は空)。`--help` / `-h` は 0 |

   **判定規則** (除外されるのは次のいずれかの Issue。それ以外は残す):

   | 条件 | 結果 |
   |---|---|
   | `assignees` が `null`・キー欠落・`[]` | 残す (実行ユーザーの特定は不要) |
   | assignee が全員、実行ユーザーの login と一致 (大文字小文字を区別しない) | 残す |
   | 実行ユーザー以外が 1 人でも含まれる (複数人・bot・Copilot を含む) | 除外 |
   | `assignees` が配列でない (文字列・オブジェクト・数値・真偽値)、または要素が文字列の `login` を持たない・`login` が空 | 除外 (実行ユーザーと確かめられないため。実行ユーザーの特定も不要) |
   | 実行ユーザーを特定できない | 空でない assignee 配列を持つ Issue をすべて除外 (fail-closed) |

   **fail-closed の理由** (ヘッダーコメントにも書く): 実行ユーザーを特定できない環境 (GitHub App のトークン・CI の `GITHUB_TOKEN`) では、assignee が実行ユーザー本人なのか他のメンバーなのかを確かめられない。除外しすぎた場合の損失は「その Issue が今回は選ばれない (再実行すれば済む)」だけだが、除外しなかった場合の損失は「他のメンバーが担当している Issue を重ねて進める」で取り返しにくい。`gh-issue-assignee.sh status` が、実行ユーザー不明かつ assignee ありを `other` にする規約とも揃う。

   **実行ユーザーの特定**: assignee 配列が空でない Issue が 1 件でもあるときだけ `gh api user --jq '.login'` を呼ぶ (1 回だけ。誰もアサインされていないときは呼ばない)。受理する条件は `gh-issue-assignee.sh` の `resolve_me` と同じ: 1 行目だけ採用し、CR と前後の空白を除去し、`^[A-Za-z0-9][A-Za-z0-9_-]*$` に一致して 100 文字以下のときだけ採用する。失敗・空出力・形式不正・100 文字超は「特定できない」とし、`Warning: could not identify the executing user (gh api user failed); excluding every issue that has an assignee` を標準エラー出力に 1 回出す。

   **標準エラー出力の要約行** (除外が 1 件以上のときだけ 1 行):

   - 特定できたとき: `Info: excluded N issue(s) assigned to someone other than the executing user: #12 (alice, bob), #15 (Copilot)`
   - 特定できなかったとき: `Info: excluded N issue(s) that have an assignee (the executing user could not be identified): #12 (alice), ...`
   - 要素は最大 20 件まで。超えた分は末尾に `, ... (+K more)`。login は `[A-Za-z0-9_.[]-]` 以外の文字を `?` に置き換えて出す (1 行を保つ。制御文字・ESC の混入対策)。assignees が不正な Issue は `(unreadable assignees)` と書く

   **境界値の期待挙動** (このスクリプトは候補を通すか止めるかの関門で、失敗時に安全側へ倒す設計なので fail-safe critical に当たる。次の表で固定する):

   | 入力・条件 | 挙動 |
   |---|---|
   | 標準入力が空・空白だけ | exit 1、標準出力は空 (上流の `gh` の失敗が「候補なし」に見えないようにする) |
   | JSON として不正・配列でない・要素がオブジェクトでない・要素に数値の `number` がない | exit 1、標準出力は空。判定を推測しない |
   | `[]` | `[]` を出力して exit 0。`gh` は呼ばない |
   | 大きな入力 (200 件超・数百 KB) | 標準入力を変数に読み、`jq` へは標準入力で渡す。`--argjson` や引数で JSON を渡さない (Linux は引数 1 つが 128 KiB まで) |
   | title などに `>`・`"`・改行・CR・多バイト文字 | 触らず通す (`jq` が再シリアライズする。`number` と `assignees` 以外を解釈しない) |
   | 入力に CRLF の改行 | `jq` は空白として読む。`gh api user` の出力の CR は除去する |
   | 依存コマンドの失敗: `gh api user` | 上の fail-closed (exit 0 のまま)。`jq` の失敗 (検証・判定のどちらも) は exit 1、標準出力は空 (途中までの出力を出さない) |

   **jq の判定ロジック** (3 回の `jq` 呼び出し — 実行ユーザーが必要かの判定・残す Issue の抽出・要約行の生成 — で共用するため、`JQ_DEFS` というシェル変数に 1 か所だけ書く。jq-1.7 で動作を確認済み。使う機能 `all/2`・`any/2`・`ascii_downcase`・`gsub`・配列スライスは jq 1.5 以降のもの):

   ```
   def atype: (.assignees | type);
   def has_assignee: if atype == "null" then false elif atype == "array" then (.assignees | length) > 0 else true end;
   def logins: if atype == "array" then [.assignees[] | if type == "object" and ((.login | type) == "string") then .login else "" end] else [] end;
   def only_me($me): ($me != "") and atype == "array" and ((logins | length) > 0) and all(logins[]; . != "" and (ascii_downcase == ($me | ascii_downcase)));
   def keep($me): (has_assignee | not) or only_me($me);
   ```

   入力の検証は `jq -e 'type == "array" and all(.[]; type == "object" and ((.number | type) == "number"))'`。実行ユーザーが必要かの判定は `any(.[]; atype == "array" and (.assignees | length) > 0)`。残す Issue の抽出は `map(select(keep($me)))` (実行ユーザー不明のときは `--arg me ""`)。

   このスクリプトは単発のパイプラインフィルタで、timeout・kill・監視の継続はない。分岐は「正常終了 = exit 0 と JSON 配列を標準出力」「異常終了 = exit 1 と `Error:` を標準エラー出力 (標準出力は空)」の 2 つだけで、上の 2 つの表がその条件の全列挙。

   実装は関数に分ける (`resolve_me`・入力の検証・判定・要約行)。`set -euo pipefail` 下で `local x=$(cmd)` は使わず、宣言と代入を分ける。結果は変数に溜めてから最後に出力する。`SCRIPT_DIR` は不要 (他のスクリプトを呼ばない)。

2. `scripts/resolve-batch-query.sh` に担当による除外を組み込む (after 1) (→ acceptance criteria 3, 4, 5)

   - (a) `gh issue list --state open --json number,labels --limit "$LIMIT"` を `--json number,labels,assignees` にする (`ISSUES_COUNT` の切り詰め警告・ラベル一致の `case` glob はそのまま)
   - (b) ラベル一致の絞り込み (`LABEL_FILTERED` の算出) と Status の絞り込みの間に、担当による除外を足す。`LABEL_FILTERED` が空なら何もしない (`gh api user` も呼ばない)。空でなければ、ラベルが一致した Issue だけに絞った JSON を `jq -c --arg nums "$LABEL_FILTERED" '($nums | split(" ") | map(select(length > 0) | tonumber)) as $keep | map(select(.number as $n | any($keep[]; . == $n)))'` で作り、`"$SCRIPT_DIR/filter-other-assignees.sh"` に標準入力で渡し、その出力から残った番号を `jq -r '[.[].number | tostring] | join(" ")'` で取り、`ASSIGNEE_FILTERED` に入れる (既存の変数と同じ、先頭に空白を置く形)。ラベルに一致しない Issue は評価しない (要約行や警告が無関係な Issue で埋まらないようにする)
   - (c) 失敗時: 上の部分が失敗したら (フィルタが非 0 で終了、または `jq` が失敗) `resolve-batch-query: failed to evaluate the assignees of the candidate issues` を標準エラー出力に出して exit 2。フィルタの標準エラー出力 (`Info:` の要約行・`Warning:`) は加工せずそのまま通す。`set -o pipefail` のもとでパイプの途中の失敗を拾えるよう、`if ! RESULT=$(a | b | c); then` の形にする
   - (d) Status の絞り込み (`for num in $LABEL_FILTERED`) と、`status:` 句なしの場合の `STATUS_FILTERED="$LABEL_FILTERED"` を、`ASSIGNEE_FILTERED` を使う形に直す。`--exclude` の処理 (`for ex in $EXCLUDE`) と昇順ソートは変えない
   - (e) ヘッダーコメント: 担当による除外の節を追加する。書く内容は 5 点: (i) 実行ユーザー以外が 1 人でもアサインされている Issue を除外する / 未アサイン (`assignees` が空配列・`null`・キー欠落) と実行ユーザーだけがアサインされている Issue は残す / (ii) 評価はラベル一致の後・Status 照会の前、実装は `filter-other-assignees.sh` / (iii) 実行ユーザーを特定できないときは、assignee がいる Issue をすべて除外し (fail-closed)、警告を標準エラー出力に出す。除外が結果から消えるだけでスクリプトは失敗しない / (iv) 終了コードの規約は変わらない: 0 成功、1 パースエラー、2 `gh` の失敗 (`gh issue list` の失敗、その出力や assignee を評価できなかった場合を含む) / (v) 除外は呼び出した時点の 1 回の評価で、assignee はロックではない
   - 既存の動作は変えない: `assignees` を持たない既存の fixture (`three_issues_json`) はそのまま通り、`gh api user` は呼ばれない

3. `skills/auto/SKILL.md` を更新する (after 1; parallel with 2) (→ acceptance criteria 1, 2, 3, 8)

   - (a)〜(h) は Changed Files の項に列挙したとおり。文面は英語で、次の内容を必ず含める (テストが固定の語句を検査するため、語句は変えない。`ARGUMENTS` に `--non-interactive` があるかで対話実行かを判定するのは、既存の Until mode (`--checkin-per-round`) と同じ):
   - **Step 1a** (`md_section` で `### Step 1a:` から切り出せる見出し。Step 1 の「Read `phase-banner.md`...」の段落の後、`### Step 2:` の前):
     1. 位置と範囲: Step 1 のバナーの直後、副作用のある処理 (Step 2 以降) の前に 1 回。`/auto N` と `/auto --resume N` に適用し、`--batch` の形はすべて Step 1 で分岐して飛ばす (Batch Mode の節が担当を扱う)
     2. 理由: 子フェーズ (`run-*.sh`) は常に `--non-interactive` で動くため、子フェーズの中の確認は警告にしかならず、assignee は以前の担当者のまま残る。精査した人と実装する人が違う分担は普通にあるので、確認は親が子フェーズを起動する前に 1 回行う。L0 の読み取りと (ユーザーが選んだときだけの) 置換で、autonomy tier にも `auto-assign` にも依存しない (書き込みの可否は `gh-issue-assignee.sh` が自分で判定する)
     3. 手順: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh status $NUMBER` をリポジトリルートから実行して標準出力の 1 語を読む。標準エラー出力の `Warning:` / `Info:` (`Info:` が assignee の login を示す) はユーザーに伝える。コマンドが実行できない (非 0) ときは警告して `unknown` と同じに扱う (assignee の問題で `/auto` を止めない)
     4. 分岐: `unassigned`・`self`・`unknown` は確認なしで Step 2 へ。`other` (bot・Copilot を含む) は、`--non-interactive` なら「#$NUMBER は <login> が担当しているが assignee を変えずに続ける」旨を警告して Step 2 へ。そうでなければ AskUserQuestion で担当者を示して、次の 3 択を出す:
        - `自分に付け替えて続ける`: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh reassign $NUMBER` を実行し、`assigned` なら付け替えた旨、`unchanged` なら何も言わない、`disabled` なら `auto-assign: false` のため assignee を変えなかった旨、`failed` なら (ヘルパーが理由を出力済み) を伝える。どの語でも Step 2 へ進む (付け替えができなかったことで `/auto` を止めない。#1543 の申し送り: 選択肢は常に出し、`disabled` を結果として伝える)
        - `付け替えずに続ける`: assignee を変えずに Step 2 へ
        - `中止`: 担当者を示し、フェーズを起動しておらずラベルも変えていない旨を出力して止まる。Step 2 以降に入らず、`run-*.sh` も実行しない
     5. XL: この Step が確認するのはコマンドで指定された Issue (XL 親) だけ。子 Issue は Step 4 の XL route の警告が扱う
   - **Count mode** (e): 後方互換の文は「`--batch N` の既存の挙動は後方互換で維持するが、実行ユーザー以外がアサインされている Issue は候補にならない (Fetch Batch Candidates 参照)。未アサインの Issue と実行ユーザーだけがアサインされている Issue は従来どおり候補」という内容を英語で。Fetch Batch Candidates のコマンドは次の形 (1 行):
     ```bash
     gh issue list --state open --label triaged --json number,title,labels,createdAt,assignees --limit 200 | ${CLAUDE_PLUGIN_ROOT}/scripts/filter-other-assignees.sh
     ```
     説明に含める事項: 出力された配列を候補とする / 標準エラー出力の `Info:` 行をユーザーに伝える / 実行ユーザーを特定できないときは assignee がいる Issue をすべて除外して警告する (fail-closed) / コマンドが失敗 (非 0) したら警告して Count mode を止め、1 件も処理しない (除外していない一覧に戻らない) / 評価は選定時の 1 回で、長い実行の途中で付いた assignee は再確認しない (assignee はロックではない)。「Filtering criteria」(Size での絞り込み・`createdAt` の降順・上位 N 件) は変えない
   - **List mode** (f): 太字の 1 行 `**Assignee warning (List mode and Resume mode; run once, before the first Issue):**` で始まるブロック (`#` の見出しにはしない。直前の `**Load stop-at setting (List mode only):**` と同じ体裁)。内容: 明示した Issue は担当では除外しない (番号を指定したことは自動選定の規則より強い意思) が、開始時に 1 回警告する / リポジトリルートから、`BATCH_LIST` の各番号 N に `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh status N` を 1 回ずつ実行し、出力が `other` の番号を集める / 1 件以上あれば、番号の一覧 (ヘルパーの `Info:` の login つき) と「それらも処理する」旨を 1 回の警告で出し、なければ何も出さない / 失敗 (非 0、または `unknown`) はその Issue について黙って飛ばす / `BATCH_LIST`・チェックポイント・順序を変えず、確認も求めない (番号を明示した batch は無人で動けるべき。確認するのは単一 Issue の Step 1a)
   - **Until mode** (g): 冒頭の追記は、`resolve-batch-query.sh` が実行ユーザー以外のアサイン済みの Issue を毎ラウンド除外すること (assignee が外れる・実行ユーザーに変わると、次のラウンドで候補に戻る) と、step 6 が再利用するのは List mode の番号付きの step 1〜7 だけで、List mode の「Assignee warning」ブロックはそれらの外にあり (stop-at のブロックと同じ)、`ROUND_LIST` は除外済みなので意図的に適用しない旨。step 4 の追記は、スクリプトの標準エラー出力 (除外した Issue を示す `Info:` と、実行ユーザーを特定できないときの警告) をユーザーに伝えること。step 4 の exit code の扱いは変えない
   - **Resume mode** (h): step 5 に、`REMAINING` を `BATCH_LIST` とみなし、最初の Issue の前に List mode の「Assignee warning」ブロックを `REMAINING` に対して実行すること (中断の間に assignee が変わりうる。List mode の番号付きの手順の外にあるため、「同じ手順」という参照だけでは含まれない) を、既存の `write_batch` を呼ばない旨の記述を保ったまま追記
   - **XL route** (d): 項目 1 の直後に、太字の 1 行 `**Assignee warning for sub-issues**` で始まる段落を追加 (`#` の見出しにはしない。番号付きの項目も増やさず、項目 2 以降の番号を変えない)。内容: 項目 2 の前に、`execution_order` の各子 Issue 番号 N に対して `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh status N` をリポジトリルートから実行し、`other` を集める / 1 件以上あれば assignee つきの一覧を 1 回の警告で出し、扇形展開が「それらも処理する」旨を伝える / 確認も除外もしない (XL 親を指定したことが子 Issue を実行する明示的な指示で、List mode で番号を明示するのと同じ) / 失敗は黙って飛ばす / XL 親自体は Step 1a で確認済み
   - **後方互換の確認**: `grep -c "skip Steps 2–6" skills/auto/SKILL.md` が 0、`grep -c "skip Steps 1a–6" skills/auto/SKILL.md` が 5 になること
   - **テストが検査する固定の語句** (文面を変えるときはテストと同時に直す): Step 1a — `gh-issue-assignee.sh status`・`gh-issue-assignee.sh reassign`・`--non-interactive`・`AskUserQuestion`・`自分に付け替えて続ける`・`付け替えずに続ける`・`中止`・`disabled`・`run-*.sh`。Count mode — `filter-other-assignees.sh`・`assignees`・`createdAt`・`fail-closed`。List mode — `Assignee warning`・`gh-issue-assignee.sh status`。Resume mode — `Assignee warning`・`REMAINING`。Until mode — `resolve-batch-query.sh`・`Assignee warning`。XL route — `Assignee warning for sub-issues`

4. テストを追加する (after 1, 2, 3) (→ acceptance criteria 5, 7, 8)。既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/filter-other-assignees.bats` の各 @test、`tests/resolve-batch-query.bats` の `assignee:` 系、`tests/auto-batch.bats` と `tests/auto.bats` の構造テスト) を追加したうえでスイートが PASS すること

   **`tests/filter-other-assignees.bats`** (新規): 先頭に `bats_require_minimum_version 1.5.0` を置き、`run --separate-stderr` で標準出力 (JSON) と標準エラー出力を分けて assert する (先例: `tests/gh-issue-assignee.bats`)。`PROJECT_ROOT` を先頭で 1 回定義する。入力は `$BATS_TEST_TMPDIR/in.json` に書き、`run --separate-stderr bash "$SCRIPT" < "$BATS_TEST_TMPDIR/in.json"` で渡す。`gh` は PATH 先頭の stub に差し替える (形式は Notes)。@test 名は `filter:` / `lookup:` / `edge:` / `usage:` で始める。括弧内は AC5 の (1)〜(4) との対応:

   - `filter:` 他のメンバーだけがアサイン→除外 (1) / 実行ユーザーだけ→残る (2) / 空配列・`null`・キー欠落の未アサイン→残る (3) / 実行ユーザーと他のメンバーの両方→除外 / bot (`dependabot[bot]`) と `Copilot`→除外 / login の大文字小文字を区別しない / 残る Issue の順序と全フィールド (`title`・`labels` など) が保たれ、標準出力が `jq -e 'type == "array"'` で読める
   - `lookup:` 実行ユーザーを特定できない (`gh api user` が失敗)→assignee のある Issue はすべて除外 (実行ユーザーと同名の login も含む)・未アサインは残る・`Warning:` が標準エラー出力に 1 回・exit 0 (4) / 空出力・複数行・CRLF 付き・形式不正・101 文字の login の各出力を、受理するもの (複数行は 1 行目・CRLF は除去) と特定不能とするものに分ける / 誰もアサインされていないとき `gh api user` が呼ばれない (呼び出しログが空) / assignee のある Issue が複数あっても `gh api user` は 1 回だけ
   - `edge:` 標準入力が空→exit 1・標準出力が空 / 不正な JSON・配列でない・`number` のない要素→exit 1・標準出力が空 / `[]`→`[]`・exit 0・`gh` が呼ばれない / `assignees` が文字列・オブジェクト・真偽値・`login` のない要素・空の `login`→除外 / `>`・`"`・改行・多バイト文字を含む title が壊れずに残る / 要約行の login の制御文字・改行・ESC が `?` に置き換わり 1 行に収まる / 要約行が 20 件で打ち切られ `(+K more)` が付く / 400 件の入力 (`jq -n` で生成) が正しく処理される / 標準エラー出力の要約行に除外した Issue 番号と login が出る
   - `usage:` 引数あり→exit 1 / `--help`→exit 0 で使い方を表示

   **`tests/resolve-batch-query.bats`** (追記): 先頭の `setup()` の `gh` mock に、`gh api user` の分岐を足す (`api graphql` の分岐の前。呼び出しを `$USER_CALL_LOG` に記録し、`MOCK_ME_FAIL=1` なら exit 1、そうでなければ `printf '%s' "$MOCK_ME"`)。既存の @test と fixture は変更しない。@test 名は `assignee:` で始める:

   - `assignee:` 他のメンバーがアサインされた Issue が結果から除かれる (1) / 実行ユーザーだけがアサインされた Issue は残る (2) / 空配列と `null` の未アサインは残る (3) / 実行ユーザーを特定できない→assignee のある Issue をすべて除外・未アサインは残る・stderr に警告・exit 0 (4) / ラベルに一致しない Issue の assignee では `gh api user` が呼ばれず、要約行にも出ない / assignee のある、ラベル一致の Issue がないとき `gh api user` が呼ばれない / 除外された Issue に対して Status の GraphQL 照会が行われない (`$GRAPHQL_CALL_LOG` に番号がない) / `status:` 句・`--exclude` と併用しても結果が正しい / フィルタが失敗したとき exit 2 (その @test の中で `WHOLEWORK_SCRIPT_DIR` を、exit 1 を返す `filter-other-assignees.sh` だけを置いたディレクトリに向ける) / ヘッダーコメントに実行ユーザー不明時の扱いと 0・1・2 の規約が書かれている (ファイル先頭の `#` で始まるコメントブロックだけを取り出して `grep` する構造テスト。行数の固定値には頼らない)

   **`tests/auto-batch.bats`** (追記): 先頭のコメントに Issue #1545 の節を足し、`resume_mode_section()` ヘルパー (`md_section "$SKILL_FILE" "### Resume mode"`) を定義する。構造テストは `section="$(…)"` の代入で受け、見出しが変わったらテストが落ちるようにする (`docs/tech.md` § BATS Markdown Section Extraction)。観点ごとに 1 件以上:

   - `Count mode section:` 候補が `filter-other-assignees.sh` を通る (コマンド行に `assignees` が含まれ、`createdAt` も含まれる) / 後方互換の文が担当による除外に触れ、元の日本語の文が残っていない / 実行ユーザー不明時の fail-closed が書かれている / コマンド失敗時に Count mode を止める記述がある
   - `List mode section:` 「Assignee warning」ブロックがあり、`gh-issue-assignee.sh status` と「除外しない」旨を含む / そのブロックが「Process each Issue in」より前にある
   - `Until mode section:` 除外が `resolve-batch-query.sh` の中で行われること、List mode の「Assignee warning」を適用しないことが書かれている
   - `Resume mode section:` List mode の「Assignee warning」を `REMAINING` に対して実行する記述がある

   **`tests/auto.bats`** (追記): `step1a_section()` ヘルパー (`md_section "$1" "### Step 1a:"`) を定義する。観点ごとに 1 件以上:

   - `Step 1a section:` `### Step 1` と `### Step 2:` の間にある / `gh-issue-assignee.sh status` と `gh-issue-assignee.sh reassign` を呼ぶ / 3 つの選択肢のラベル (`自分に付け替えて続ける`・`付け替えずに続ける`・`中止`) が揃っている / `--non-interactive` で assignee を変えずに警告して続ける / 中止で `run-*.sh` を実行せずラベルも変えない / `disabled` の扱いがある / `--batch` の形では飛ばす (SKILL.md 全体で `skip Steps 1a–6` が 5 か所、`skip Steps 2–6` が 0 か所)
   - `XL route:` 子 Issue の警告が扇形展開の前にある (`**XL route:` から最初の `---` までの範囲に `status` と警告の記述がある)
   - `allowed-tools:` frontmatter に `gh-issue-assignee.sh:*` と `filter-other-assignees.sh:*` がある

   **検出力の確認** (AC5): 実装とテストを書き、`scripts/resolve-batch-query.sh` の変更をコミットした後に、次の 3 点を確認してから元に戻す (確認用の変更はコミットしない)。結果は Code Retrospective に書く。(i) `git checkout origin/main -- scripts/resolve-batch-query.sh` で修正前の内容に戻し、`bats tests/resolve-batch-query.bats` の `assignee:` 系のうち (1)・(4) の @test が FAIL すること (確認後に `git checkout HEAD -- scripts/resolve-batch-query.sh` で戻す)。(ii) `filter-other-assignees.sh` の `only_me` を常に真にする (他のメンバーを除外しなくなる) 一時変更で、`bats tests/filter-other-assignees.bats` の複数件が FAIL すること。(iii) 実行ユーザー不明時の除外を外す一時変更で、`lookup:` の @test が FAIL すること。

5. ドキュメントと日本語ミラーを更新する (after 1, 2, 3) (→ acceptance criteria 6)

   - `docs/workflow.md`: Orchestration の `/auto` の説明に次を追記する (英語。各 1〜3 文):
     - `/auto 123` の段落 (「If `phase/ready` is absent...」の段落の後に新しい段落): 開始時の担当の確認 (Step 1a)。`/auto 123` と `/auto --resume 123` は、フェーズを起動する前に Issue の assignee を読む。実行ユーザー以外 (bot・Copilot を含む) がアサイン済みなら、対話実行では `自分に付け替えて続ける` / `付け替えずに続ける` / `中止` で確認し (中止ではフェーズを起動せずラベルも変えない)、`--non-interactive` では警告して assignee を変えずに続ける。確認が親にある理由 (子フェーズは常に `--non-interactive`)。未アサインと自分だけの Issue は黙って進む。XL では確認は XL 親だけで、他のメンバーが担当の子 Issue は扇形展開の前に警告だけを出す。`auto-assign` と autonomy tier に依存しない
     - `--batch N` / `--batch N1 N2 ...` の項: Count mode は実行ユーザー以外がアサインされている Issue を候補から除く (未アサインと実行ユーザーだけの Issue は残る)。判定は `scripts/filter-other-assignees.sh`、選定時の 1 回。実行ユーザーを特定できないとき (GitHub App のトークンなど) は assignee のある Issue をすべて除外する (fail-closed)。List mode は除外せず、開始時に他のメンバーがアサイン済みの Issue を 1 回の警告で一覧する
     - `--batch --resume` の項: 残りの Issue に対して同じ開始時の警告を出す
     - `--batch --until <query>` の項: 各ラウンドの候補から、実行ユーザー以外がアサインされている Issue を除く (`scripts/resolve-batch-query.sh` の内部。規則は Count mode と同じ)。毎ラウンド再評価されるので、assignee が外れた Issue は次のラウンドで候補に戻る。このため List mode の開始時の警告はラウンドごとには出さない
   - `docs/ja/workflow.md`: 上記を日本語で同期する (114・122・124 行付近の `--batch` の段落と、`/auto` の説明の段落)。コードフェンスの数が英語版と一致していることを確認する (`docs/translation-workflow.md` の手順 5)。日本語の括弧は半角 `()` の前後に半角スペースを入れる
   - `docs/structure.md`: Key Files の「Process management」で、`scripts/resolve-batch-query.sh` の行に「実行ユーザー以外がアサインされている Issue を `filter-other-assignees.sh` で除外する」旨を追記し、直後に `scripts/filter-other-assignees.sh` の行を追加する (標準入力の JSON 配列から実行ユーザー以外が担当の Issue を除く / bot は other / assignee がいるときだけ実行ユーザーを `gh api user` で特定し、特定できなければ assignee のある Issue をすべて除外する fail-closed / `resolve-batch-query.sh` と `/auto` の Count mode が使う / bash 3.2 互換、を 1 行にまとめる)
   - `docs/ja/structure.md`: 227 行付近の `scripts/resolve-batch-query.sh` の行の同じ位置に日本語で同期する
   - `modules/l0-surfaces.md`: L0 Surface SSoT 表の `Assignees` 行の Primary callers 列に `/auto` を追記する (`status` と `reassign` をヘルパー経由で呼び、候補の一括除外は `filter-other-assignees.sh` と `resolve-batch-query.sh` で行う旨を括弧で)。#1544 が同じセルに `/issue`・`/spec`・`/code` を足すので、競合したら両方を残す形で解消する
   - 最後に `docs/guide/workflow.md` (Changed Files の候補) を読み、追加する場合は `docs/ja/guide/workflow.md` も同期する

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md に、/auto N の開始時 (子フェーズを起動する前) に実行ユーザー以外がアサイン済みかを確認する手順が書かれている。対話実行では「自分に付け替えて続ける / 付け替えずに続ける / 中止」の 3 択で確認し、付け替えなら親が assignee を付け替え、中止なら子フェーズを起動しない。--non-interactive では assignee を変更せずに警告して続行する" --> `/auto 123` は子フェーズを起動する前に、実行ユーザー以外がアサイン済みかを確認する。対話実行では 3 択で確認し (付け替えなら親が付け替え、中止なら子フェーズを起動しない)、`--non-interactive` では警告して続ける
- <!-- verify: rubric "skills/auto/SKILL.md の --batch N1 N2 ... (List mode) で、開始時に実行ユーザー以外がアサイン済みの Issue を一覧で警告し、それらの Issue も除外せずに処理することが書かれている" --> 番号を明示する `--batch N1 N2 ...` では、開始時に他のメンバーがアサイン済みの Issue を一覧で警告する (除外はしない)
- <!-- verify: rubric "skills/auto/SKILL.md の --batch N (Count mode) と --batch --until (Until mode) の候補選定で、実行ユーザー以外がアサインされている Issue を除外し、未アサインの Issue と実行ユーザーだけがアサインされている Issue を対象にすることが書かれている。Count mode 冒頭の後方互換の記述もこの変更と矛盾しないように更新されている" --> <!-- verify: grep "assignee" "skills/auto/SKILL.md" --> `/auto --batch N` と `/auto --batch --until <query>` は、実行ユーザー以外がアサインされている Issue を候補から除く
- <!-- verify: grep "assignees" "scripts/resolve-batch-query.sh" --> <!-- verify: rubric "scripts/resolve-batch-query.sh が実行ユーザー以外がアサインされている Issue を結果から除外し、assignees が空配列または null の Issue を正しく扱う。実行ユーザーの login を特定できない場合の扱いがヘッダーコメントに書かれており、既存の exit code の規約 (0 / 1 / 2) は変わっていない" --> `scripts/resolve-batch-query.sh` が、実行ユーザー以外がアサインされている Issue を除外する。実行ユーザーを特定できない場合の扱いがヘッダーコメントに書かれている
- <!-- verify: rubric "/auto の候補除外について、bats テストが (1) 実行ユーザー以外がアサイン済みの Issue は除外、(2) 実行ユーザーだけがアサイン済みの Issue は残る、(3) 未アサイン (assignees が空配列または null) は残る、(4) 実行ユーザーの login を特定できない場合の挙動、の各ケースを、他ユーザーがアサイン済みの assignees を含む fixture を使って検証しており、修正前の実装に対して FAIL する形になっている" --> 候補除外について、他のメンバー・自分だけ・未アサイン・実行ユーザー不明の各ケースを bats テストで確認しており、修正前の実装では FAIL する
- <!-- verify: rubric "docs/workflow.md の /auto の説明 (--batch N と --batch --until の項) に、実行ユーザー以外がアサインされている Issue が候補から除外されることと、/auto N の開始時に他のメンバーの担当を確認することが書かれている" --> `docs/workflow.md` の `/auto` の説明に、候補からの除外と、開始時の確認が書かれている
- <!-- verify: github_check "gh pr checks --json name,state --jq '.[] | select(.name==\"Run bats tests\") | .state'" "SUCCESS" --> CI の bats テスト (Run bats tests) が通る
- <!-- verify: github_check "gh pr checks --json name,state --jq '.[] | select(.name==\"Validate skill syntax\") | .state'" "SUCCESS" --> CI の Skill 構文チェック (Validate skill syntax) が通る

### Post-merge

- 実行ユーザー以外がアサイン済みの Issue に対話セッションから `/auto 123` を実行したとき、子フェーズを起動する前に 3 択の確認が表示されることを確認する <!-- verify-type: opportunistic -->

## Smoke Test

- <!-- verify: command "bash scripts/resolve-batch-query.sh --query label:triaged" --> 実 GitHub に対する読み取りのみの疎通確認 (1): `gh issue list --json number,labels,assignees` の実出力が `resolve-batch-query.sh` の担当による除外を通り、exit 0 で Issue 番号が返る。リテラル引数の単一コマンドで、パイプを使わない
- <!-- verify: command "gh issue list --state open --json number,assignees --limit 5 | bash scripts/filter-other-assignees.sh" --> 実 GitHub に対する読み取りのみの疎通確認 (2): `gh issue list --json number,assignees` の実出力が `filter-other-assignees.sh` に読め、JSON 配列が返って exit 0。パイプの前段の `gh` が失敗すると標準入力が空になり、フィルタが exit 1 で落ちるため、前段の失敗も検出できる

`assign` / `reassign` は実 Issue の assignee を変更し通知を発生させるため、ここには含めない。このリポジトリには assignee のある Issue がない (取得日 2026-10-24) ので、どちらの確認でも `gh api user` は呼ばれない。実行ユーザー不明・他のメンバーの担当の経路は bats の stub で確認する。

## Notes

### 外部仕様の確認結果 (取得日はすべて 2026-10-24)

| 項目 | 結果 | 根拠 |
|---|---|---|
| `gh issue list --json` の `assignees` フィールドの形 | 各要素が `{"databaseId":N,"id":"...","login":"...","name":"..."}`。未アサインは `"assignees":[]`。`gh issue view --json assignees` と同じ形 (#1543 の fixture と一致) | 実機 (このリポジトリ: `gh issue list --state open --json number,assignees --limit 3`、他のユーザーの担当がある形: `gh issue list --repo microsoft/vscode --state open --json number,assignees --limit 40`。どちらも読み取りのみ) |
| `--limit` と `assignees` の関係 | `--limit 3` と `--limit 40` のどちらでも、各 Issue に `assignees` が含まれる (追加の取得は不要)。`--limit 200` は未確認 | 実機 (上記と同じ呼び出し) |
| jq の機能 | `all/2`・`any/2`・`ascii_downcase`・`gsub`・配列スライスは jq 1.5 以降の機能。判定ロジック・要約行・入力検証・番号の部分集合の抽出は jq-1.7 で動作確認済み | 実機 (`jq-1.7`、`gh version 2.101.0`)。CI と macOS の jq-1.6 では未確認 (使う機能は同じ) |
| 実行ユーザーを特定できない条件 | `gh api user` が失敗する条件 (GitHub App のトークン・CI の `GITHUB_TOKEN`) は #1542 / #1543 の調査による。実機では再現していない | `docs/spec/issue-1543-assignee-helper-auto-assign.md` の Notes |

**実機で確認しなかったこと**: (1) `gh api user` が失敗する実環境 (App トークン・`GITHUB_TOKEN`) での fail-closed の動作 — bats の stub で再現する。(2) 書き込み (`reassign`) の実機確認 — #1543 と同様に、実 Issue の assignee を変更し通知を発生させるため範囲外で、#1544 の Post-merge で行われる。(3) 新スクリプトを含む Smoke Test の実行そのもの — スクリプトが存在しないため、この `/spec` では走らせていない。ただし形は実測済み: worktree の隔離ガードの下で、Smoke Test (1) と同じ単一コマンド `bash scripts/resolve-batch-query.sh --query label:triaged` (実装前の現行版) と、(2) と同じ形のパイプ `gh issue list --state open --json number,assignees --limit 5 | bash scripts/filter-premise-targets.sh` (既存の標準入力フィルタ) は、どちらも拒否されずに exit 0 で実行できた (取得日 2026-10-24)。一方、同じ呼び出しに `; echo "exit=${PIPESTATUS[0]}"` を足した複合形は拒否された (`modules/verify-patterns.md` § 34 の「複雑すぎる構文」の一例)。Smoke Test の `command` には、このような複合形を足さない。万一 (2) が拒否された場合は、(2) を外して (1) だけを残し、そのことを `/code` が Code Retrospective の `Deviations from Design` に記録する (パイプの前段と後段を別々の `command` に分けない: 前段の出力を後段に渡せないため)。

**fixture の出所と形**: bats の stub と fixture が出す JSON の形は上表の 2 つの実機コマンド (取得日 2026-10-24) による。実在のユーザー名・id は使わず、ダミーの `alice` (実行ユーザー)・`bob`・`Copilot`・`dependabot[bot]`、id は `U_dummy`・`BOT_dummy` を使う。

### 設計判断 (非対話モードでの自動解決)

Issue 本文が `/spec` で決めると委ねた 3 点 (`--batch --resume` の扱い・XL の扱い・実行ユーザー不明時の方針) と、#1543 の申し送りに対する決定を含む。

- **判定を新規スクリプトに集約した**: Count mode の `gh issue list` と Until mode の `resolve-batch-query.sh` の両方が同じ規則で除外する必要があり、`/auto` の `allowed-tools` には `gh api` がないので、実行ユーザーの特定は SKILL.md の散文ではできない。検討した代替案: (A) Count mode で候補ごとに `gh-issue-assignee.sh status` を呼ぶ — 候補ごとに `gh issue view` と `gh api user` が走って呼び出しが O(候補数) になり、判定が散文にしか存在せず bats で検証できない (#1457 と同じ問題)。(B) `resolve-batch-query.sh` に jq を直書きして Count mode は散文にとどめる — 規則の実装が 2 つになり、Count mode が検証されない。(C) `gh-issue-assignee.sh` に一覧向けのサブコマンドを足す — 同スクリプトは「サブコマンドと Issue 番号の 2 引数」を契約としており (#1543 で固定済み)、並行する #1544 が呼ぶ側なので、変更を避けて別ファイルにした。(D) Count mode も `resolve-batch-query.sh` で候補を取る — 取得窓が変わる (`gh issue list --label triaged` の直近 200 件ではなく、ラベルなしの直近 200 件をローカルで絞る形になる) ため、後方互換を壊す
- **fail-closed を採った** (実行ユーザーを特定できないとき、assignee のある Issue はすべて除外): 除外しすぎた損失は再実行で取り戻せるが、除外しなかった損失 (他のメンバーの担当を重ねて進める) は取り戻しにくい非対称性。`gh-issue-assignee.sh status` の規約 (assignee あり・実行ユーザー不明は `other`) とも揃う。GitHub App のトークンや CI の `GITHUB_TOKEN` で無人実行する環境では、人間が担当を付けた Issue を自動で拾わない、という望ましい挙動になる。警告に原因を出し、`gh` を PAT で認証し直せば解消する
- **`gh api user` は assignee のある Issue があるときだけ遅延して呼ぶ**: 誰もアサインされていない大多数の呼び出しで API を 1 回節約し、実行ユーザー不明の警告が無関係な場面で出るのを避ける。既存の `tests/resolve-batch-query.bats` が `gh api user` の mock なしで動き続けるための前提でもある
- **除外の位置は「ラベル一致 → 担当 → Status の GraphQL → `--exclude`」**: 安い局所フィルタを先に置き、Issue ごとに GraphQL を呼ぶ Status の照会を減らす。担当の評価をラベル一致の後に置くのは、要約行と警告が無関係な Issue で埋まらないようにするため。`--exclude` の位置は既存のまま変えない (並べ替えは結果を変えないが、この Issue の範囲外の最適化になる)
- **Resume mode でも警告する**: 中断の間に他のメンバーが残りの Issue に着手している可能性があり、警告は情報提供だけで安い (残りの Issue 1 件につき `status` 1 回)。除外ではなく警告なので、再開の結果は変わらない。Resume mode は List mode の手順を参照するだけで `AUTO_STOP_AT` の読み込みなどの暗黙の取り込みに頼っているので (#953 の部分参照の問題)、警告は明示して参照する
- **Until mode には List mode の開始時警告を適用しない**: `ROUND_LIST` は `resolve-batch-query.sh` が除外済みで、警告の対象 (他のメンバーの Issue) が残らない。step 6 が再利用するのは List mode の番号付き step 1〜7 だけなので、ブロックを番号付きの手順の外に置けば自然に適用されない。そのうえで Until mode の節に意図的に適用しない旨を明記する
- **XL は親を確認し、子 Issue は警告のみ**: 親の確認だけだと、他のメンバーが担当している子 Issue を扇形展開が確認なしに進める。ただし 3 択を子ごとに出すと、無人に近い扇形展開の途中で何度も止まる。XL 親を指定したこと自体が子 Issue を実行する明示的な指示で、List mode が「番号を明示した以上は除外せず警告のみ」とするのと同じ関係にあるため、警告のみとした
- **`auto-assign: false` でも 3 択を出す**: `reassign` は `disabled` を返して何もしないが、`gh-issue-assignee.sh` 自身が書き込みの可否を判定する設計 (`modules/detect-config-markers.md`: 呼び出し側は再判定しない)。選択肢を隠すと呼び出し側が `HAS_AUTO_ASSIGN` を読む必要が出る。`disabled` を伝えて続行する
- **評価は選定時の 1 回だけ (処理直前の再確認はしない)**: 処理直前の再確認を List mode の手順に入れると、明示指定の List mode にも効いてしまい (除外しない方針と衝突する)、Until mode の再利用との条件分岐が増える。assignee はロックではないという #1542 の制約の範囲内であり、SKILL.md の Count mode にその旨を書く。Until mode はラウンドごとに再評価される
- **`status` が `unknown` のとき Step 1a は続行する**: #1542 の方針 8 (失敗しても止めない)。ヘルパー自身が標準エラー出力に警告を出している。List mode と XL の警告では、失敗を黙って飛ばす (警告の対象が増える見込みがなく、ヘルパーの警告が既に出ているため)
- **`--resume N` にも Step 1a を適用する**: 中断の間に状況が変わりうるため。以前に「付け替えずに続ける」を選んでいた場合は再度聞かれるが、頻度が低く、情報の古さのほうが問題になる
- **子フェーズが同じ警告を重ねて出すこと**: 親で「付け替えずに続ける」を選んだ後に、#1544 で組み込まれる子フェーズ (`--non-interactive`) が警告を重ねて出す件の扱いは #1544 の `/spec` で決める (そちらの Issue 本文が明記している)。この Issue の範囲外
- **Issue 本文と既存実装の矛盾は検出されなかった**: 背景に書かれた事実 (子フェーズが `--non-interactive` で動く: `run-spec.sh`・`run-code.sh`・`run-issue.sh` が `ARGUMENTS: N --non-interactive` を渡す / Count mode の `gh issue list --state open --label triaged ...` / `resolve-batch-query.sh` が `assignees` を見ていない / `/auto` の `allowed-tools` に `gh issue edit` も `gh api` もない / Count mode 冒頭の後方互換の文 / Until mode と Resume mode が List mode の手順を参照する / `resolve-batch-query.bats` の fixture に `assignees` も `gh api user` の mock もない / `tests/auto-batch.bats` が `### Count mode`・`### List mode`・`### Until mode`・`### Resume mode` の見出しと順序で検査する) をすべてコードで確認した
- 実行ユーザーの特定は既存の先例 (`scripts/gh-issue-assignee.sh` の `resolve_me`、`scripts/post-fallback-review-summary.sh`、`skills/triage/SKILL.md` の `--assignee me`) と同じ `gh api user` を使う。新しい検出方法は導入しない
- 監査・調査型の Issue ではない (新機能の実装であり、複数の既存項目を分類する成果物はない)
- 認証情報・セキュリティポリシーとの整合: 認証情報の保存・秘匿情報は扱わない (login 名の照合と `gh api user` の読み取りだけ)。`SECURITY.md` の GitHub 操作の一覧と許可パターンに既に含まれる

### fail-safe critical な変更の扱い

`scripts/filter-other-assignees.sh` と `scripts/resolve-batch-query.sh` の変更は、Issue を自動処理の対象にするかどうかを決める関門 (基準 (a)) で、失敗時に安全側へ倒す設計 (基準 (c)) を含むので fail-safe critical に当たる。境界値と依存コマンドの失敗の期待挙動は Implementation Steps の 1 の表で固定した (空入力・大きな入力・特殊文字・CRLF・多バイト文字・`gh api user` の失敗)。`jq` の失敗は途中までの出力を出さず exit 1 にする。呼び出し側の対応は、Count mode が「警告して Count mode を止める (処理を 1 件もしない)」、`resolve-batch-query.sh` が exit 2。

### bats の入力形式

- **`tests/filter-other-assignees.bats`**: 標準入力は `gh issue list --json number,...,assignees` と同じ形の JSON 配列。例: `[{"number":1,"title":"t","assignees":[]},{"number":2,"assignees":[{"id":"U_dummy","login":"bob","name":"Bob","databaseId":1}]},{"number":3,"assignees":null},{"number":4}]`。`gh` の stub は `setup()` で `$MOCK_DIR/gh` に書き、`export PATH="$MOCK_DIR:$PATH"` で差し替える (環境変数で挙動を切り替え、ヒアドキュメントは引用付きにして実行時に変数を読む): すべての呼び出しを `$GH_CALL_LOG` に `echo "$*"` で追記する / `gh api user ...` → `MOCK_ME_FAIL=1` なら何も出さず exit 1、そうでなければ `printf '%s' "$MOCK_ME"` を出力して exit 0 (`MOCK_ME` が空なら空出力のケース。CRLF は `printf 'alice\r\n'` を `MOCK_ME` に入れて再現する) / それ以外の呼び出しは記録だけして exit 0。「`gh api user` が呼ばれない」ケースは `$GH_CALL_LOG` が空であることで assert する
- **`tests/resolve-batch-query.bats`**: 既存の `gh issue list` の mock は `--json` の引数を無視して `$MOCK_ISSUE_LIST_JSON` をそのまま返す。担当のケースは `MOCK_ISSUE_LIST_JSON` に `assignees` を含む配列を渡す (例: `[{"number":10,"labels":[{"name":"retro/code"}],"assignees":[{"id":"U_dummy","login":"bob","name":"Bob","databaseId":1}]}, ...]`)。`gh api user` の mock は `$MOCK_ME` を返す (空は何も出力せず exit 0、`MOCK_ME_FAIL=1` は exit 1)。呼び出しは `$USER_CALL_LOG` に追記する
- **構造テスト**: 受け入れの語句は Implementation Steps の 3・4 に挙げた固定の語句を使う

### 規模の見積もり (Step 18 の再評価に使う)

Changed Files は 12 件 (候補の `docs/guide/workflow.md` と、その日本語ミラーを除く)。内訳はスクリプトのロジック変更 2 (新規 1)、SKILL.md 1、テスト 4 (新規 1)、`docs/` 4 (うち翻訳ミラー 2)、`modules/` 1。ファイル数の軸は、翻訳ミラー (`modules/doc-checker.md` が「`/doc translate` が生成する翻訳出力で、実装対象ではない」として扱う `docs/ja/`) の 2 件を除くと 10 件で L。複雑さの補正は、加算要因が「分岐の多い新規スクリプトのロジック」と「複数モードにまたがる SKILL.md の変更」、減算要因が「#1543 で確立した `gh-issue-assignee.sh` と同じ規約の横展開」と「半数がドキュメントとテストの追記」で、差し引き 0 段階として L。triage 時点の M より大きい。

### 他の Issue との並行作業

- **#1544 (`/issue`・`/spec`・`/code`)** は取得日 2026-10-24 時点で `phase/spec` で、#1545 と並行して進む。`modules/l0-surfaces.md` の `Assignees` 行の Primary callers 列は両方が編集するため、後からマージするほうで競合する。両方の追記を残す形で解消する
- **`docs/workflow.md`**: #1544 は Label Management の節、#1545 は Orchestration の `/auto` の節を編集するので、同じ行は競合しない

### 既存の関連事項 (この Issue の範囲外)

- Resume mode の手順は、List mode の「Load stop-at setting (List mode only)」ブロックを明示して取り込んでいない (`AUTO_STOP_AT` は List mode の step 7 が使う)。Until mode はこれを明示して取り込んでいる (step 1)。#953 の部分参照の問題と同じ型の既存の隙間で、この Issue では「Assignee warning」だけを明示して参照し、stop-at の扱いは変えない

### 測定

- `grep -n "skip Steps" skills/auto/SKILL.md` — 5 件 (Step 1 の `--batch` 分岐の 4 件と、`## Batch Mode (--batch)` 冒頭の 1 件)。測定範囲: `skills/auto/SKILL.md` のみ。`grep -rn "Steps 2–6" tests/ docs/*.md modules/` は 0 件 (参照しているテスト・文書はない)。main の ca1b5b31 時点
- 担当に関する既存の言及: `grep -rn -i "assignee" skills/auto/SKILL.md scripts/resolve-batch-query.sh` は 0 件 (Issue 本文の `premise` マーカーと一致)

### 検証に関する記録 (SPEC_DEPTH=light のため、振り返りの代わりにここへ記録する)

- **新規分岐ロジックに対する新規テストケース要件**: 新しい分岐を持つのは、Implementation Steps の 1 (`filter-other-assignees.sh` の判定・fail-closed・入力検証)、2 (`resolve-batch-query.sh` の除外)、3 (SKILL.md の Step 1a の 4 分岐・List/Resume/XL の警告・Count mode の除外)。AC5 と AC7 (CI の bats) は、既存スイートの PASS だけでなく、Step 4 に列挙した新規テストケース (`tests/filter-other-assignees.bats` の全件、`tests/resolve-batch-query.bats` の `assignee:` 系、`tests/auto-batch.bats` と `tests/auto.bats` の構造テスト) の追加を前提とする。修正前の実装で FAIL することは、Step 4 の「検出力の確認」で確かめる
- **LLM 層と決定論の層の分担** (`skills/spec/skill-dev-constraints.md` § LLM-assisted Skill Phase Test Strategy): 決定論の層 (除外の判定・実行ユーザーの特定・入力検証・終了コード) は bats の実行テストで確かめる。LLM が実行する層 (Step 1a の 3 択、List/Resume/XL の警告) は SKILL.md の構造テストで語句と順序を確かめ、実際の表示は Post-merge の opportunistic 条件で確かめる
- **文字列照合の verify command の語**: AC3 の `grep "assignee" "skills/auto/SKILL.md"` と AC4 の `grep "assignees" "scripts/resolve-batch-query.sh"` の語は、どちらも現時点では 0 件 (Issue 本文の `premise` マーカーと一致) で、実装が導入する (Step 2 (a) の `--json number,labels,assignees`、Step 3 の Step 1a 以降の全記述)。実装前は FAIL、実装後は PASS になる向きで、常時 PASS にはならない
- **コストの高い・不可逆な Implementation Step はない**: Smoke Test は読み取りのみ。検出力の確認の一時変更はローカルでコミットしない。`spec-approval-needed` マーカーは付けない
- **Post-merge の `opportunistic` 条件**: 「`/auto 123` を実行したとき〜を確認する」という形が `modules/verify-classifier.md` の `opportunistic` の定義 (あるスキルの実行時に確認する) に合う。自動化できる verify command は付けられない (対話の表示を見る条件)

### その他

- **Pre-merge 項目数**: この Spec の Pre-merge は 8 件で、SPEC_DEPTH=light の目安 (5 件) を超える。Issue 本文の `## Acceptance Criteria > Pre-merge` を verify command ごと転記する規則 (件数の一致検査を含む) を優先した。Implementation Steps は目安内の 5 件にまとめた
- **英語のみにするファイル**: `skills/`・`modules/`・`scripts/` に追記する散文・コメントに CJK 文字を入れない (inline code・二重引用符・単一引用符・コードフェンスの中は検出対象外)。`docs/`・`tests/` は対象外だが、`tests/` のコード・コメントは英語にする
- **コミット前の確認**: 新規スクリプトは `chmod +x` してから `git add` する (git mode 100755)
- **実行する確認コマンド**: `bats tests/filter-other-assignees.bats tests/resolve-batch-query.bats tests/auto-batch.bats tests/auto.bats tests/auto-xl-concurrency.bats`、`bats tests/` 全体、`python3 scripts/validate-skill-syntax.py skills/`、`bash scripts/check-allowed-tools.sh`、`bash scripts/check-forbidden-expressions.sh`、`bash scripts/check-translation-sync.sh` (`docs/guide/xl-decomposition.md` の OUTDATED は今回と無関係の既存の差分)、`git diff -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py`、`bash scripts/check-bare-bracket-assertions.sh`
- **bats の書き方の注意** (#1543 のレビューで 2 回重なった問題): 最終行ではない `! grep ...` と `[[ "$stderr" ... ]]` は、失敗しても テストが FAIL しない (または bash 3.2 で ok と報告される)。`|| false` を付けるか、`run grep ...` の後に `[ "$status" -ne 0 ]` で書く。`"$stderr"` を使う行は `scripts/check-bare-bracket-assertions.sh` が見ないので特に注意する
