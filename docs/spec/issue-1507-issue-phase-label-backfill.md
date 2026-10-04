# Issue #1507: issue: 既存 Issue のリファインで phase/issue へのラベル遷移が抜けても batch が止まらないようにする

## Overview

`/issue` の Existing Issue Refinement で LLM が Step 3 (`gh-label-transition.sh $NUMBER issue`) だけを飛ばすと、リファイン本体と Issue Retrospective が完了していても `phase/issue` が付かない。`run-issue.sh` の completion check (`reconcile-phase-state.sh issue --check-completion`) が `matches_expected:false` を返し、silent no-op として exit 1 になるため、`/auto` がその Issue で止まる。`docs/reports/orchestration-recoveries.md` には、2026-10-02 の #1484、2026-10-04 の #1494 と #1502 の計 3 件が記録されている。

Issue 本文は、方針 a (`claude -p` 起動前に決定的に付与) と方針 b (Issue Retrospective を根拠にした事後補完) のどちらを採るかを `/spec` に委ねている。本 Spec は **方針 b** を採る。`run-issue.sh` は、claude が exit 0 で終了し、completion check が `matches_expected:false` を返し、かつ実行開始後に first-class な author が `## Issue Retrospective` を投稿していた場合に限り、`gh-label-transition.sh $ISSUE_NUMBER issue` でラベルを補完して exit 0 にする。根拠が確認できない場合は従来どおり exit 1 (silent no-op) とする。方針 a を採らない理由は Notes に記録した。

## Reproduction Steps

1. `phase/*` ラベルが無い Issue に対して `/auto` (または `scripts/run-issue.sh N` を直接) を実行する
2. `claude -p` が `/issue N --non-interactive` を実行し、リファインを進めて Step 13 で `## Issue Retrospective` を投稿するが、Step 3 の `gh-label-transition.sh N issue` を実行しないまま exit 0 で終了する
3. `reconcile-phase-state.sh issue N --check-completion` が `"matches_expected":false` (`issue #N has no phase/issue or later phase label`) を返し、`run-issue.sh` が `Warning: claude exited 0 but issue phase did not complete (silent no-op).` を出して exit 1 になる

決定的な再現 (bats): `claude` スタブは何もせず exit 0、`reconcile-phase-state.sh` スタブは `matches_expected:false`、`gh` スタブは実行開始後に投稿された `## Issue Retrospective` コメントを返す。変更前の `run-issue.sh` はこの構成で exit 1 になる。

## Root Cause

