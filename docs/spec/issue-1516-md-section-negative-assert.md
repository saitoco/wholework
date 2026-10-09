# Issue #1516: tests: md_section を否定アサーションで検査するテストで節の取得失敗を検出

## Overview

#1514 (PR #1515) で bats テストの Markdown 節抽出を共通ヘルパー `md_section` (`tests/helpers/markdown-section.bash`) にまとめたが、見出しが見つからないときの exit 1 がテストに伝わらない呼び出し形が 6 テストに残っている。節の中身を否定アサーション (「〜を含まない」の検査) で確かめるテストは、見出しが改名されて節が空になっても PASS し続ける。

本 Issue で行うことは次の 2 点。

1. `md_section` (またはそれを包むラッパー関数) の結果を否定アサーションで検査している 6 テストを、節を素の代入 (`section="$(wrapper)"`) で受ける形に直し、見出し未検出でテストが FAIL するようにする
2. `docs/tech.md` (と日本語ミラーの `docs/ja/tech.md`) の `### BATS Markdown Section Extraction` 節に、否定アサーション (negative assertion) で検査するときの受け方の規約を明記する

対象外は Issue 本文のとおり。`tests/auto.bats` の `notable_judgment_section` は `md_section` ではなく inline awk で、置き換えを伴うため範囲外。

## Changed Files

- `tests/auto-batch.bats`: `List mode section: body grep read path removed` を、節を `section="$(list_mode_section)"` で受けてから `run grep -q 'json body' <<< "$section"` に変更 — `@test` 本文のみ。bash 3.2+ 互換 (`$(...)` と `<<<` のみ)
- `tests/review.bats`: `Non-Interactive Mode Behavior: job count is resolved as a separate literal step, not inline command substitution` を、`run non_interactive_mode_behavior_section` + `$output` から `section="$(non_interactive_mode_behavior_section)"` + `$section` に変更
- `tests/code.bats`: 3 テスト (`Behavioral Change Detection subsection does not restate the execution surface constraint`、`Step 9 full-suite override does not invoke the serial whole-suite form`、`Step 9 full-suite override resolves the job count as a separate literal step (no inline command substitution)`) を、`run xxx_section "$SKILL_FILE"` + `$output` から `section="$(xxx_section "$SKILL_FILE")"` + `$section` に変更
- `tests/verify.bats`: `Step 6 Re-runs description no longer re-verifies already-checked conditions` を、`step6_section | grep` から `section="$(step6_section)"` + `printf '%s\n' "$section" | grep` に変更
- `docs/tech.md`: `### BATS Markdown Section Extraction` 節の「終了ステータス」の箇条書きを終了ステータスの説明だけにし、続けて、節を素の代入で受ける規約、否定アサーションの前段に置いてはいけない 4 つの形、肯定アサーションは従来の形で足りる旨を追加する
- `docs/ja/tech.md`: 上記の日本語ミラー (`### BATS の Markdown 節抽出`)。`docs/tech.md` と同一コミットに含める (`scripts/check-translation-sync.sh` は最終コミット時刻の比較で IN_SYNC を判定するため)
- [Steering Docs sync candidate] inbound の keyword check はスキップ: Changed Files に SKILL.md・`modules/`・`scripts/` を含まないため
- [Steering Docs sync candidate (listing-side)] スキップ: ファイルの追加・削除・リネームもディレクトリ構成の変更も無いため (`docs/structure.md` のファイル数コメントも変わらない)

変更不要の確認 (grep と実読で確認済み):

- `tests/audit-manual-waiting-count.bats`、`tests/auto-completion-report.bats`、`tests/review-rubric-safe.bats`: 節を `| grep -q` の肯定アサーションだけで検査している (空の節では grep が失敗する)
- `tests/worktree-lifecycle.bats`、`tests/orchestration-fallbacks.bats`: すでに `s="$(...)"` / `block=$(md_section ...)` の素の代入で受けている
- `tests/auto.bats`: `md_section` を使う `step*_section` の呼び出しは肯定アサーションのみ。否定アサーションがあるのは inline awk の `notable_judgment_section` (L164、L177) で範囲外
- `tests/markdown-section.bats`: ヘルパー自体の単体テスト (`run md_section` + 明示的な `$status` 検査 + `refute_output_has`)。本 Issue の AC が列挙する 10 ファイルに含まれない
- `tests/helpers/markdown-section.bash` ([Outbound pointer sync candidate] として確認): ヘッダーコメントは呼び出し方 (`run` か代入か) に言及しておらず、新しい規約と矛盾しない (全文を読んで確認)

