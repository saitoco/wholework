# Issue #1479: merge: pre-merge-check.sh が check script の無い repo で毎回 Error を出さないように

## Overview

`scripts/pre-merge-check.sh` は check script (`scripts/check-forbidden-expressions.sh`) を対象 repo の worktree 内で解決する。この script を同梱するのは wholework 自身だけのため、同梱しない downstream repo では `/merge` (`scripts/run-merge.sh`) のたびに次の 2 行が出力される。

```
Error: check script not found in worktree at <absolute-path>/wt/scripts/check-forbidden-expressions.sh
Warning: pre-merge-check.sh could not complete (exit 1); proceeding (fail-open).
```

merge 自体は fail-open で進むため実害はないが、(1) error 風の出力が毎回出てオペレーターが警告を読み飛ばすようになり、check script を同梱する repo で本当に check が完了しなかった場合の警告も埋もれる、(2) downstream repo の Verify Retrospective 2 件で原因が「plugin が local checkout であること」に誤帰属され、本当の原因が見過ごされた、という問題がある。

本 Issue は「check script が base ref と head ref の**両方**に無い」ケースを、環境エラーではなく**対象外 (not applicable)** として扱う。`pre-merge-check.sh` が `NOT_APPLICABLE: ...` を stdout に 1 行出力して exit 0 とし、`/review` Step 9 の exit code 分類表 (exhaustive 宣言) にこの新しい出力を載せる。片方の ref にだけ script がある場合と git 操作の失敗は、従来どおり環境エラー (exit 1) のままとする。

## Reproduction Steps

1. `scripts/check-forbidden-expressions.sh` を持たない repo (wholework plugin を使う downstream repo) で PR を用意する
2. `/merge <PR番号>` (または `scripts/run-merge.sh <PR番号>`) を実行する
3. `run-merge.sh` が `wait-ci-checks.sh` の直後に `pre-merge-check.sh <PR番号>` を呼ぶ。`pre-merge-check.sh` は base ref の ephemeral worktree 内で check script を探し、無いので stderr に `Error: check script not found in worktree at <tmp>/wt/scripts/check-forbidden-expressions.sh` を出して exit 1 する
4. `run-merge.sh` が exit 1 を「分類器が完了できなかった」とみなし、`Warning: pre-merge-check.sh could not complete (exit 1); proceeding (fail-open).` を stderr に出して merge を続行する

spec 時点で再現を確認済み: bats fixture (bare origin + 作業 repo + gh mock) を手動で再現し、base / head の両方から check script を削除した状態で現行の `scripts/pre-merge-check.sh` を実行すると、exit 1 と `Error: check script not found in worktree at /tmp/tmp.XXXXXX/wt/scripts/check-forbidden-expressions.sh` になった (Notes の「spec 時点のプロトタイプ検証」参照)。

## Root Cause

`scripts/pre-merge-check.sh` の `run_check_on_ref()` 内にある存在確認 (`[[ ! -f "$wt/$CHECK_REL" ]]`、HEAD `fc28fcdb` 時点で L61-66) が、check script が無い状態を一律に環境エラー (exit 1) として扱う。この関数は base を先に評価して即 `exit 1` するため、head 側を見ることもない。その結果、次の 2 つを区別できない。

- 両 ref に script が無い = そもそもこの repo には check が存在しない (対象外)
- 片方の ref にだけ無い、または git 操作が失敗した = 本当の環境エラー

さらに `run-merge.sh` (L102-108) は exit 2 以外の非 0 を一律に fail-open 警告にするため、対象外の repo では merge のたびに Error と Warning が出る。

修正方針の妥当性: worktree を作る**前**に、各 ref の tree 内に check script が存在するかを `git ls-tree` で判定する。tree レベルで判定する理由は 2 つ。(1) worktree 内の `-f` 判定は、checkout 側の異常 (sparse checkout 等で tree にはあるが展開されない) まで「不在」と誤認しうるが、tree 判定なら ref の内容そのものを見られる。(2) 対象外 repo では worktree の作成・削除自体が不要になる。判定結果は 3 通りに分岐する。両方不在は `NOT_APPLICABLE:` (exit 0)、片方のみ不在は環境エラー (exit 1)、両方存在は既存の分類ロジック (変更なし) である。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective — Background の事実確認、`/review` Step 9 の exhaustive な exit code 表に `NOT_APPLICABLE:` を載せる AC (AC5) の追加、出力 prefix `NOT_APPLICABLE:` と stdout 出力の Auto-Resolve を記録 (本 Spec に反映済み。ただし AC5 の「non-blocking」記述のみ本 Spec で再判断した。Notes の「Issue 本文と既存実装の整合性確認」参照) / https://github.com/saitoco/wholework/issues/1479#issuecomment-5963832778
- saito / MEMBER / first-class / Triage AC audit 警告 — AC4 の `command "bats tests/pre-merge-check.bats"` は既存テストだけで常時 PASS になるとの指摘。新規テスト名を本 Spec で確定し `file_contains` を併記した (Issue 本文の AC4 に反映済み) / https://github.com/saitoco/wholework/issues/1479#issuecomment-5963832931

## Changed Files

