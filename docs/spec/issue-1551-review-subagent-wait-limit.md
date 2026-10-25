# Issue #1551: review: サブエージェントの結果が届かないときの待機上限と縮退手順を定め、#1522 対処後の再発原因を特定

## Overview

`/review` の Step 10 が起動するサブエージェント (`review-light`・`review-spec`・`review-bug`・10.3 の検証・Edge Case Pre-check の計測) の結果が届かないときに、待機の上限と縮退の手順を決まった形で実行し、縮退したことをレビュー結果に残す。あわせて、#1481・#1522 の対処後もなお結果が届かなかった原因を特定する (結果は `## Notes` の「原因の特定」)。

原因は 2 つが重なったことである。(1) PR #1549 の `/review --full` では、5 本の `Agent` 呼び出しがすべて `run_in_background` を省略しており、ハーネスの既定 (background) で起動された。このとき戻り値は `Async agent launched successfully` だけで、結果は載らない。(2) 結果ファイル経路 (#1522) には待機の上限が無く、オーケストレーターは起動の約 75 秒後に見切って自前レビューに縮退し、作業の途中だった 5 本を `TaskStop` した。サブエージェントが完走するには 94〜294 秒かかる (前景で完走した 17 本の実測) ので、結果ファイルが間に合う余地は構造上なかった。

方針は次の 3 点。

1. **防ぐ**: Step 10 の `Task(...)` をすべて `run_in_background=false` で起動すると明記する (起動例にも入れる)。前景で起動すれば結果は戻り値に載る
2. **上限付きで待つ**: 戻り値に結果が載らなかったとき (対話セッションの fork のように前景を指定しても background になる環境、または指定漏れ) は、新規スクリプト `scripts/wait-subagent-results.sh` で fan-out ごとに 1 回だけ、上限 480 秒の前景待機をしてから代替レビューに縮退する。待機の前に止めない・代替しない
3. **残す**: 縮退したサブエージェントごとに固定書式の 1 行 (`- Sub-agent degradation: ...`) を作り、Review Response Summary と Spec の review retrospective に残す

## Reproduction Steps