## Implementation Steps

1. 否定アサーション 6 テストを、節を素の代入で受ける形に変更する (→ 受け入れ条件 1)
   - 着手前に Notes の「再調査コマンド」を実行し、範囲内が 6 件であることを確認する。増減があれば同じ形で追随する (Issue 本文の Known Affected Sites の指示)
   - 各テストの先頭に `# Plain assignment (not run) so a missing heading fails the test (Issue #1516)` を 1 行付ける。この文言には `_section` / `md_section` を含めない (再調査コマンドの `[section]` 欄が、代入行を指すようにするため)
   - 行番号は main@1e08a8eb 時点。各テストで `$output` を参照している行は、すべて `$section` に置き換える
     - `tests/auto-batch.bats` L52: `run grep -q 'json body' <<< "$(list_mode_section)"` を 2 行に分ける — `section="$(list_mode_section)"` と `run grep -q 'json body' <<< "$section"`。L53 の `[ "$status" -ne 0 ]` は変えない
     - `tests/review.bats` L156-158: `run non_interactive_mode_behavior_section` を `section="$(non_interactive_mode_behavior_section)"` にし、L157-158 の `"$output"` を `"$section"` にする
     - `tests/code.bats` L109-110: `run behavioral_change_detection_section "$SKILL_FILE"` を `section="$(behavioral_change_detection_section "$SKILL_FILE")"` にし、L110 の `"$output"` を `"$section"` にする
     - `tests/code.bats` L124 と L130: `run step9_section "$SKILL_FILE"` を `section="$(step9_section "$SKILL_FILE")"` にし、L130 の `run bash -c '...' _ "$output"` を `_ "$section"` にする (L125-129 の既存コメントと L131 の `[ "$status" -ne 0 ]` は残す)
     - `tests/code.bats` L135-137: `run step9_section "$SKILL_FILE"` を `section="$(step9_section "$SKILL_FILE")"` にし、L136-137 の `"$output"` を `"$section"` にする
     - `tests/verify.bats` L162-164: 先頭に `section="$(step6_section)"` を置き、3 行を `if printf '%s\n' "$section" | grep -q -F "..."; then false; fi` と `printf '%s\n' "$section" | grep -q -F "..."` (2 行) に書き換える (検索文字列は変えない)
   - 肯定アサーションだけの他のテスト (`run xxx_section` + `[[ "$output" == ... ]]`、`xxx_section | grep -q`) は変更しない。空の節ではそれだけで失敗する
2. `docs/tech.md` の `### BATS Markdown Section Extraction` 節を更新する (parallel with 1) (→ 受け入れ条件 2, 3)
   - L242 の箇条書き (`The exit status is 1 ...`) を、終了ステータスの説明だけにし、その後ろに次の内容を追加する。現在の L242 の後半 (`Use s="$(md_section ...)" so a renamed heading ...`) は、追加する段落に移る。続く `This replaced per-test inline awk ...` の段落は残す
   - 見出しは追加しない。`section_contains` の走査範囲は、この `###` 見出しから次の同レベル以上の見出し (`## Forbidden Expressions`) の直前までで、追加内容はその中に収まる
   - 追加内容の英文に、リテラル `negative assertion` を含める (AC3 の `section_contains` 用。着手前の `docs/tech.md` には 0 件で、AC3 は何もしなくても PASS するものではない)
   - 置き換え後の文面:

     ````markdown
     - The exit status is 1 when the heading is not found (output is empty) and 2 when `END_LEVEL` is omitted and `HEADING_PREFIX` does not start with `#`.

     Receive the section with a plain assignment in the test body (`s="$(md_section ...)"`, or `s="$(step0_section "$FILE")"` for a wrapper function) so that a renamed heading fails the test instead of passing against an empty section. bats runs the test body under `set -e`, which turns the failed assignment into a test failure:

     ```bash
     @test "Step 0 does not mention the removed flag" {
         section="$(step0_section "$SKILL_FILE")"
         [[ "$section" != *"--removed-flag"* ]]
     }
     ```

     This matters most for a negative assertion, a check that something is absent from the section (`[[ "$section" != *foo* ]]`, `run grep ...` followed by `[ "$status" -ne 0 ]`, `if ... | grep -q foo; then false; fi`). An empty section satisfies every negative assertion, so a renamed heading would pass silently. Do not put a form that discards the exit status in front of one:

     - `run step0_section "$FILE"` followed by `[[ "$output" != ... ]]`: `run` always succeeds and keeps the status in `$status`.
     - `grep ... <<< "$(step0_section "$FILE")"`: a here-string does not propagate the command substitution's status.
     - `step0_section "$FILE" | grep ...`: a pipeline reports only its last command's status.
     - `local s="$(step0_section "$FILE")"`: `local` returns 0; declare with `local s` first, then assign on the next line.

     A positive assertion (`step0_section "$FILE" | grep -q foo`, or `[[ "$output" == *foo* ]]` after `run`) fails on an empty section by itself, so it may keep those forms.
     ````

