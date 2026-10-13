# Issue #1525: test: サブエージェント起動への name= の再混入を検出する bats テストを追加

## Overview

#1522 (PR #1524) は、`/review` の Step 10 のサブエージェント (`review-light`・`review-spec`・`review-bug`・`bug-verify`・Parser/Validator Edge Case Pre-check の計測 `edge-case`) と、`modules/verify-executor.md` 経由で起動する rubric の採点役を、`name` を付けずに起動するように変えた。agent teams が有効な対話セッションでは、`name` 付きの起動は in-process の teammate になり、結果が呼び出し元ではなく main セッションへ届く。呼び出し元が fork のサブエージェントだと、結果を受け取れず、止めることもできない。

手順書は散文なので、今後の編集で `name=` が戻っても何も検知されず、#1522 の症状が静かに再発する。#1522 の review では `review-bug` の 2 系統が回帰テストの欠如を指摘した (SHOULD) が、当時は実行環境に `bats` が無く、追加は見送られた。今は実行環境に bats 1.11.1 が入っており (`bats --version` で確認)、ローカルでも実行できる。

この Issue は、回帰テスト `tests/subagent-launch-unnamed.bats` を 1 本新設して CI の bats に載せる。テストは次の 2 点を満たす。

1. `skills/review/SKILL.md` と `modules/verify-executor.md` に、#1522 以前の明示的な名前 (`name="review-light-$NUMBER"`・`rubric-grader-$NUMBER` など) が再び入ると FAIL する
2. 「名前を付けない」旨の説明文 (`` Do not pass a `name` ``・`` without a `name` ``) では FAIL しない

