# Issue #1544: skills: /issue・/spec・/code の着手時に assignee を設定し、他メンバーの担当なら付け替え・続行・中止を確認

## Overview

#1542 (XL 親) の sub-issue ② (スキルへの組み込み)。#1543 で用意済みの `scripts/gh-issue-assignee.sh` (判定・付与・付け替え) と `gh-label-transition.sh --assign` を使い、既存 Issue の精査 (`/issue 123`)・`/spec`・`/code` の着手時に、未アサインなら実行ユーザーを assignee に設定し、他のメンバーがアサイン済みなら重複着手を避けるために確認する。

要点:

- 3 スキル共通の「担当確認」の手順を、新規モジュール `modules/assignee-check.md` に集約する (状況の読み取り → 他のメンバーがいれば、対話では 3 択、非対話では警告)。各 SKILL.md には呼び出し位置と要点だけを書く。`modules/phase-banner.md` や `modules/l0-surfaces.md` の Comment Consumption Procedure と同じ「Read and follow」の形。手順を `modules/l0-surfaces.md` に足さないのは、そのモジュールを読む全スキルの `allowed-tools` に `gh-issue-assignee.sh` が必要になり (`validate-skill-syntax.py` のクロスファイル検査)、毎フェーズ読むファイルも長くなるため
- 確認は副作用のある処理より前、各 SKILL.md の Step 1 の末尾で行う。`/issue 123` は Step 2 の triage 自動実行より前、`/spec`・`/code` は Step 2 の worktree 入場より前。「中止」を選んだ時点では何も書き込んでおらず、フェーズラベルも変わらない
- 付与は、既存のラベル遷移のコマンドに `--assign` を足して行う (`/issue` Step 3、`/spec` Step 3、`/code` Step 4)。未アサインのときだけ付き、既存の assignee は上書きも追加もしない。「Comment Consumption → ラベル遷移」の順序 (#1316、#1507) は変えない
- 「自分に付け替えて続ける」を選んだときだけ、確認の直後に `reassign` を実行する。「付け替えずに続ける」は何もしない
- 非対話 (`--non-interactive`) は `modules/ambiguity-detector.md` の High-Stakes Decision (skip 層) として扱い、assignee を変えずに警告して続ける。同モジュールの一覧に 1 項目を足す
- 新規作成 (`/issue "タイトル"`) は変更しない (assignee を設定しない)
- Issue が `/spec` に委ねた 2 点を決めた (Notes 参照): `/auto` 配下の子フェーズが重ねて警告を出すことは許容する。`run-issue.sh` のラベル補完では付けない

## Consumed Comments

No new comments since last phase.

## Changed Files

- `modules/assignee-check.md`: 新規ファイル。標準の 4 セクション (Purpose / Input / Processing Steps / Output) と Notes。内容は Implementation Steps 1。追記する文字列は英語のみ (日本語は `"..."`・`` `...` ``・コードフェンスの中に限る。`scripts/check-language-convention.py` が CI で検出する)
- `skills/issue/SKILL.md`: (a) frontmatter の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh:*` を追加 (b) 冒頭の「Key per-step behavior in non-interactive mode」に Existing Issue Step 1 の項目を追加 (c) Existing Issue Refinement の Step 1 の末尾に Assignee check のブロックを追加 (d) Existing Issue Refinement の Step 3 のコマンドに `--assign` を付け、説明の段落を追加 (e) New Issue Creation の Step 7 に「この遷移は assignee を設定しない」の 1 文を追加。ステップ見出しは増減・番号変更しない。追記する文字列は英語のみ
- `skills/spec/SKILL.md`: (a) `allowed-tools` に同じ項目を追加 (b) 冒頭の「Key per-step behavior in non-interactive mode」に Step 1 の項目を追加 (c) Step 1 の末尾に Assignee check のブロックを追加 (d) Step 3 のコマンドに `--assign` を付け、説明の段落を追加。追記する文字列は英語のみ
- `skills/code/SKILL.md`: (a) `allowed-tools` に同じ項目を追加 (b) Step 1 の末尾に Assignee check のブロックを追加 (c) Step 4 の `Both routes:` のコマンドに `--assign` を付け、説明の段落を追加。`## Autonomous Mode (--auto)` の委譲手順と Step 3 は変更しない。追記する文字列は英語のみ
- `modules/ambiguity-detector.md`: High-Stakes Decisions (exhaustive list) に `Assignee takeover` の項目を 1 つ追加 (先例: `Costly/irreversible Implementation Step execution`)。追記する文字列は英語のみ
- `docs/workflow.md`: Label Management の冒頭の段落に assignee への 1 文を足し、`### Label Transition Map` の表の直後 (`### XL Parent Issue Phase Management` の前) に `### Assignee` の小節を追加 (内容は Implementation Steps 3)
- `docs/ja/workflow.md`: [translation sync] 上記の日本語ミラー (ラベル管理)。`docs/translation-workflow.md` の Sync Procedure に従う。日本語の括弧は半角 `()` の前後に半角スペース
- `docs/structure.md`: [Steering Docs sync candidate: listing-side sub-check] Key Files の modules 一覧の `modules/l0-surfaces.md` の行の直後に `modules/assignee-check.md` の行を追加 (frontmatter の `ssot_for` に `directory-layout` があることを確認済み。Directory Layout の木構造は個別ファイルを載せないので変更不要)
- `docs/ja/structure.md`: [translation sync] 上記の日本語ミラー
- `tests/assignee-check.bats`: 新規ファイル。モジュール・各 SKILL.md の呼び出し位置・`--assign`・ドキュメントの構造テスト (Implementation Steps 4)

**変更不要 (grep・Read で確認済み):**

- `README.md` と `CLAUDE.md`: スキルの挙動・モジュール・ラベル・assignee の列挙がない (README は全 68 行を `modules/`・`tests/`・`assignee`・`label` で grep して 0 件。CLAUDE.md は言語・移行・用語の規約だけ)。`modules/doc-checker.md` と `modules/skill-dev-doc-impact.md` の影響判定の表が挙げる文書のうち、該当するのは `docs/workflow.md` (フェーズの説明) だけ
- `docs/guide/customization.md`・`docs/guide/autonomy.md`・`docs/tech.md`・`modules/autonomy-tier.md`・`modules/detect-config-markers.md`: #1543 で `auto-assign`・autonomy tier の例外・着手時の付与を記述済みで、今回の挙動と矛盾しない (各ファイルの該当箇所を Read で確認)
- `docs/guide/workflow.md` と `docs/ja/guide/workflow.md`: スキルごとのコマンドと Size の案内で、ラベル遷移や担当者の記述がない。着手時の挙動は `docs/workflow.md` の Label Management が担うので追加しない
- `modules/l0-surfaces.md`: Assignees 行の Primary callers は `gh-issue-assignee.sh`・`gh-label-transition.sh --assign` のスクリプトだけで、Labels 行 (`gh-label-transition.sh` だけ) と同じ書き方。スキル名は足さない (#1545 も同じ列を編集する見込みで、並行する 2 つの Issue が同じセルを触るのを避ける)
- `scripts/gh-issue-assignee.sh`・`scripts/gh-label-transition.sh`: #1543 のインターフェースをそのまま使う。変更なし
- `scripts/run-issue.sh`・`scripts/run-spec.sh`・`scripts/run-code.sh`: 開始時のフェーズへのラベル遷移を呼ぶのは `run-issue.sh` のラベル補完 (174 行目) だけで、そこは付けない方針 (Notes)。`--non-interactive` は 3 つとも渡している (`run-issue.sh:121`、`run-spec.sh:265`、`run-code.sh:312,318`)
- `.claude/settings.json.template`: ワイルドカードが全スクリプトを覆う (#1543 で確認済み)
- `skills/auto/SKILL.md`: #1545 の範囲
- 既存の bats (`tests/code.bats`・`tests/spec.bats`・`tests/issue.bats` ほか): `### Step N:` の前方一致で節を取り出して検査しており、見出しを増減・改名しないので影響を受けない。`gh-label-transition.sh $NUMBER code` などの呼び出し形を SKILL.md に対して固定している既存テストはない (grep 確認)

**同期候補の探索結果** (測定範囲: `grep -rlF "<keyword>" docs/ tests/ scripts/ modules/`、`docs/spec/`・`docs/reports/`・`docs/sessions/` を含む全ファイル。main の ca1b5b31 時点):

- キーワード `assignee-check.md`・`Assignee check`: 既存ファイルへの一致は 0 件 (新規の識別子のため、既存ドキュメントに同期漏れの候補はない)
- [Steering Docs sync candidate] keyword "gh-issue-assignee" skipped: matched 12 files (no discriminating power)
- [Steering Docs sync candidate] keyword "auto-assign" skipped: matched 15 files (no discriminating power)
- [Steering Docs sync candidate] keyword "gh-label-transition.sh" skipped: matched 77 files (no discriminating power)
- [Steering Docs sync candidate] keyword "l0-surfaces.md" skipped: matched 85 files (no discriminating power)
- [Steering Docs sync candidate] keyword "Existing Issue Refinement" skipped: matched 52 files (no discriminating power)
- `HAS_AUTO_ASSIGN` は 3 件 (`modules/detect-config-markers.md`・`tests/gh-issue-assignee.bats`・#1543 の Spec) で、いずれも今回の変更と無関係
- 既存の `assignee` への言及で今回の変更と矛盾するものはない (`/triage --assignee` は読み取りだけ)
- listing-side sub-check (新規ファイルの追加で発火): 候補集合は `ssot_for: directory-layout` を持つ `docs/structure.md` とルートの `README.md`。README は列挙がないので変更不要 (上記)。`docs/ja/` は翻訳ミラーとして別途同期する

## Implementation Steps

AC 番号は `## Verification > Pre-merge` の並び順 (AC1 = 付与、AC2 = 新規作成、AC3 = 他のメンバーの分岐、AC4 = 副作用より前、AC5 = `docs/workflow.md`、AC6 = bats の CI、AC7 = Skill 構文の CI)。

1. `modules/assignee-check.md` を新規作成する (→ AC1, AC3, AC4)

   **構成**: `# assignee-check` の下に 1〜2 文の概要、続けて `## Purpose`・`## Input`・`## Processing Steps`・`## Output`・`## Notes` (見出しは `##`、Processing Steps の中の小見出しは `###`) を英語で書く。日本語は `"..."`・`` `...` ``・コードフェンスの中だけにする。

   **Input**: `ISSUE_NUMBER` (処理中の Issue 番号)、`PHASE_NAME` (`issue` / `spec` / `code`。メッセージにだけ使う)、`NON_INTERACTIVE` (呼び出し元の ARGUMENTS に `--non-interactive` があれば `true`、なければ `false`)。

   **Processing Steps** (すべての分岐を次のとおり固定し、「適切に」「必要に応じて」のような曖昧な表現は残さない):

   - 前提: リポジトリルート (`.wholework.yml` のあるディレクトリ) から、1 コマンドずつ単純なコマンドとして実行する (`gh-issue-assignee.sh` は `auto-assign` を CWD から読むため。worktree 入場前に実行するのでメイン作業ツリーのルートになる)
   - `### 1. Read the assignment status`: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh status $ISSUE_NUMBER` を実行する。`STATUS` は、出力のうち行全体が `unassigned` / `self` / `other` / `unknown` のいずれかに一致する行。`Info:` と `Warning:` で始まる行は人向けのメッセージで、結果の語ではない。該当する行がない (コマンドが無い・実行できない・異常終了・想定外の出力) ときは「結果なし」とする。行は前後の空白と CR を除いてから比べる

     | STATUS | 動作 | 結果 |
     |---|---|---|
     | `unassigned` | 何もしない (呼び出し元のラベル遷移の `--assign` が付ける) | `continue` |
     | `self` | 何もしない | `continue` |
     | `unknown` | 何もしない (ヘルパーが `Warning:` を出している) | `continue` |
     | 結果なし | 次の 1 行を出力する (下のコードフェンス) | `continue` |
     | `other` | 次の `### 2.` へ | `### 2.` の結果 |

     結果なしの 1 行 (コードフェンス内): `assignee を確認できませんでした (Issue #{ISSUE_NUMBER})。そのまま続行します`

     注記: `other` は実行ユーザー以外の assignee がいることを表す。bot (Copilot など) も他のメンバーとして数える。実行ユーザーを特定できないときは、assignee が 1 人でもいれば `other` になる (ヘルパーの契約)。

   - `### 2. Another member is assigned (STATUS is other)`: `LOGINS` は標準エラー出力の `Info: issue #N is assigned to: <logins>` の行にある login の一覧。その行がないときは、メッセージでは「another member」にあたる語を使う。`LOGINS` は表示にだけ使い、シェルのコマンドには入れない。
     - **対話実行** (`NON_INTERACTIVE=false`): AskUserQuestion で単一選択を出す。選択肢は次の 3 つで、この順序・この文言 (ダブルクォート付き) にする。質問文と各選択肢の説明は、コードフェンスの中に日本語で書く。AskUserQuestion が使えない (呼び出しが失敗する) ときは、非対話実行と同じ扱いにする

       | 選択肢 | 動作 | 結果 |
       |---|---|---|
       | `"自分に付け替えて続ける"` | `### 3.` を実行する | `continue` |
       | `"付け替えずに続ける"` | 何もしない | `continue` |
       | `"中止"` | 中止の通知を出力して、呼び出し元スキルをただちに終了する。`Do not run any later step` と書く (triage・worktree 入場・ラベル遷移・assignee の書き込み・コメント投稿・Spec の作成など、以降の手順は一切実行しない) | `abort` |

       中止の通知 (コードフェンス内、2 行): `中止しました: Issue #{ISSUE_NUMBER} は {LOGINS} にアサインされています。assignee もフェーズラベルも変更していません` / `続行する場合は、担当者に確認してから /{PHASE_NAME} {ISSUE_NUMBER} を再実行してください`
     - **非対話実行** (`NON_INTERACTIVE=true`): AskUserQuestion も `reassign` も呼ばない。`modules/ambiguity-detector.md` の Three-Tier Policy の skip 層として、標準の警告形式で 2 行を出力して続行する (結果 `continue`)。1 行目は `[non-interactive mode] Skipping high-stakes action: reassigning issue #{ISSUE_NUMBER} from {LOGINS} to the executing user`、2 行目は ``To perform this action, run `/{PHASE_NAME} {ISSUE_NUMBER}` interactively.``
   - `### 3. Reassign (only after "自分に付け替えて続ける")`: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh reassign $ISSUE_NUMBER` を実行し、出力の語で分岐する。どの結果でも呼び出し元スキルは止めない (結果 `continue`)

     | 結果の語 | 意味 | 出力 |
     |---|---|---|
     | `assigned` | 実行ユーザーが assignee になった (ヘルパーが同時着手の `Warning:` を出していたら、そのまま利用者に見せる) | `assignee を実行ユーザーに付け替えました (Issue #{ISSUE_NUMBER})` |
     | `unchanged` | 付け替える相手がもういない (確認の間に外された) か、すでに実行ユーザーだけ | なし |
     | `disabled` | `auto-assign: false` のため何もしなかった | `auto-assign: false のため assignee は付け替えていません。そのまま続行します` |
     | `failed`・語なし・想定外の語 | 失敗 (理由はヘルパーの `Warning:`) | `assignee を付け替えられませんでした (理由は上の Warning を参照)。assignee は変更せず続行します` |

   **Output**: `continue` (呼び出し元は次の手順へ進む) または `abort` (対話実行で `"中止"` が選ばれたときだけ。呼び出し元は以降の手順を実行せずに終了する)。このモジュールは assignee を設定する経路を `reassign` 以外に持たない。

   **Notes に書く内容** (見出しごとに 1 項目 1 段落):

   - 確認を副作用より前に置く理由: `/issue N` は Step 2 の triage 自動実行が title・Type・Size・Value を書き込む。`/spec`・`/code` は Step 2 で worktree に入り、コメントの取り込みと作業ディレクトリの掃除を行う。これらの後で中止すると、他のメンバーの Issue に書き込みか worktree が残る
   - `assign` を呼ばない理由: 未アサインへの付与は呼び出し元のラベル遷移 (`--assign`) が担い、「ラベル遷移 → 付与」を 1 コマンドで保証する。ここで付けると同じ判定が 2 回になる
   - `auto-assign: false` と autonomy tier との関係: 確認は `auto-assign` の値にも tier にも関係なく動く (人が手で付けた assignee を尊重するため)。止まるのは `reassign` の書き込みだけ (`disabled`)。呼び出し側は `HAS_AUTO_ASSIGN` を再判定しない (`modules/detect-config-markers.md`)。そのため `"自分に付け替えて続ける"` は `auto-assign: false` でも選択肢に出し、`disabled` を受けて案内する
   - 失敗は止めない (fail-open): ヘルパーが無い・結果が読めない・`reassign` が失敗・AskUserQuestion が使えない、のどれでもフェーズは続く。フェーズを止めるのは利用者の明示的な `"中止"` だけ。依拠する方針は #1542 の「失敗しても止めない」
   - `/auto` の子フェーズ (`run-*.sh` は常に `--non-interactive`) は、親が確認して「付け替えずに続ける」を選んだ後でも、同じ警告を 1 フェーズにつき 1 回出す。この重なりは許容する (警告は事実どおりで 1 行にすぎず、抑止には `run-*.sh` と全 SKILL.md を通る引数が新たに要る)
   - ヘッドレス実行では、セッションの最終結果だけが wrapper のログに残るため、途中で出した警告は残らないことがある (他の非対話の警告と同じ制約。`modules/phase-banner.md` の Notes)
   - 呼び出し元の表 (Callers): `skills/issue/SKILL.md` (Existing Issue Refinement Step 1)、`skills/spec/SKILL.md` (Step 1)、`skills/code/SKILL.md` (Step 1)。新しいスキルが読むようになったら行を足す

   **テストが完全一致で検査する文言** (言い換えない): `# assignee-check`、`## Purpose`、`## Input`、`## Processing Steps`、`## Output`、`${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh status $ISSUE_NUMBER`、`${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh reassign $ISSUE_NUMBER`、`"自分に付け替えて続ける"`・`"付け替えずに続ける"`・`"中止"` (この順)、`[non-interactive mode] Skipping high-stakes action:`、`Do not run any later step`、語 `unassigned`・`self`・`other`・`unknown`・`assigned`・`unchanged`・`disabled`・`failed`

   **この手順の性質** (fail-safe critical: 前提確認のゲートに当たる): 入力は Issue 番号 (ヘルパーが正の整数か検証する) とヘルパーの出力だけ。空・想定外の出力は「結果なし」で続行 (fail-open)。login の特殊文字 (`dependabot[bot]` など) は表示にだけ使い、コマンドに入れない。依存コマンドの失敗はすべて続行側に倒す。止める経路は利用者の明示的な選択だけ

2. 3 つの SKILL.md を更新する (after 1) (→ AC1, AC2, AC3, AC4, AC7)

   共通: ステップ見出しは増やさず、番号も変えない (`Step N.M` 形式は検証で禁止、既存テストも見出しの前方一致に依存)。本文 (コードフェンス・インラインコード・HTML コメントの外) に半角の `!` を書かない。日本語は `"..."` の中だけ。本文中のツール名として `validate-skill-syntax.py` が検査する語 (`Edit`・`WebFetch`・`WebSearch`・`EnterWorktree` など) は、その SKILL.md の `allowed-tools` に無いものを書かない。

   **`allowed-tools`** (3 ファイル): frontmatter の `${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh:*` の直後に `, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh:*` を足す。モジュールが `gh-issue-assignee.sh` を参照するので、モジュールを読む全スキルに必要 (クロスファイル検査)。

   **Assignee check のブロック** (3 ファイルの Step 1 の末尾。`<N>` と `<PHASE>` と `<FIRST SIDE EFFECT>` は下の表のとおり)。ブロックは太字ラベルで始まる 1 段落にし、見出しにはしない:

   ```markdown
   **Assignee check (run before Step 2's <FIRST SIDE EFFECT>):** Read `${CLAUDE_PLUGIN_ROOT}/modules/assignee-check.md` and follow the "Processing Steps" section with parameters: `ISSUE_NUMBER=$NUMBER`, `PHASE_NAME=<PHASE>`, `NON_INTERACTIVE=true` when ARGUMENTS contains `--non-interactive` (otherwise `false`). The check only reads the assignee, and it must come before Step 2 because <WHY>. When a member other than the executing user is assigned, an interactive run asks with AskUserQuestion whether to "自分に付け替えて続ける", "付け替えずに続ける", or "中止"; a `--non-interactive` run leaves the assignee unchanged, prints a warning, and continues. Choosing "中止" ends <ENDS>: <LEFT>. An Issue with no assignee is assigned in Step <T> together with the label transition; an existing assignee is never overwritten or added to.
   ```

   | スキル | `<FIRST SIDE EFFECT>` | `<PHASE>` | `<WHY>` | `<ENDS>` | `<LEFT>` | `<T>` |
   |---|---|---|---|---|---|---|
   | `/issue` (Existing Issue Refinement) | `triage auto-chain` (`Step 2's triage auto-chain`) | `issue` | `Step 2 writes the title, Type, Size, and Value` | `the refinement here` | `no triage write, no label change, and no assignee change remains` | `3` |
   | `/spec` | `Worktree Entry` | `spec` | `Step 2 creates the worktree, consumes comments, and sweeps the work directory` | `/spec here` | `no worktree, no label change, and no assignee change remains` | `3` |
   | `/code` | `Worktree Entry` | `code` | `Step 2 creates the worktree, consumes comments, and sweeps the work directory` | `/code here` | `no worktree, no label change, and no assignee change remains` | `4` |

   挿入位置 (近傍の文脈で指定): `/issue` は Existing Issue Refinement の Step 1 の最後の段落 (`Detect embedded links in body and comments; ...`) の直後。`/spec` は Step 1 の `` `ISSUE_TYPE` is referenced in Step 10 template selection. `` の直後。`/code` は Step 1 の `Generate a short description from the title ...` の直後。

   **ラベル遷移** (3 ファイル): 次のコマンドに変え、コードブロックの直後に同じ説明の段落を足す。

   - `/issue` Existing Issue Refinement の `### Step 3: Label Transition`: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER issue --assign`
   - `/spec` の `### Step 3: Label Transition (start)`: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER spec --assign`
   - `/code` の `### Step 4: Create Branch & Label Transition` の `Both routes:` のコードブロック: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER code --assign`

   説明の段落 (3 ファイルで同一。この文面をそのまま使う):

   ```markdown
   `--assign` also sets the executing user as the assignee, but only when the Issue has none: an existing assignee is never overwritten or added to. It runs after the label update succeeds, and a failure to set the assignee only prints a warning, so the transition still succeeds. If the command prints a `Warning:` line (for example, another member was assigned at about the same time), show it to the user and continue.
   ```

   遷移先が `issue` / `spec` / `code` 以外の既存のラベル遷移 (`/issue` の `done`・`ready`、`/spec` の `ready`、`/code` の `verify`、New Issue Creation Step 7 の `issue`) には `--assign` を付けない。

   **非対話の項目** (`/issue` と `/spec` の冒頭の「Key per-step behavior in non-interactive mode」。先頭の項目として追加):

   - `/issue`: `- **Existing Issue Step 1** (Assignee check): **skip** (High-Stakes Decision — taking over another member's Issue); output the warning, leave the assignee unchanged, and continue`
   - `/spec`: `- **Step 1** (Assignee check): **skip** (High-Stakes Decision — taking over another member's Issue); output the warning, leave the assignee unchanged, and continue`
   - `/code` には一覧が無い。`## Error Handling in Non-Interactive Mode` の skip の項目が `modules/ambiguity-detector.md` の一覧を参照しているので、変更不要

   **New Issue Creation の Step 7** (`/issue` のみ): `gh-label-transition.sh $NUMBER issue` のコードブロックの直後、`After applying labels, set blocked-by ...` の段落の前に 1 文を足す: `This transition does not set an assignee: a newly created Issue is not assigned to its creator. Only Existing Issue Refinement sets an assignee (its Step 3).` (`--assign` という語は書かない。構造テストが New Issue Creation の節に `--assign` が無いことを確認する)

3. `modules/ambiguity-detector.md` とドキュメントを更新する (parallel with 2) (→ AC3, AC5)

   - `modules/ambiguity-detector.md`: `High-Stakes Decisions (exhaustive list — ...)` の最後の項目 (`**Size downgrade from XL to L**`) の直後に追加する: `` - **Assignee takeover**: replacing another member's assignee with the executing user (the "自分に付け替えて続ける" choice in `modules/assignee-check.md`); it removes someone else's ownership marker, so it needs a human decision — leave the assignee unchanged and continue ``
   - `docs/workflow.md`:
     - (a) `## Label Management` の冒頭の段落 (`Uses `phase/*` labels to visualize Issue progress. Each skill automatically manages labels as the workflow advances.`) の末尾に 1 文を足す: `The Issue's assignee shows who is working on it (see [Assignee](#assignee)).`
     - (b) `### Label Transition Map` の表の直後、`### XL Parent Issue Phase Management` の前に、`### Assignee` (h3) の小節を追加する。本文は次のとおり (AC5 の「役割分担」と「着手時の付与・確認の挙動」を満たす内容。事実はモジュールの手順と一致させる):

       ```markdown
       ### Assignee

       `phase/*` labels show how far an Issue has progressed; the Issue's assignee shows who is working on it. Both change when a phase starts, so other members can see the owner and the progress in the places they already look (the Issue list, the Projects board, "Assigned to me").

       - **Assignment at phase start**: when `/issue N` (refining an existing Issue), `/spec`, or `/code` moves the phase label to `phase/issue`, `phase/spec`, or `phase/code`, it also sets the executing user as the assignee, but only when the Issue has no assignee. An existing assignee is never overwritten and a second assignee is never added, so the first phase that starts on an Issue is the one that assigns it.
       - **Not assigned**: a new Issue created with `/issue "title"` (the creator is not necessarily the owner), `/triage`, `/audit`, and the label backfill in `scripts/run-issue.sh`. `/review`, `/merge`, and `/verify` do not assign either, because an earlier phase has already settled the owner.
       - **When another member is assigned**: `/issue N`, `/spec`, and `/code` check this first, before any other action (before the triage auto-chain for `/issue N`, before entering the worktree for `/spec` and `/code`). An interactive run asks whether to reassign the Issue to you and continue, to continue without reassigning, or to abort; aborting leaves the phase label, the triage fields, and the worktree untouched. A `--non-interactive` run leaves the assignee unchanged, prints a warning, and continues. The procedure is defined in [`modules/assignee-check.md`](../modules/assignee-check.md).
       - **Kept after completion**: the assignee is not removed at `phase/done` or when the Issue is closed, so it records who handled the Issue.
       - **Failures never stop a phase**: when the executing user cannot be identified (for example with a GitHub App token or the CI `GITHUB_TOKEN`) or the assignment is not permitted, only a warning is printed. An assignee is not a lock: after assigning, the Issue is re-read and a warning is printed if someone else was assigned at about the same time, but two sessions of the same user cannot be told apart.
       - **Settings**: `auto-assign: false` in `.wholework.yml` stops the assignment and the reassignment only; the check for other members' assignments still runs. Neither depends on the autonomy tier. See the [Customization Guide](guide/customization.md).
       ```
   - `docs/ja/workflow.md`: `## ラベル管理` に上の (a)(b) を日本語で同期する。冒頭の段落の末尾に 1 文、`### ラベル遷移マップ` の表の直後・`### XL 親 Issue のフェーズ管理` の前に `### 担当者 (assignee)` の小節。リンクは `../../modules/assignee-check.md` と、ja ディレクトリ内の `guide/customization.md` (`docs/ja/guide/customization.md`) を指す。(a) の `(see [Assignee](#assignee))` にあたる部分は、アンカーに頼らず小節名 (`担当者`) で案内する文にする。コードフェンスの数は英語版と一致 (この小節には追加なし)。日本語の括弧は半角 `()` の前後に半角スペース
   - `docs/structure.md`: Key Files の modules 一覧で、`- `modules/l0-surfaces.md` — ...` の行の直後に追加する: `` - `modules/assignee-check.md` — pre-flight assignee check shared by `/issue` (existing Issue refinement), `/spec`, and `/code`, run before the first side effect: asks whether to reassign, continue, or abort when another member is assigned (a `--non-interactive` run warns and continues); never assigns an unassigned Issue (the label transition's `--assign` does) ``
   - `docs/ja/structure.md`: 同じ位置 (`modules/l0-surfaces.md` の行の直後) に日本語で同期する: `` - `modules/assignee-check.md` — `/issue` (既存 Issue の精査)・`/spec`・`/code` が最初の副作用より前に実行する担当者確認の共通手順。他のメンバーがアサイン済みのとき、付け替え・続行・中止を確認する (`--non-interactive` では警告して続行)。未アサインの Issue には付与しない (ラベル遷移の `--assign` が付与する) ``

4. `tests/assignee-check.bats` を新規作成する (after 1, 2, 3) (→ AC6, AC7)。既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/assignee-check.bats` の各 @test) を追加したうえでスイートが PASS すること

   **入力の形式**: 構造テスト。入力は実ファイルそのもの。ファイル先頭で `load 'helpers/markdown-section'` を読み込み、`setup()` で `PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` を定義する。節の取り出しは `md_section FILE HEADING_PREFIX` (見出しの前方一致、コードフェンス内の見出しは無視、次の同レベル以上の見出しまで)。節の見出しの前方一致は次を使う: `/issue` の `### Step 1: Fetch Issue Information` (New Issue Creation の Step 1 は `Collect Basic Information` なので一意)、`### Step 3: Label Transition`、`## New Issue Creation`。`/spec` の `### Step 1: Fetch Issue Information`、`### Step 3: Label Transition`。`/code` の `### Step 1: Fetch Issue Info`、`### Step 4: Create Branch & Label Transition`。`docs/workflow.md` の `## Label Management`、`docs/ja/workflow.md` の `## ラベル管理`

   **書き方の注意** (#1543 のレビューで見つかった型): 最終行ではない `! cmd` は失敗してもテストが FAIL しない。否定の検査は `run cmd` のあとに `[ "$status" -eq 1 ]` で書く。`[[ ... ]]` の単独文は bash 3.2 で失敗が見逃されるので `|| false` を付けるか `[ ... ]` を使う。`$(...)` への代入は宣言と分ける (`local x; x=$(...)`)。ファイル内のコード・コメントは英語

   **@test の一覧** (名前は `module:` / `skill:` / `docs:` / `run-issue:` で始める):

   - `module: assignee-check.md has the four standard sections` (4 つの `##` 見出し)
   - `module: reads the status and reassigns through gh-issue-assignee.sh` (2 つのコマンド文字列)
   - `module: covers every status word and every reassign result word` (語 8 個を `grep -qw` で 1 つずつ。どれが欠けたかを出力する)
   - `module: offers the three choices in the specified order` (3 つのラベルの最初の出現行の昇順)
   - `module: skips the takeover in a non-interactive run with the standard warning` (`NON_INTERACTIVE` と標準の警告形式)
   - `module: abort stops the calling skill before any later step` (`Do not run any later step`)
   - `ambiguity-detector: lists the assignee takeover as a High-Stakes Decision` (`Assignee takeover` と `modules/assignee-check.md`)
   - `skill: issue calls the assignee check in Existing Issue Refinement Step 1` / `skill: spec calls the assignee check in Step 1` / `skill: code calls the assignee check in Step 1` (各 Step 1 の節に、太字ラベル `**Assignee check (run before Step 2`、フルパス `${CLAUDE_PLUGIN_ROOT}/modules/assignee-check.md`、3 つのラベルがある)
   - `skill: the assignee check comes before the first side effect in issue, spec, and code` (太字ラベルの行番号 < `/issue` の `### Step 2: Auto-chain to triage`、`/spec` の `### Step 2: Worktree Entry`、`/code` の `### Step 2: Worktree Entry` の行番号)
   - `skill: issue, spec, and code allow gh-issue-assignee.sh` (`allowed-tools:` の行にフルパス付きの `gh-issue-assignee.sh:*`)
   - `skill: the start-of-phase label transition passes --assign in issue, spec, and code` (`/issue` Step 3、`/spec` Step 3、`/code` Step 4 の各節に、`gh-label-transition.sh $NUMBER <phase> --assign` の形)
   - `skill: only one label transition per skill passes --assign` (各 SKILL.md で `gh-label-transition\.sh \$NUMBER [a-z]+ --assign` に一致する行が 1 行。説明の段落には完全なコマンド形を書かないので数が合う)
   - `skill: issue New Issue Creation does not assign and does not run the assignee check` (`## New Issue Creation` の節を一時ファイルに書き出し、`--assign` と `assignee-check.md` が無いことを `run grep` + `[ "$status" -eq 1 ]` で確認)
   - `docs: workflow.md Label Management describes the assignee role split and the start-time behavior` (節に `assignee`・`auto-assign`・`modules/assignee-check.md`)
   - `docs: ja workflow.md ラベル管理 mentions the assignee` (節に `assignee`)
   - `docs: structure.md and its ja mirror list modules/assignee-check.md`
   - `run-issue: the phase/issue label backfill does not assign` (`scripts/run-issue.sh` に `--assign` が無い。ラベル補完で付けない判断の回帰ガード)

   **実装前の状態に対して FAIL すること**: `/code` の New Verification-Test Pre-implementation FAIL Check に従う。実装後・コミット前に、実装対象のファイル (`modules/assignee-check.md`・3 つの SKILL.md・`modules/ambiguity-detector.md`・`docs/workflow.md`・`docs/ja/workflow.md`・`docs/structure.md`・`docs/ja/structure.md`) を一時的に実装前の状態に戻し (新規の `modules/assignee-check.md` は退避する)、`bats tests/assignee-check.bats` の新規テストが FAIL することを確認してから元に戻す。PASS してしまうテストは、パターンを絞るか節の抽出 (`md_section`) に切り替える。結果は `## Code Retrospective` に "Confirmed pre-implementation FAIL for N new test(s)." の形で記録する。`run-issue:` のテストと `skill: issue New Issue Creation does not assign ...` のテストの 2 本は、「変更しない」ことの回帰ガード (否定の検査) なので、実装前の状態でも PASS する (対象外)

5. 検査コマンドで確認する (after 4) (→ AC6, AC7)

   - `python3 scripts/validate-skill-syntax.py skills/` (Skill 構文チェックの CI と同じ。本文の `!`、`allowed-tools` とスクリプト参照、モジュール経由のスクリプト参照を検査する)
   - `bats tests/assignee-check.bats tests/code.bats tests/spec.bats tests/issue.bats` のあと、`bats tests/` 全体 (`/code` Step 9 の並列の形で実行する)
   - `bash scripts/check-forbidden-expressions.sh` (`docs/` と `tests/` も対象。`docs/product.md` § Terms で deprecated とされた語を書かない)
   - `git diff -U100000 origin/main...HEAD -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py` (CJK の混入。日本語が `"..."`・`` `...` ``・コードフェンスの外に出ていないこと)
   - `bash scripts/check-translation-sync.sh` (`docs/workflow.md`・`docs/structure.md` と ja の同期。#1543 時点で `docs/guide/xl-decomposition.md` は無関係の既存の OUTDATED)
   - `bash scripts/check-bare-bracket-assertions.sh`
   - `.claude/` 配下のファイルは変更しないので `git add -f` は不要

## Verification

### Pre-merge

- <!-- verify: rubric "skills/issue/SKILL.md の Existing Issue Refinement、skills/spec/SKILL.md、skills/code/SKILL.md の着手時の手順に、Issue が未アサインなら実行ユーザーを assignee に設定し、すでに assignee がいる場合は上書きも追加もしないことが書かれている" --> <!-- verify: grep "assignee" "skills/issue/SKILL.md" --> <!-- verify: grep "assignee" "skills/spec/SKILL.md" --> <!-- verify: grep "assignee" "skills/code/SKILL.md" --> 既存 Issue の精査 (`/issue 123`)・`/spec`・`/code` の着手時に、Issue が未アサインなら実行ユーザーが assignee に設定される。すでに assignee がいる場合は、上書きも追加もしない
- <!-- verify: rubric "skills/issue/SKILL.md で、assignee を設定する手順は Existing Issue Refinement (/issue 123) にだけあり、New Issue Creation (/issue \"タイトル\") のフローには assignee を設定する手順がない" --> 新規作成 (`/issue "タイトル"`) では assignee を設定しない
- <!-- verify: rubric "skills/issue/SKILL.md の Existing Issue Refinement、skills/spec/SKILL.md、skills/code/SKILL.md に、実行ユーザー以外がアサイン済みの場合の分岐が書かれている。対話実行では AskUserQuestion で「自分に付け替えて続ける / 付け替えずに続ける / 中止」の 3 択を示す。--non-interactive の実行では assignee を変更せずに警告を出力して続行する" --> 実行ユーザー以外がアサイン済みのとき、対話実行では「自分に付け替えて続ける / 付け替えずに続ける / 中止」の 3 択で確認する。非対話実行 (`--non-interactive`) では assignee を変えずに警告だけを出して続ける
- <!-- verify: rubric "他のメンバーの担当の確認が副作用のある処理より前に行われ、中止を選んだ場合に何も残らない。具体的には、/issue 123 では Step 2 の triage 自動実行より前に、/spec と /code では worktree に入るより前に確認しており、中止の場合はフェーズラベルを変更せず、triage の書き込みや worktree も残さずに終了する" --> 他のメンバーの担当の確認は副作用のある処理より前に行う (`/issue 123` は triage の自動実行より前、`/spec`・`/code` は worktree に入る前)。中止を選ぶと、フェーズラベルを変えず、triage の書き込みや worktree も残さずに終了する
- <!-- verify: section_contains "docs/workflow.md" "Label Management" "assignee" --> `docs/workflow.md` の Label Management に、assignee で担当者を、`phase/*` ラベルで進み具合を表すという役割分担と、着手時の付与・確認の挙動が書かれている
- <!-- verify: github_check "gh pr checks --json name,state --jq '.[] | select(.name==\"Run bats tests\") | .state'" "SUCCESS" --> CI の bats テスト (Run bats tests) が通る
- <!-- verify: github_check "gh pr checks --json name,state --jq '.[] | select(.name==\"Validate skill syntax\") | .state'" "SUCCESS" --> CI の Skill 構文チェック (Validate skill syntax) が通る

### Post-merge

- 未アサインの Issue に `/issue 123` (精査)・`/spec`・`/code` のいずれかを実行したとき、その Issue の assignee に実行ユーザーが設定されることを確認する <!-- verify-type: opportunistic -->

## Notes

### 設計判断 (非対話モードでの自動解決)

- **共通手順をモジュールにした**: 同じ手順が 3 スキルにあり、#1545 の `/auto` の親も同じ 3 択を使う。SKILL.md に 3 回書くと、結果の語の扱い (`disabled` など) や文言がずれていく。先例は `modules/phase-banner.md`・`modules/l0-surfaces.md` の Comment Consumption Procedure・`modules/phase-work-dir.md`。`modules/l0-surfaces.md` に足す案は採らない: `validate-skill-syntax.py` は、モジュールが参照するスクリプトを、そのモジュールを読む全 SKILL.md の `allowed-tools` に要求する (`validate_modules_scripts_in_allowed_tools`)。`l0-surfaces.md` は多くのスキルが読むので、今回触らないスキルまで `allowed-tools` の変更が要る。AC の rubric は SKILL.md の記述を見るため、各 SKILL.md の呼び出し部分にも、付与の条件・3 択の文言・非対話の挙動・確認の位置を短く書いて、モジュールを読まなくても要点が分かるようにした
- **確認は Step 1 の末尾**: 番号を振り直さない・`Step N.M` は禁止・英字付きの見出しも増やさない、という制約から、既存のステップの中に太字ラベルの段落として足す。`/issue` の Step 1 には長い Comment Consumption の段落があるが、これは読み取りだけで書き込みを伴わないので、その後に置いても「副作用より前」は守られる。バナー (Step 1 の途中) の後なので、利用者はどの Issue か分かった状態で確認を受ける
- **付与は `--assign`、付け替えは確認の直後**: 付与をラベル遷移に相乗りさせると「ラベル遷移 → 付与」が 1 コマンドで保証され、Comment Consumption → ラベル遷移の順序も崩れない。`gh-label-transition.sh` の既存の許可 (`allowed-tools`) で足りる。付け替えを後ろ (ラベル遷移の位置) に寄せる案は、選択結果を Step 1 から Step 3・4 まで持ち回る必要があり (`/code` は間に Step 3 の Abort 分岐もある)、採らない。代償として、付け替えの後に別の理由で止まると assignee だけが変わってラベルは変わらない状態が残りうるが、利用者が「自分に付け替える」と明示した結果なので許容する
- **非対話は High-Stakes (skip 層)**: 他のメンバーの担当を人の確認なしに付け替えないのは「人の判断が要る」決定で、先例は `Costly/irreversible Implementation Step execution` (`modules/costly-step-protocol.md`)。skip 層は「実行しない + 警告 + 続行」で、Auto-Resolve Log への記録は要らない (記録するのは挙動を変える自動決定。今回の自動決定は何もしないこと)。`/code` Step 3 の `phase/ready` 確認は、非対話の既定が「Spec なしで進める」という挙動の変更なので記録を残している。この点で先例と形が違う
- **`disabled` は案内する (選択肢は減らさない)**: `auto-assign: false` でも確認は動く (#1542 方針 10) ので、3 択のうち「付け替え」が何もしない。`modules/detect-config-markers.md` は、呼び出し側が `HAS_AUTO_ASSIGN` を再判定してはならないとしているため、選択肢を出し分けず、`reassign` の結果 `disabled` を受けて案内する。確認の時点で `HAS_AUTO_ASSIGN` を使える状態のスキルがないことも、出し分けを採らない理由 (`/spec` は Step 5、`/issue` は Step 4 で初めて設定を読む。`/code` は Step 0 で読むが、保持する変数に `HAS_AUTO_ASSIGN` を入れていない)
- **`/auto` 配下の子フェーズの重複警告は許容する** (Issue が `/spec` に委ねた判断): 親が確認して「付け替えずに続ける」を選んだ後も、子フェーズ (`run-*.sh` は常に `--non-interactive`) は同じ警告を 1 フェーズにつき 1 回出す。警告は事実どおり (assignee は他のメンバーのまま) で 1 行にすぎず、抑止するには `run-*.sh` と 3 つの SKILL.md を通る新しい引数が要り、並行して進む #1545 の設計に依存してしまう。許容する旨はモジュールの Notes に書く。#1545 が抑止を望む場合は、そちらで引数を足す
- **`run-issue.sh` のラベル補完では付けない** (Issue が `/spec` に委ねた判断): 補完が働くのは、`/issue` が Issue Retrospective を投稿したのに Step 3 を飛ばした異常系だけ (`run-issue.sh` の `_issue_retro_posted_since` の分岐)。補完の役目は完了の目印である `phase/issue` ラベルの復元で、着手時の目印 (assignee) を事後に足すと、利用者が離れた後の書き込みになる。未アサインのままなら、次のフェーズ (`/spec`・`/code`) の着手時に付く。見える化が最大 1 フェーズ遅れるだけで、`run-issue.sh` と `tests/run-issue.bats` を変えずに済む。回帰ガードとして、補完のコマンドに `--assign` が無いことを bats で確認する
- **`/code N --auto` の委譲経路は対象外**: `## Autonomous Mode (--auto)` は `run-code.sh` に委譲して終了するだけの薄い入口で、起動された子は `--non-interactive` で警告のみになる。親で確認する形は #1545 の `/auto` と同じ設計の話なので、そちらの方針が決まってから、必要なら別 Issue で扱う
- **`modules/l0-surfaces.md` の Primary callers は変えない**: #1543 の申し送りは「スキル名を足すのは #1544・#1545 の側」だったが、Labels 行は `gh-label-transition.sh` だけを書いており、スクリプト単位の列挙で足りる。#1545 も同じセルを編集する見込みで、並行する 2 つの Issue が同じセルを触ると競合する。必要になったら #1545 の完了後にまとめて足す
- **Issue 本文と既存実装の矛盾は検出されなかった**: 背景の事実をすべてコードで確認した (`/issue` Existing Issue Refinement の Step 2 が triage、Step 3 がラベル遷移 / `/spec` Step 2 が worktree・Step 3 がラベル遷移 / `/code` Step 2 が worktree・Step 4 がラベル遷移 / New Issue Creation Step 7 と `run-issue.sh:174` が `issue` への遷移 / `tests/code.bats` が `### Step N:` の前方一致で検査 / `run-*.sh` が `--non-interactive` を付ける / Comment Consumption の cutoff は `labeled` イベントだけを見る)
- 監査・調査型の Issue ではない (新しい手順の追加であり、複数の既存項目を分類する成果物はない)
- 外部仕様の新しい依存はない。#1543 のヘルパーのインターフェース (標準出力の語・終了コード 0・標準エラー出力の `Info:` / `Warning:`) だけを使う。標準エラー出力がシェルツールの結果に含まれることは、このセッションの Bash 呼び出し (`ls` の失敗メッセージが結果に出た) で観測した (取得日 2026-10-24)。`Info:` の行が見えない環境でも、モジュールは「another member」にあたる語で続行する。`context: fork` の `/code` での AskUserQuestion は、既存の Step 3 (`phase/ready` 確認) が先例

### 実機で確認していないこと

- 対話での 3 択の表示・中止の挙動は LLM 駆動の手順で、bats では確認できない (配線と文言の構造テストまで)。Post-merge の opportunistic AC (未アサインの Issue での assignee の設定) と、初回の対話実行での目視に委ねる
- 書き込みを伴う実機確認 (#1543 から持ち越し: 追加 API が割り当てできないユーザーを黙って無視するか、置換 API の実挙動) は、この Issue の Post-merge で初めて行われる

### 実装時の注意

- **CJK 検査**: `skills/`・`modules/` に追記する文字列は、日本語を `"..."`・`` `...` ``・コードフェンスの中にだけ置く。複数行にまたがるダブルクォートは検査が行単位なので効かない。1 行で閉じる
- **`!` の禁止**: SKILL.md の本文 (コードフェンス・インラインコード・HTML コメントの外) に半角の `!` を書かない。`modules/` は検査対象外だが、揃えて避ける
- **モジュールが参照するスクリプトのパス**: `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` の形で書くスクリプトは、モジュールを読む 3 スキルすべての `allowed-tools` に必要。モジュールには `gh-issue-assignee.sh` のほか、`gh-label-transition.sh` を `${CLAUDE_PLUGIN_ROOT}/scripts/` 付きで書く場合も 3 スキルに既にある。他のスクリプトをこの形で書かない
- **禁止語**: `docs/`・`tests/` を含めて、`docs/product.md` § Terms で deprecated とされた語 (一覧は `scripts/check-forbidden-expressions.sh`) を書かない。この Spec 自身も `docs/` 配下として検査対象になるので、禁止語を例として列挙しない
- **翻訳ミラー**: 日本語の括弧は半角 `()` の前後に半角スペース。コードフェンスの数を英語版と一致させる

### 新規テストケースの要件 (Step 13 は light で省略されるため、ここに記録)

新規の分岐ロジック (担当確認の手順、`--assign` の付与、非対話の skip) に対して、既存スイートが PASS することだけでなく、`tests/assignee-check.bats` の新規 @test (Implementation Steps 4 の一覧) を追加したうえでスイートが PASS すること。手順そのものは LLM 駆動なので、テストは「配線 (参照・位置・`allowed-tools`・`--assign`)」と「文言の固定」の構造検査にとどまる。

### 規模の見積もり (Step 18 の再評価に使う)

Changed Files は 10 件 (新規 2、翻訳ミラー 2、残りは既存ファイルへの追記)。ファイル数の軸では L (6〜10)。複雑さの補正は、加算要因が「複数のスキルにまたがる変更」、減算要因が「既存パターン (Read and follow のモジュール、`--assign`、`/code` Step 3 の先例) の横展開」で、差し引き 0 のまま L。triage 時点の M より大きい。

### その他

- **Pre-merge 項目数**: この Spec の Pre-merge は 7 件で、SPEC_DEPTH=light の目安 (5 件) を超える。Issue 本文の `## Acceptance Criteria > Pre-merge` を verify command ごと転記する規則 (件数の一致検査を含む) を優先した。Implementation Steps は目安内の 5 件にまとめた
- **Smoke Test は省略**: 実 GitHub への書き込みを伴う確認 (`--assign`・`reassign`) は Issue の assignee を変更し通知を発生させるため入れない。読み取りだけの `status` の疎通は #1543 の Smoke Test で済んでいる
- **コミット前の確認**: 新規ファイル (`modules/assignee-check.md`・`tests/assignee-check.bats`) は `git add` する。`.claude/` 配下は変更しない

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1〜5 を Spec のとおりに実施した (モジュール、3 SKILL.md、`ambiguity-detector.md`、`docs/workflow.md`・`docs/structure.md` と ja ミラー、bats)

### Design Gaps/Ambiguities
- Step 3 の `phase/ready` 確認は `matches_expected: true` (観測ラベル: `triaged`, `phase/ready`) で、Auto-Resolve Log に記録する判断は発生しなかった
- 実装前 FAIL 確認: コミット前の作業ツリーのため `git stash` は使わず、`git archive HEAD` の展開コピー (phase work directory 配下) に新規 bats だけを置いて実行した。worktree 分離ガードが複合の git コマンドを拒否するため、アーカイブ作成と展開を別コマンドに分けた
- Confirmed pre-implementation FAIL for 17 new test(s). 実装前でも PASS したのは回帰ガードの否定検査 2 本 (`skill: issue New Issue Creation does not assign ...`、`run-issue: ...`) で、Spec の想定どおり
- bats の実行は `bats --jobs 4 tests/` (全 2390 件) で not ok なし。`validate-skill-syntax.py`・`check-forbidden-expressions.sh`・`check-language-convention.py` も問題なし。`check-bare-bracket-assertions.sh` の警告 (1009 件) は既存ファイル由来で、今回追加した `tests/assignee-check.bats` は該当なし

### Rework
- なし

## review retrospective

### Spec vs. implementation divergence patterns
- Spec の「質問文と各選択肢の説明は、コードフェンスの中に日本語で書く」を、実装が実行時の指示として英訳しただけで、文面そのものをモジュールに固定していなかった (SHOULD)。Spec の記述が「固定する」とも「実行時に作る」とも読めたことが原因で、他の固定文言 (結果なし・中止の通知) とは扱いがそろっていなかった。Spec で文面を固定したい箇所は、「コードフェンスの中に書く」ではなく、文面そのものを Spec に載せると取りこぼしにくい
- ヘルパー (`gh-issue-assignee.sh`) の出力契約をモジュールが要約するとき、実装の細部 (`status` が括弧書きを付ける・`unchanged` を返す条件) と食い違った。ヘルパーのヘッダーコメントを転記するか参照にすると食い違わない

### Recurring issues
- `LOGINS` の切り出しが、`modules/assignee-check.md` と同じ手順を持つ #1545 の `skills/auto/SKILL.md` Step 1a (`/spec` 済み) にもそのまま写っている。#1545 の `/code` 時点で、今回の修正後の定義 (最初の ` (` の前まで) に揃える必要がある

### Acceptance criteria verification difficulty
- rubric 4 件は diff の読み取りだけで判定でき、UNCERTAIN はなかった。CI の 2 件は `gh pr checks` で確認でき、PASS にしてチェックを付けた
- 対話での 3 択の表示・中止の挙動は LLM 駆動で bats では確認できず、構造テスト (配線と固定文言) までに限られる。実機の確認は Post-merge の opportunistic AC に残る

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- CI (bats・Skill 構文チェック) 成功・approved・pre-merge AC 全件チェック済みの状態で、設定どおり squash でマージした (コンフリクトなし)

### Deferred Items
- Post-merge の opportunistic AC (未アサインの Issue で `/issue 123`・`/spec`・`/code` を実行したとき assignee が設定されること) は `/verify` で確認する

### Notes for Next Phase
- 対話での 3 択の表示・中止の挙動と、書き込みを伴う `reassign` の実機確認は構造テストでは見られていない
- #1545 の `/code` では `modules/assignee-check.md` に揃えること

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 確認を副作用 (triage・worktree 入場) より前に置く設計と、`/auto` 配下の子フェーズの重複警告を許容する判断を Notes に明記しており、並行する #1545 が参照して整合できた

#### design
- Size を M → L に更新 (Changed Files 10 件)。親 #1542 の Auto Retrospective に分割時の見積もり過小として記録済み

#### code
- rework なし。実装前 FAIL を 17 件の新規テストで確認した

#### review
- 3 択の質問文をモジュールに固定していなかった点と、ヘルパーの出力契約の要約の食い違いを SHOULD として拾い、修正された
- `LOGINS` の切り出し定義 (最初の ` (` の前まで) を #1545 の `/auto` Step 1a にも揃えるよう申し送ったが、マージ後の `skills/auto/SKILL.md` Step 1a は「`assigned to:` の後の login 一覧」とだけ書いており、括弧書きを除く規則が反映されていない (表示用のみで動作への影響は小さい)

#### merge
- 競合なし。#1545 とは別箇所の編集で CLEAN

#### verify
- Pre-merge 7 件は SKIPPED (チェック済み)。Post-merge の opportunistic 条件 1 件は、この /auto の子フェーズが新機能のマージ前の skill で動いたため観測できず、未チェックのまま `phase/verify` に残す

### Improvement Proposals
- `skills/auto/SKILL.md` の Step 1a が `modules/assignee-check.md` と同じ担当確認手順を重複して持っており、すでに `LOGINS` の切り出し規則 (最初の ` (` の前まで) が食い違っている。Step 1a をモジュール呼び出しに置き換える (モジュールの `PHASE_NAME` に `auto` を加え、`/auto` 固有の「子フェーズを起動しない」中止文言だけを Step 1a に残す)。#1545 の Spec Notes が「両方が main に入った後の改善候補」として /verify に委ねていたもの
