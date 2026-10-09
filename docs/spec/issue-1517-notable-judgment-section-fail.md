# Issue #1517: tests: auto.bats の notable_judgment_section が節を取れないとき否定アサーションが素通りするのを防ぐ

## Overview

`tests/auto.bats` の `notable_judgment_section` は、番号付きリスト項目 `3. **Notable judgment**` から次の `4. **` の直前までを切り出す inline awk である。開始行が見つからなくても exit 0 で空を返すため、sub-step の番号や文言が変わって節が空になると、節を `run` + `$output` で受けて否定アサーションで検査するテストが黙って PASS する。#1516 で `md_section` 系の 6 テストを素の代入に直したときに、範囲外として持ち越した残りの 1 件である。

本 Issue で行うことは次の 4 点。

1. `notable_judgment_section` が開始行を見つけられなかったとき exit 1 を返す (`tests/helpers/markdown-section.bash` の `md_section` と同じ `END { if (!found) exit 1 }`)
2. 同じ awk を使う `notable_judgment_jq_command` が、その失敗を呼び出し元に伝える (節を先に代入で受けてから、2 段目の awk に渡す)
3. 節を否定アサーションで検査している 2 テストを、節を素の代入 `section="$(notable_judgment_section ...)"` で受ける形に直す
4. 1 と 2 の退行を恒久的に検知する単体テストを 2 件追加する (受け入れ条件の文面には無いが、目的に直結する)

節の境界が Markdown の見出しではなく番号付きリストなので、`md_section` への置き換えはしない (Issue 本文のとおり)。

## Changed Files

- `tests/auto.bats`: 抽出ヘルパー 2 関数の修正、否定アサーション 2 テストの受け方の変更、単体テスト 2 件の追加。変更はヘルパー関数と `@test` 本文だけで、他のファイルには影響しない。bash 3.2+ 互換 (`local`、`$(...)`、`|| return`、`printf`、POSIX の範囲の awk のみ。`END { if (!found) exit 1 }` は `md_section` と同じ idiom)

変更不要の確認 (grep と実読で確認済み):

- `git grep -n "notable_judgment_section\|notable_judgment_jq_command"` (範囲: リポジトリ全体の追跡ファイル): `tests/auto.bats` に 7 行 (L157、L162、L168、L176、L183、L191、L208)。ほかは `docs/spec/` の #1514・#1516 の Spec (履歴記録で変更対象外) だけで、`tests/auto.bats` 以外に呼び出し元は無い
- `tests/auto.bats` の `Notable judgment section references all four aggregated count fields`: 肯定アサーションだけで、空の節ではそれだけで FAIL する (実測)。変更しない
- `tests/auto.bats` の `Notable judgment jq aggregation ...` 2 テスト: 呼び出し形は変更しない (理由は Notes の「自動解決した判断」)
- `docs/tech.md`、`docs/ja/tech.md`: 変更しない。受け入れ条件 2 が参照する `BATS Markdown Section Extraction` 節の規約には、今回の修正がそのまま沿う。番号付きリスト項目のような見出し基準でない抽出関数への追記は、Issue の範囲外 (受け入れ条件は `tests/auto.bats` のみ) で `docs/ja/tech.md` の同期も要るため見送り
- [Steering Docs sync candidate] inbound の keyword check はスキップ: Changed Files に SKILL.md・`modules/`・`scripts/` を含まないため
- [Steering Docs sync candidate (listing-side)] スキップ: ファイルの追加・削除・リネームもディレクトリ構成の変更も、サブコマンドの追加・削除も無いため
- [Outbound pointer sync candidate] スキップ: `tests/auto.bats` に他のリポジトリファイルを指す "See also" や "SSoT:" の記述が無い (`git grep -n -E "See also|for the full reference|SSoT:|\]\(" -- tests/auto.bats` が 0 件)

## Implementation Steps

行番号は main@71d53240 時点。