テストは文書の文字列検査で、LLM の応答は扱わない。変更は新規ファイル 1 件のみで、`skills/`・`modules/`・`agents/` の本文は変えない。検査対象は上の 2 ファイルに限る (Issue の Out of Scope: `skills/issue/SKILL.md` Step 12a の名前付き起動は #1521 が意図した形)。

## Changed Files

測定範囲: リポジトリ内で変更するファイル (本 Spec 自身を除く)。新規 1 件、既存 0 件 (測定の基準: `main` の `d839f882`、2026-10-14)。

- `tests/subagent-launch-unnamed.bats`: 新規ファイル。bash 3.2+ 互換 (`mapfile`・連想配列・`grep -P` を使わない)。内容は Notes の「検証済みの試作」を土台にする
- [Steering Docs sync candidate] `docs/structure.md`: 新規ファイルの追加なので、Directory Layout の `tests/` ブロックと Key Files が個別のテストを列挙していないかを `/code` で再確認する。Spec 作成時の確認では変更不要。`tests/` は `<script-name>.bats`・`helpers/`・`fixtures/` を役割で書くだけで、個別の `tests/*.bats` の名前は 0 件 (`grep -n -o -E 'tests/[A-Za-z0-9_.-]+\.bats' docs/structure.md`)。ファイル数は同ファイル自身の Maintenance rule で書かない方針
- [Steering Docs sync candidate] `README.md`: テストの列挙が無いことを `/code` で再確認する。Spec 作成時の確認では `grep -c -i -E 'bats|tests/' README.md` が 0 件で、変更不要

**同期候補の機械的スイープ** (測定コマンド: `grep -n -o -E 'tests/[A-Za-z0-9_.-]+\.bats' docs/tech.md docs/structure.md docs/workflow.md README.md`、範囲: 4 ファイル。`docs/spec/`・`docs/sessions/` は履歴なので除く):

- [Listing-side sub-check] 発火する (新規ファイルの追加)。候補集合は、直下の steering ドキュメントのうち frontmatter の `ssot_for` に `directory-layout` を持つもの (`grep -l "directory-layout" docs/*.md` が `docs/structure.md` の 1 件だけで、先頭の frontmatter の `ssot_for` に載っていることを確認した) と、ルートの `README.md`。上の 2 件を同期候補として挙げた
- [Steering Docs sync candidate (inbound)] 発火しない。Changed Files に SKILL.md・`modules/`・`scripts/` のファイルが無い
- [Outbound pointer sync candidate] 該当なし。新規ファイルは、検査対象の 2 ファイルと `skills/issue/SKILL.md` Step 12a にコメントで言及するだけで、それらの内容は変わらない
- `docs/tech.md`: 個別の `.bats` ファイル名が出るのは経緯の説明 6 件のみ (L143・L145・L150・L151・L152・L205。watchdog の再較正と並列実行の flaky の説明) で、テストの一覧ではない。Testing Strategy 節は個別のテストを列挙しない。変更不要
- `docs/workflow.md`: `bats|tests/` に当たる 2 件 (L56・L58) は patch route の bats 注意書きと operate route の説明で、テストの一覧ではない。変更不要
- `modules/doc-checker.md` と `modules/skill-dev-doc-impact.md` の Change Types: 「Skill の追加・変更・削除」「Agent・共有モジュールの追加・変更・削除」「Script の追加・変更・削除」のいずれにも当たらない (テストの追加は含まれない)。`docs/workflow.md`・`CLAUDE.md` は変更不要
- `docs/migration-notes.md`: CLI の署名・フラグ・引数の変更は無いので対象外
- `docs/ja/*`: `docs/*.md` の変更が無いので同期対象なし (`docs/translation-workflow.md`)
- リポジトリ内の他の参照: `grep -rln -E 'rubric-grader|review-light-\$|bug-verify-\$|edge-case-\$NUMBER|subagent-launch-unnamed' scripts tests .github README.md CLAUDE.md docs/guide docs/workflow.md docs/tech.md docs/structure.md` が 0 件。旧名を探す他のスクリプトも、新しいテスト名を参照する文書も無い

## Implementation Steps

1. `tests/subagent-launch-unnamed.bats` を新規作成する。挿入する文面はすべて英語 (→ 受入条件 1, 2, 3)。全文は Notes の「検証済みの試作」にあり、Spec 作成時に `.tmp/` で bats 1.11.1 により検証した (現行ファイルに対して 15 件 PASS)。`/code` はこれを土台にして、次の構成にする
   - 実ファイルの検査 (3 件): `skills/review/SKILL.md` に明示的な名前が無い。`modules/verify-executor.md` に無い。検査対象の起動箇所 (`subagent_type=` と `Grader sub-agent name and stop`) が 2 ファイルにまだある (空振りの防止。`modules/verify-patterns.md` §26 の「母集団の非空性」にあたる基準点)
   - 検出器の単体テスト (12 件): #1522 以前の形が、実ファイルのコピーへの 1 行の追記で検出される (review-light・review-spec・review-bug の 2 系統・bug-verify・edge-case・rubric-grader)。3 つの規則 (Notes の R1・R2・R3) がそれぞれ単独で効く。「名前を付けない」説明文と、紛らわしい文字列 (`TaskStop(task_id: "<agent ID>")`・結果ファイルのパス・`select(.name=="<job_name>")`・`job_name="x"`・`SKILL_NAME="review"`・`name: review`) は検出されない。対象ファイルが無い・空のときは失敗する
   - 検出器の判定は「追記した行が報告に出るか」だけで行い、ファイル全体の状態に依存させない。実ファイルが汚れたとき (本物の回帰) に、実ファイルの検査 2 件だけが FAIL し、検出器の単体テストへ連鎖しないようにするため
   - fail-safe の挙動 (このテストは CI のゲートとして、手順書の文面を受け入れるか拒否するかを決めるので明示する)
     - 対象ファイルが無い・空: 検出器は status 2 を返し、テストを失敗させる。手順書の移動・改名・切り詰めを「名前なし」として PASS にしない (fail closed)
     - 依存コマンドの失敗: `grep` の終了コードを区別する (0 = 検出、1 = なし、2 以上 = エラー)。エラーは status 2 で失敗させる。`cp`・`printf` の失敗はテストのエラー (`set -e`) として失敗する
     - 特殊文字: `$NUMBER` を含む文字列は単一引用符で書き、展開させない。`name="…"` は二重・単一引用符の両方、`name = "…"` のように `=` の前後に空白がある形、行頭のインデント付き、散文中のインラインのすべてで検出する。CRLF の行末は規則に影響しない (`printf 'name="x"\r\n' | grep -a -c -E …` が 1 を返すことを実測)。多バイト文字を含む行 (`skills/review/SKILL.md` の `前景` を含む行など) は `grep -a` で扱い、`LC_ALL=C` でも結果が変わらない (実測)
     - 入力の大きさ: 対象は 1168 行と 480 行で、行単位の `grep` なので影響しない。rubric の表の行のような長い行も検出の対象になる
   - `@test` の名前に `$`・`"`・`#` を入れない (bats の名前の解釈と TAP 出力を避ける)。一時ファイルは `$BATS_TEST_TMPDIR` に作り、並列実行で衝突させない
2. ローカルで検証する (after 1) (→ 受入条件 2)
   - `bats tests/subagent-launch-unnamed.bats` が全件 PASS する
   - `bats --jobs 4 tests/subagent-launch-unnamed.bats` (並列) と `LC_ALL=C bats tests/subagent-launch-unnamed.bats` も全件 PASS する
   - `bash scripts/check-forbidden-expressions.sh` が成功する。`bash scripts/check-bare-bracket-assertions.sh` の出力に新規ファイルの行が出ない
3. 回帰検知の実効性を確認する (after 1) (→ 受入条件 3)。`.tmp/` 配下に `tests/`・`skills/review/`・`modules/` の最小ツリーを作り、実ファイルのコピーへ旧名を足して実行する。`skills/review/SKILL.md` のコピーには `Task(` の次に `     name="review-light-$NUMBER",` の行を、`modules/verify-executor.md` のコピーには `- **Name**:` の行の `none.` を `` `rubric-grader-$NUMBER`. `` に置き換える。実ファイルの検査 2 件だけが FAIL し (該当行を行番号つきで表示する)、残りは PASS のままであること。確認後に `.tmp/` の一時ファイルを削除し、コミットしない。Spec 作成時に同じ手順で確認済み (Notes)
4. Steering Docs の同期候補を確認する (parallel with 2, 3) (→ SHOULD)。`docs/structure.md` と `README.md` を読み、個別のテストファイルを列挙する記述が無いことを確認する。あれば追記し、無ければ変更しない
5. patch route で commit・push する (`/code` の既定の流れ) (after 2, 3, 4)。push 後の CI (`test.yml`) の bats ジョブが成功することを確認する (→ 受入条件 4)。bats が実行環境に無いときの `command "bats …"` の扱いは `docs/workflow.md` の `/code` の節に従う (CI の bats ジョブの結果で補う)

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/subagent-launch-unnamed.bats" --> 回帰テスト `tests/subagent-launch-unnamed.bats` を新規作成する
- <!-- verify: command "bats tests/subagent-launch-unnamed.bats" --> 現在の `skills/review/SKILL.md` と `modules/verify-executor.md` に対してテストが通る
- <!-- verify: rubric "tests/subagent-launch-unnamed.bats が、skills/review/SKILL.md の Step 10 のサブエージェント起動 (review-light・review-spec・review-bug・bug-verify・edge-case) と modules/verify-executor.md の rubric 採点役の起動について、#1522 以前の明示的な名前 (例: name=\"review-light-$NUMBER\"、rubric-grader-$NUMBER) が再び入ると FAIL する検査を持っている。検査は「name を付けない」旨の説明文 (例: Do not pass a `name`、without a `name`) を誤検出しない" --> 明示的な名前の再混入で FAIL し、「名前を付けない」旨の説明文では FAIL しない
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion,status --jq 'if .[0].status != \"completed\" then \"in_progress\" else .[0].conclusion end'" "success" --> CI (test.yml) の bats ジョブが通る (patch route)

### Post-merge

- `skills/review/SKILL.md` または `modules/verify-executor.md` を変更する Issue で、`tests/subagent-launch-unnamed.bats` が `name` の再混入を FAIL として検出する (再混入が起きなければ SKIPPED のまま据え置く) <!-- verify-type: opportunistic -->

## Notes

**検査の設計** (Spec 作成時に `.tmp/` で試作し、bats 1.11.1 で検証済み。全文は末尾の「検証済みの試作」):

検出器 `explicit_name_lines FILE` は、`grep -a -n -E` で対象ファイルを行単位に走査し、次の規則のどれかに当たる行を `行番号:本文` で出力する。終了コードは 0 = なし、1 = あり、2 = 失敗 (ファイルが無い・空、`grep` のエラー)。

- **R1 (`name` 引数)**: `(^|[^[:alnum:]_])name[[:space:]]*=[[:space:]]*"` と、引用符が `'` の `(^|[^[:alnum:]_])name[[:space:]]*=[[:space:]]*'`。`Task(...)` の例の `name="…",` の行と、散文中のインライン (`each with an explicit` の後ろの `name="edge-case-…"`) の両方を捕まえる
- **R2 (#1522 以前の名前)**: `(review-light|review-spec|review-bug-diff|review-bug-security|bug-verify|edge-case|rubric-grader)-\$NUMBER`。`name=` を伴わない散文 (`` Stop `review-light-$NUMBER` as soon as … ``、`**Name**: ` の行) を捕まえる。結果ファイルは `.tmp/subagent-result-$NUMBER-<label>.md` と番号が先に来るので当たらない
- **R3 (名前指定の停止)**: `TaskStop\(task_id: "[^<]`。名前なしの正しい形は `TaskStop(task_id: "<agent ID>")` で、`[^<]` により当たらない

測定 (測定コマンド: 4 つの正規表現の和集合を `grep -c -E -e … -e …` で数えた。範囲: 各ファイル全体。基準は `main` の `d839f882`):

- 現行: `skills/review/SKILL.md` (1168 行) は 0、`modules/verify-executor.md` (480 行) は 0
- #1522 以前 (`git show 8009f1b2^:<path> | grep -a -c -E …`): `skills/review/SKILL.md` は 17 行 (`Names and Stop` の `TaskStop` 一覧 8 行、`Task(...)` の `name=` の行 5 行、`edge-case` のインライン 1 行、`TaskStop(task_id: "…")` を含む散文 3 行)。`modules/verify-executor.md` は 3 行 (翻訳表の `rubric "text"` の行、`**Name**` の行、`**Stop**` の行)。Issue 本文が挙げる名前 (`review-light`・`review-spec`・`review-bug` の 2 系統・`bug-verify`・`edge-case`・`rubric-grader`) はすべて含まれる
- 規則を絞った理由: 引用符を要求しない緩い `name=` は、`modules/verify-executor.md` の `select(.name==\"<job_name>\")` を含む 4 行 (L94・L100・L108・L135) に当たる (`grep -c 'name=' modules/verify-executor.md` が 4)。R1 は `=` の直後の引用符を要求するので当たらない。左の境界 `(^|[^[:alnum:]_])` は `job_name="x"` のような識別子の一部を除く (`SKILL_NAME="review"` は大文字のため元々当たらない)

不在を確認するテストが空振りしないための基準点 (`modules/verify-patterns.md` §26): (1) 制御群 — 旧名を実ファイルのコピーへ追記すると検出される (検出器が動いている証拠)、(2) 母集団の非空性 — 起動箇所が 2 ファイルにまだある、(3) 実履歴 — #1522 以前の 17 行と 3 行が検出される (Spec 作成時に実測。CI の `actions/checkout` は履歴を持たないので、テストには組み込まない)。

**入力形式 (bats テストの入力)**:

- 検査対象: Markdown の 2 ファイルの全行。検出器は `grep -a -n -E` で行単位に走査する (見出しでは区切らない)
- 検出器の単体テストの入力: 実ファイルのコピー (`$BATS_TEST_TMPDIR` 配下) の末尾に 1 行を `printf '%s\n'` で追記する。追記する行は #1522 以前の実際の行を写した形にする
  - `skills/review/SKILL.md`: `     name="review-light-$NUMBER",` (5 スペース + `name=`。`Task(...)` の例の行そのまま)。review-spec・review-bug-diff・review-bug-security・`bug-verify-$NUMBER-{n}` も同じ形。edge-case は散文中のインライン (`each with an explicit` + バッククォートで囲んだ `name="edge-case-$NUMBER-{n}"`)
  - `modules/verify-executor.md`: `- **Name**: ` で始まりバッククォートで囲んだ `rubric-grader-$NUMBER` を含む行と、`TaskStop(task_id: "rubric-grader-$NUMBER")`
- 追記する行は単一引用符で書き、`$NUMBER` をシェルに展開させない

**設計判断と却下案**:

- 採用: 検出器を bats ファイルの中の関数にする。`scripts/` に新しい検査スクリプトを足すと、`allowed-tools` の更新や `WHOLEWORK_SCRIPT_DIR` のモックが要り、変更が 1 ファイルで済まなくなる。検査は CI のテスト専用で、他から呼ばれない
- 採用: ファイル全体を走査する。見出しで区切る案 (`md_section` で Step 10 だけを取り出す) は、見出し名の変更で空振りする (`docs/tech.md` の BATS Markdown Section Extraction が警告する失敗) うえに、Step 8 の grader の記述や `modules/verify-executor.md` 側の再混入を逃す。全体走査は、現行ファイルで 0 件であることを実測して成立を確認した
- 採用: 検出器の単体テストは、実ファイルのコピーに 1 行を足す形にする。固定の最小ファイルを土台にする案は、実ファイルの大きさ・文字コード・長い行での動作確認を失う。判定を「追記した行が報告に出るか」にすることで、実ファイルが汚れた本物の回帰のとき、実ファイルの検査 2 件だけが FAIL する (Spec 作成時に、旧名を戻したコピーで確認済み: 15 件中 2 件だけが `not ok`)
- 却下 (`git show 8009f1b2^:…` の履歴を使って旧名を検出する): CI の `actions/checkout@v4` は既定で履歴を持たない (深さ 1)。テストが履歴に依存すると CI で失敗する
- 却下 (リポジトリ全体の `Task(... name=...)` を検査する): `skills/issue/SKILL.md` L574・L577・L580 の `name="scope-$NUMBER"`・`name="risk-$NUMBER"`・`name="precedent-$NUMBER"` で FAIL する。#1521 が意図した形で、Issue の Out of Scope でもある (測定コマンド: `grep -rn -E '(^|[^[:alnum:]_])name[[:space:]]*=[[:space:]]*"' skills modules agents --include='*.md'`、範囲: 3 ディレクトリの `*.md`。命中はこの 3 行だけ)
- 却下 (`agents/review-*.md`・`skills/review/workflow-guidance.md` を検査対象に足す): Issue の範囲 (2 ファイル) を超える。`agents/` の frontmatter の `name:` はエージェント定義の名前で、起動時の `name` ではない
- 却下 (引用符を要求しない緩い `name=`): 上の「規則を絞った理由」のとおり、`select(.name==…)` の 4 行を誤検出する

**CI・環境**:

- CI は `ubuntu-24.04` の runner で `apt` の `bats 1.10.0-1` を使う (`test.yml` の run 38397393897 のログで確認、2026-10-14)。ローカルは 1.11.1。試作が使う機能は `run`・`$BATS_TEST_TMPDIR` (1.4.0 以降)・`@test` だけで、既存の 101 ファイルが `BATS_TEST_TMPDIR` を使っている (`grep -l 'BATS_TEST_TMPDIR' tests/*.bats | wc -l`)
- CI は `bats --jobs $(nproc) tests/` で全件を並列に実行するので、新しいテストは自動で載る (`test.yml` の変更は不要)。試作は `--jobs 4` の並列実行と `LC_ALL=C` でも 15 件 PASS を確認した
- CI Dependency Minimum Override (`modules/size-workflow-table.md`): 非該当。新規の自己完結のテストで、`tests/` の並列化フラグの変更も共有 fixture の追加もなく、CI ワークフローの変更もなく、CI 固有の環境に依存しない。Size S のまま patch route
- macOS (BSD grep): ローカルでは未実行。使う構文は POSIX の ERE (`[[:alnum:]]`・`[[:space:]]`・`-E`・`-e`・`-a`) のみ。CI の `macos-shell` ジョブは `bash -n scripts/*.sh` だけで、bats は実行しない

**AC4 の注意** (triage の AC 監査コメントの指摘。Issue 本文は変えない):

- 実装前の基準: `test.yml` の main の最新 run は 38397393897 (headSha `d839f882`、2026-10-13T12:27:15Z、`success`)。つまり AC4 のコマンドは実装前でも `success` を返し、実装コミットの run がまだ始まっていなければ、前のコミットの `success` を読んで PASS しうる
- 影響は小さい。テスト本体の実行は AC2 が直接確かめ、AC4 は CI の bats ジョブ (Ubuntu / bats 1.10.0) でも通ることの補助的な確認にとどまる
- `/verify` での扱い: AC4 を判定するときは、最新 run の `headSha` が実装コミット以降であることも確かめる (`gh run list --workflow=test.yml --branch=main --limit=1 --json headSha,conclusion,status`)。実装コミットの run が `in_progress` のときは PENDING として再実行する

**失敗時の挙動 (Edge cases)**:

| 状況 | 動作 |
|------|------|
| 対象ファイルが無い・空 | 検出器が status 2 を返し、実ファイルの検査が FAIL する (「名前なし」として PASS にしない) |
| `grep` がエラー終了 (終了コード 2 以上) | status 2 で失敗する。「検出なし」と取り違えない |
| 実ファイルに旧名が戻る | 実ファイルの検査 2 件が FAIL し、該当行を行番号つきで表示する。検出器の単体テストは影響を受けない |
| 起動箇所が別ファイルへ移る | 「起動箇所がまだある」の検査が FAIL する。検査対象を更新するまで CI が赤くなる |
| 「名前を付けない」旨の説明文 | 検出されない (`name` が引用符つきの `=` で代入されていない) |
| 検査対象の説明文が `name="…"` を例示する | 検出される。手順書に `name="…"` の例を書かない方針と整合する (LLM が写すおそれがある)。説明文は `name` だけで書く |
| 将来、結果ファイルのパスの並びを `<label>-$NUMBER` に変える | R2 が誤検出する。テストの失敗メッセージが行を示すので、並びを戻すか R2 を更新する |

**Issue 本文との相違 (Conflict with implementation)**:

- なし。Background の主張はすべて現状のコードと履歴に一致する。#1522 以前の名前は `git show 8009f1b2^:…` で確認した (`skills/review/SKILL.md` の L585・L646・L653・L660・L699 の `name=` の行と L547 のインライン、`modules/verify-executor.md` の L303・L304)。#1522 の `review-bug` の指摘と bats の有無は、#1522 の Spec の Retrospective と `bats --version` で確認した。Out of Scope の `skills/issue/SKILL.md` Step 12a の名前付き起動は L574・L577・L580 に現存する

**その他の判定**:

- 監査・調査型の Issue か: いいえ (既存項目の分類ではなく、回帰テストの新設)。ただし本文が引く識別子 (ファイルのパス、見出し `Grader sub-agent name and stop`、`subagent_type=`、旧名) は、現行ファイルまたは履歴で存在を確認した
- fail-safe critical か: 該当する (b: 手順書の文面を受け入れるか拒否するかを決める検証)。edge case の挙動は Implementation Step 1 と上の表に列挙した
- 新規テストケースの要件: 既存のスクリプト・モジュール・スキルに新しい分岐を足す変更は無い (新規ファイルのみ)。このファイル自体が新規テストなので、追加の要件は無い
- bats の自己参照: 検出器は 2 ファイルだけを走査し、bats ファイル自身は走査しないので、旧名を含む追記用の行で自己検出しない。`tests/` を走査して旧名を探すスクリプトは無い (`scripts/check-forbidden-expressions.sh` は非推奨語だけ。試作は非推奨語 0 件を確認済み)。`scripts/check-bare-bracket-assertions.sh` の対象行 (`[[ "$output"` で始まる行) は `|| false` つき
- Smoke Test: 置かない (外部サービスや MCP の呼び出しが無い)
- 費用・不可逆なステップ: 無い (`spec-approval-needed` は不要)。外部サービスへのログインも無い
- `allowed-tools` の影響: `scripts/*.sh` の新規追加も `modules/*.md` の変更も無いので、影響連鎖チェックの対象外。`/code` の既存の `bats` 実行権限で足りる (`docs/workflow.md` の `/code` の節が `bats` を許可済みのパターンに挙げている)
- verify-type の整合: Post-merge の opportunistic 条件は、`modules/verify-classifier.md` の opportunistic の定義 (将来の実行で偶然に判定できる条件) に沿う。再混入が起きなければ SKIPPED のまま残る旨が条件に書かれている。`auto` 条件で verify command の無いものは無い
- Issue 本文の検証コマンド: Issue 本文が SSoT なので、Pre-merge の 4 件は逐語でコピーした (`modules/verify-patterns.md` §18)。件数は Issue と一致 (light の上限 5 件以内)。patch route で `github_check "gh pr checks"` の形は使われていない (AC4 は `gh run list` の形)
- Size の再評価: Changed Files は新規 1 件で Axis 1 は XS-S。Axis 2 は、既存の「散文の手順を bats で固定する」パターンの横展開 (減) と、検出器とその自己検証を持つ新しい構成 (増) が相殺され、Size S のまま (Step 18 で確認)。CI Dependency Minimum Override は非該当

**Uncertainty** (light のためここに記録):

- **macOS (BSD grep) での動作**: ローカルの Linux (GNU grep) では実測したが、BSD grep では未実行。POSIX の構文だけを使うので問題は起きにくいが、CI の bats は Linux のみ。検証方法: macOS の開発環境で `bats tests/subagent-launch-unnamed.bats` を実行する (必須ではない)。影響範囲: Implementation Step 1
- **CI の bats 1.10.0 での実行**: ローカルは 1.11.1 で検証した。使う機能は 1.4.0 以降の基本機能で、既存の 101 ファイルが同じ機能を CI で使っている。検証方法: AC4 の CI の結果。影響範囲: Implementation Step 5
- **AC4 の空振り**: 上の「AC4 の注意」。AC2 が直接の確認で、`/verify` で `headSha` を確かめる。影響範囲: Implementation Step 5

**検証済みの試作 (テストファイル全文)**: Spec 作成時に `.tmp/` で作って検証した (現行ファイルに対して 15 件 PASS、`--jobs 4` と `LC_ALL=C` でも 15 件 PASS、旧名を戻したコピーでは実ファイルの検査 2 件だけが FAIL)。試作は検証後に削除した (コミット対象外)。`/code` はこの内容を `tests/subagent-launch-unnamed.bats` として作成し、実行して確かめる。

```bats
#!/usr/bin/env bats

# Regression guard for unnamed sub-agent launches (Issue #1525, follow-up of #1522).
#
# With agent teams enabled in an interactive session, an Agent/Task launch that carries a
# `name` starts an in-process teammate. Its result goes to the main session instead of back to
# the launching orchestrator, which can neither receive nor stop it when it is itself a forked
# sub-agent. #1522 removed every explicit name from:
#   - skills/review/SKILL.md: the Step 10 sub-agents (review-light, review-spec, review-bug,
#     bug-verify) and the Parser/Validator Edge Case Pre-check measurement sub-agents (edge-case)
#   - modules/verify-executor.md: the rubric grader
# These tests fail when an explicit name comes back in either file.
#
# skills/issue/SKILL.md Step 12a is deliberately not scanned: its named investigation agents
# (scope / risk / precedent) are intended (#1521).
#
# The tests validate documentation text only; no LLM response is mocked.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
REVIEW_SKILL="$PROJECT_ROOT/skills/review/SKILL.md"
VERIFY_EXECUTOR="$PROJECT_ROOT/modules/verify-executor.md"

# Explicit-name shapes (ERE, matched per line):
# 1. a `name` argument with a quoted value: name="x" or name='x'. The left boundary keeps
#    identifiers such as job_name="x" out, and a jq comparison such as .name=="x" has no quote
#    right after its first "=".
NAME_ARG_DQ='(^|[^[:alnum:]_])name[[:space:]]*=[[:space:]]*"'
NAME_ARG_SQ="(^|[^[:alnum:]_])name[[:space:]]*=[[:space:]]*'"
# 2. the names used before #1522, "<label>-$NUMBER". Result files are named
#    .tmp/subagent-result-$NUMBER-<label>.md (the number comes first), so they do not match.
OLD_NAMES='(review-light|review-spec|review-bug-diff|review-bug-security|bug-verify|edge-case|rubric-grader)-\$NUMBER'
# 3. TaskStop addressed by a literal name; the unnamed form is TaskStop(task_id: "<agent ID>")
NAMED_STOP='TaskStop\(task_id: "[^<]'

# explicit_name_lines FILE
#   Prints "LINE:text" for each line of FILE that carries an explicit sub-agent name.
#   Status: 0 = none found, 1 = found, 2 = FILE missing or empty, or grep failed (fail closed,
#   so that a moved or truncated target never passes as "no names").
explicit_name_lines() {
    local file="$1" hits="" rc=0
    if [ ! -s "$file" ]; then
        echo "explicit_name_lines: $file is missing or empty" >&2
        return 2
    fi
    hits="$(grep -a -n -E -e "$NAME_ARG_DQ" -e "$NAME_ARG_SQ" -e "$OLD_NAMES" -e "$NAMED_STOP" "$file")" || rc=$?
    case "$rc" in
        0) printf '%s\n' "$hits"; return 1 ;;
        1) return 0 ;;
        *) echo "explicit_name_lines: grep failed on $file (status $rc)" >&2; return 2 ;;
    esac
}

# copy_with_line SRC LINE
#   Copies SRC into the test's temp dir, appends LINE, and prints the copy's path.
copy_with_line() {
    local copy
    copy="$BATS_TEST_TMPDIR/$(basename "$1")"
    cp "$1" "$copy"
    printf '%s\n' "$2" >> "$copy"
    printf '%s\n' "$copy"
}

# The two helpers judge only the appended LINE, never the whole file, so that a real regression
# in the current files fails the two "current files" tests alone and does not cascade into
# these detector tests.

# assert_flagged FILE LINE: FILE with LINE appended reports LINE.
assert_flagged() {
    local mutant
    mutant="$(copy_with_line "$1" "$2")"
    run explicit_name_lines "$mutant"
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$2"* ]] || false
}

# assert_not_flagged FILE LINE: FILE with LINE appended does not report LINE.
assert_not_flagged() {
    local mutant
    mutant="$(copy_with_line "$1" "$2")"
    run explicit_name_lines "$mutant"
    echo "$output"
    [ "$status" -ne 2 ]
    [[ "$output" != *"$2"* ]] || false
}

# --- the current files -------------------------------------------------------------------

@test "review SKILL.md: no Step 10 sub-agent launch carries an explicit name" {
    run explicit_name_lines "$REVIEW_SKILL"
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "verify-executor.md: the rubric grader launch carries no explicit name" {
    run explicit_name_lines "$VERIFY_EXECUTOR"
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "the scanned files still hold the sub-agent launches this guard covers" {
    # Reference point for the two checks above: without it, a launch section moved to another
    # file would leave them passing against text that no longer contains any launch.
    grep -q 'subagent_type=' "$REVIEW_SKILL"
    grep -q 'Grader sub-agent name and stop' "$VERIFY_EXECUTOR"
}

# --- a reintroduced name is reported (the pre-#1522 forms) -----------------------------------

@test "review SKILL.md: a reintroduced review-light name is detected" {
    assert_flagged "$REVIEW_SKILL" '     name="review-light-$NUMBER",'
}

@test "review SKILL.md: a reintroduced review-spec name is detected" {
    assert_flagged "$REVIEW_SKILL" '     name="review-spec-$NUMBER",'
}

@test "review SKILL.md: reintroduced review-bug names are detected" {
    assert_flagged "$REVIEW_SKILL" '     name="review-bug-diff-$NUMBER",'
    assert_flagged "$REVIEW_SKILL" '     name="review-bug-security-$NUMBER",'
}

@test "review SKILL.md: a reintroduced bug-verify name is detected" {
    assert_flagged "$REVIEW_SKILL" '     name="bug-verify-$NUMBER-{n}",'
}

@test "review SKILL.md: a reintroduced edge-case name is detected" {
    assert_flagged "$REVIEW_SKILL" 'launch a Task sub-agent in parallel, each with an explicit `name="edge-case-$NUMBER-{n}"` (`{n}` = 1 or 2)'
}

@test "verify-executor.md: a reintroduced rubric-grader name is detected" {
    assert_flagged "$VERIFY_EXECUTOR" '- **Name**: `rubric-grader-$NUMBER`, where `$NUMBER` is the calling skill number.'
    assert_flagged "$VERIFY_EXECUTOR" 'TaskStop(task_id: "rubric-grader-$NUMBER")'
}

# --- each rule is live on its own -----------------------------------------------------------

@test "detects any quoted name argument, not only the pre-1522 names" {
    assert_flagged "$REVIEW_SKILL" '     name="my-reviewer",'
    assert_flagged "$REVIEW_SKILL" "     name='my-reviewer',"
    assert_flagged "$VERIFY_EXECUTOR" 'launch the grader with name = "my-grader"'
}

@test "detects a pre-1522 name written without a name argument" {
    assert_flagged "$REVIEW_SKILL" 'Stop `review-light-$NUMBER` as soon as its result is in hand.'
    assert_flagged "$VERIFY_EXECUTOR" 'Give each grader `rubric-grader-$NUMBER-{n}` so that each can be stopped on its own.'
}

@test "detects TaskStop addressed by a literal name instead of the agent ID" {
    assert_flagged "$REVIEW_SKILL" 'TaskStop(task_id: "my-reviewer")'
    assert_flagged "$VERIFY_EXECUTOR" 'TaskStop(task_id: "grader-1")'
}

# --- explanatory text and look-alikes are not reported --------------------------------------

@test "does not flag text that says no name is passed" {
    assert_not_flagged "$REVIEW_SKILL" 'Every Task in Step 10 is launched **without a `name`**.'
    assert_not_flagged "$REVIEW_SKILL" 'Never add a `name` to a Step 10 launch, not even to make a later TaskStop easier.'
    assert_not_flagged "$VERIFY_EXECUTOR" '- **Name**: none. Do not pass a `name` to the grader Agent/Task call.'
}

@test "does not flag look-alike text" {
    assert_not_flagged "$VERIFY_EXECUTOR" 'TaskStop(task_id: "<agent ID>")'
    assert_not_flagged "$REVIEW_SKILL" 'Result file: .tmp/subagent-result-$NUMBER-review-light.md'
    assert_not_flagged "$REVIEW_SKILL" 'Result file: .tmp/subagent-result-$NUMBER-edge-case-{n}.md'
    assert_not_flagged "$VERIFY_EXECUTOR" 'Result file: .tmp/subagent-result-$NUMBER-rubric-grader-{n}.md'
    assert_not_flagged "$VERIFY_EXECUTOR" "--jq '.[] | select(.name==\"<job_name>\") | .state'"
    assert_not_flagged "$VERIFY_EXECUTOR" 'job_name="Run bats tests"'
    assert_not_flagged "$REVIEW_SKILL" 'SKILL_NAME="review"'
    assert_not_flagged "$REVIEW_SKILL" 'name: review'
}

# --- the check itself fails closed ----------------------------------------------------------

@test "a missing or empty target file fails the check instead of passing it" {
    run explicit_name_lines "$BATS_TEST_TMPDIR/does-not-exist.md"
    [ "$status" -eq 2 ]
    : > "$BATS_TEST_TMPDIR/empty.md"
    run explicit_name_lines "$BATS_TEST_TMPDIR/empty.md"
    [ "$status" -eq 2 ]
}
```

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective (検査対象を 2 ファイルに限った判断、AC4 を `gh pr checks` から `gh run list` の形へ変えた経緯) / https://github.com/saitoco/wholework/issues/1525#issuecomment-6147904217
- saito / MEMBER / first-class / ⚠️ Triage AC audit: verify command に問題があります (AC4 の `gh run list` の形が、実装前でも main の最新 run の `success` を読んで PASS しうる点の指摘) / https://github.com/saitoco/wholework/issues/1525#issuecomment-6147904794
- 参考: cutoff (`phase/issue` の付与、2026-10-13T14:29:35Z) より前の triage の AC 監査コメント (saito / MEMBER / https://github.com/saitoco/wholework/issues/1525#issuecomment-6147862473) は `/issue` で消費済みで、Issue 本文の AC4 (`gh pr checks` から `gh run list` への変更) に反映されている

## Code Retrospective

### Deviations from Design
- なし。Notes の「検証済みの試作」をそのまま `tests/subagent-launch-unnamed.bats` として作成した

### Design Gaps/Ambiguities
- 新規テストの検証は、検出器の単体テスト 12 件が実ファイルのコピーへの追記で動く形のため、実装前状態へ戻して FAIL を見る確認の対象外 (対象ファイルを変更する実装ではない)。代わりに Implementation Step 3 の最小ツリーで旧名を足したコピーを実行し、実ファイルの検査 2 件だけが FAIL して残り 13 件は PASS のままであることを確認した
- Steering Docs の同期候補 (`docs/structure.md`・`README.md`) は、個別の `tests/*.bats` の列挙が無いことを再確認し、変更しなかった
- `scripts/check-language-convention.py` の対象は `skills/`・`modules/`・`scripts/` で `tests/` を含まないため、この変更では対象外
- bats は実行環境に導入済み (1.11.1) なので、AC2 (`command "bats …"`) はローカルで実行して PASS を確認した。bats-absent の除外は発火しない

### Rework
- なし

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の試作を変更せずに採用した (15 件 PASS。通常実行・`--jobs 4`・`LC_ALL=C` のいずれも同じ)
- AC1〜AC3 は Step 10 で Issue 本文のチェックボックスを `[x]` にした。AC3 (rubric) は、旧名の再混入で実ファイルの検査 2 件が FAIL し、説明文・紛らわしい文字列は検出されないことを実測して判断した

### Deferred Items
- AC4 (`github_check "gh run list" … "success"`): 実装コミットの push 前は評価できないため未チェックのまま。push 後の CI の結果を `/verify` で判定する
- Post-merge の opportunistic 条件: `skills/review/SKILL.md` または `modules/verify-executor.md` を変更する将来の Issue まで SKIPPED のまま

### Notes for Next Phase
- AC4 を判定するときは、最新 run の `headSha` が実装コミット以降であることを確かめる (`gh run list --workflow=test.yml --branch=main --limit=1 --json headSha,conclusion,status`)。`in_progress` なら PENDING として再実行する
- macOS (BSD grep) での実行は未確認 (必須ではない)。CI の bats は Ubuntu の 1.10.0