- `scripts/pre-merge-check.sh`: (1) header コメントの Exit codes を `0 (CLEAN/FIXED/PRE_EXISTING/NOT_APPLICABLE)` に更新し、NOT_APPLICABLE の説明コメントを追加 (2) fetch ブロックの直後 (`# Run the check on a given ref in an ephemeral detached worktree.` コメントの直前) に `probe_check_on_ref()` 関数と、両 ref の probe 結果による分岐 (両方不在: `NOT_APPLICABLE:` を stdout に出して exit 0 / 片側のみ: stderr に `Error:` を出して exit 1 / 両方存在: 既存フローへ) を追加。`run_check_on_ref()` と分類ブロックは変更しない — bash 3.2+ 互換 (`git ls-tree` と `[[ ]]` のみ使用し、`mapfile`・連想配列は使わない)
- `tests/pre-merge-check.bats`: ヘルパー `_remove_check_script_on_branch()` を追加し、新規テスト 6 件を追加 (Implementation Steps 2 参照)。既存 8 件のテストは変更しない
- `skills/review/SKILL.md`: Step 9 の exit code 分類表に `NOT_APPLICABLE:` 行 (exit 0 / Blocking) を追加し、exit 1 行の括弧書きに新しい環境エラー要因を追記し、表の直後の fail-closed 説明に `NOT_APPLICABLE:` の扱いを 1 段落追加する。追加行は英語のみ (CI の Language Convention check 対象)
- `tests/review.bats`: Step 9 の新規行を固定するテストを 1 件追加する。既存の `enumerates all four classifications` テストは変更しない
- `docs/structure.md`: `scripts/pre-merge-check.sh` の説明 (L238) の分類リストに `NOT_APPLICABLE (exit 0; ...)` を追加する [Steering Docs sync]
- `docs/ja/structure.md`: 上記の日本語ミラー (L231) を同期する [`docs/translation-workflow.md` の同期手順]
- `modules/orchestration-fallbacks.md`: `## baseline-failure` の Escalation と Rationale を更新する [Steering Docs sync]
- `skills/issue/spec-test-guidelines.md`: [Steering Docs sync candidate・優先度低] marker file 規則の表と Applicability の記述に NOT_APPLICABLE シナリオを加えるか、`/code` が本文を読んで判断する (Implementation Steps 4 参照)

変更不要と確認したもの (いずれも grep / Read で確認済み):

- `scripts/run-merge.sh`: L102-108 は exit code だけで分岐する (2: abort / 0: 続行 / その他: fail-open 警告)。新しい outcome は exit 0 なので分岐の変更は不要。stdout の `NOT_APPLICABLE:` 行は run-merge の出力にそのまま流れる (informational)
- `tests/run-merge.bats`: `pre-merge-check.sh` は mock 化されており (L151-156 の既定 mock と L753 以降の exit 2 テスト)、`run-merge.sh` 自体が変わらないため変更不要
- `skills/merge/SKILL.md` L40: 「新規 FAILURE は abort、pre-existing は通す」という概要のみで outcome を列挙していないため変更不要
- `README.md` / `README.ja.md` / `docs/workflow.md` / `docs/ja/workflow.md` / `CLAUDE.md`: `pre-merge-check` の言及が 0 件 (`grep -c`)。`modules/doc-checker.md` と `modules/skill-dev-doc-impact.md` の Change Type (script / skill の変更に対する README・workflow の更新) に該当する更新対象はない
- `skills/review/SKILL.md` の frontmatter `allowed-tools`: `${CLAUDE_PLUGIN_ROOT}/scripts/pre-merge-check.sh:*` は登録済み (新規 script の追加なし)
- `modules/ci-failure-classifier.md`: `skills/review/SKILL.md` Step 9 からの outbound pointer 先だが、`pre-merge-check` の言及が 0 件で、今回の変更 (NOT_APPLICABLE の追加) の影響を受けない

## Implementation Steps