1. `tests/auto.bats` の抽出ヘルパー 2 関数を直す (→ 受け入れ条件 1)
   - `notable_judgment_section` (L155-159): awk プログラムの末尾に `END{if (!found) exit 1}` を足し、直前のコメントに「番号付きリスト項目なので `md_section` は使えない」「`md_section` と同じく開始行が無ければ exit 1」を書く。置き換え後:

     ````bash
     # Extract Notable judgment sub-step (L3 auto-retrospective step 3): from
     # "3. **Notable judgment**" to the next numbered sub-step heading (Issue #913).
     # A numbered list item is not a Markdown heading, so md_section does not apply. Like
     # md_section, exits 1 when the start line is not found (Issue #1517).
     notable_judgment_section() {
         awk '/^3\. \*\*Notable judgment\*\*/{found=1} found && /^4\. \*\*/{exit} found{print} END{if (!found) exit 1}' "$1"
     }
     ````

   - `notable_judgment_jq_command` (L180-186): パイプラインは最後の awk の終了ステータスしか返さない (bats のテスト本体は `set -o pipefail` を有効にしておらず、関数の中で設定すると呼び出し側の shell に漏れる) ので、先に `notable_judgment_section` の結果を代入で受け、失敗ならその終了ステータスで `return` する。`local` と代入は別の行にする (`local section="$(...)"` は終了ステータスを隠す)。置き換え後:

     ````bash
     # Extract the jq aggregation command embedded in the Notable judgment sub-step
     # (first fenced ```bash block only — later blocks in the same sub-step cover the
     # "commit events.jsonl and stop" git sequence, not the aggregation itself).
     # Fails with notable_judgment_section's status when the sub-step is not found; the section
     # is captured first because a pipeline would report only the second awk's status (Issue #1517).
     notable_judgment_jq_command() {
         local section
         section="$(notable_judgment_section "$1")" || return
         printf '%s\n' "$section" | awk '/```bash/{p=1; next} p && /```/{exit} p'
     }
     ````