- `phase/issue` の付与が、LLM が実行する 1 行のコマンド (`skills/issue/SKILL.md` Existing Issue Refinement の Step 3) だけに依存している。Step 3 は長い Comment Consumption の記述の直後、refine 本体 (Step 4〜15) の前にあり、見落とされやすい位置にある
- `run-issue.sh` の完了判定は `phase/(issue|ready|code|review|merge|verify|done)` ラベルの有無だけである (`reconcile-phase-state.sh` の `_completion_issue`)。そのため「リファインが実行されなかった」 (真の silent no-op) と「リファインは完了したがラベルだけ抜けた」を区別できず、後者も exit 1 にしてしまう
- 修正方針の妥当性: 両者を区別できる証拠が GitHub 側に残っている。Step 13 の Issue Retrospective は、リファインの終盤 (Step 9 の Issue 本文更新の後) に投稿される成果物である。記録された `/issue` フェーズの 3 件 (#1484, #1494, #1502。計測範囲: `docs/reports/orchestration-recoveries.md` の全 53 エントリのうち `phase: issue` のもの) は、いずれも retro 投稿済みでラベルだけが欠落しており、真の silent no-op の記録は `/issue` フェーズでは 0 件である。したがって「実行中に retro が投稿された」ことを根拠にした事後補完は、誤補完を避けつつ実際の発生パターンを覆える

## Changed Files

- `scripts/run-issue.sh`: 完了判定の `matches_expected:false` 分岐に、証拠付きの事後補完を追加する。変更点は 3 つで、claude 起動前の実行開始時刻 `_RUN_START_TS` の取得、判定用ヘルパー `_issue_retro_posted_since()` の追加、`matches_expected:false` 分岐の分割である。分岐は、証拠があれば `gh-label-transition.sh $ISSUE_NUMBER issue` で補完し、証拠がなければ従来どおり exit 1 にする — bash 3.2+ 互換 (配列・`mapfile` は使わない。`[[ =~ ]]` と `local` のみ)
- `tests/run-issue.bats`: `setup()` に `gh-label-transition.sh` の既定モックを追加し、コメント fixture に本番の jq フィルタを適用する `gh` モックの補助関数と、補完まわりの新規テストケース 8 件を追加する。冒頭コメントのモック一覧に `gh-label-transition.sh` を追記する
- [Steering Docs sync candidate] keyword "run-issue.sh" skipped: matched 112 files (no discriminating power)
- [Steering Docs sync candidate] keyword "_issue_retro_posted_since" (新設するヘルパー名): 既存の参照は 0 件のため同期候補なし

## Implementation Steps

1. `scripts/run-issue.sh` に判定ヘルパーと実行開始時刻の取得を追加する (→ 受け入れ条件 1)
   - `trap '_maybe_emit_phase_complete' EXIT` の行の直後に、ヘルパー `_issue_retro_posted_since()` を追加する。引数は実行開始時刻 (UTC ISO 8601)。処理は次の順とする
     1. 引数が `YYYY-MM-DDTHH:MM:SSZ` の形式でなければ return 1
     2. `gh issue view "$ISSUE_NUMBER" --json comments --jq '<プログラム>' 2>/dev/null` を実行し、失敗したら return 1
     3. 出力が `^[0-9]{4}-[0-9]{2}-[0-9]{2}T` で始まる場合のみ return 0、それ以外は return 1
   - jq プログラムは、`authorAssociation` が `OWNER` / `MEMBER` / `COLLABORATOR` のコメントのうち、`(.body // "")` が `test("^\\s*## Issue Retrospective")` に一致し、かつ `createdAt` が引数以上のものの `createdAt` を `sort | last // empty` で 1 件だけ返す。引数はシェルの単一引用符を切って埋め込む (形式を 1 で検証済みの固定長文字列だけが入る)
   - `SECONDS=0` の直前に `_RUN_START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _RUN_START_TS=""` を追加する。claude の起動 (retry-on-kill の再起動を含む) より前の時刻になる
   - fail-safe critical のエッジケース (判定は fail-closed に統一する。誤った補完は真の silent no-op を完了と誤認させるが、誤った非補完は変更前と同じ停止に戻るだけで非対称なため):
     - `_RUN_START_TS` が空または形式不正 → 証拠なし。空のまま jq に埋め込むと `createdAt >= ""` が全コメントで真になり、過去の retro を証拠にしてしまう
     - `gh` が非 0 終了、空出力、または非タイムスタンプ出力 (rate limit 文言を exit 0 で出す場合を含む) → 証拠なし
     - コメントが 0 件、本文が null または空、見出しが本文の途中にだけ現れる → 証拠なし。`(.body // "")` で null を空文字に揃え、`test` は文字列先頭にアンカーする (先頭の空白・改行は許容)
     - 本文に CRLF、`>`、`"`、多バイト文字を含む場合 → すべて jq 内で処理され、bash には最大 1 つのタイムスタンプしか戻らない。入力が巨大でも bash 側の扱いは変わらない
     - author が `OWNER` / `MEMBER` / `COLLABORATOR` 以外 → 証拠なし (`modules/l0-surfaces.md` § Trust Boundary の first-class と同じ)
2. 完了判定ブロックの `matches_expected:false` 分岐を分ける (after 1) (→ 受け入れ条件 1, 3)
   - `elif echo "$_reconcile_out" | grep -q '"matches_expected":false'; then` の中身を次のようにする
     - `_issue_retro_posted_since "$_RUN_START_TS"` が真: `Warning: claude exited 0 but phase/issue is missing although /issue posted its Issue Retrospective during this run. Backfilling phase/issue. reconcile: ...` を stderr に出し、`"$SCRIPT_DIR/gh-label-transition.sh" "$ISSUE_NUMBER" issue` を実行する。成功なら `EXIT_CODE` は 0 のまま (後続の `wrapper_exit` / `phase_complete` の emit は既存コードがそのまま扱う)。失敗なら `Warning: phase/issue backfill failed for issue #N; issue phase did not complete (silent no-op).` を stderr に出して `EXIT_CODE=1`
     - 偽: 既存の `Warning: claude exited 0 but issue phase did not complete (silent no-op). reconcile: ...` と `EXIT_CODE=1` を維持する
   - `EXIT_CODE` が 143 の分岐には手を入れない (kill された実行は完了とみなさない)
   - この分岐の直前に英語のコードコメントを置き、次の 3 点を記す。まず claude 起動前にラベルを付与しない理由 (Comment Consumption の cutoff、完了判定、`/auto` の再開経路。`modules/l0-surfaces.md` § "Pre-pipeline comment coverage" を参照先にする)。次に補完したラベルの付与時刻が次フェーズの cutoff になること。最後に補完の対象が exit 0 のみであること
3. `tests/run-issue.bats` の `setup()` と補助関数を追加する (parallel with 1, 2) (→ 受け入れ条件 2)
   - `setup()` に `gh-label-transition.sh` の既定モックを追加する。引数を `$LABEL_TRANSITION_LOG` に追記し、`${LABEL_TRANSITION_EXIT:-0}` で終了する。ファイル冒頭の `Mocks:` コメントにも追記する
   - 補助関数 `_use_issue_comments` を追加する。引数の JSON を fixture ファイルに書き、`gh` モックを差し替える。差し替えた `gh` は、`issue view ... --json comments` で渡された `--jq` (または `-q`) のプログラムを fixture に実際の `jq -r` で適用して出力する。`GH_COMMENTS_FAIL=1` のときは exit 1 にする
4. 新規テストケースを追加する (after 3。Step 1, 2 より先に実行し、1 件目が FAIL することを確認してよい) (→ 受け入れ条件 2, 4)
   - 既存のテストケースを `bats tests/run-issue.bats` の全件 PASS のまま保つことに加え、新規ロジック (補完分岐) を検証する新規テストケースを追加し、全件が PASS すること。名前は既存の `reconcile:` 系に合わせ `backfill:` 接頭辞とする
   - 1 件目 `backfill: exit 0 + matches_expected:false + Issue Retrospective posted during this run backfills phase/issue and exits 0`: status 0、`$LABEL_TRANSITION_LOG` が `123 issue` の 1 行、出力に `Backfilling phase/issue`、`wrapper_exit phase=issue exit_code=0` と `phase_complete` の emit を検証する (変更前の実装では exit 1 になり FAIL する)
   - 2 件目 `backfill: Issue Retrospective older than the run start is not evidence`: `createdAt` が `2000-01-01T00:00:00Z` → status 1、遷移の呼び出しなし、出力に `silent no-op`
   - 3 件目 `backfill: Issue Retrospective from an external author is not evidence`: `authorAssociation` が `NONE` と `CONTRIBUTOR` → status 1、遷移の呼び出しなし
   - 4 件目 `backfill: heading mentioned mid-body is not evidence`: 本文が `intro\n## Issue Retrospective` → status 1、遷移の呼び出しなし
   - 5 件目 `backfill: comment lookup failure is fail-closed`: `GH_COMMENTS_FAIL=1` → status 1、遷移の呼び出しなし
   - 6 件目 `backfill: label transition failure keeps exit 1`: `LABEL_TRANSITION_EXIT=1` → status 1、出力に `backfill failed`
   - 7 件目 `backfill: exit 143 + matches_expected:false is not backfilled`: claude モックが 143 で終了 (`WHOLEWORK_RETRY_ON_KILL_MAX_SEC=0`)、retro の証拠あり → status 143、遷移の呼び出しなし
   - 8 件目 `backfill: no label transition when matches_expected:true`: reconcile が true、retro の証拠あり → status 0、遷移の呼び出しなし
5. 検証する (after 1, 2, 3, 4) (→ 受け入れ条件 4)
   - `bats tests/run-issue.bats` の全件 PASS を確認してから、`bats tests/` を実行する
   - 本番の jq プログラムを一度だけ実 `gh` で評価し、gojq でも構文が通ることを確認する。`gh issue view 1507 --json comments --jq '<Step 1 のプログラム。引数は 2026-10-04T14:20:00Z>'` の出力が `2026-10-04T14:24:12Z` (#1507 の `/issue` retro。MEMBER) になる

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-issue.sh で、/issue の Existing Issue Refinement が完了したのに LLM が phase/issue ラベル遷移を実行しなかった場合でも phase/issue が付く仕組み (claude -p 起動前の決定的なラベル遷移、または Issue Retrospective コメントの存在を根拠にした補完) が実装されている" --> LLM がラベル遷移を飛ばしても `phase/issue` が付く
- <!-- verify: rubric "tests/ 配下の run-issue.sh の bats に、claude -p (スタブ) が phase/issue ラベルを付けずに終了したケースで、run-issue.sh が最終的に phase/issue を付与して exit 0 になる (または起動前に付与済みである) ことを検証するテストがあり、変更前の実装では FAIL する" --> ラベル遷移が抜けたケースを bats が回帰テストとして保護している
- <!-- verify: rubric "run-issue.sh 経由の /issue Existing Issue Refinement が、phase/issue ラベル付与前 (パイプライン投入前) に投稿された Issue コメントを引き続き消費できる。run-issue.sh または skills/issue/SKILL.md の変更後も、modules/l0-surfaces.md の Comment Consumption Procedure の cutoff 解決が、起動前のラベル付与や補完によって投入前コメントを取りこぼす状態になっていない" --> ラベル遷移の確定化によって、パイプライン投入前のコメント消費 (cutoff 解決) が退行していない
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

- マージ後、`/auto --batch` による既存 Issue のリファイン (`run-issue.sh` 経由の `/issue` フェーズ) が累計 10 件以上実行された時点で、その実行群について `docs/reports/orchestration-recoveries.md` に phase: issue・cause: `missing-phase-label` の `manual-recovery-label-backfill` 記録が 0 件であり、`phase/issue` 欠落の silent no-op で `/issue` フェーズが停止していないことを確認する。ベースライン: 2026-10-04 の 1 日で `/issue` 9 件中 2 件 (#1494, #1502 の記録、同ファイルの 2026-10-04 08:05 UTC / 12:36 UTC エントリ)。最小サンプル: マージ後のリファイン実行 10 件 (実行数は `.tmp/auto-events.jsonl` の `phase=issue` の `phase_start` イベント、または `docs/sessions/*/session.md` で数える)。10 件に満たない間は SKIPPED (サンプル待ち) として判定しない <!-- verify-type: observation event=auto-run session=next when=mode:batch -->

## Notes

### 方針 a と b の判断 (Issue 本文が `/spec` に委ねた選択)

方針 b (事後補完、retro コメントを根拠とする) を採用した。方針 a (claude 起動前の付与) は次の 3 点で採らない。

- **cutoff の退行**: `modules/l0-surfaces.md` § "Pre-pipeline comment coverage" のとおり、`/issue` Step 1 は `phase/*` が未付与であることを前提に cutoff を空に解決し、投入前のコメントを消費する。起動前に `phase/issue` を付けると cutoff が起動時刻になり、投入前のコメントが消費対象から外れる。回避するには l0-surfaces の cutoff 解決、SKILL.md、プロンプトへの引き渡しを同時に変える必要があり、AC 3 の退行リスクを新たに抱える
- **完了判定が空になる**: `reconcile-phase-state.sh` の `_completion_issue` は、`phase/(issue|ready|…)` ラベルの有無だけで `/issue` の完了を判定する。起動前に付与すると常に完了と判定され、`/issue` フェーズの完了判定が機能しなくなる
- **再開時にリファインが飛ぶ**: `/auto` は `phase/issue` が付いた Issue を `/spec` から始める (`skills/auto/SKILL.md` の "`phase/issue` label present (no `phase/ready`)" 分岐)。リファインの途中で落ちた Issue が、再開時にリファインされないまま `/spec` に進んでしまう

方針 b の根拠コメントが常に存在するとは限らない点 (`/issue` Step 13 の skip condition) は、次のとおり扱った。

- 実測 (出所: `gh issue view {1492,1493,1494,1495,1496,1497,1501,1502,1504} --json comments`、取得日 2026-10-04。計測範囲: 2026-10-04 に `run-issue.sh` で `/issue` を通した 9 件。判定: 本文が `## Issue Retrospective` で始まるコメントの有無): 8 件に retro があり、無かったのは #1496 のみ
- `docs/reports/orchestration-recoveries.md` に記録された `/issue` フェーズの 3 件 (#1484 の `issue-phase-silent-no-op`、#1494 と #1502 の `manual-recovery-label-backfill`。計測範囲: 同ファイルの全 53 エントリのうち `phase: issue` のもの) は、いずれも retro 投稿済みでラベルだけが欠落していた。真の silent no-op (リファイン自体が実行されない) の記録は `/issue` フェーズでは 0 件
- 残余ケース (retro の skip condition に該当し、かつラベルも抜けた) は補完しない。従来どおり exit 1 (silent no-op) で止まるため、変更前より悪化しない (fail-closed)。ラベル欠落率 2/9 と retro なしの率 1/9 が独立と仮定した場合の目安は 約 2.5% / 実行 (n=9 の目安値で、10 件で 1 件以上出る確率は約 22%)。Post-merge の観察条件で残余の記録が出た場合は、Step 13 の skip condition の見直しや、決定的な完了マーカーの追加を別途検討する

### 補完したラベルの時刻と次フェーズの cutoff

補完された `phase/issue` の付与時刻は、`/issue` の実行終了後になる。`/spec` の Comment Consumption の cutoff は直近の `phase/*` 付与時刻なので、`/issue` が Step 1 で消費した後から補完までの間に他者が投稿したコメントは、`/spec` の消費対象から外れる (LLM が Step 3 を実行する通常経路では、この窓は Step 1〜3 の間だけ)。`run-merge.sh` の事後補完 (`phase/review` から `phase/verify`) と同型の性質として受け入れる。AC 3 (cutoff の非退行) は、補完を claude の終了後に限り、起動前の付与を行わないことで満たす。`skills/issue/SKILL.md` と `modules/l0-surfaces.md` は変更しない。

### fail-safe critical の判定

`run-issue.sh` の完了判定は、phase を完了とみなすかどうかを決める gate であり (基準 a)、`|| true` / `2>/dev/null` を使う既存パターンを含む (基準 c。`grep -nF -e 'fail_open' -e '|| true' -e '2>/dev/null' scripts/run-issue.sh` で確認した)。そのため fail-safe critical として扱い、エッジケースの期待動作を Implementation Steps の Step 1 に明記した。

### 監査/調査型 Issue の判定

no。複数の既存項目を分類する監査ではなく、不具合の修正である。

### 既存パターンとの整合

- 時刻の比較は `modules/l0-surfaces.md` Step 2 (ISO 8601 UTC 文字列の辞書順比較) と、形状ガード付きのタイムスタンプ取得は `scripts/reconcile-phase-state.sh` の `_operate_signal_ts()` と揃えた
- `gh --jq` は gojq で評価され、bats のモックは jq (jq-1.7) で評価する。使う構文 (`select` / `test` / `sort` / `last // empty` / 文字列比較) は両者に共通で、`test("^\\s*## Issue Retrospective")` が文字列先頭にだけアンカーされることを jq-1.7 と実 `gh` (上記 9 件) で確認した
- `gh issue view --json comments` の `authorAssociation` は camelCase (REST の `author_association` とは別名)。`modules/l0-surfaces.md` § Trust Boundary と同じ

### bats テストの入力形式

- コメント fixture: `gh issue view N --json comments` と同じ最上位形状の JSON `{"comments":[{"authorAssociation":"MEMBER","body":"## Issue Retrospective\n...","createdAt":"2099-12-31T23:59:59Z"}]}`。`gh` モックは `--jq` (または `-q`) の引数を実際の jq プログラムとして fixture に適用するため、本番のフィルタ (trust tier / 見出しのアンカー / `createdAt`) を通る
- 時刻は固定値で扱い、実行時刻に依存させない。実行開始より後は `2099-12-31T23:59:59Z`、前は `2000-01-01T00:00:00Z`
- `gh-label-transition.sh` のモック: 引数を `$LABEL_TRANSITION_LOG` に追記し、`LABEL_TRANSITION_EXIT` (既定 0) で終了する。補完の呼び出しは `123 issue` の 1 行で検証する
- `tests/run-issue.bats` は `WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定している。新規スクリプトは追加しないが、`run-issue.sh` が新たに `$SCRIPT_DIR/gh-label-transition.sh` を呼ぶため、`setup()` に既定モックを置く (未配置だと補完の経路で exit 127 になり、判定が不定になる)

### ドキュメント影響の確認 (更新不要と判断した文書)

- `README.md`: `run-issue` と `silent no-op` の記述なし (grep で確認)
- `docs/workflow.md`: `phase/issue` はラベル表の 1 行 (`/issue` から `/spec`) と Kanban 自動化の説明にだけ現れ、ラッパーの完了判定には触れていない (grep で確認)
- `docs/structure.md`: `scripts/run-issue.sh` の Key Files エントリは "run issue skill" で、変更後も正確。スクリプトとテストの追加・削除はなく、ファイル数コメントも変わらない
- `docs/guide/`: `run-issue` の記述なし。`phase/issue` は `xl-decomposition.md` の 1 箇所だけで無関係
- `modules/phase-state.md`: `issue` フェーズの完了シグネチャ (`phase/(issue|ready|…)` ラベル) は変わらない。補完は reconciler の外 (wrapper) の動作
- `SECURITY.md`: ラベルの追加・削除は既に宣言されている。新たな権限は不要
- `docs/ja/*`: トップレベルの `docs/*.md` を変更しないため、翻訳の同期は不要
- `modules/l0-surfaces.md` と `skills/issue/SKILL.md`: 変更しない。補完は起動前の付与ではなく事後で、cutoff 解決に影響しないため。SKILL.md に「補完される」と書くと、LLM が Step 3 を飛ばしてよい根拠になり得るため記載しない

### その他の確認結果

- Issue 本文の事実主張 (completion check から exit 1 になる経路、Step 3 の位置、`run-merge.sh` の事後補完、他の wrapper が起動前にラベル遷移しないこと、手動復旧記録 2 件、l0-surfaces の cutoff 解決、Step 13 の skip condition) をコードで確認し、矛盾は検出されなかった
- `allowed-tools` への影響なし: 新規スクリプトの追加も `modules/*.md` の変更もない。`gh-label-transition.sh` は wrapper (bash) から呼ばれ、SKILL.md の frontmatter は経由しない
- costly/irreversible な Implementation Step はなく、`spec-approval-needed` マーカーは付けない。外部サービスへのログインを要する Step もない
- verify-type の確認: Post-merge の観察条件は、基準値 (2/9)、最小サンプル (10 件)、イベント、期待される証拠を条件文に含んでおり、変更しない
- Size は S のまま (変更ファイル 2 件。スクリプトのロジック変更による引き上げと、原因が明確な不具合修正による引き下げが相殺)。ルートは patch
- 新規ロジックの検証: Step 4 の 8 件のテストケースが、補完の分岐を既存スイートの PASS に加えて検証する
- Title Drift Check: Issue 本文を更新していないため、ドリフトなし

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (issue フェーズ): 方針 a と b の選択を spec に委ねる判断と、選択を左右する制約の記録。要件の変更なし / https://github.com/saitoco/wholework/issues/1507#issuecomment-5981013102

## Code Retrospective

### Deviations from Design
- Spec の Implementation Steps どおりに実装した。逸脱なし。Step 4 の「1 件目が FAIL することを確認」は、ローカルに bats が無いため bats ではなく自前の最小ハーネス (`.tmp/harness.sh`、同じ 8 シナリオを同じモック構成で実行) で代替した。変更前の `run-issue.sh` では 1 件目と 6 件目が FAIL、変更後は 8 件すべて PASS
- 新規テストの `[[ "$output" == ... ]]` のうち、後続の文が続く 3 箇所には `|| false` を付けた (bash 3.2 の `set -e` 非伝播対策。`scripts/check-bare-bracket-assertions.sh` の推奨に従う)

### Design Gaps/Ambiguities
- 実行環境 (headless) に bats が無く、`bats tests/` の AC (Pre-merge 4 件目) はローカルで評価できなかった。Step 14 の CI-based bats AC confirmation に回す。bats-core を取得して実行する試みは権限判定で拒否されたため追わなかった
- 本番の jq プログラムは、fixture 6 パターンと実 `gh` (#1507 の `/issue` retro、`2026-10-04T14:24:12Z`) で評価し、期待どおりの出力になることを確認した

### Rework
- 自前ハーネスの初回実行で 1 件目が FAIL したが、原因はハーネス側 (親環境の `EMIT_PHASE_NAME` が残り `_EMIT_PHASE_OWNED` が空になっていた) で、bats の `setup()` と同じ `unset` を足して解消した。実装側の不具合ではない

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の方針 b どおり、`run-issue.sh` の完了判定の `matches_expected:false` 分岐で、実行開始後に first-class author が投稿した `## Issue Retrospective` を根拠に `gh-label-transition.sh $ISSUE_NUMBER issue` で補完し exit 0 にした。根拠が確認できない場合 (形式不正・gh 失敗・外部 author・見出しが本文途中・開始前のコメント) は従来どおり exit 1 (fail-closed)
- 起動前にラベルを付けない方針 a は採らず、`skills/issue/SKILL.md` と `modules/l0-surfaces.md` は変更していない (cutoff の非退行を維持)

### Deferred Items
- `bats tests/` (Pre-merge 4 件目) は bats 未導入のためローカル未実行。push 後の CI の `Run bats tests` ジョブで確認する (Step 14)
- Post-merge の観察条件 (リファイン 10 件以上で `missing-phase-label` の手動復旧 0 件) は `/verify` で扱う

### Notes for Next Phase
- 補完されたラベルの付与時刻は `/issue` 終了後になり、次フェーズの cutoff になる (Spec Notes に記録済み。`run-merge.sh` の事後補完と同型)
- retro の skip condition に該当し、かつラベルも抜けた残余ケースは補完されず、従来どおり exit 1 で止まる。Post-merge で残余の記録が出た場合は別途検討する