1. **`scripts/pre-merge-check.sh` を変更する** (→ acceptance criteria 1, 2, 3)

   - header コメント (L1-4) の `# Exit codes:` 行を `# Exit codes: 0 (CLEAN/FIXED/PRE_EXISTING/NOT_APPLICABLE), 1 (env error), 2 (NEW_FAILURE)` に更新し、その直下に NOT_APPLICABLE の説明を英語のコメントで追加する。内容: check script が base と head の両 ref に無い場合はこの repo では対象外 (not applicable) であり環境エラーではない / 片側のみ存在する場合と git の失敗は exit 1 のまま
   - fetch ブロック (`git fetch` 失敗時に `Error: git fetch failed ...` で exit 1 する箇所) の**直後**、`# Run the check on a given ref in an ephemeral detached worktree.` コメントの**直前**に、次を追加する
     - `probe_check_on_ref()` 関数: 引数 `ref` に対し、`if ! listing=$(git ls-tree --name-only "origin/${ref}" -- "$CHECK_REL"); then` の形で実行する (`set -e` 下で、失敗時に独自の `Error:` を出してから終了するため)。非 0 終了なら `echo "Error: could not inspect origin/$ref for $CHECK_REL" >&2` して `exit 1`。成功時は `listing` が空でなければ `_ref_has_check=true`、空なら `_ref_has_check=false` を設定する。stderr は抑制しない (git の `fatal:` 行を診断に残す)
     - **probe の失敗を「不在」と解釈してはならない**。「不在」と読めるのは、probe が成功し (exit 0)、かつ出力が空のときだけ
     - `local listing` の宣言と代入は別行にする (`local listing=$(...)` は終了コードを隠すため使わない)
     - `probe_check_on_ref` はコマンド置換 (`$(...)`) の中で呼ばず、直接呼び出して `_ref_has_check` で結果を受け取る (関数内の `exit 1` を呼び出し元スクリプトの終了にするため。既存の `run_check_on_ref` と `_check_exit` の流儀に揃える)
     - 呼び出しと分岐: `probe_check_on_ref "$BASE_REF"` → `base_has_check=$_ref_has_check`、`probe_check_on_ref "$HEAD_REF"` → `head_has_check=$_ref_has_check`。その後
       - 両方 `false`: `echo "NOT_APPLICABLE: $CHECK check is not applicable ($CHECK_REL is absent from both $BASE_REF and $HEAD_REF)"` を **stdout** に出して `exit 0`
       - `base_has_check` と `head_has_check` が異なる: `echo "Error: $CHECK_REL exists on only one of $BASE_REF (present: $base_has_check) and $HEAD_REF (present: $head_has_check)" >&2` して `exit 1`
       - 両方 `true`: 何もせず既存フロー (`run_check_on_ref` 以降) へ進む
   - `run_check_on_ref()` と末尾の分類ブロックは**変更しない**。関数内の `[[ ! -f "$wt/$CHECK_REL" ]]` ガードは、「tree には script があるが worktree に通常ファイルとして展開されない」異常を引き続き exit 1 で報告する防御として残す
   - 追加行はすべて英語にする (CJK 文字を含めない)。CI の `Language Convention check` が `scripts/` の追加行を走査する
   - エッジケースと依存コマンド失敗時の挙動 (fail-safe critical のため明記する):

     | 入力 / 状況 | 期待される挙動 | 根拠 |
     |-------------|----------------|------|
     | 引数なし / 未知の check 名 | `Usage:` / `Error: unknown check` を stderr、exit 1 (既存) | 変更なし |
     | `gh pr view` が空の head / base ref を返す | `Error: could not resolve ...` exit 1 (既存) | 変更なし |
     | `git fetch` 失敗 | `Error: git fetch failed ...` exit 1 (既存) | ref の内容を判定できない状態を、対象外と誤認しない |
     | probe (`git ls-tree`) の失敗 (ref 解決不能など) | `Error: could not inspect ...` exit 1 (新規) | **fail-closed**。失敗を「不在」と読むと git の不調が `NOT_APPLICABLE` (exit 0) に化け、`/review` の gate を誤って緩める入口になる。不在は「成功かつ出力が空」だけ |
     | 両 ref の tree に script が無い | `NOT_APPLICABLE:` を stdout、exit 0 (新規) | この repo には check が存在しない。`/merge` は従来も fail-open で進んでいたので実効は同じで、ノイズだけが消える |
     | 片側の ref にだけ script がある | `Error: ... exists on only one of ...` exit 1 (メッセージは新規、exit code は従来どおり) | PR が check を追加・削除している等、判定の前提が崩れている。呼び出し元の既存の扱い (`/merge`: fail-open、`/review`: fail-closed) を維持する |
     | 両 ref の tree に script があるが worktree に展開されない | `Error: check script not found in worktree ...` exit 1 (既存ガード) | tree と checkout の不整合は環境エラー |
     | `git worktree add` 失敗 | `Error: git worktree add failed ...` exit 1 (既存) | 変更なし |
     | check script 自体が非 0 で終了 | その ref の FAIL として分類 (既存) | 変更なし |
     | worktree 削除・`rm -rf` の失敗 | 無視 (`\|\| true`、既存) | cleanup はベストエフォート。判定に影響しない |
     | 特殊文字を含む ref 名 (`/`・`+`・`#`・多バイト文字) | すべて引用符付きの 1 引数として渡す。probe の結果は「空か否か」だけを見て、内容をパースしない | 既存の `git fetch` / `git worktree add` と同じ扱い |
     | 出力に改行・CRLF が含まれる場合 | probe は空 / 非空だけを判定する。`NOT_APPLICABLE:` 行の prefix は常に先頭 | 分類ラベルの検出が ref 名の中身に依存しない |
     | 空・巨大な入力 | PR 番号が空・不正なら `gh` が失敗して非 0 終了 (既存)。巨大でも probe の出力は最大 1 行 | 入力サイズに依存する処理を追加しない |