2. 節を否定アサーションで検査している 2 テストを、素の代入で受ける形に変更する (after 1) (→ 受け入れ条件 2)
   - 各テストの先頭に `# Plain assignment (not run) so a missing section fails the test (Issue #1517)` を 1 行付ける (#1516 の `# Plain assignment (not run) so a missing heading fails the test (Issue #1516)` と同じ書式。この文言には `_section` / `md_section` を含めない。再調査コマンドの `[section]` 欄が代入行を指すようにするため)
   - `Notable judgment section uses jq -sc aggregation, not a raw events dump` (L161-165): `run notable_judgment_section "$SKILL_FILE"` を `section="$(notable_judgment_section "$SKILL_FILE")"` にし、2 行の `[[ "$output" ... ]]` を `[[ "$section" ... ]] || false` にする (検索文字列は変えない)
   - `Notable judgment section no longer references the non-existent watchdog_timeout event` (L175-178): 同様に `section="$(...)"` にし、`[[ "$section" != *"watchdog_timeout"* ]] || false` にする
   - `Notable judgment section references all four aggregated count fields` (L167-173) は変更しない

3. 退行を検知する単体テストを 2 件追加する (after 1) (→ 受け入れ条件 1)。新しい失敗の分岐を検証する新規テストケースであり、既存スイートが PASS することだけでなく、この 2 件を追加したうえでスイートが PASS すること
   - `Notable judgment section helper returns status 1 with empty output when the start line is missing`: `no longer references the non-existent watchdog_timeout event` の直後に置く
   - `Notable judgment jq command helper returns status 1 with empty output when the start line is missing`: `notable_judgment_jq_command` の定義の直後 (集計テスト 2 件の前) に置く
   - 書式は `tests/markdown-section.bats` の `md_section: missing heading returns status 1 with empty output` と同じ (heredoc のフィクスチャ + `run` + `[ "$status" -eq 1 ]` + `[ -z "$output" ]`)。フィクスチャは開始行を `3. **Notable judgement**` に改名した 3 行で、`$BATS_TEST_TMPDIR/doc.md` に書く (テストごとに独立で、並列実行でも衝突しない)
   - 終了ステータスは `-ne 0` ではなく `-eq 1` で見る。awk の構文エラー (mawk は status 2 で stderr に出力する) など、別の理由の失敗を取り違えないため
   - 1 件目の全文 (2 件目は関数名を `notable_judgment_jq_command` に変えるだけで、フィクスチャと検査は同じ):

     ````bash
     @test "Notable judgment section helper returns status 1 with empty output when the start line is missing" {
         cat > "$BATS_TEST_TMPDIR/doc.md" <<'EOF'
     3. **Notable judgement** (renamed)
        - body
     4. **Fetch the Metrics section**
     EOF
         run notable_judgment_section "$BATS_TEST_TMPDIR/doc.md"
         [ "$status" -eq 1 ]
         [ -z "$output" ]
     }
     ````

     heredoc の終端 `EOF` は、実ファイルでは行頭に置く (上の例はリスト内のインデントのため字下げしている)。フィクスチャの本文行 (`3. **...`、`   - body`、`4. **...`) も行頭から書く

4. ローカル検証 (after 1, 2, 3) (→ 受け入れ条件 1, 2, 3)
   - bats の実行: `tests/auto.bats` と `tests/markdown-section.bats` を実行し、全件 PASS を確認する (期待: `tests/auto.bats` は 29 件)。`bats` が PATH に無ければ、前回の取得先 `/tmp/bats-dl/src/bin/bats` (bats-core v1.11.1) が残っていればそれを使い、無ければ bats-core を新しい空ディレクトリに取得する。ワークツリー隔離ガードが glob、`&`、複合コマンドを拒否するため、ファイル名はリテラルで並べた単純なコマンドにする
   - 変異確認: 追跡ファイルの `skills/auto/SKILL.md` は変えず、`.tmp/` に作業コピーを作って行う。次を 1 コマンドずつ実行する
     - `mkdir -p .tmp/mut/tests/helpers .tmp/mut/skills/auto`
     - `cp tests/auto.bats .tmp/mut/tests/auto.bats`
     - `cp tests/helpers/markdown-section.bash .tmp/mut/tests/helpers/markdown-section.bash`
     - `cp skills/auto/SKILL.md .tmp/mut/skills/auto/SKILL.md`
     - `sed -i 's/^3\. \*\*Notable judgment\*\*/3. **Notable judgement**/' .tmp/mut/skills/auto/SKILL.md`
     - `bats .tmp/mut/tests/auto.bats` (期待は Notes の「変異確認の期待値」)
   - 再調査コマンド (Notes) を再実行し、範囲内 2 テストの `[section]` 欄がどちらも `section="$(notable_judgment_section "$SKILL_FILE")"` の代入行になっていることを確認する
   - 任意 (必須ではない): 新規 2 テストの検出力の確認。作業コピーで `notable_judgment_section` から `END{if (!found) exit 1}` を外すと新規 2 件とも FAIL し、`notable_judgment_jq_command` をパイプライン形に戻すと 2 件目だけが FAIL する (/spec のリハーサルで確認済み)
   - `git status --short` で、差分が `tests/auto.bats` だけであることを確認する。作業コピーは `.tmp/` (gitignore 済み) に置くので差分に出ない

## Verification

### Pre-merge

- <!-- verify: rubric "tests/auto.bats の notable_judgment_section (および同じ awk を使う notable_judgment_jq_command) が、開始行 '3. **Notable judgment**' を見つけられなかったときに非 0 の終了ステータスを返す" --> 節の開始行が見つからないとき、抽出関数が失敗を返す
- <!-- verify: rubric "tests/auto.bats で notable_judgment_section の結果を否定アサーションで検査しているテストが、run + $output や <<< \"$(...)\" ではなく、素の代入 (例: section=\"$(notable_judgment_section ...)\") で節を受けており、docs/tech.md の BATS Markdown Section Extraction 節の規約に沿っている" --> 否定アサーションのテストが節を素の代入で受けている
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion,status --jq 'if .[0].status != \"completed\" then \"in_progress\" else .[0].conclusion end'" "success" --> CI (test.yml) all jobs pass (patch route)

### Post-merge

なし

## Notes

### 自動解決した判断

- **修正方法は inline awk への `END { if (!found) exit 1 }` の追加**。`md_section` と同じ idiom で、`tests/markdown-section.bats` と CI で実績がある。検討した他の案:
  - 番号付きリスト用の共通ヘルパー (`md_list_item` など) を `tests/helpers/` に足す: 呼び出し元は `notable_judgment_*` の 1 組だけで、ヘルパーの単体テストも要る。Issue の目的 (失敗を伝える) に対して過大なので見送り
  - 各テストに「節の見出し行を含む」という肯定アサーションを足す: テストごとに検査行が増え、関数が失敗を返さないまま残る。受け入れ条件 1 は関数が失敗を返すことを求めている
- **`notable_judgment_jq_command` は、節を先に代入で受けてから 2 段目の awk に渡す**。パイプラインは最後のコマンドの終了ステータスしか返さない (実測: 開始行が無くても status 0)。`set -o pipefail` は bats のテスト本体で有効になっておらず、関数の中で設定すると呼び出し側の shell に漏れる。副次効果として、`notable_judgment_section` と同じ awk の重複コピーが 1 つに集約される
- **肯定アサーションだけのテスト (`Notable judgment section references all four aggregated count fields`) は変更しない**: 空の節ではそれだけで FAIL する (実測と変異確認)。#1516 と同じ判断で、`docs/tech.md` の "A positive assertion ... may keep those forms" にも沿う。変更を 2 テストに絞り、レビュー範囲を小さくする
- **jq 集計の 2 テスト (`Notable judgment jq aggregation ...`) の呼び出し形は変更しない**: `cmd=$(notable_judgment_jq_command ... | sed ...)` はパイプラインで関数の終了ステータスを捨てるが、続く `[ "$output" = '{...}' ]` の厳密一致が、空の抽出 (`bash -c ""` は何も出力しない) では必ず FAIL する (実測)。これらは否定アサーションのテストではない
- **書き換える `[[ ]]` の行には `|| false` を付ける**: bash 3.2 では非末尾の `[[ ]]` の失敗が `set -e` に伝わらない (`skills/code/skill-dev-validation.md` の "Bash 3.2: Bare `[[ ]]` Assertions Do Not Propagate `set -e`")。同じファイルの `Step 3 section has ...` 系 (L37-45) に先例がある。変更しない行 (`references all four ...` の 4 行) は触らない (同文書に、既存の検出箇所は無関係な変更では直さなくてよいとある)
- **単体テスト 2 件を追加する (受け入れ条件の文面には無い)**: 受け入れ条件 1 の「失敗を返す」は rubric だけで検証されるため、退行を機械的に検知する手段が無い。`tests/markdown-section.bats` の `md_section: missing heading returns status 1 with empty output` と同じ形で 2 件足す。作業コピーで修正を外すと検知できることを確認済み (Implementation Step 4 の「任意」)

### Issue 本文との相違 (Conflict with implementation)

- Issue Background と #1516 の Spec は、否定アサーションを持つ 2 テスト (L161、L175) がどちらも、節が空だと黙って PASS するとしている。実測では、L161 の `Notable judgment section uses jq -sc aggregation, not a raw events dump` は否定アサーションの前に肯定アサーション `[[ "$output" == *"jq -sc"* ]]` (L163) があり、bash 4.1 以降 (測定環境は bash 5.2.37) では節が空だとその行で FAIL する。素通りするのは bash 3.2 (macOS のシステム bash) だけ。L175 の `no longer references the non-existent watchdog_timeout event` は否定アサーションだけで、全 bash で素通りする。どちらも受け入れ条件 2 の対象なので、本 Issue では両方を直す (bash の版に依存せず、失敗位置も節の取得行になる)

### 実測: 呼び出し形ごとの挙動

開始行を `3. **Notable judgement**` に改名した `skills/auto/SKILL.md` に対して、旧実装 (修正前) と新実装 (本 Spec の置き換え後) の呼び出し形ごとの結果。

| 呼び出し形 | 結果 |
|-----------|------|
| 旧関数 + `run` + 否定アサーション | PASS (素通り) |
| 旧関数 + 素の代入 + 否定アサーション | PASS (素通り。旧関数が 0 を返すため) |
| 新関数 + `run` + 否定アサーション | PASS (素通り。`run` が終了ステータスを `$status` に逃がすため) |
| 新関数 + 素の代入 + 否定アサーション | FAIL (代入行で失敗) |
| 新関数 + 素の代入 + 肯定→否定 (`uses jq -sc aggregation` の形) | FAIL (代入行で失敗) |
| 新関数 + `run` + 肯定アサーションだけ (`references all four ...` の形) | FAIL (肯定アサーションで失敗) |
| 現行の jq 集計テスト本体 + 新関数 | FAIL (JSON の厳密一致で失敗) |

関数の修正と呼び出し形の変更は、どちらか片方では素通りが残るため、両方が要る。

ヘルパーの終了ステータスと出力:

| 入力 | 旧 `notable_judgment_section` | 新 `notable_judgment_section` | 旧 `notable_judgment_jq_command` | 新 `notable_judgment_jq_command` |
|------|------|------|------|------|
| 現行の SKILL.md | 0 / 節 | 0 / 旧と同一の出力 | 0 / jq ブロック | 0 / 旧と同一の出力 |
| 開始行を改名 | 0 / 空 | 1 / 空 | 0 / 空 | 1 / 空 |

- 存在しないファイルは、新旧とも awk のエラーで非 0
- 終了行 `4. **Fetch the Metrics section**` を改名した場合は、新関数は status 0 のまま、次の `4. **` 行 (現状の SKILL.md では L1070) まで節が延びる。受け入れ条件は開始行だけを対象とするので範囲外。節が広がる方向は、否定アサーションが誤って FAIL しうるが、素通りはしない
- `skills/auto/SKILL.md` には `3. **` / `4. **` で始まる番号付きリストが複数ある (範囲: 同ファイルのみ。`grep -n '^3\. \*\*'` は 8 行、`grep -n '^4\. \*\*'` は 9 行)。開始パターン `^3\. \*\*Notable judgment\*\*` は L816 の 1 行にだけ一致する

出所: main@71d53240 の作業ツリー、mawk 1.3.4.20250131-1、bats-core 1.11.1 (`/tmp/bats-dl/src/bin/bats`)、bash 5.2.37。プローブ `.tmp/probe-1517.bats` とリハーサル用コピー (`.tmp/rh-real/`、`.tmp/rh-mut/`) はコミットしていない (実測後に削除)。実測日 2026-10-09。CI は `ubuntu-latest` の `apt-get install bats` で、バージョンが異なる可能性があるが、代入の失敗がテストの失敗になる点は bats 1.x で共通で、#1516 の 6 テストと `tests/worktree-lifecycle.bats` が CI で同じ前提に依存している。

### 検証の参照点 (受け入れ条件 2 は不在確認)

`modules/verify-patterns.md` §26 に従い、受け入れ条件 2 の参照点を記録する。

- 変更前の検出リスト: `notable_judgment_section` の結果を否定アサーションで検査していた 2 テスト (`Notable judgment section uses jq -sc aggregation, not a raw events dump` (L161)、`Notable judgment section no longer references the non-existent watchdog_timeout event` (L175))。どちらも `run notable_judgment_section` + `[[ "$output" ... ]]` の形
- 対照群: 肯定アサーションだけで `run` 形のまま残る `Notable judgment section references all four aggregated count fields`。素の代入で受けている `tests/code.bats` の `section="$(stepNN_section ...)"` 形と `tests/worktree-lifecycle.bats` の `s="$(...)"` 形
- 母集団の非空性: 2 テストは、再調査コマンドの出力と該当行の実読で実在を確認済み

### 再調査コマンド (測定範囲付き)

範囲: `tests/auto.bats` のみ。`@test` ブロックごとに、`_section` または `md_section` を含む行 (最初の 1 行を `[section]` として表示) と、否定を示す記述 (`!=`、`-ne `、`then false`、`refute`、`grep -v`、`grep -qv`、行頭の `!`、`run !`) を含む行の両方があるテストを列挙する (#1516 の再調査コマンドの対象ファイルを 1 つに絞ったもの)。

```bash
awk 'function flush() { if (name != "" && sec != "" && neg != "") printf "%s:%d: %s\n  [section] %s\n%s", fname, startline, name, sec, neg } FNR==1 { flush(); name=""; sec=""; neg="" } /^@test / { flush(); name=$0; fname=FILENAME; startline=FNR; sec=""; neg=""; next } name != "" { if (sec == "" && $0 ~ /_section|md_section/) sec = FNR ": " $0; if ($0 ~ /!=|-ne |then false|refute|grep -v|grep -qv|^[[:space:]]*! |run ! /) neg = neg "    " FNR ": " $0 "\n" } END { flush() }' tests/auto.bats
```

着手前 (main@71d53240) の結果は 2 テスト (L161、L175)。`[section]` 欄はどちらも `run notable_judgment_section "$SKILL_FILE"` の行。着手後の期待: 同じ 2 テストが列挙され、`[section]` 欄が `section="$(notable_judgment_section "$SKILL_FILE")"` の代入行になる (`run` が出る場合は未修正)。リハーサルでこの出力を確認済み。

### 変異確認の期待値

Implementation Step 4 の変異確認 (開始行を改名した SKILL.md に対して `tests/auto.bats` を実行) の期待。テスト名で示す (番号は追加で変わる)。

- 修正後 (29 件): FAIL は 5 件、PASS は 24 件
  - FAIL: `Notable judgment section uses jq -sc aggregation, not a raw events dump` (失敗位置は `section=` の代入行)、`Notable judgment section references all four aggregated count fields` (最初の `[[ "$output" == ... ]]`)、`Notable judgment section no longer references the non-existent watchdog_timeout event` (失敗位置は `section=` の代入行)、`Notable judgment jq aggregation produces zeroed counts on an empty events file`、`Notable judgment jq aggregation counts matching events and ignores unrelated ones` (どちらも JSON の厳密一致)
  - PASS: 新規の単体テスト 2 件 (SKILL.md ではなくフィクスチャを使うため) を含む、そのほか
- 参照 (修正前のテストで同じ変異を当てた結果、27 件): FAIL は 4 件で、上の FAIL から `no longer references the non-existent watchdog_timeout event` を除いたもの。この 1 件だけが素通りで PASS する
- 変異なしの SKILL.md に対する修正後: 29 件すべて PASS

### その他

- **Size 再評価**: Changed Files は 1 件 (`tests/auto.bats`)。軸 1 は XS-S。軸 2 は、既存パターン (`md_section` の idiom と #1516 の素の代入) の横展開で -1、ヘルパーへの失敗の分岐の追加で +1 となり相殺して S。triage 時の Size S から変更なし (patch route)。個別テスト内の変更で、並列化フラグや共有モックフィクスチャではない (新規テストのフィクスチャは `$BATS_TEST_TMPDIR` 配下でテストごとに独立) ので、CI Dependency Minimum Override にも該当しない。`always-pr` は未設定なので、受け入れ条件 3 は patch route 形 (`gh run list --branch=main`) のままでよい。実際の判定は、実装コミットの push 後に `/verify` で行われる
- **audit / investigation 型の判定: no**。目的はテストの修正で、項目の分類結果を後続処理の判断根拠として残す成果物ではない。Spec に書いたテスト名・関数名・行番号は、着手時点の grep と実読で存在を確認した
- **fail-safe critical の判定: no**。変更対象はテストファイル内のヘルパーと `@test` で、ゲートでも検証器でも安全側の既定値を返すスクリプトでもない。それでも境界の挙動 (開始行なし、終了行なし、ファイルなし) は上の「実測」で確認した
- **新規分岐ロジックのテスト要件**: 対象 (`notable_judgment_section` に失敗の分岐を足す)。Implementation Step 3 の単体テスト 2 件で満たす
- **Pre-implementation FAIL Check (`skills/code/SKILL.md`)**: 対象外。新規テストは終了ステータスと出力の検査で、同項の対象は文字列一致アサート。代わりに、修正を外した作業コピーで新規テストが FAIL することを /spec のリハーサルで確認した
- **bats テストの入力形式**: 入力は `skills/auto/SKILL.md` の Markdown。`3. **Notable judgment** (...)` で始まる番号付きリスト項目 (L816) から、次の `4. **` で始まる行 (L845) の直前までが節で、先頭近くに字下げされた ` ```bash ` のコードフェンス (jq 集計) を含む。単体テストのフィクスチャは、開始行を改名した 3 行の Markdown
- **CI の bats**: `bats --jobs $(nproc) tests/` の並列実行。新規テストは `$BATS_TEST_TMPDIR` だけを使うので衝突しない。`ubuntu-latest` のみで、macOS ジョブは `scripts/*.sh` の `bash -n` だけ。bats テストのコードは bash 3.2+ でも解釈できる構文に限る
- **外部仕様の確認**: awk の `exit` (主ルールの `exit` は END を実行し、END 内の `exit expr` が終了ステータスを決める) と bats の `set -e` は、CI と同系統のツール (mawk、bats-core、bash) での直接測定と、リポジトリ内の先例 (`md_section` の同一 idiom) で裏付けたため、外部ドキュメントの参照は不要と判断した
- **禁止表現の走査**: Spec と docs は `scripts/check-forbidden-expressions.sh` の走査対象。非推奨の用語を書かない
- **コストが高い・不可逆な手順**: なし。外部サービスへのログインを伴う手順: なし

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1-3 を Spec の置き換え後コードのとおりに実装した (変更は `tests/auto.bats` のみ)

### Design Gaps/Ambiguities
- なし。変異確認 (開始行を `3. **Notable judgement**` に改名した作業コピー) の結果は Spec の期待値どおり: 29 件中 FAIL 5 件 (`uses jq -sc aggregation`、`references all four aggregated count fields`、`no longer references the non-existent watchdog_timeout event`、jq 集計 2 件)、PASS 24 件 (新規単体テスト 2 件を含む)
- 再調査コマンドの再実行で、範囲内 2 テストの `[section]` 欄がどちらも `section="$(notable_judgment_section "$SKILL_FILE")"` の代入行になることを確認した
- `scripts/check-bare-bracket-assertions.sh` は `references all four ...` の 4 行を報告するが、Spec で意図的に変更対象外としたもの (情報提供のみ)
- Pre-implementation FAIL Check は Spec Notes のとおり対象外 (新規テストは終了ステータスと出力の検査)。代わりに /spec リハーサルで検出力を確認済み
- 実行環境に `bats` が PATH に無く、`/tmp/bats-dl/src/bin/bats` (bats-core) を使用した。受け入れ条件に bats コマンドを使うものは無いので、bats-absent AC の持ち越しは発生しない

### Rework
- なし

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `notable_judgment_section` に `END{if (!found) exit 1}` を足し、`notable_judgment_jq_command` は節を先に代入で受けてから 2 段目の awk に渡す形にした (パイプラインは最後の awk の終了ステータスしか返さないため)
- 否定アサーションの 2 テストは `section="$(...)"` の素の代入 + `|| false` で受ける形にし、肯定アサーションだけのテストは変更しなかった

### Deferred Items
- 受け入れ条件 3 (`github_check "gh run list ..."`) は patch route の実装コミットが push されるまで評価できないため未チェックのまま。`/verify` で評価する

### Notes for Next Phase
- 受け入れ条件 1・2 (rubric) は /code Step 10 でチェック済み。変更は `tests/auto.bats` のみ
- 終了行 `4. **` を改名した場合は節が延びる方向にずれるが、素通りはしない (Spec Notes に記載済み)