3. `docs/ja/tech.md` の `### BATS の Markdown 節抽出` 節 (L218-235) を同期する (after 2) (→ 受け入れ条件 2 の翻訳同期)
   - L233 の箇条書きを同じ構成で置き換える。コードフェンスの数は `docs/tech.md` と合わせて 4 から 6 になる (`docs/translation-workflow.md` の Sync Procedure 5)。`docs/tech.md` と同一コミットに含める
   - 置き換え後の文面:

     ````markdown
     - 見出しが見つからないと終了ステータス 1 (出力は空)、`END_LEVEL` 省略かつ `HEADING_PREFIX` が `#` で始まらないと終了ステータス 2。

     節はテスト本体の素の代入 (`s="$(md_section ...)"`、ラッパー関数なら `s="$(step0_section "$FILE")"`) で受ける。こうすれば、見出しの改名時に空の節に対して素通りせず、テストが失敗する。bats はテスト本体を `set -e` で実行するため、代入の失敗がそのままテストの失敗になる。

     ```bash
     @test "Step 0 does not mention the removed flag" {
         section="$(step0_section "$SKILL_FILE")"
         [[ "$section" != *"--removed-flag"* ]]
     }
     ```

     特に重要なのが否定アサーション (節の中に何かが無いことの検査。`[[ "$section" != *foo* ]]`、`run grep ...` のあとの `[ "$status" -ne 0 ]`、`if ... | grep -q foo; then false; fi`) である。空の節はどの否定アサーションも満たすため、見出しが改名されても黙って PASS する。否定アサーションの前段に、終了ステータスを捨てる次の形を置かない。

     - `run step0_section "$FILE"` のあとに `[[ "$output" != ... ]]`: `run` は常に成功し、ステータスは `$status` に残る。
     - `grep ... <<< "$(step0_section "$FILE")"`: here-string はコマンド置換のステータスを伝えない。
     - `step0_section "$FILE" | grep ...`: パイプラインは最後のコマンドのステータスだけを返す。
     - `local s="$(step0_section "$FILE")"`: `local` が 0 を返す。先に `local s` と宣言し、次の行で代入する。

     肯定アサーション (`step0_section "$FILE" | grep -q foo`、`run` のあとの `[[ "$output" == *foo* ]]`) は、空の節ではそれだけで失敗するため、これらの形のままでよい。
     ````

4. ローカル検証 (after 1, 2, 3) (→ 受け入れ条件 1, 4)
   - bats の実行: 変更した 4 ファイルと `tests/markdown-section.bats` を実行し、全件 PASS を確認する。`bats` が PATH に無ければ、前回の取得先 `/tmp/bats-dl/src/bin/bats` (bats-core v1.11.1) が残っていればそれを使い、無ければ bats-core を新しい空ディレクトリに取得する。ワークツリー隔離ガードが glob と `&` を拒否するため、ファイル名はリテラルで並べた単純なコマンドにする
   - 変異確認: Notes の表のとおり、6 テストそれぞれの見出しを `sed -i` で一時的に壊し、該当テストが FAIL することを確認する。各変異のあと `git checkout -- <SKILL.md>` で必ず戻す
   - 再調査コマンドを再実行し、範囲内 6 テストの `[section]` 欄がすべて `section="$(...)"` の代入行になっていることを確認する
   - `git status --short` で、差分が Changed Files の 6 ファイルだけであることを確認する