2. **`tests/pre-merge-check.bats` にテストを追加する** (after 1) (→ acceptance criteria 4, 1, 2)

   - ヘルパー `_remove_check_script_on_branch()` を、既存ヘルパー (`_setup_feature_branch` / `_mock_gh_refs`) と同じ並びに追加する。処理: `<branch>` を checkout → `git rm -q scripts/check-forbidden-expressions.sh` → commit → `git push origin <branch>` → `git checkout main`
   - 新規テスト 6 件を追加する。**名前は下記のとおりに固定する** (AC4 の `file_contains` がこの文字列を参照する)

     1. `@test "NOT_APPLICABLE: script absent from both refs exits 0 with NOT_APPLICABLE label"` — fixture: `_remove_check_script_on_branch main` → `_setup_feature_branch "feature-no-check" "clean content"` → `_mock_gh_refs "feature-no-check" "main"`。assert: `[ "$status" -eq 0 ]`、output が `NOT_APPLICABLE:` と `not applicable` を含み、`Error` と `Warning` を含まない
     2. `@test "env error: check script present on base only exits 1"` — fixture: `_setup_feature_branch "feature-drops-check" "clean content"` → `_remove_check_script_on_branch "feature-drops-check"` → `_mock_gh_refs "feature-drops-check" "main"`。assert: status 1、output が `only one of` を含み、`NOT_APPLICABLE` を含まない
     3. `@test "env error: check script present on head only exits 1"` — fixture: `_setup_feature_branch "feature-adds-check" "clean content"` (script を持つ main から分岐) → `_remove_check_script_on_branch main` (base から script を消す) → `_mock_gh_refs "feature-adds-check" "main"`。assert は 2 と同じ
     4. `@test "env error: git fetch failure exits 1"` — `_mock_gh_refs "no-such-branch" "main"` (origin に無い head ref)。assert: status 1、output が `git fetch failed` を含む
     5. `@test "env error: git worktree add failure exits 1"` — 両 ref に script がある通常の fixture (`_setup_feature_branch "feature-clean" "clean content"` と `_mock_gh_refs "feature-clean" "main"`) に、`$MOCK_DIR/git` の shim を置く。shim は `git worktree add` のときだけ `exit 1`、それ以外は実 git の絶対パス (shim 作成**前**に `command -v git` で取得する) へ `exec` する。assert: status 1、output が `git worktree add failed` を含む
     6. `@test "env error: git ref inspection failure is not read as absent exits 1"` — 5 と同じ fixture で、shim が `ls-tree` のときだけ `echo "fatal: simulated ls-tree failure" >&2` して `exit 128` する。assert: status 1、output が `could not inspect` を含み、`NOT_APPLICABLE` を含まない (probe の失敗が「不在」に化けないことを固定する)
   - 新規テストの文字列 assert は `[[ "$output" == *"..."* ]] || false` (否定は `[[ "$output" != *"..."* ]] || false`) の形で書く。bash 3.2 では `[[ ]]` を単体で書くと `set -e` で失敗が伝播しないため、`|| false` が必要 (`scripts/check-bare-bracket-assertions.sh` の警告対象で、`tests/resolve-preview-env.bats` に既存例がある)。`[ "$status" -eq N ]` はそのままでよい
   - 既存の 8 テスト (名前を含む) は変更しない

3. **`skills/review/SKILL.md` Step 9 と `tests/review.bats` を更新する** (parallel with 1, 2) (→ acceptance criteria 5)

   - `skills/review/SKILL.md` の `### Pre-existing failure exception (baseline attribution)` 内、`Branch on the exit code (exhaustive):` の表を変更する (見出し行と既存 4 行の順序は保つ)
     - `FIXED:` / `CLEAN:` を扱う exit 0 の行の**直後**、exit 1 の行の**直前**に、次の行を挿入する。**1 行で書く** (AC5 の `grep "NOT_APPLICABLE:.*Blocking"` は同一行に両方があることを要求する)

       ```
       | 0 | `NOT_APPLICABLE:` | check script absent from both base and head — nothing to compare, so no baseline attribution was made | **Blocking** — the exception does not apply; inject the MUST entry as before, and its body must state that baseline attribution was not applicable (check script absent from both refs) |
       ```
     - exit 1 の行の括弧書きを `(env error: missing args; ref resolution, fetch, ref inspection, or worktree-add failure; or the check script present on only one ref)` に更新する (表の exhaustive 性を保つため)
   - 表の直後にある `Exit 1 is fail-closed rather than mirroring ...` で始まる段落の**後**に、新しい段落を追加する。内容は次の趣旨 (文面は `/code` が整えてよいが、英語のみ・半角 `!` 禁止):

     ```
     `NOT_APPLICABLE:` is blocking for the same reason, even though its exit code is 0. The classifier exits 0 so that `run-merge.sh` — where it only adds a gate — proceeds without a fail-open warning in repositories that do not ship the check script. Here, however, it made no baseline attribution (there was nothing to compare), so the same principle applies: fall back to the behavior that existed before the classifier was introduced, which means keeping the block.
     ```
   - Step 9 の他の箇所は**変更しない**: Non-blocking outcome handling の `PRE_EXISTING` / `FIXED` / `CLEAN` の列挙 (L441, L446, L452) と、Step 10 の injection 文 2 箇所 (L568, L643) は、`NOT_APPLICABLE:` が Non-blocking の集合に入らないため、既存の記述のまま正確である
   - `tests/review.bats`: 既存の `@test "Step 9: pre-existing CI failure exception enumerates all four classifications"` の**直後**に、新規テスト 1 件を追加する: `@test "Step 9: pre-existing CI failure exception keeps NOT_APPLICABLE: blocking despite exit 0"`。`step9_section` から (a) `NOT_APPLICABLE:` を含むこと、(b) 表の行 (行頭が `| 0 |` で、2 列目が `NOT_APPLICABLE:`) が `**Blocking**` を含むこと、を検証する (`grep -q -F` / `grep -q -E`)。既存テストの名前と内容は変更しない