1. `run-review.sh` (headless、`--non-interactive`、Claude Code 2.1.310) 経由で `/review N --full` を実行する。Workflow 経路は使わず、静的な `Task(...)` の構成で動く (headless では `skills/review/workflow-guidance.md` L50 により、`capabilities.workflow: true` でも静的な Task に戻る)
2. `/review` が Step 10 で `Agent` (SKILL.md の疑似記法では `Task(...)`) を `run_in_background` なしで起動する (PR #1549 では 5 本: `review-spec`、`review-bug` ×2、エッジケース計測 ×2)
3. どの起動の戻り値も `Async agent launched successfully` だけで、結果は載らない (サブエージェント側の記録は `requestShape: background`)
4. オーケストレーターは結果ファイルを 3 回確認し (起動の 28・58・66 秒後)、まだ無いので 75 秒後に自前レビューへ縮退して 5 本を `TaskStop` する。サブエージェントは作業の途中で止まり、結果ファイルは書かれない

再現の頻度: 引数を省略した起動は、ローカルに transcript が残る review 22 セッション (2026-10-02〜10-24) のうち 2 回 (2026-10-16 の PR #1532、2026-10-24 の PR #1549)。

## Root Cause

要因は 3 つで、根拠は `## Notes` の「原因の特定」にまとめた。

- **起動形態が指定されていない**: `skills/review/SKILL.md` の前景の規則 (L39・L465) は「`run_in_background: true` を付けない」「結果を同じターンで使う」とだけ言い、Step 10 の `Task(...)` の起動例 (10.0・10.2・10.3) にも `run_in_background` が無い。`run_in_background: false` を名指しするのは Workflow 経路の退避先を述べる `skills/review/workflow-guidance.md` L50 だけである。引数を省略した起動は、公式ドキュメントどおり background が既定であり、headless の `claude -p` でも例外ではない (ローカルに残る 57 本のうち、`false` を指定した 51 本は前景、省略した 6 本は background で、例外が無い)
- **待機の上限が無い**: #1522 の結果ファイル経路は、代替レビューの所要時間をそのまま猶予とし、代替後に 1 回確認して止める。代替が数十秒で済めば、猶予も数十秒になる。サブエージェントが結果ファイルを書くのは作業の最後なので、94〜294 秒かかる実行には間に合わない
- **縮退が記録されない**: Review body の `Sub-agent fallback` の 1 行しか残らず、Review Response Summary にも Spec の review retrospective にも載らない。PR #1549 では retrospective に文章で書かれただけで、固定書式が無いため後から集計できない

#1481・#1522 の対処は退行しておらず、PR #1549 のセッションでも設計どおりに動いた。この事象は、それらの対処が扱わない経路 (起動形態の指定と、結果ファイル経路の待機時間) で起きた。

## Changed Files

測定範囲: リポジトリ内で変更するファイル (本 Spec 自身を除く)。既存 5 件、新規 3 件。同期候補の掃引は `grep -rl -- "<keyword>" docs/ tests/ scripts/ modules/` (`docs/spec/` と `docs/sessions/` は履歴なので除く)。

- `scripts/wait-subagent-results.sh`: 新規。`chmod +x` してから `git add` する (git mode 100755)。bash 3.2+ 互換 (`mapfile`・連想配列・`${var,,}`・`((x++))` を使わない。算術は `x=$((x+1))` の形)
- `tests/wait-subagent-results.bats`: 新規。上のスクリプトの分岐を検証する (新しい分岐ロジックに対する新規テストケース)
- `tests/review-subagent-wait.bats`: 新規。`skills/review/SKILL.md` の構造を検証する回帰ガード (`tests/subagent-launch-unnamed.bats` と同じ型)
- `skills/review/SKILL.md`: 10 か所 (Implementation Step 3 の E1〜E10)
- `docs/tech.md`: Architecture Decisions の `/review` のサブエージェント記述 (L71) の末尾に 2 文を足す [Steering Docs sync candidate]
- `docs/ja/tech.md`: 同じ内容を日本語で足す (L62、`docs/translation-workflow.md` の同期手順) [Steering Docs sync candidate]
- `docs/structure.md`: Key Files の Scripts の「Process management」に新スクリプトの 1 行を足す (`wait-ci-checks.sh` の次、L242 付近) [Steering Docs sync candidate]
- `docs/ja/structure.md`: 同じ 1 行を日本語で足す (L235 付近) [Steering Docs sync candidate]

**同期候補の掃引と「変更不要」の裏取り** (キーワード: `run_in_background`、`wait-subagent-results`、`Sub-agent degradation`、`Sub-agent Result Fallback`、`subagent-result`。`Sub-agent Names and Stop` は `docs/ tests/ scripts/ modules/` に 0 件):

- `run_in_background`: 8 件 (しきい値の 8 を超えない)。`docs/reports/` の 3 件は履歴の報告書で変更しない。`tests/review.bats` は `前景`・`run_in_background`・`timeout`・`600000` の存在だけを見るので、追記では壊れない (実測: 関連 4 ファイルのベースライン 65 件が PASS)。`tests/code.bats`・`modules/test-runner.md` は `/code` と bats の実行の話で無関係。`scripts/guard-prefix.sh` と `modules/execution-context.md` は共有層で、変更しない (Notes の「範囲外」)
- `wait-subagent-results`・`Sub-agent degradation`: 0 件 (この Issue が導入する名前なので衝突しない)
- `Sub-agent Result Fallback`: `modules/execution-context.md` (Precedents の 1 件) と `docs/reports/ja/single-agent-loop-assessment-2026-10-24.md` (報告書)。見出しは残すので変更しない
- `subagent-result`: `docs/tech.md`・`docs/ja/tech.md` (上で変更)、`tests/subagent-launch-unnamed.bats` (名前の混入を見るガードで、結果ファイル名は検出対象外のため変更不要)、`modules/verify-executor.md` (grader の起動手順。範囲外)
- [Listing-side sub-check] 発火する (新規ファイルを足すため)。候補は `ssot_for: directory-layout` を宣言する `docs/structure.md` と、ルートの `README.md`。`docs/structure.md` は Scripts の 1 行を足す。`README.md` は `grep -c -E 'scripts/|\.sh' README.md` が 0 で、スクリプトを列挙していないので変更しない。Directory Layout の木は `tests/` と `scripts/` を総称で書き、ファイル数のコメントも無い (`docs/structure.md` の保守規則) ので変更しない
- [Outbound pointer sync candidate] `skills/review/SKILL.md` の pointer を調べた。`modules/execution-context.md` § "Re-invocation Guarantee and Notification-Dependent Waiting" と `modules/verify-executor.md` は既存の節名を指すだけで、その節の内容はこの変更で変わらない。`skills/review/workflow-guidance.md` L50 は「Workflow 経路を使えないとき、`run_in_background: false` の静的 Task に戻る」と述べ、新しい起動例と矛盾しない (変更不要)。`agents/review-*.md` の `## Deliver Results` は結果ファイルの書き方を述べるだけで変更不要
- `README.md`・`docs/workflow.md`・`CLAUDE.md` (`modules/skill-dev-doc-impact.md` の Change Types の対象): `grep -c -E 'subagent-result|Sub-agent Result Fallback|run_in_background|TaskStop|Task\('` が 3 ファイルとも 0 で、スキルの追加・削除・役割の変更も無いので変更不要
- `docs/migration-notes.md`: 既存スクリプトの CLI・フラグ・引数順の変更が無いので対象外
- `docs/ja/*`: 翻訳元の `docs/tech.md`・`docs/structure.md` の変更に伴う `docs/ja/tech.md`・`docs/ja/structure.md` だけが同期対象

## Implementation Steps

1. **待機スクリプトとそのテストを作る** (→ 受入条件 2・4)
   - `scripts/wait-subagent-results.sh`: ヘッダーコメント (用途、`Usage: wait-subagent-results.sh [--interval <sec>] <timeout-sec> <result-file>...`、出力、終了コード、`Bash 3.2+ compatible.`)、`set -euo pipefail`。サブエージェントの結果ファイルがすべて「存在し、空でない通常ファイル」になるか、`<timeout-sec>` 秒が経つかの早い方まで、前景でブロックする
     - 出力: stdout に引数の順で 1 ファイル 1 行、`ready <path>` または `missing <path>` (出力は待機の終了時にまとめて出す)。stderr に最後の 1 行 `wait-subagent-results: <ready>/<total> ready after <N>s (limit <L>s)` (`<N>` は `SECONDS` で測った経過秒、`<L>` は切り詰め後の上限)
     - 終了コード: 0 = すべて ready、1 = 使い方の誤り、2 = 上限に達しても 1 つ以上が missing
     - 定数: 上限の切り詰め値 `MAX_TIMEOUT_SEC=540` (Bash ツールの 600000 ms の天井の内側)、既定の確認間隔 `5` 秒 (`--interval` で変える。テスト用)
     - **分岐の全列挙** (`skills/spec/skill-dev-constraints.md` の「ブランチ分岐ロジックの挙動全列挙」に従う):

       | 分岐 | 条件 | 動作・出力 | 終了コード | 監視の継続 |
       |------|------|-----------|-----------|-----------|
       | 引数: `--interval` | 値が 1 以上の整数 | 確認間隔を設定する | - | - |
       | 引数: `--interval` の誤り | 値が無い、整数でない、0 | stderr に理由と usage を出し、stdout は空 | 1 | 終了 |
       | 引数: 未知のオプション | timeout より前の `--*` で `--interval` 以外 | 同上 | 1 | 終了 |
       | 引数: timeout の誤り | 無い、`^[0-9]+$` に合わない (負数・小数・空文字・非数) | 同上 | 1 | 終了 |
       | 引数: timeout が大きい | 540 を超える (桁数が 5 を超える値も含む。`10#` 付きで 10 進に解釈し、先頭の 0 を 8 進にしない) | 540 に切り詰め、stderr に `wait-subagent-results: Warning: timeout <given> clamped to 540` | - | 続行 |
       | 引数: ファイルが無い | timeout の後に 1 つも無い | usage | 1 | 終了 |
       | 引数: 改行を含むパス | どれかのパスに改行 | usage (`path must not contain a newline`)。出力が行単位なので受け付けない | 1 | 終了 |
       | 判定: 全件 ready | すべて `[ -f ]` かつ `[ -s ]` | `ready` を引数順に出し、summary を stderr に出す | 0 | 終了 |
       | 判定: 未達があり期限内 | 経過秒 < timeout | `sleep` を `min(interval, 残り秒)` で 1 回入れて再判定 | - | 継続 |
       | 判定: 未達があり期限到達 | 経過秒 >= timeout | `ready`/`missing` を引数順に出し、summary を出す | 2 | 終了 |
       | timeout が 0 | 判定を 1 回だけ行う (`sleep` しない) | 上の「全件 ready」または「期限到達」と同じ | 0 / 2 | 終了 |
       | error path: `sleep` の失敗 | 割り込み・コマンド無し | 無視して再判定する (打ち切りは時計で行うので、ループは期限で必ず終わる) | - | 継続 |
       | timeout 条件 | `SECONDS` (bash 組み込み) で測った経過秒が timeout に達する | 上の「期限到達」 | 2 | 終了 |
       | kill 条件 | 無い (子プロセスは `sleep` だけ)。SIGINT・SIGTERM は既定動作で終了し、後始末する一時ファイルも無い | - | シェルの既定 | 終了 |

     - **fail-safe critical の扱い**: このスクリプトの失敗を、呼び出し側 (`skills/review/SKILL.md`) は「待たずに縮退する」側に倒す (終了コードが 0・2 以外、実行できない、ツールがバックグラウンドへ移した、のどれでも `wait-not-run`)。スクリプトの側では、空文字のパスは `missing` として出し (`[ -s "" ]` が偽)、`>`・`"`・CRLF・多バイト文字を含むパスは `printf '%s %s\n'` でそのまま出して判定はクォートして行う。ファイルでなく directory のパスは `missing`。同じパスの重複は引数の数だけ出す
   - `tests/wait-subagent-results.bats` (`bats_require_minimum_version 1.5.0`、stdout と stderr を分けるので `run --separate-stderr`、`PROJECT_ROOT` はほかの bats と同じ求め方)。時間のかかるテストは `--interval 1` と 2〜3 秒の timeout にし、`sleep` はモックしない (モックすると時計で打ち切るループが空回りする)。入力の形式: 引数は `[--interval N] <timeout> <file>...`、stdout は `ready <path>` / `missing <path>` の行、stderr の最終行は `wait-subagent-results: R/T ready after Ns (limit Ls)`。ケース:
     1. 全件が最初から ready: 終了コード 0、stdout が引数順の `ready` 行、stderr の summary が `3/3 ready after 0s` 形式
     2. 一部が missing で timeout 2: 終了コード 2、`ready`・`missing` が引数順に混ざる、経過が 2 秒以上 6 秒未満
     3. 待機中にファイルが現れる (背景で 1 秒後に作る): 終了コード 0、経過が timeout 未満
     4. 空のファイルは missing (timeout 0): 終了コード 2
     5. directory のパスは missing (timeout 0): 終了コード 2
     6. timeout 0 は 1 回だけ判定して `sleep` せず、missing なら 2 秒未満で終了コード 2
     7. 引数なし → 終了コード 1、stderr に usage、stdout は空
     8. timeout だけでファイルが無い → 1
     9. timeout が非数・負数・小数・空文字 → それぞれ 1
     10. `--interval` の値が無い・0・非数 → 1。未知のオプション → 1
     11. 540 を超える timeout は切り詰められる (全件 ready にして即終了させ、stderr に `clamped to 540` と summary の `limit 540s`)。`010` のような先頭 0 の値が 10 秒として扱われること (8 秒ではない) を、全件 ready の summary の `limit 10s` で確かめる
     12. 空白・`>`・`"`・多バイト文字を含むパスがそのまま出る
     13. 改行を含むパス → 1
     14. 確認間隔が残り時間を超えない: `--interval 5` と timeout 1 で、終了までが 3 秒未満
     15. 同じパスの重複は引数の数だけ出る
   - 新規スクリプトは `scripts/` の他のスクリプトから呼ばれない (呼ぶのは `skills/review/SKILL.md` の散文だけ) ので、`WHOLEWORK_SCRIPT_DIR` のモック追加は要らない
2. **SKILL.md の構造テスト `tests/review-subagent-wait.bats` を先に作る** (Step 1 の後) (→ 受入条件 2・3・4)。SKILL.md の変更に依存するケースが、変更前の `skills/review/SKILL.md` に対して FAIL することを確かめてから Step 3 を適用する (実装前の失敗の確認。`git stash` も写しも要らない)。`tests/subagent-launch-unnamed.bats` の型 (検出関数、現行ファイルへの検査、検出力の確認、検出器が閉じる側に倒れる) と `tests/helpers/markdown-section.bash` の `md_section` を使う。区間は `## Step 10:` の節 (終端は `## Step 11:`) など、`md_section` で取り、空の節で素通りしないよう代入で受ける。ケース:
   1. Step 10 のすべての `Task(` の起動例が `run_in_background=false` を持つ (`Task(` の行から閉じの `)` の行までを走査する検出関数。起動例が 5 つ以上あることも確かめて、見出しの改名で素通りしないようにする)
   2. 検出関数が `run_in_background=false` の欠けた起動例を報告する (現行ファイルの写しから 1 行を消して検査し、その起動例だけが報告される)
   3. Edge Case Pre-check の手順 3 の文が `run_in_background=false` を含む
   4. `**Launch mode.**` の段落が、引数を省略すると background になることと `run_in_background=false` を述べる
   5. `**Wait limit.**` の段落が、`480`、`wait-subagent-results.sh 480`、`timeout: 540000`、「once」、`wait-limit-exceeded`、`wait-not-run` を含む
   6. 上限の数値の整合: SKILL.md の例の `480` が、スクリプトの切り詰め値 `540` 以下であり、`timeout: 540000` (ms) が `480` 秒より大きい
   7. `allowed-tools` の frontmatter に `scripts/wait-subagent-results.sh:*` がある
   8. Step 10 の `Sub-agent Result Fallback` に固定書式 `- Sub-agent degradation: {label} ({aspect}): {disposition}; reason={reason}; waited={N}s` がある
   9. Step 14 の要約テンプレートに `### Sub-agent Degradation` と省略の規則があり、Retrospective に `Sub-agent degradation:` の複写の指示がある
   10. 古い文 `which is what gives its result file time to appear` が残っていない (新しい手順と矛盾する文の再混入を防ぐ。節の取得が失敗したときに通らないようにする)
   11. `Never wait for a result` が SKILL.md にちょうど 1 回だけある (premise の前提が崩れていないこと)
   12. 検出器が閉じる側に倒れる: 存在しない・空のファイルを渡すと失敗する
3. **`skills/review/SKILL.md` を編集する** (Step 1・2 の後) (→ 受入条件 2・3・4)。Step 2 のテストが PASS になるまで適用する。文面はすべて英語 (CJK 文字を入れない)。半角の `!` を本文に入れない。`Never wait for a result` の文は 1 か所のまま残す (Issue の premise マーカーが `grep_count` で 1 を見る)。編集前に `grep -n -E 'wait limit|upper bound|maximum wait|wait (up to|at most)' skills/review/SKILL.md` が 0 件であることを確かめる (受入条件 2 の grep が実装前は偽である基準線)。行 39 (`前景` を含む唯一の行) は編集しない
   - **E1 (frontmatter `allowed-tools`、行 5)**: `${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh:*, ` の直後に `${CLAUDE_PLUGIN_ROOT}/scripts/wait-subagent-results.sh:*, ` を足す
   - **E2 (`## Non-Interactive Mode Behavior`)**: 入れ子の箇条書き「The timeout must fit inside the tool's 600000 ms ceiling.」(行 40) の直後に、同じ字下げ (2 スペース) で次の箇条書きを足す

     ```text
       - **Pass `run_in_background: false` on every Step 10 sub-agent launch (Issue #1551).** Not setting `run_in_background: true` is not the same thing: an Agent/Task call that leaves the parameter out starts the sub-agent in the background by default, also in headless `claude -p`, and its return value is then only an acknowledgment (`Async agent launched successfully`) while the result would arrive as a later notification that this session never receives. The one bounded wait described under "Wait limit" in Step 10 comes before the "Sub-agent Result Fallback" named above, and a sub-agent is never stopped or substituted before that wait has run or has been found impossible.
     ```
   - **E3 (Step 10 の `**Foreground dispatch reminder ...**` 段落)**: 末尾の文 `When a result is not in hand, follow "Sub-agent Result Fallback" below instead of waiting.` を次に置き換える

     ```text
     Start every `Task(...)` with `run_in_background=false` (see "Launch mode" below). When a result is still not in hand, take the one bounded wait described under "Wait limit" below and then follow "Sub-agent Result Fallback"; there is no other way to wait.
     ```
   - **E4 (`### Sub-agent Names and Stop`)**: 最初の段落 (`Every \`Task(...)\` launched in Step 10 ... is launched **without a \`name\`** ...`) の直後、`**Result file.**` の前に、次の段落を足す。見出しの文言 `Sub-agent Names and Stop` は変えない (多くの箇所が名前で参照する)

     ```text
     **Launch mode.** Every `Task(...)` launched in Step 10 passes `run_in_background=false` (Issue #1551). Claude Code starts a sub-agent in the background when the parameter is left out, also in headless `claude -p`; the launch call then returns only an acknowledgment (`Async agent launched successfully`), and the result would arrive as a later notification that a session without a re-invocation guarantee never receives. The review of PR #1549 left the parameter out of all five launches, and none of their return values carried a result. With `run_in_background=false` the call returns when the sub-agent has finished, and its return value carries the result (the normal case of "Collecting a result"). Launch the sub-agents of one fan-out in a single message so that they still run in parallel. A rule that only forbids `run_in_background: true` does not select the foreground, because leaving the parameter out selects the background. Where the harness runs a launch in the background anyway (for example a forked `/review` started from an interactive session), the result file and the "Wait limit" below take over.
     ```
   - **E5 (`**Collecting a result**` の番号付き一覧の 2 と 3)**: 次に置き換える (1 は変えない)

     ```text
     2. The return value carries no result (a background acknowledgment, a teammate start, empty output, or an error) → `Read` its result file and use it if it exists. For the sub-agents of the same fan-out whose file does not exist yet, take the one bounded wait described under "Wait limit" below, then `Read` those files once more.
     3. Neither yields a result → for `review-light`, `review-spec`, and `review-bug`, apply "Sub-agent Result Fallback" below, which degrades to the orchestrator's own review and records the degradation. A 10.3 verification sub-agent whose verdict is missing leaves its issue unverified (10.3), and an Edge Case Pre-check measurement sub-agent whose result is missing counts as no findings; both are recorded as degradations too (item 6 of "Sub-agent Result Fallback").
     ```
   - **E6 (`Never wait for a result: ...` の段落と、その直後)**: 既存の段落の末尾に 1 文を足し、直後に `**Wait limit.**` の段落を足す (この Spec では内側にコードフェンスを含むため、外側を 4 つのバッククォートで示している。SKILL.md には外側のフェンスを書かない)

     ````text
     Never wait for a result: do not end the turn to wait, and do not poll in a loop. A sub-agent that is still running may keep working while the orchestrator does other work. The only wait is the one bounded call described next.

     **Wait limit.** A sub-agent writes its result file as its last action, after its whole review, and a review sub-agent needs a few minutes for that (up to about 300 seconds in the runs measured for Issue #1551). When, after the launch calls of a fan-out have returned, some sub-agents still have no result, first finish every other piece of work that does not need their results. Then wait once, for at most 480 seconds (the wait limit), with one plain foreground Bash command, passing `timeout: 540000` (inside the tool's 600000 ms ceiling) and naming every result file of the fan-out that does not exist yet, with the PR number substituted literally:

     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/wait-subagent-results.sh 480 .tmp/subagent-result-$NUMBER-<label>.md [more result files of the fan-out ...]
     ```

     The script returns as soon as every listed file exists and is not empty, and otherwise when the wait limit is reached. It prints `ready <path>` or `missing <path>` for each file, a summary line `wait-subagent-results: {ready}/{total} ready after {N}s (limit {L}s)` on standard error, and exits 0 (all ready), 2 (at least one file still missing at the limit), or 1 (usage error). `Read` each `ready` file as that sub-agent's result. The limit counts waits as well as seconds: one wait per fan-out, never a second wait for the same fan-out, no loop around the call, and no `sleep` of your own. No sub-agent is stopped, substituted, or given up on before this wait has run or has been found impossible. For each `missing` file, and for every file of a wait that could not be run (the script is missing or not executable, it exits 1, or the tool moved the command to the background), do not wait any longer: go to "Sub-agent Result Fallback" at once. The reason recorded there is `wait-limit-exceeded` for a `missing` file and `wait-not-run` for a wait that could not be run.
     ````
   - **E7 (`### Sub-agent Result Fallback`)**: 4 か所
     - 冒頭の段落を次に置き換える

       ```text
       Even with `run_in_background=false`, the harness decides how a launch returns: an Agent/Workflow call can still come back as a background teammate/task whose result arrives only as a later completion notification (a forked `/review` started from an interactive session, or a launch that left the parameter out). A fork-executed Skill has no re-invocation guarantee (`${CLAUDE_PLUGIN_ROOT}/modules/execution-context.md` § "Re-invocation Guarantee and Notification-Dependent Waiting"), so that notification never reaches the review and the Review Response Summary is never posted (Issue #1481). Asking the orchestrator to "wait synchronously" is therefore not enough. When a result is not in hand, the orchestrator first looks for the sub-agent's result file, then takes the one bounded wait of "Wait limit", and only for a sub-agent that still has no result does it perform that review itself and record the degradation. A substitute review alone throws away the findings the sub-agent had already produced (Issue #1522), and a substitute review that starts before the sub-agent has had its wait throws away the sub-agent's whole run (Issue #1551).
       ```
     - 項目 2 (`**Collect from the result file**`) の `Read the sub-agent's result file (labels per "Sub-agent Names and Stop").` の直後に ` Do this after the one bounded wait of "Wait limit" has run for the fan-out (or has been found impossible).` を足す
     - 項目 3 (`**Substitution**`) の最後の文 `Do not stop the sub-agent yet: it keeps working while the orchestrator does this, which is what gives its result file time to appear.` を `Do not stop the sub-agent yet: item 4 reads its result file once more after the substitution, because the file can still appear while the orchestrator works.` に置き換える (古い文を残すと、待機が先に走る新しい手順と矛盾する)
     - 項目 5 の次に、次の項目 6 を足す

       ```text
       6. **Record the degradation (fixed format)**: for every Step 10 sub-agent whose result could not be obtained and was therefore substituted or given up (the `Sub-agent fallback` cases of item 5, a missing 10.3 verdict, a missing Edge Case Pre-check measurement), keep one line in exactly this format:

          `- Sub-agent degradation: {label} ({aspect}): {disposition}; reason={reason}; waited={N}s`

          `{label}` is the result-file label from "Sub-agent Names and Stop" (`review-light`, `review-spec`, `review-bug-diff`, `review-bug-security`, `bug-verify-{n}`, `edge-case-{n}`). `{aspect}` names its perspective in a few words (for example `spec and documentation review`, `diff bug scan`, `security scan`, `all 4 aspects`, `edge case execution`, `bug issue verification`). `{disposition}` is `substituted by orchestrator`, `treated as no findings`, or `issue passed through unverified`. `{reason}` is `wait-limit-exceeded` (the bounded wait ran to its limit with the file still missing) or `wait-not-run` (the wait could not be run). `{N}` is the whole seconds the bounded wait took (the `after {N}s` of the summary line the script prints on standard error), or `0` for `wait-not-run`. Step 14.1 puts these lines verbatim under `### Sub-agent Degradation` in the Review Response Summary, and the Retrospective copies them verbatim under `### Recurring issues` in the Spec's `## review retrospective`. The line prefix `- Sub-agent degradation:` stays verbatim even when the rest of the summary is localized. A run without any degradation writes no such line and no such section. In `--review-only` mode Step 14 and the Retrospective are skipped, so the `Sub-agent fallback` lines of the Review body are the only record there.
       ```
   - **E8 (起動例と参照の括弧書き)**: 次の 5 つの `Task(` の例 (10.0 の `review-light`、10.2 の `review-spec`・`review-bug` ×2、10.3 の検証) すべてで、`subagent_type=...,` の行の直後に、同じ字下げ (5 スペース) で `run_in_background=false,` の行を足す。Parser/Validator Edge Case Pre-check の手順 3 の文は `each without a \`name\` and with its own result file` を `each without a \`name\`, with \`run_in_background=false\`, and with its own result file` に直す。「(return value, then result file)」型の括弧書き 4 か所を、末尾に `, then the one bounded wait` を足した形にする: Edge Case Pre-check 手順 3 の末尾 (`(return value, then result file)`)、10.0 手順 5 (`(return value, then \`.tmp/subagent-result-$NUMBER-review-light.md\`)`)、10.2 手順 4 (`(return value, then its result file)`)、10.3 手順 3 (`(return value, then the result file)`)
   - **E9 (Step 14.1 の要約テンプレート)**: テンプレート (` ```markdown ` のフェンス) の `### Claude Review Response` の表の直後、`### Lightweight Re-check Results` の前に、見出しレベル `###` で次を足す。テンプレートの後ろ (`**If no acceptance criteria updates (Step 13 skipped)**: omit that section.` の次) に、省略の規則の 1 行を足す

     ```markdown
     ### Sub-agent Degradation

     - Sub-agent degradation: review-spec (spec and documentation review): substituted by orchestrator; reason=wait-limit-exceeded; waited=480s
     ```

     ```text
     **If no Step 10 sub-agent result was substituted or lost** (no `Sub-agent degradation:` line from item 6 of "Sub-agent Result Fallback"): omit the Sub-agent Degradation section. Otherwise copy the lines verbatim; the `- Sub-agent degradation:` prefix stays even when the heading is localized.
     ```
   - **E10 (`## Retrospective` の Steps の 2)**: 末尾に次の文を足す

     ```text
     If Step 10 produced any `Sub-agent degradation:` lines (item 6 of "Sub-agent Result Fallback"), copy them verbatim as bullets under `### Recurring issues`, so that `/verify` can see them.
     ```
4. **文書を同期する** (Step 2・3 と並行可) (→ 受入条件 4)。英語の変更と、`docs/translation-workflow.md` の手順に沿った日本語ミラーの変更を同じ変更に入れる
   - `docs/tech.md` Architecture Decisions の `/review` の記述 (L71) の末尾 (`... is stopped with \`TaskStop\` by agent ID.` の後) に足す: `Step 10 launches also pass \`run_in_background=false\`: the harness starts a sub-agent in the background by default, also in headless \`claude -p\`, and a background launch returns only an acknowledgment (Issue #1551). A result that is still missing is waited for once, for at most 480 seconds (\`scripts/wait-subagent-results.sh\`), before the orchestrator substitutes for the sub-agent, and every substituted or lost result is recorded in the Review Response Summary and the Spec's review retrospective.`
   - `docs/ja/tech.md` (L62): 同じ内容を日本語で足す
   - `docs/structure.md` の Scripts の「Process management」(`wait-ci-checks.sh` の次) に足す: `- \`scripts/wait-subagent-results.sh\` — bounded foreground wait for sub-agent result files (\`.tmp/subagent-result-<N>-<label>.md\`): \`[--interval SEC] <timeout-sec> <result-file>...\` prints \`ready <path>\` / \`missing <path>\` per file and exits 0 (all ready), 2 (at least one missing when the limit is reached; the limit is clamped to 540 s), or 1 (usage error); called by \`skills/review/SKILL.md\` Step 10 "Wait limit" (one call per fan-out, limit 480 s)`
   - `docs/ja/structure.md` (L235 付近): 同じ 1 行を日本語で足す
5. **確認する** (Step 1〜4 の後) (→ 受入条件 4)
   - `bats tests/wait-subagent-results.bats tests/review-subagent-wait.bats tests/subagent-launch-unnamed.bats tests/review.bats tests/edge-case-execution-context.bats tests/worktree-lifecycle.bats` (既存分は実装前に 65 件が PASS。新規の 2 ファイルは Step 1・2 で PASS・実装前 FAIL を確認済みで、ここでは全体が PASS することを確かめる)
   - `bats --jobs <N> tests/` の全体 (`nproc` の結果を先に別コマンドで出し、リテラルで置く。`$(...)` を `bats` の行に入れない)
   - `python3 scripts/validate-skill-syntax.py skills/`、`bash scripts/check-allowed-tools.sh`、`bash scripts/check-forbidden-expressions.sh`、`bash scripts/check-translation-sync.sh` (`docs/guide/xl-decomposition.md` の OUTDATED は既存で無関係)、`git diff -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py`、`bash scripts/check-bare-bracket-assertions.sh`、`bash -n scripts/wait-subagent-results.sh`

## Verification

### Pre-merge

- <!-- verify: rubric "docs/spec/ 配下の issue-1551-*.md の ## Notes セクションに、PR #1549 の review でサブエージェントの結果も結果ファイルも届かなかった原因が、#1481・#1522 の対処との関係 (対処の対象外の経路か、対処の退行か) とともに特定されている。原因はログ・コード上の経路などの根拠を伴い、推測だけの記述ではない" --> #1481・#1522 の対処後も結果が届かなかった原因が、根拠とともに Spec の `## Notes` に特定されている
- <!-- verify: rubric "skills/review/SKILL.md に、起動したサブエージェントの結果 (または結果ファイル) が届かない場合の待機上限 (これを超えたら待たずに縮退する時間または回数の上限) が数値または明確な条件で書かれており、オーケストレーター自身による代替レビューへの縮退手順に接続している。既存の 'Never wait for a result' と Sub-agent Result Fallback の記述だけでは満たされず、待機上限の記述が新たに加わっている必要がある" --> <!-- verify: grep "(wait limit|upper bound|maximum wait|wait (up to|at most)|待機上限|待機の上限)" "skills/review/SKILL.md" --> 結果が届かないときの待機上限と縮退手順が `skills/review/SKILL.md` に書かれている
- <!-- verify: rubric "縮退した場合 (サブエージェントの結果も結果ファイルも届かず、オーケストレーターが代替した場合) に、どの観点のサブエージェントが代替されたかを示す固定書式の記録が、既存の Review body の 'Sub-agent fallback' 行に加えて、Review Response Summary コメントまたは Spec の review retrospective にも残る手順が skills/review/SKILL.md に書かれている" --> 縮退したことと対象の観点が、レビューの要約コメントまたは Spec の review retrospective に残る
- <!-- verify: github_check "gh pr checks --json name,state --jq '.[] | select(.name==\"Run bats tests\") | .state'" "SUCCESS" --> CI の bats テスト (Run bats tests) が通る

### Post-merge

- なし (Issue 本文の Acceptance Criteria に Post-merge の項目はない)。効果は、次回以降の `/review --full` で、サブエージェントの結果が戻り値で届くことと、縮退した場合に `- Sub-agent degradation:` の行が要約と retrospective に載ることを、`/verify` の振り返りで見る

## Notes

### 原因の特定 (受入条件 1)

**結論**: PR #1549 の `/review --full` でサブエージェントの結果も結果ファイルも届かなかったのは、(1) 5 本の起動が `run_in_background` を省略した background 起動で、戻り値が確認応答だけだったこと、(2) 結果ファイル経路 (#1522) が待機の上限を持たず、オーケストレーターが起動の約 75 秒後にサブエージェントの作業の途中で `TaskStop` したこと、の 2 つが重なったため。**#1481・#1522 の対処の退行ではなく、それらの対処の対象外の経路 (起動形態の指定と、結果ファイル経路に与える待機時間) で起きた**。Issue 本文の「バックグラウンドで動き続けた」は正確でない: 5 本は動き続けたのではなく、オーケストレーター自身が 75 秒後に止めた。

**根拠** (出所: ローカルの Claude Code の transcript とイベントログ。取得日 2026-10-25。ホームディレクトリ配下で `~/.claude/projects/-home-saito-src-wholework/cf9b1799-b6dc-4f84-b521-3bb0116df4ee.jsonl` と、同名の `cf9b1799-.../subagents/agent-*.jsonl`・`agent-*.meta.json`、およびリポジトリの `.tmp/auto-events.jsonl`)。時刻は UTC、2026-10-24:

| # | 観測 | 値 | 何を示すか |
|---|------|----|-----------|
| 1 | 5 本の `Agent` の `tool_use` の入力キー (14:45:07〜14:45:25) | `description`・`prompt`・`subagent_type` の 3 つだけ。`run_in_background` も `name` も無い | 起動形態を指定していない。`name` は付けておらず #1522 の規則は守られている |
| 2 | 5 本の戻り値 (14:45:25.87〜.90) | どれも `Async agent launched successfully. ... agentId: ...` | 戻り値に結果は載らない (結果ファイル経路の前に、戻り値の経路が空) |
| 3 | 5 本の `subagents/agent-*.meta.json` | `"requestShape":"background","requestNonInteractive":true,"launchedWithDefaults":true`、`finished` は無い | 非対話 (`-p`) でも既定で background。`launchedWithDefaults` は引数を省略した起動 |
| 4 | 5 本の起動プロンプト | どれも `result file=.tmp/subagent-result-1549-<label>.md` と「最後の操作として書く」指示を含む (14:45:02 の `rm -f .tmp/subagent-result-1549-*.md` も実行済み) | #1522 の結果ファイル経路は設計どおり整っていた |
| 5 | オーケストレーターの結果ファイル確認 | 14:45:53 (起動の 28 秒後)、14:46:24 (58 秒後)、14:46:31 (66 秒後) の 3 回とも `.tmp/` に `subagent-result-*` が無い | 確認は 3 回あったが、猶予は数十秒だった |
| 6 | 14:46:40 のオーケストレーターの文と `TaskStop` | 「結果ファイルがまだ出ていないため、自分で 4 観点のレビューを行いました。残りのサブエージェントを停止します」。続く 5 回の `TaskStop` はすべて `Successfully stopped task` (14:46:40.35〜14:46:41.23) | 起動の 75 秒後に見切って止めた。#1522 の停止 (agent ID 指定) は成功している |
| 7 | 5 本の transcript の長さ | 起動の 14:45:25.86〜.89 から停止の 14:46:40.40〜41.23 まで、74〜75 秒。最後のツール呼び出しは停止の 1〜10 秒前 (`review-spec` 14:46:39.8 の Bash、`review-bug` セキュリティ 14:46:33.7 の `bats` 実行、ほか) | 作業の途中で止められた。5 本とも結果ファイルは書いていない (`Write` の対象に `subagent-result` を含むパスは無い) |
| 8 | 同種のサブエージェントが前景で完走した時間 (PR #1539・#1541・#1547・#1548、2026-10-22〜10-24、17 本) | `review-spec` 94〜264 秒、`review-bug` 94〜273 秒、エッジケース計測 111〜294 秒。結果ファイルは完走時に書かれた | 75 秒では完走できない。猶予の上限が数十秒では、結果ファイルは構造上間に合わない |
| 9 | 同日 14:33 の PR #1548 の `review-bug` の作業量 | 94〜115 秒で 12〜13 回のツール呼び出し。PR #1549 の `review-bug` は 74 秒で 11〜12 回の時点で止められた | 完走の直前だった。数十秒の猶予があれば結果が届いた可能性が高い |
| 10 | 起動形態とキーの有無の対応 (ローカルに残る review 関連の 57 サブエージェント、2026-10-02〜10-24、Claude Code 2.1.287〜2.1.310、すべて `requestNonInteractive: true`) | `run_in_background: false` を指定した 51 本はすべて `requestShape: foreground` (`finished: true`)。キーを省略した 6 本 (PR #1549 の 5 本と 2026-10-16 の PR #1532 の 1 本) はすべて `background` | 起動形態はキーの有無だけで決まり、例外が無い。ハーネスの版は要因でない (PR #1548 の 14:33 の前景と PR #1549 の 14:45 の background は、どちらも 2.1.310) |
| 11 | 2026-10-16 の PR #1532 の `review-light` (Claude Code 2.1.301) | キーを省略 → 確認応答 → 約 15 秒後に結果ファイル無しと判断 → `TaskStop` → 自前レビュー | 同じ署名の再発。`review-light` は前景では 16〜68 秒かかる |
| 12 | `skills/review/SKILL.md` (c396f028 時点) | 前景の規則は L39 (`do not set \`run_in_background: true\``) と L465 (`Foreground dispatch reminder`) で、起動の例 (L580・L640・L646・L652・L690) に `run_in_background` が無い。`run_in_background: false` を名指しするのは `skills/review/workflow-guidance.md` L50 だけ (Workflow を使えないときの退避先) | 「`true` を付けない」は引数の省略で満たされ、省略は background を選ぶ。コード上の経路 |
| 13 | 公式ドキュメント (取得日 2026-10-25) | tools-reference § Agent tool behavior: "Claude Code runs subagents in the background by default, apart from the cases that run in the foreground"。sub-agents § Run subagents in foreground or background: "With nothing configured, a subagent that Claude spawns from your main conversation starts in the background."、`claude -p`: "Claude can wait, on its own judgment or when you ask." | 既定は background で、`-p` でも前景にするかは呼び出し側の判断。per-call の `run_in_background` パラメーターは公式ドキュメントに記載が無いが、実機の transcript (上の 10) と、この実行のツール定義の説明で確認できる |

測定範囲 (8・10): ローカルの `~/.claude/projects/-home-saito-src-wholework*/*/subagents/agent-*.meta.json` のうち、`agentType` が `wholework:review-*` のもの、または `description` が `dge` を含む (Edge case) もの。親の `tool_use` の入力は、`toolUseId` で同じ project ディレクトリの transcript から引いた。ローカルに transcript が残らない実行は含まない。

**#1481・#1522 の対処との関係**:

- #1481 (結果が手元に無いのにターンを終えない、代替レビューに進む): PR #1549 でも設計どおり働いた。ターンを終えて待つことはせず、代替レビューで先へ進んだ。対処の対象は「待ってターンを終えない」で、「何秒待つか」は含まない
- #1522 (`name` を付けない、結果ファイル、代替後の再確認、agent ID での `TaskStop`): 5 点すべて働いた (観測 1・4・5・6・7)。`review-bug` は `Write` を使えていた (フィクスチャの書き込みが成功)。結果ファイル経路が空だったのは、経路の故障ではなく、サブエージェントが結果ファイルを書くのは作業の最後であり、その前に止めたため
- 対象外だった経路: (a) 起動形態。#1522 の Spec は `run_in_background: false` を却下した (「対話セッションでは fork mode が既定で ON で、指定しても効かない環境が、まさに今回の対象」)。この前提は対話セッションの fork には当てはまるが、headless の `claude -p` には当てはまらない (観測 10 で、`-p` では指定が効く)。(b) 待機の長さ。#1522 の Spec は Uncertainty に「結果ファイルの確認が早すぎる: 代替レビュー (数分) より先にサブエージェントが終わらない場合、遅れて届く指摘は捨てられる。ベストエフォートとして受け入れる」と書き、待機スクリプトの新設を「別 Issue で待機スクリプトを検討する」として却下した。見込みの「数分」は誤りで、実際の猶予 (起動から `TaskStop` まで) は 15〜75 秒だった (PR #1532 は約 15 秒、PR #1549 は約 75 秒)。この Issue はその別 Issue にあたる
- 退行ではないことの確認: #1522 の変更 (`name` の削除、結果ファイル、`Write`、`TaskStop`) は PR #1549 の時点で main に入っており (観測 1・4・6 のとおり全部が効いている)、その後に削られた記述は無い

**推定 (観測でなく、修正に影響しない)**: モデルが引数を省略した理由。この実行のツール定義の `run_in_background` の説明は、「次の操作が結果に依存し、ほかに有用な作業が無いときだけ `false`、そうでなければ background のまま」と述べる。PR #1549 のオーケストレーターは起動後に Step 8 の作業を続けており、並行作業をする意図で既定のままにした可能性がある。22 セッション中 20 セッションは `false` を付けたので、SKILL.md が求めていなくても付ける傾向が強いが、規則が無いので毎回保証されない。修正は選択肢そのものを消す (起動例に `run_in_background=false` を入れる)。

### Issue 本文との相違 (Conflict with implementation)

- Background の「バックグラウンドで動き続けた」は、細部が実際と違う。5 本は 14:46:40 にオーケストレーターが `TaskStop` で止めており (観測 6)、止められた時点で作業の途中だった。したがって「結果が届かなかった」ことの意味は、サブエージェントの故障でなく、待機の打ち切りが早すぎたことである
- Background の「#1522 の対処後もなお結果が届かない原因」は、対処の退行でも対処の欠陥でもなく、対象外の経路 (上のとおり)
- Issue 本文の前提 (`premise: grep_count "Never wait for a result" "skills/review/SKILL.md" -eq 1`) は現状のコードと一致する (実測 1 件)。この Spec はその文を残す
- 解決方針の変更: 受入条件は変えていない。ただし AC2 の「待機上限」は、「待たない」方針と衝突しないよう、「ターンを終えて待たない・自分でポーリングしない・`sleep` しない」を守ったまま、fan-out ごとに 1 回だけ、スクリプトによる上限 480 秒の前景待機とした

### 設計判断と却下案

- 採用: 防ぐ (`run_in_background=false` を起動例に入れる) + 上限付きで待つ (`scripts/wait-subagent-results.sh`、480 秒、fan-out ごとに 1 回) + 残す (固定書式の 1 行を要約と retrospective に)。防ぐだけでは、指定が効かない環境 (対話セッションの fork) と指定漏れ (今回のように 22 セッション中 2 回) で同じ縮退が続く。待つだけでは、headless で毎回 background になり、毎回数分待つことになる。両方入れて、前景が効く環境では待機が一度も要らず、効かない環境では上限付きで待つようにする
- 待機の長さ 480 秒: 前景で完走した 17 本の最大が 294 秒で、その約 1.6 倍。Bash ツールの天井 (600000 ms) の内側に収まるよう、`timeout: 540000` と、スクリプト側の切り詰め 540 秒を置く。足りないと分かれば、定数 (SKILL.md の 480 と例、スクリプトの切り詰め) を変える。`.wholework.yml` のキーにはしない (使う場所が 1 か所で、設定を増やすと `detect-config-markers.md`・`docs/guide/customization.md`・翻訳も増える)
- 採用: 待機はスクリプトで行う。モデルが `sleep` やポーリングで待つと、Bash ツールが前景の `sleep` を拒否し (実行環境の説明)、ワークツリーの隔離ガードも複雑なコマンドを拒否する (#1522 の実測)。スクリプトなら 1 回の単純なコマンドで、`scripts/wait-ci-checks.sh` と同じ前例 (上限付きの待機を、スクリプトに閉じ込める) に従う。`modules/execution-context.md` の MUST の規則は「通知待ちでターンを終えない」であり、上限のある前景のスクリプトは当たらない。同じ節の系 (天井を超えるコマンドは background へ移される) には、上限を 540 秒に切り詰めることで従う
- 却下 (待機の上限を散文だけで書く): 待つ手段が無いので、「代替レビューの所要時間を猶予にする」という現状を上限と呼び直すだけになり、今回の事象 (75 秒で見切る) を追認する
- 却下 (`Monitor` で待つ): 完了通知を待つ機構で、再呼び出しの保証が無い面 (headless、fork) では通知が届かない。`TaskOutput` は公式ドキュメントで v2.1.277 に削除済み
- 却下 (新しい event marker `type=review-subagent-degraded`): 固定書式の 1 行で足り、`modules/l0-surfaces.md` の網羅的な marker 一覧を増やさずに済む。機械的な集計が要るなら、`- Sub-agent degradation:` の接頭辞で検索できる
- 却下 (各 sub-agent の自己制限時間を prompt に書く): サブエージェントは時刻を安定して測れず、制限に達したら何を返すかも定義できない
- 範囲外 (follow-up 候補として記録。この Issue では触れない): 同じ隙が共有層にもある。(1) `modules/verify-executor.md` の rubric grader の起動手順は `run_in_background` を指定せず、結果ファイルを他の条件の評価後に 1 回確認して止める。(2) `scripts/guard-prefix.sh` の `GUARD_PREFIX` は「前景で実行し、同じターンで結果を使う」と言うが、Agent/Task の前景を引数 `run_in_background: false` で明示する指示は無い。(3) `modules/execution-context.md` の MUST の規則に、「Agent/Task の前景は引数の明示」を足す余地がある。いずれも 4 スキル以上、または 5 つの wrapper に届く共有層で、この Issue (`/review` の Step 10) の範囲を超えるため、起票は `/verify` の振り返りに委ねる

### 失敗時の挙動 (Edge cases)

| 状況 | 動作 |
|------|------|
| 前景で起動して結果が戻り値に載る (通常) | その結果を使う。待機も結果ファイルの確認も要らない。サブエージェントは終了済みで止めない |
| 引数を省略して確認応答だけが返る (指定漏れ) | 結果ファイルを `Read` し、無ければ fan-out ごとに 1 回だけ待機スクリプトを呼ぶ。全件 ready なら縮退しない |
| 対話セッションの fork で、前景を指定しても background になる | 同上 (結果ファイルと待機が受ける) |
| 待機が上限に達し、一部が missing (終了コード 2) | missing の分だけ代替レビューに縮退し、代替の後に結果ファイルをもう一度 `Read` し、無ければ `TaskStop` で止め、`reason=wait-limit-exceeded` の固定書式の行を残す |
| 待機スクリプトが無い・実行できない・終了コード 1・ツールが background へ移した | 待たずに縮退し、`reason=wait-not-run`、`waited=0s` の行を残す。ターンを終えて通知を待たない |
| 10.3 の検証の判定が無い | その issue は未検証のまま通す (既存の扱い)。固定書式の行は `issue passed through unverified` |
| Edge Case Pre-check の計測の結果が無い | 指摘なしとして扱う (既存の扱い)。固定書式の行は `treated as no findings` |
| `--review-only` | Step 14 と Retrospective が無いので、Review body の `Sub-agent fallback` の行だけが記録になる |
| `TaskStop` が失敗する | ベストエフォートとして無視する (既存の扱い)。待機・要約・後続の処理を止めない |
| Workflow 経路 (`workflow-guidance.md`) | 結果ファイルを使わない。この変更の対象外 (Workflow を使えないときの静的 Task は `run_in_background=false` の起動例に従う) |
| 縮退が無い実行 | 固定書式の行も `### Sub-agent Degradation` の節も出さない |

### 新規テストケースの要件

- 新しい分岐ロジックを足す (`scripts/wait-subagent-results.sh`)。既存スイートの PASS だけでなく、`tests/wait-subagent-results.bats` の新規ケース (Implementation Step 1 の 15 件) を足して PASS させる
- SKILL.md の散文の変更は、`tests/review-subagent-wait.bats` の新規ケース (Step 2 の 12 件) で構造を固定する。`tests/subagent-launch-unnamed.bats` が `name` の再混入を見張るのと同じ型で、`run_in_background=false` の欠落を CI で検出する (網羅の主張「every `Task(...)` が持つ」の機械的な検証)
- bats の入力形式: スクリプトの引数は `[--interval N] <timeout> <file>...`、期待する stdout は `ready <path>` / `missing <path>` の行 (引数順)、stderr の最終行は `wait-subagent-results: R/T ready after Ns (limit Ls)`。SKILL.md の構造テストの入力は `skills/review/SKILL.md` そのもの (検出力の確認は写しの 1 行を削って検査する)
- `@test` 名の方針: 検証コマンドから `.bats` の `@test` 名を引く受入条件は無いので、名前の形は固定しない。既存の bats の書き方に合わせる。最終行でない `! grep` や `[[ ... ]]` は `|| false` を付ける (`scripts/check-bare-bracket-assertions.sh`)
- ベースライン: 実装前に `bats tests/review.bats tests/subagent-launch-unnamed.bats tests/edge-case-execution-context.bats tests/worktree-lifecycle.bats` は 65 件すべて PASS (bats 1.11.1)

### 外部仕様の確認と出所

取得日はすべて 2026-10-25。

- https://code.claude.com/docs/en/tools-reference § Agent tool behavior: "Claude Code runs subagents in the background by default, apart from the cases that run in the foreground." 同ページ: `TaskOutput` は "Removed in v2.1.277. Previously retrieved output from a background task; Claude reads a background task's output file with `Read` instead"、`TaskStop` は "Stops a running background task by ID"。§ Timeout and output limits: 前景の Bash は既定 2 分、上限 10 分 (`BASH_DEFAULT_TIMEOUT_MS`・`BASH_MAX_TIMEOUT_MS`)。"When a foreground command reaches its timeout without finishing, Claude Code moves it to the background instead of stopping it, unless the command starts with `sleep`."
- https://code.claude.com/docs/en/sub-agents § Run subagents in foreground or background: "With nothing configured, a subagent that Claude spawns from your main conversation starts in the background." "**`claude -p` and the Agent SDK**: Claude can wait, on its own judgment or when you ask." 同ページに per-call の `run_in_background` パラメーターの記載は無い (frontmatter の `background` フィールドだけ)
- 実機の観測: 上の観測 10 (ローカルの transcript)。この `/spec` の実行のツール定義も、Agent の `run_in_background` を「既定は background。`false` は次の操作が結果に依存するときだけ」と説明している
- 実機で未確認: 対話セッションの fork で `run_in_background: false` が効くか。この実行は headless で、再現できない

### スクリプトの設計メモ

- 時計は `SECONDS` (bash 組み込み) を使い、外部コマンド `date` を呼ばない。`sleep` のモックは使わない (モックするとループが空回りする)
- 数値の解釈は `10#` 付きの算術 (`timeout="$((10#$value))"`) にし、先頭の 0 が 8 進にならないようにする。桁数が多い値は算術に入れる前に切り詰める (オーバーフローで errexit しない)
- `set -e` の下では `((x++))` が 0 のとき終了コード 1 を返して落ちる。カウンターは `x=$((x+1))` の形にする
- stdout は待機の終了時にまとめて出す (途中で一部だけ出ると、呼び出し側が部分的な出力を読むため)
- 呼び出し側 (SKILL.md) の契約: 終了コード 0・2 以外、実行できない、background へ移された、のどれも `wait-not-run`

### その他の判定

- 監査・調査型の Issue か: いいえ。既存項目を分類する Issue ではなく、原因の特定を伴う不具合の修正。ただし Notes と本文に書いた識別子 (SKILL.md の行番号と見出し名、`workflow-guidance.md` L50、agent ID、時刻) は、`grep -n`・transcript の再読で存在を確認した
- fail-safe critical か: はい (呼び出し側が失敗を「待たずに縮退する」側へ倒す設計の補助スクリプト)。空・巨大な入力、特殊文字、依存コマンド (`sleep`) の失敗の扱いは Implementation Step 1 に列挙した
- 費用・不可逆なステップ: 無い (`spec-approval-needed` は不要)。外部サービスへのログインも無い
- `allowed-tools` の影響: 新規 `scripts/*.sh` を `skills/review/SKILL.md` が呼ぶので、その frontmatter に `${CLAUDE_PLUGIN_ROOT}/scripts/wait-subagent-results.sh:*` を足す (E1)。ほかの SKILL.md は呼ばない。`modules/*.md` は変更しないので、モジュール経由の影響連鎖は無い。`/review` の `Task` は既に `allowed-tools` にある
- Size の再評価: Changed Files は 8 件 (Axis 1 の 6-10 件は L)。スクリプトの分岐の追加 (+1) と、原因の明確な不具合の修正 (-1) が相殺して L。トリアージ時の M から Step 18 で見直す。経路は pr のまま
- CI の制約 (`/code` で守る): 追加する文言は英語のみ (`scripts/check-language-convention.py` が `skills/`・`modules/`・`scripts/` の差分の `+` 行から仮名と漢字を検出する。既存行を編集するとその行の日本語の地の文が初めて検出されるので、`前景` を含む行 39 は触れない)。半角 `!` を `skills/review/SKILL.md` の本文に入れない (`scripts/validate-skill-syntax.py`)。非推奨用語を使わない (`scripts/check-forbidden-expressions.sh`)。新規スクリプトは `bash -n` が通ること (macOS の bash 3.2 のジョブ)
- 一時ファイル: 検証用の大きな作業ファイル (リポジトリの写し、依存のインストール、ビルド) は作っていない。`phase-work-dir.sh clean` は no-op
- `/code` の注意: `git stash` を使わない。実装前の失敗の確認は、Step 2 のテストを Step 3 より先に実行して行う (写しは要らない)。新規スクリプトは `chmod +x` してから `git add`

## Consumed Comments

- saito / MEMBER / first-class / `## Issue Retrospective` (`--non-interactive` での曖昧点 4 点の自動解決、受入条件の変更理由、triage の結果の記録。要件の追加・変更は無い) / https://github.com/saitoco/wholework/issues/1551#issuecomment-6391301422

## Code Retrospective

### Deviations from Design
- 設計からの逸脱は無い。Implementation Steps 1〜4 を Spec のとおりに実施した (E10 の文は Retrospective の Steps 2 の最後の箇条書きの末尾に足した)

### Design Gaps/Ambiguities
- 新規テスト `tests/review-subagent-wait.bats` の 12 件のうち 10 件が、変更前の `skills/review/SKILL.md` に対して FAIL することを確認した (Confirmed pre-implementation FAIL for 10 new test(s))。残る 2 件 (`Never wait for a result` が 1 回、検出関数が閉じる側に倒れる) は前提と検出器の自己検査なので、変更前から PASS するのが正しい
- この `/code` の実行で grader (`Agent`、`run_in_background=false`) を 3 本起動したところ、戻り値には結果が載らず、完了後に別メッセージ (hand-back) として結果が届いた。前景を指定しても、harness の経路によっては結果が戻り値でなくメッセージで届く。結果ファイルの有無は確認していない (grader の結果は届いたので不要だった)。`/review` の "Wait limit" と結果ファイル経路が引き続き必要な根拠の一つになる
- AC4 (`gh pr checks` の bats) は PR 作成前の Step 10 では評価できないため、チェックを付けずに残した (`/review` が評価する)

### Rework
- Retrospective の Steps 2 に足した文で、直前の文との間の句点が抜けていた (grader の指摘で発見し、修正コミットを足した)。再発防止は、`E10` のような「既存行の末尾に文を足す」編集で、結合部の句読点を差分で目視すること

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `scripts/wait-subagent-results.sh` は `$SECONDS` で期限を切り、`sleep` を入れても期限で必ず終わる設計にした。上限は 540 秒に切り詰め (Bash ツールの 600000 ms の内側)、SKILL.md の例は 480 秒
- `tests/review-subagent-wait.bats` は `Task(` の起動例を走査する検出関数で「すべての起動例が `run_in_background=false` を持つ」を機械的に固定し、起動例が 5 つ未満なら閉じる側に倒れる
- SKILL.md の文面は英語のみで、`Never wait for a result` は 1 か所のまま残した (Issue の premise marker が `grep_count` で 1 を見る)

### Deferred Items
- 共有層 (`modules/verify-executor.md` の grader 起動、`scripts/guard-prefix.sh`、`modules/execution-context.md`) の同じ隙は Spec の Notes「範囲外」のとおり触れていない。起票は `/verify` の振り返りに委ねる
- AC4 (CI の `Run bats tests`) は PR の CI 結果で確認する

### Notes for Next Phase
- `/review` では、`skills/review/SKILL.md` の Step 10 の 5 つの起動例に `run_in_background=false` があること、"Wait limit" の 480 秒 / `timeout: 540000` / スクリプトの切り詰め 540 秒の整合、固定書式 `- Sub-agent degradation:` が Step 14.1 と Retrospective に出ることを見る
- ローカルの `bats --jobs 4 tests/` (2480 件) は失敗なし。`check-translation-sync.sh` の `docs/guide/xl-decomposition.md` の OUTDATED は既存で無関係
- 変更したのは `/review` の記述だけで、ほかの SKILL.md の `allowed-tools` への影響は無い