## Verification

### Pre-merge

- <!-- verify: rubric "md_section を読み込んでいる tests/audit-manual-waiting-count.bats, tests/auto-batch.bats, tests/auto-completion-report.bats, tests/auto.bats, tests/code.bats, tests/orchestration-fallbacks.bats, tests/review-rubric-safe.bats, tests/review.bats, tests/verify.bats, tests/worktree-lifecycle.bats のうち、md_section (またはそれを包むラッパー関数) の結果を否定アサーション (「〜を含まない」「〜が存在しない」の検査) で検査しているテストが、md_section が見出しを見つけられずに失敗した場合にテスト自体が FAIL する形で書かれている。run + [[ \"$output\" != ... ]] や <<< \"$(...)\" のように md_section の終了ステータスを捨てる呼び出し形が、否定アサーションの前段に残っていない" --> 否定アサーションの前段で `md_section` の失敗がテストに伝わる
- <!-- verify: rubric "docs/tech.md の BATS Markdown Section Extraction 節 (または同等の bats テスト規約の節) に、md_section の結果を否定アサーションで検査するときは終了ステータスを捨てない形で受ける、という規約が書かれている" --> 規約が `docs/tech.md` に明記されている
- <!-- verify: section_contains "docs/tech.md" "BATS Markdown Section Extraction" "negative assertion" --> `docs/tech.md` の BATS Markdown Section Extraction 節に、否定アサーション (`negative assertion`) の扱いが記載されている
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion,status --jq 'if .[0].status != \"completed\" then \"in_progress\" else .[0].conclusion end'" "success" --> CI (test.yml) all jobs pass (patch route)

### Post-merge

- なし

## Notes

### 自動解決した判断