4. **ドキュメントを同期する** (parallel with 1〜3) (対応する acceptance criteria なし — SHOULD レベルの整合)

   - `docs/structure.md` (L238 の `scripts/pre-merge-check.sh` 項目): 分類リスト `NEW_FAILURE (exit 2) / PRE_EXISTING / FIXED / CLEAN (exit 0) / env error (exit 1)` を `NEW_FAILURE (exit 2) / PRE_EXISTING / FIXED / CLEAN (exit 0) / NOT_APPLICABLE (exit 0; check script absent from both refs) / env error (exit 1; includes the check script being present on only one ref)` に更新する
   - `docs/ja/structure.md` (L231): 上記を日本語で同期する (`docs/translation-workflow.md` の同期手順。該当行は code fence を含まないため、fence 数の確認は不要)
   - `modules/orchestration-fallbacks.md` の `## baseline-failure`
     - Escalation の `If pre-merge-check.sh exits 1 (env error: ref resolution, fetch, or worktree failure) ...` の項目の括弧書きに `ref inspection` と `check script present on only one ref` を加え、直後に 1 項目を追加する: `A repository that ships the check script on neither ref is not an env error: pre-merge-check.sh prints a NOT_APPLICABLE: line and exits 0, so run-merge.sh proceeds without a fail-open warning.`
     - Rationale の `classifies the result (NEW_FAILURE / PRE_EXISTING / FIXED / CLEAN)` に `NOT_APPLICABLE` を加える
   - `skills/issue/spec-test-guidelines.md` ([Steering Docs sync candidate]・優先度低): `### When the marker file pattern is needed` の表に `NOT_APPLICABLE (script absent from both refs)` 行 (base / head とも check script なし、空コミットのリスクは Yes) を追加し、`### Applicability` の「mandatory for PRE_EXISTING and CLEAN scenarios」に NOT_APPLICABLE を加える。`/code` が本文を読んで更新か見送りかを最終判断してよい (見送る場合は Code Retrospective に理由を残す)
   - `modules/` と `skills/` 配下の追加行は英語のみにする (CI の `Language Convention check`)

5. **検証を実行する** (after 1〜4)

   - `bash -n scripts/pre-merge-check.sh` (構文)、`bash scripts/check-forbidden-expressions.sh` (禁止表現。`docs/` と `tests/` も走査対象)、`python3 scripts/validate-skill-syntax.py skills/` (SKILL.md の構文) を実行する
   - CI の `Language Convention check` 相当として、`git diff -U100000 origin/main...HEAD -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py` を実行し、追加行に CJK 文字が無いことを確認する (patch route で PR が無い場合は、`origin/main...HEAD` を直前のコミットとの差分に読み替える)
   - `bats tests/pre-merge-check.bats` と `bats tests/review.bats` を前景で実行する。**spec を作成した環境には bats が未インストール** (`command -v bats` が空) のため、実行環境にも無い場合は CI の `Run bats tests` ジョブの結果で確認する。その際、Notes の「手動再現シナリオ」を使って新しい `pre-merge-check.sh` の挙動を手元で確認してもよい

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/pre-merge-check.sh treats the case where the check script is absent from both the base ref and the head ref as not applicable: it prints a short informational line (not 'Error') and exits 0 without a fail-open warning" --> When neither ref contains the check script, the check is reported as not applicable and exits 0
- <!-- verify: rubric "scripts/pre-merge-check.sh still reports an error (non-zero exit) when the check script exists on one ref but not the other, or when git worktree add / git fetch fails" --> Partial presence and git failures are still reported as errors
- <!-- verify: grep "not applicable" "scripts/pre-merge-check.sh" --> <!-- verify: file_contains "scripts/pre-merge-check.sh" "NOT_APPLICABLE:" --> The not-applicable path is identifiable in the script
- <!-- verify: command "bats tests/pre-merge-check.bats" --> <!-- verify: file_contains "tests/pre-merge-check.bats" "NOT_APPLICABLE: script absent from both refs" --> <!-- verify: file_contains "tests/pre-merge-check.bats" "env error: check script present on" --> Tests cover the not-applicable case (both refs lack the script), the partial-presence error cases (script on only one ref), and the existing error cases
- <!-- verify: file_contains "skills/review/SKILL.md" "NOT_APPLICABLE:" --> <!-- verify: grep "NOT_APPLICABLE:.*Blocking" "skills/review/SKILL.md" --> `skills/review/SKILL.md` Step 9's exit-code classification table (declared exhaustive) lists the `NOT_APPLICABLE:` output as an exit 0 row that stays **Blocking** (the classifier made no baseline attribution, so the section's existing fail-closed principle for classifier no-verdict outcomes applies), so the new outcome does not fall outside the table

### Post-merge

- なし

## Notes

### Issue 本文と既存実装の整合性確認 (conflict detection)

- Issue 本文 Background の事実主張 (check script を対象 repo の worktree 内で解決する / 同梱するのは wholework のみ / `/merge` のたびに 2 行が出る / merge は fail-open で進む) は、`scripts/pre-merge-check.sh` L61-66 と `scripts/run-merge.sh` L102-108 で確認でき、いずれも一致した。再現も spec 時点で確認済み (Reproduction Steps 参照)。
- **矛盾を 1 件検出した (Issue の AC5 にある「non-blocking」という記述と、`/review` Step 9 の既存原則)**。AC5 は `NOT_APPLICABLE:` を「exit 0 / non-blocking」として表に載せるとしていた。しかし Step 9 の表における Non-blocking は、「分類器が帰属を判定し、この PR の責任ではないと示した」ことを意味する (`PRE_EXISTING` / `FIXED` / `CLEAN`)。同じ節には「分類器が判定を出せないときは、分類器導入前の挙動に戻す」という原則があり、exit 1 を fail-closed とする根拠になっている。`NOT_APPLICABLE:` は「比較する対象が無い」= 判定を出していないので、`/review` では導入前の挙動、つまり Blocking に戻すのが原則に整合する。
  - Non-blocking にすると、`Forbidden Expressions check` が FAILURE で、かつ check script が両 ref に無い repo (同名の job が別実装で動いている等) で、帰属の根拠なしに gate が緩む。その状況は現状 exit 1 = Blocking なので、AC5 の記述どおりにすると**従来より安全側から外れる退行**になる。実際にこの経路に到達することは稀だが (`Forbidden Expressions check` の job 定義は wholework 自身の workflow にある)、表の exhaustive 性のために行が必要で、到達した場合の安全側の挙動を決めておく必要がある。
- **解決 (非対話モードの auto-resolve)**: exit code は Issue のとおり 0 とする (`run-merge.sh` が警告なしで進めるため)。`/review` Step 9 の表では **Blocking** とする。Issue 本文の AC5 は、description に Blocking を明記し、`grep "NOT_APPLICABLE:.*Blocking"` を併記する形に更新済み。`/merge` の実効挙動は変わらず (従来も fail-open で進んでいた)、`/review` の実効挙動も変わらない (従来の exit 1 と同じ Blocking)。この選択により Step 9 の変更箇所は「表 1 行 + exit 1 行の括弧書き + 説明 1 段落」に収まる。Non-blocking にしていれば、Non-blocking outcome handling の 3 分類の列挙 (L441, L446, L452) と Step 10 の injection 文 2 箇所 (L568, L643) の合計 4 箇所以上の更新が必要だった。
- 上記の判断は Step 15 の Issue コメントにも Autonomous Auto-Resolve Log として記録する。

### 検出方式の選択 (tree probe と worktree 内判定)

- 採用: worktree を作る前に `git ls-tree --name-only origin/<ref> -- <path>` で tree 内の存在を判定する。挙動は git 2.47.3 で実測した (出所: spec 時点のこの worktree での実行。存在: パスを出力して exit 0 / 不在: 空出力で exit 0 / 無効な ref: `fatal: Not a valid object name` で exit 128)。
- 不採用 (1): `run_check_on_ref()` を「不在なら状態変数を立てて戻る」に変え、両 ref の評価後に判定する案。変更は小さいが、片側のみ不在でも head の check を実行してから error にするため無駄が出ること、不在判定が checkout 後のファイル有無 (`-f`) に依存して sparse checkout 等の異常が対象外に化けること、対象外 repo でも worktree を 2 回作ることから採らなかった。
- 不採用 (2): `git cat-file -e <ref>:<path>`。「path が無い」と「ref が無効」がどちらも非 0 で区別できず、probe の失敗が不在に化ける。

### Fail-safe critical script の判定

- 判定: **該当**。(a) merge gate の判定源である (exit 2 で `run-merge.sh` が abort し、`/review` Step 9 の例外判定の根拠にもなる)。(c) 現行 script に `|| true` と `2>/dev/null` を含む cleanup がある (L56, L62, L63, L71, L72。`grep -nF -e 'fail_open' -e '|| true' -e '2>/dev/null' scripts/pre-merge-check.sh` で確認。`fail_open()` 関数は無い)。
- エッジケースと依存コマンド失敗時の fail-open / fail-closed の方針とその根拠は、Implementation Steps 1 の表に記載した。要点は、新設の probe の失敗を fail-closed (exit 1) にすること、`NOT_APPLICABLE` を `/review` では Blocking にすること、`/merge` 側は従来どおりの fail-open の扱いを保つことの 3 点である。

### Audit / investigation-type 判定

- 該当しない。既存項目を分類して判定根拠を永続化する調査ではなく、既存 script の挙動修正である。

### Tag / enum の意味拡張に対する consumer 確認

- exit 0 は従来「CLEAN / FIXED / PRE_EXISTING = 帰属上問題なし」を意味していたが、帰属判定を行わない `NOT_APPLICABLE` が加わることで、exit 0 の意味が拡張される。consumer の列挙: `grep -rln "pre-merge-check" .` から `docs/spec/`・`docs/sessions/`・`docs/reports/`・`.git` を除外 (scope: repository 全体、現行ファイルのみ、HEAD `fc28fcdb` 時点) → 12 files (`docs/ja/structure.md`、`docs/structure.md`、`modules/orchestration-fallbacks.md`、`scripts/pre-merge-check.sh`、`scripts/run-merge.sh`、`skills/issue/spec-test-guidelines.md`、`skills/merge/SKILL.md`、`skills/review/SKILL.md`、`tests/auto.bats`、`tests/pre-merge-check.bats`、`tests/review.bats`、`tests/run-merge.bats`)。
- このうち exit code や出力 prefix で分岐する consumer は `scripts/run-merge.sh` (exit code のみ) と `skills/review/SKILL.md` Step 9 (prefix 付きの表) の 2 つ。前者は変更不要、後者は Implementation Steps 3 で対応する。残りは記述のみ (`docs/structure.md`、`docs/ja/structure.md`、`modules/orchestration-fallbacks.md`、`skills/issue/spec-test-guidelines.md`、`skills/merge/SKILL.md`) か、テスト (`tests/auto.bats` は fixture 方式に言及するコメントのみ)。この列挙は grep 結果のスナップショットであり、網羅性の宣言ではない。