- **AC3 の verify command を修正し、Issue 本文を更新した**: `section_contains` の見出し引数は、先頭の `#` と空白を除去した見出し行に対する部分一致 (`modules/verify-executor.md` の `section_contains` の定義)。Issue 本文の `"### BATS Markdown Section Extraction"` は、どの見出しにも一致せず恒久的に UNCERTAIN になるため、`"BATS Markdown Section Extraction"` に直した。根拠は triage の AC 監査コメント (https://github.com/saitoco/wholework/issues/1516#issuecomment-6077186316) と、Issue Retrospective の「`/spec` が Comment Consumption で拾い、見出し引数から `###` を除去する」という指示。verify command の SSoT は Issue 本文なので (`modules/verify-patterns.md` §18)、Issue 本文を先に直し、Spec はそれを写した。Issue 本文の変更はこの 1 か所だけ
- **節の受け方は素の代入 `section="$(wrapper)"` に統一**。検討した他の案:
  - `md_section` 側で失敗を伝える: `run` は呼び出し先の終了ステータスを `$status` に逃がしてテスト本体には 0 を返すため、ヘルパーを変えても `run xxx_section` の形では防げない (下記の実測の A)
  - 否定アサーションの前に肯定アサーション (見出し行の存在確認) を足す: 動くが、テストごとに検査行が増え、`code.bats` の `Behavioral Change Detection` のように肯定側が自然に存在しないテストでは検査を新設することになる。素の代入は、既存の `code.bats` (`section="$(step10_section ...)"`) と `worktree-lifecycle.bats` (`s="$(...)"`) の流儀と同じで、検査行が増えない
  - 再発防止の lint (`.bats` を走査して禁止の 4 形を検出するテスト): AC は既存サイトの修正と規約の明記で、範囲外。必要なら別 Issue
- **肯定アサーションだけのテストは変更しない**: 空の節では `grep -q` や `[[ == ]]` がそれだけで失敗するため。変更を 6 テストに絞り、レビュー範囲を小さくする
- **範囲外**: `tests/auto.bats` の `notable_judgment_section` (inline awk、否定アサーションが L164・L177) は同じ素通りの危険があるが、Issue 本文が範囲外と明記している。`md_section` への置き換えと素の代入への変更をセットにした別 Issue の候補

### 実測: 呼び出し形ごとの挙動

見出しが無い (`md_section` が exit 1) ときの結果を、bats-core v1.11.1 の使い捨てプローブで実測した。

| 呼び出し形 | 見出しなし |
|-----------|-----------|
| A: `run wrapper` + `[[ "$output" != *x* ]]` | PASS (素通り) |
| B: `run grep -q x <<< "$(wrapper)"` + `[ "$status" -ne 0 ]` | PASS (素通り) |
| C: `if wrapper \| grep -q x; then false; fi` | PASS (素通り) |
| F: `local s="$(wrapper)"` + 否定アサーション | PASS (`local` が終了ステータスをマスク) |
| D: `section="$(wrapper)"` + `[[ "$section" != *x* ]]` | FAIL |
| G: `local s` の次の行で `s="$(wrapper)"` + 否定アサーション | FAIL |
| H: `section="$(wrapper)"` + `run bash -c '...' _ "$section"` + `[ "$status" -ne 0 ]` | FAIL |
| I: `section="$(wrapper)"` + `if printf '%s\n' "$section" \| grep -q x; then false; fi` | FAIL |

見出しがある場合は、素の代入の形 (E、J) も PASS する。出所: bats-core v1.11.1 (`/tmp/bats-dl/src`。#1514 の `/code` で取得されたもの)、プローブ `.tmp/probe-1516.bats` (実測後に削除、実測日 2026-10-09)。CI は `apt-get install bats` (ubuntu-latest) で、バージョンが異なる可能性があるが、テスト本体が `set -e` で動き、代入の失敗がテストの失敗になる点は bats 1.x で共通で、既存の `worktree-lifecycle.bats` も CI で同じ前提に依存している。

### 再調査コマンド (測定範囲付き)

範囲: `tests/*.bats` の全ファイル (`tests/helpers/` は含まない)。`@test` ブロックごとに、`_section` または `md_section` を含む行 (最初の 1 行を `[section]` として表示) と、否定を示す記述 (`!=`、`-ne `、`then false`、`refute`、`grep -v`、`grep -qv`、行頭の `!`、`run !`) を含む行の両方があるテストを列挙する。

```bash
awk 'function flush() { if (name != "" && sec != "" && neg != "") printf "%s:%d: %s\n  [section] %s\n%s", fname, startline, name, sec, neg } FNR==1 { flush(); name=""; sec=""; neg="" } /^@test / { flush(); name=$0; fname=FILENAME; startline=FNR; sec=""; neg=""; next } name != "" { if (sec == "" && $0 ~ /_section|md_section/) sec = FNR ": " $0; if ($0 ~ /!=|-ne |then false|refute|grep -v|grep -qv|^[[:space:]]*! |run ! /) neg = neg "    " FNR ": " $0 "\n" } END { flush() }' tests/*.bats
```

着手前 (main@1e08a8eb) の結果は 20 テスト。範囲内 6 件のほかは、粗い一致による範囲外の列挙:

| 区分 | 件数 | 内訳 |
|------|------|------|
| 範囲内 (`md_section` ラッパー) | 6 | `auto-batch.bats:51`、`code.bats:108` / `123` / `134`、`review.bats:155`、`verify.bats:161` |
| 範囲外: inline awk | 2 | `auto.bats:161` / `175` (`notable_judgment_section`) |
| 範囲外: ヘルパー自体の単体テスト | 7 | `markdown-section.bats` (`run md_section` + 明示的な `$status` 検査 + `refute_output_has`) |
| 範囲外: 偽陽性 | 5 | `run-{issue,merge,review,spec}.bats` の 4 件 (スタブ名 `_append_consumed_comments_section` が `_section` に一致)、`get-auto-session-report.bats:163` (inline `sed` で切り出した `residuals_section`、最終コマンドの `! echo ... \| grep`) |

着手後の期待: 同じ 20 テストが列挙されるが、範囲内 6 テストの `[section]` 欄は `section="$(...)"` の代入行になる (`run` / `<<<` / パイプの形ではなくなる)。

### 検証の参照点 (AC1 は不在確認)

`modules/verify-patterns.md` §26 に従い、AC1 の参照点を記録する。

- 変更前の検出リスト: 上の範囲内 6 テスト (main@1e08a8eb 時点)
- 対照群: すでに素の代入で受けているテスト (`tests/code.bats` L254-L312 の `section="$(stepNN_section ...)"` 形、`tests/worktree-lifecycle.bats` の `s="$(...)"` 形)。変更されずに残り、再調査コマンドでも範囲内に入らない
- 母集団の非空性: 範囲内 6 テストは、再調査コマンドの出力と該当行の実読で実在を確認済み

### 変異確認の対象表 (Step 4)

各テストが参照する SKILL.md と、見出しを壊す `sed` の例。`md_section` は前方一致なので、末尾に文字を足すだけでは壊れない。見出しの途中を変える。bats の入力は `SKILL.md` の Markdown で、ラッパー関数は見出しの接頭辞から次の同レベル以上の見出しの直前までを返し、接頭辞が見つからないと exit 1 を返す。

| テスト | ラッパーの見出し (前方一致) | SKILL.md | 変異の例 |
|--------|---------------------------|----------|---------|
| `auto-batch.bats:51` | `### List mode` | `skills/auto/SKILL.md:1179` | `s/^### List mode (/### Lists mode (/` |
| `review.bats:155` | `## Non-Interactive Mode Behavior` | `skills/review/SKILL.md:29` | `s/^## Non-Interactive Mode Behavior/## Non-Interactive Modes Behavior/` |
| `code.bats:108` | `#### Behavioral Change Detection` | `skills/code/SKILL.md:360` | `s/^#### Behavioral Change Detection/#### Behavioural Change Detection/` |
| `code.bats:123` / `134` | `### Step 9:` | `skills/code/SKILL.md:347` | `s/^### Step 9: Run Tests/### Step 09: Run Tests/` |
| `verify.bats:161` | `### Step 6: ` | `skills/verify/SKILL.md:313` | `s/^### Step 6: Update/### Step 06: Update/` |

変異の間は、対象の SKILL.md 以外を触らない。任意 (必須ではない): 変更前のテストに同じ変異を当て、6 テストが素通りで PASS することを先に確認しておくと、バグの再現になる。

### その他

- **Size 再評価**: Changed Files は 6 件 (bats 4 + docs 2)。`docs/ja/tech.md` は機械的な日本語ミラー追随で、実質件数に数えない (#183・#1463・#1484 の前例)。実質 5 件で軸 1 は M、軸 2 は同一パターンの横展開・原因が明確で -1 となり S。triage 時の Size S から変更なし (patch route)。`tests/` の変更だが、並列化フラグや共有モックフィクスチャではなく個別テスト内のアサーション変更なので、CI Dependency Minimum Override にも該当しない。AC4 は patch route 形 (`gh run list`) のままでよい。実装コミットの push 後でないと意味を持たないため、実際の判定は `/verify` で行われる (`skills/code/SKILL.md` Step 10 の patch route の扱い)
- **audit / investigation 型の判定: no**。目的はテストと規約の修正で、項目の分類結果を後続処理の判断根拠として残す成果物ではない。Spec に書いたテスト名・行番号・関数名は、着手時点の grep と実読で存在を確認した
- **fail-safe critical の判定: no**。変更対象はテストと文書で、ゲートや検証器、安全側の既定値を返すスクリプトではない
- **新規分岐ロジックのテスト要件: 対象外**。既存スクリプト・モジュール・スキルへの新しい分岐の追加ではなく、既存テストの受け方の変更。受け入れ条件に代わる検出力の確認は、Step 4 の変異確認で行う
- **bats テストの入力形式**: 入力は `skills/{auto,review,code,verify}/SKILL.md` の Markdown (上の変異確認の対象表の見出し)。新しいデータ形式は無い
- **CI の bats**: `ubuntu-latest` のみで、macOS ジョブは `scripts/*.sh` の `bash -n` だけ。bats テストのコードは bash 3.2+ でも解釈できる構文に限る
- **禁止表現の走査**: Spec と docs は `scripts/check-forbidden-expressions.sh` の走査対象。非推奨の用語 (旧称の verify 系の用語など) を書かない
- **コストが高い・不可逆な手順**: なし。外部サービスへのログインを伴う手順: なし

## Consumed Comments

- saito / MEMBER / first-class / triage の AC 監査: AC3 の `section_contains` の見出し引数に先頭の `###` を含めており恒久的に UNCERTAIN になる (Pattern 6 サブパターン 1)、`###` を除く修正案 / https://github.com/saitoco/wholework/issues/1516#issuecomment-6077186316
- saito / MEMBER / first-class / Issue Retrospective: 対象範囲を `md_section` とラッパー関数に限定した判断、CI 確認の AC を patch route 形にした判断、AC3 の欠陥は `/spec` が Comment Consumption で拾って修正する旨 / https://github.com/saitoco/wholework/issues/1516#issuecomment-6077189908

## Code Retrospective

### Deviations from Design
- なし。Spec の Implementation Steps 1〜4 を記載どおりに実施した。

### Design Gaps/Ambiguities
- 着手前の再調査コマンドは Spec の想定どおり範囲内 6 件で、増減はなかった。
- bats は PATH に無く、前回の取得先 `/tmp/bats-dl/src/bin/bats` が残っていたためそれを使った。bats-core の再取得は不要だった。
- worktree 隔離ガードが複合コマンド (関数定義と `;` 連結を含む変異確認ループ) を拒否したため、変異確認は `sed -i` / bats / `git checkout --` を 1 コマンドずつに分けて実施した。Spec の Step 4 は「単純なコマンドにする」と書いていたが、変異確認のループも同様に分割が必要な点は書かれていなかった。
- 新規の文字列一致アサーション (verification-style test) は追加していない (既存テストの受け方の変更のみ)。そのため Pre-implementation FAIL Check は対象外。代わりに変異確認で検出力を確認した。

### Rework
- なし。変異確認 (6 テストすべてで見出しを壊して FAIL を確認、各変異後に `git checkout --` で復元) は初回で期待どおりの結果だった。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 否定アサーション 6 テストを、節を素の代入 `section="$(wrapper)"` で受ける形に統一した (Spec の決定どおり。`md_section` 側の変更や lint の新設は行わない)。
- 実装は 2 コミットに分けた: テスト 4 ファイルの変更と、`docs/tech.md` / `docs/ja/tech.md` の同一コミット (`closes #1516` を付与)。

### Deferred Items
- AC4 (CI `test.yml` 成功の確認、`github_check "gh run list"`): 実装コミットの push 前は評価できないため未チェックのまま。push 後の CI 結果を `/verify` で判定する。
- `tests/auto.bats` の `notable_judgment_section` (inline awk、否定アサーションあり) は Issue 本文で範囲外。必要なら別 Issue。

### Notes for Next Phase
- Issue 本文の AC1〜3 は `/code` でチェック済み (rubric 2 件と `section_contains` 1 件)。AC4 だけが残る。
- bats をローカル実行できたため (`/tmp/bats-dl/src/bin/bats`)、変更 4 ファイルと `tests/markdown-section.bats` は全件 PASS を確認済み。CI の全体結果は未確認。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- triage の AC 監査で、AC3 の `section_contains` の見出し引数に `###` が入っていて恒久的に UNCERTAIN になる欠陥が見つかった。`/spec` が Comment Consumption でこれを拾い、Issue 本文を修正した。監査から修正までの経路が設計どおりに機能した。
- 呼び出し形ごとの挙動を使い捨てプローブで実測し、表にした (A〜J)。`local s="$(...)"` が終了ステータスを隠す F の形まで押さえたので、規約の「前段に置いてはいけない 4 つの形」に根拠が付いた。

#### design
- 素の代入に統一する判断は、既存の `code.bats` と `worktree-lifecycle.bats` の書き方と揃っていて、テストの検査行も増えない。lint の新設は範囲外として見送った。

#### code
- 手戻りはなかった。変異確認 (見出しを壊すと 6 テスト・7 件が FAIL) で検出力を確かめている。
- worktree の隔離ガードが、変異確認のループ (関数定義と `;` の連結) を拒否した。Spec の Step 4 は「単純なコマンドにする」としか書いておらず、ループも分割が要る点が抜けていた。同じ拒否はこのセッションの `/auto` 側でも複数回起きている。

#### review
- patch route なので review フェーズはない。

#### merge
- main へ直接 push し、CI (test.yml) は success だった。

#### verify
- AC1〜3 は `/code` でチェック済みのため SKIPPED とし、残る AC4 (CI) は PASS だった。FAIL も UNCERTAIN もない。

### Improvement Proposals
- `tests/auto.bats` の `notable_judgment_section` は inline awk で、否定アサーション (L164・L177) の前段で節が取れなかったときに素通りする。本 Issue の範囲外とした残りの 1 件で、`md_section` への置き換えと素の代入への変更をまとめて行う。