### Steering Docs sync candidate check の結果

- 判別力フィルタ (`grep -rl "<keyword>" docs/ tests/ scripts/ modules/ 2>/dev/null | wc -l`、scope: 4 ディレクトリ、`docs/spec/` 等の履歴を含む)
  - `NOT_APPLICABLE`: 0 files (本 Issue が導入する新しい label で、既存の consumer は無い)
  - [Steering Docs sync candidate] keyword "pre-merge-check.sh" skipped: matched 22 files (no discriminating power)
  - [Steering Docs sync candidate] keyword "PRE_EXISTING" skipped: matched 11 files (no discriminating power)
  - [Steering Docs sync candidate] keyword "NEW_FAILURE" skipped: matched 14 files (no discriminating power)
  - [Steering Docs sync candidate] keyword "orchestration-fallbacks" skipped: matched 154 files (no discriminating power)
- 補足: 規定どおり個別ヒットの評価は広げていない。Changed Files の同期候補は、上の consumer 確認の 12 files (現行ファイルのみ) から選んだ。履歴の `docs/spec/` `docs/sessions/` `docs/reports/` は同期対象外 (`docs/translation-workflow.md` の Exclusions と `modules/doc-checker.md` の除外規則と同じ扱い)。

### allowed-tools impact chain check

- Case 1 (新規 `scripts/*.sh`): 新規 script の追加は無いため対象外。
- Case 2 (`modules/*.md` の変更): `modules/orchestration-fallbacks.md` を変更するため実施した。追記文は `pre-merge-check.sh` に言及するが、新しい script 呼び出しは導入しない (既存の Fallback Steps 1 がすでに `scripts/pre-merge-check.sh <pr-number>` の手動実行を案内している)。reader は `grep -rl "modules/orchestration-fallbacks\.md" skills/*/SKILL.md` で `skills/auto/SKILL.md`、`skills/review/SKILL.md`、`skills/verify/SKILL.md` の 3 件。frontmatter の `allowed-tools` に `pre-merge-check.sh:*` があるのは review のみ (auto と verify は 0 件) だが、今回の変更は呼び出しを追加しないため、いずれも変更不要。

### 新規テストケース要件 (SPEC_DEPTH=light のため、Step 13 の代わりにここへ記録)

- 新規の分岐ロジック (`NOT_APPLICABLE` / 片側のみ存在 / probe 失敗) を `scripts/pre-merge-check.sh` に追加するため、`bats tests/pre-merge-check.bats` が既存スイートで PASS するだけでは不十分で、新規ロジックを検証する新規テストケースを追加したうえでスイートが PASS する必要がある。Implementation Steps 2 の 6 件が該当する (`NOT_APPLICABLE:` 分岐 → 1、片側のみ存在の分岐 → 2・3、git 失敗系 → 4・5・6)。
- `skills/review/SKILL.md` の表の行追加は分岐ロジックではなく文書だが、`tests/review.bats` の新規 1 件で固定する。
- AC4 に `file_contains` を併記したのは、既存スイートが実装前から PASS するため、新規テストを 1 件も追加しなくても PASS してしまう問題 (Triage AC audit の指摘) への対応である。

### bats テストの入力フォーマット

- fixture: 一時ディレクトリ内に bare repo (`origin.git`) と作業 repo (`repo`) を `git init` で作り、`origin` を bare に向ける。初期コミット (`main`) に `scripts/check-forbidden-expressions.sh` (stub: `skills/` 配下に `FORBIDDEN` を含むと exit 1) と `skills/x.md` を置いて push する (`setup()` の既存実装)。
- `gh` は `$MOCK_DIR/gh` の mock。`gh pr view <N> --json headRefName -q .headRefName` と `... baseRefName ...` に対し、`_mock_gh_refs <head> <base>` が設定した branch 名を 1 行で返す。
- script の有無は ref ごとの tree で制御する。`_remove_check_script_on_branch <branch>` が `git rm` → commit → push するため、空コミットにはならない。
- base と head が同一内容になるシナリオでも、`_setup_feature_branch` が branch 固有の marker file を追加するため空コミットにならない (`skills/issue/spec-test-guidelines.md` の「base/head 比較 bats テスト」参照)。
- git の失敗は `$MOCK_DIR/git` の shim で再現する (`worktree add` / `ls-tree` のときだけ失敗し、それ以外は shim 作成前に `command -v git` で取得した実 git の絶対パスへ `exec` する)。`$MOCK_DIR` は `setup()` で `PATH` の先頭に入っているため、script 内の `git` 呼び出しも shim を経由する。

### `@test` 名の規則確認

- `grep "@test" tests/pre-merge-check.bats` の結果: `usage error: ...` / `unknown check name ...` / `NEW_FAILURE: base PASS / head FAIL exits 2` / `PRE_EXISTING: both FAIL exits 0 with PRE_EXISTING label` / `CLEAN: both PASS exits 0 with CLEAN label` / `FIXED: base FAIL / head PASS exits 0 with FIXED label` / `env error: headRefName empty exits 1` / `env error: baseRefName empty exits 1`。形式は `<LABEL or category>: <説明> exits <N>[ with <LABEL> label]` で、コロンの後ろは小文字始まり。新規 6 件はこの形式に合わせた。
- AC4 の `file_contains` は新規テスト名の部分文字列 (`NOT_APPLICABLE: script absent from both refs` と `env error: check script present on`) を参照する。`tests/review.bats` の新規テスト名は、既存の `Step 9: pre-existing CI failure exception ...` の接頭辞に合わせた。

### 文字列照合 verify command の存在確認

- AC3・AC4・AC5 の `grep` / `file_contains` が参照する文字列は、いずれも実装が導入する文字列である。実測で、`scripts/pre-merge-check.sh`、`skills/review/SKILL.md`、`tests/pre-merge-check.bats`、`tests/review.bats` の 4 ファイルとも `NOT_APPLICABLE` と `not applicable` が 0 件 (`grep -c`) であることを確認した。実装前の main で PASS する (空振りの) AC は無い。
- `grep` の pattern に BRE 専用のメタ文字 (`\|`・`\(`・`\)`・`\+`・`\?`) は含めていない。AC5 の `NOT_APPLICABLE:.*Blocking` は ERE として有効で、表の行が 1 行で書かれることを前提とする (Implementation Steps 3 で明記した)。

### 手動再現シナリオ (spec 時点のプロトタイプ検証)

- Spec 作成時に、変更後の `pre-merge-check.sh` の試作と、bats fixture を手動で再現するハーネス (使い捨てで、リポジトリには残さない) を作り、worktree 内の `.tmp/` で実行した。試作は 28 / 28 のチェックを通過した。同じハーネスを現行の script に実行すると、新規挙動に該当するチェック 8 件 (S1 の exit 0・label・メッセージ・`Error` 不在、S2 / S3 の `only one of`、S6 の probe) だけが失敗し、他は通過した。つまり、エラー系の挙動と既存の 4 分類は保存されている。

  | ID | fixture | 期待 | 対応するテスト |
  |----|---------|------|----------------|
  | R1 | 両 ref に script・同内容 | exit 0 / `CLEAN` | 既存 |
  | R2 | head のみ `FORBIDDEN` を含む | exit 2 / `NEW_FAILURE` | 既存 |
  | R3 | base・head とも `FORBIDDEN` を含む | exit 0 / `PRE_EXISTING` | 既存 |
  | R4 | base のみ `FORBIDDEN` を含む | exit 0 / `FIXED` | 既存 |
  | S1 | base・head とも script を削除 | exit 0 / `NOT_APPLICABLE:` / `Error` と `Warning` が無い | 新規 1 |
  | S2 | base のみ script あり | exit 1 / `only one of` | 新規 2 |
  | S3 | head のみ script あり | exit 1 / `only one of` | 新規 3 |
  | S4 | head ref が origin に無い | exit 1 / `git fetch failed` | 新規 4 |
  | S5 | git shim: `worktree add` が失敗 | exit 1 / `git worktree add failed` | 新規 5 |
  | S6 | git shim: `ls-tree` が失敗 | exit 1 / `could not inspect` (`NOT_APPLICABLE` ではない) | 新規 6 |
  | S7 | script の位置にディレクトリがある | exit 1 / `check script not found in worktree` (既存ガード) | なし (手動確認のみ) |

### 言語・静的チェック

- `docs/` と `tests/` も `scripts/check-forbidden-expressions.sh` の走査対象 (`SCAN_DIRS="skills/ modules/ agents/ tests/ docs/"`)。本 Spec を含め、旧称の語 (一覧は `docs/product.md` § Terms の 'Formerly called' 列) を書かない。
- `skills/` `modules/` `scripts/` の追加行は、CI の `Language Convention check` が CJK 文字を弾くため英語のみとする。`tests/` のコメントとテスト名も英語 (CLAUDE.md の Language Conventions: Source code は English)。`docs/ja/structure.md` は日本語。

### 範囲外の観察 (コード読解のみ。未再現)

- 同一 repo 内の branch ではなく、fork 由来の PR では head ref が `origin` に存在せず、`git fetch origin <head> <base>` が失敗する。その場合は script の有無によらず exit 1 と fail-open 警告になる可能性がある。AC2 が「git fetch の失敗は引き続きエラー」と規定しており、本 Issue の範囲外とした。必要なら別 Issue で扱う。

### その他

- costly / irreversible な Implementation Step、外部サービスへのログインを要する Step は無い (`spec-approval-needed` / `external-auth-required` の対象外)。
- UI に関わる変更は無いため、UI Design phase は対象外。
- Issue 本文は、AC3 (hint 追加)・AC4 (新規テスト名の hint 追加)・AC5 (description と hint) を更新した。AC1 / AC2 は変更していない。Post-merge は「なし」のまま。
