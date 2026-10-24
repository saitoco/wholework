# Issue #1550: auto: Step 1a の担当確認を modules/assignee-check.md の呼び出しに置き換えて重複を解消

## Overview

#1542 (XL) の sub-issue #1544 (`modules/assignee-check.md`) と #1545 (`/auto` の Step 1a) は並行して実装されたため、`skills/auto/SKILL.md` の Step 1a が同じ担当確認の手順を直接持っている。両者はすでに食い違っており、たとえば `LOGINS` の切り出しは、モジュールが「`assigned to: ` の後から最初の ` (` の前まで」、Step 1a が「`assigned to:` の後の login 一覧」とだけ書いている。この Issue で手順を `modules/assignee-check.md` に一本化し、`/auto` と `/issue`・`/spec`・`/code` で文言や判定規則がずれないようにする。

要点:

- **`skills/auto/SKILL.md` の Step 1a**: 結果の語の読み取り、`LOGINS` の切り出し、3 択の文言と順序、非対話の警告、`reassign` の結果の扱い、中止の通知を除き、`modules/assignee-check.md` を `PHASE_NAME=auto` で読んで実行する形にする。Step 1a に残すのは `/auto` 固有の差分だけ: 適用範囲 (単一 Issue の経路)、親が確認する理由、`continue` なら Step 2 へ・`abort` なら子フェーズを起動せずに終了、XL は親だけを確認
- **`modules/assignee-check.md`**: Input の `PHASE_NAME` に `auto` を加え、`auto` の中止の通知 (子フェーズを起動していないことを示す文言) をモジュールに定義する。Callers 表に `skills/auto/SKILL.md` の行を足す
- **`tests/auto.bats`**: Step 1a のテストを、`gh-issue-assignee.sh` の `status` / `reassign` を直接呼ぶことの検証から、モジュールを読む形であることの検証に更新する
- **`tests/assignee-check.bats`・`docs/structure.md`・`docs/ja/structure.md`**: モジュール側の新しい分岐 (`auto` の中止の通知・Callers 表) のテストと、モジュールの読み手を列挙している `docs/structure.md` の記述を更新する

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: tests/auto.bats の更新と Callers 表の行追加を受け入れ条件に追加し、CI 条件を gh run list 形式にした。docs の「共有」記述を Changed Files に含めるか、要約をどこまで残すかは spec で決める / https://github.com/saitoco/wholework/issues/1550#issuecomment-6390984782

(`phase/issue` ラベルの付与 `2026-10-24T23:37:38Z` より前に投稿された triage の AC 監査コメントは、cutoff より前のため対象外)

## Changed Files

- `modules/assignee-check.md`: `/auto` を呼び出し元に加える。追記する文字列は英語のみ (日本語は inline code・二重引用符・コードフェンスの中だけ。`scripts/check-language-convention.py` が散文の CJK を検出する)。`${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` の形の新しいスクリプト名は書かない (`validate-skill-syntax.py` の `validate_modules_scripts_in_allowed_tools` が、モジュールを読む全 SKILL.md の `allowed-tools` に要求するため)
  - (a) 冒頭の説明文: 共有する呼び出し元に `/auto` (single-Issue path) を加え、「最初の副作用より前」に「`/auto` では子フェーズを起動する前」を添える
  - (b) `## Input` の `PHASE_NAME`: 値を `issue`・`spec`・`code`・`auto` にし、`auto` が `### 2.` の中止の通知を選ぶことを書く
  - (c) `## Processing Steps` 冒頭の「worktree に入る前なので cwd は main checkout の root」の文に、`/auto` の親セッションは worktree に入らないことを添える
  - (d) `### 2. Another member is assigned (STATUS is other)`: 中止の行 (表) の「後続の step を実行しない」の列挙に子フェーズの起動を加える。既存の中止の通知 (2 行) の前置きを `issue`・`spec`・`code` 用と明示し、直後に `PHASE_NAME=auto` 用の通知を別のコードフェンスで固定文として定義する (1 行目は現行の Step 1a と同一: `中止しました: Issue #{ISSUE_NUMBER} は {LOGINS} にアサインされています。フェーズは起動しておらず、assignee もラベルも変更していません`、2 行目は `続行する場合は、担当者に確認してから /auto {ISSUE_NUMBER} を再実行してください`)
  - (e) `## Notes` の `### Why the check comes before any side effect`: `/auto` の親は子フェーズ (`run-*.sh`) がラベルの遷移とコメントの投稿を行う前に 1 回確認する、という 1 文を足す。`### Child phases under \`/auto\``: 「親 (Step 1a。このモジュールを `PHASE_NAME=auto` で呼ぶ) が確認して付け替えずに続けた後も、子フェーズが同じ警告を出す」ことが分かるよう 1 句足す (許容する旨は変えない)
  - (f) `### Callers` の表: `skills/auto/SKILL.md` の行を足す。Position 列は `Step 1a (single-Issue path: /auto N and /auto --resume N; Batch Mode and the XL sub-issue fan-out only warn and never call this module)` の趣旨
- `skills/auto/SKILL.md`: `### Step 1a: Assignee Check (single-Issue path)` の本文を置き換える (見出しは変えない: `tests/auto.bats` の `step1a_section` が `### Step 1a:` で切り出す)。追記する文字列は英語のみ。本文に半角 `!` を書かない (`scripts/validate-skill-syntax.py`)。`allowed-tools` は変更不要 (`gh-issue-assignee.sh:*` は既に載っており、モジュールが参照するスクリプトはこの 1 本だけ)
  - 残す: 先頭の適用範囲の段落 (`/auto N` と `/auto --resume N`、`--batch` は Step 1 で分岐済み、Step 1 のバナーの直後・Step 2 より前)、`**Why the parent checks**` の段落 (最後の文は「autonomy tier にも `auto-assign` にも依存せず、判定はモジュールが行うので、ここで `auto-assign` を読まない」の趣旨に縮める)、末尾の XL の項
  - 置き換える: 現行の項目 1・2 (`gh-issue-assignee.sh status` の実行、`STATUS` と `LOGINS` の定義、結果なしのメッセージ、`other` の分岐、非対話の警告、3 択、`reassign` の結果の語、中止の通知) を、(1) モジュールの呼び出し (`${CLAUDE_PLUGIN_ROOT}/modules/assignee-check.md` を読み、`"Processing Steps"` に従う。パラメータは `ISSUE_NUMBER=$NUMBER`、`PHASE_NAME=auto`、`NON_INTERACTIVE=true` (ARGUMENTS に `--non-interactive` を含むとき。含まなければ `false`)。状態の読み取り・選択肢・非対話の警告・付け替え・すべてのメッセージ (`PHASE_NAME=auto` の中止の通知を含む) はモジュールが定義するので、ここで言い直さない)、(2) モジュールの結果の扱い (`continue` は Step 2 へ。`abort` は、モジュールが `PHASE_NAME=auto` 用の中止の通知を出した後に `/auto` を直ちに終了する。後続の step を実行しない: Step 2 以降なし、子フェーズ (`run-*.sh`) の起動なし、ラベル遷移なし、Issue コメントなし) の 2 項目にする
- `tests/auto.bats`: `# --- Step 1a: assignee check (Issue #1545) ---` の節のテストを更新する (テスト名は下の Implementation Steps 3)。削除: `Step 1a section: calls gh-issue-assignee.sh status and reassign`、`Step 1a section: the three option labels appear in order`、`Step 1a section: --non-interactive warns with the Skip-tier format and changes nothing`、`Step 1a section: abort stops before any later step and leaves labels alone`、`Step 1a section: disabled result of reassign is handled`。維持: `Step 1a section: located between Step 1 and Step 2`、`SKILL.md: batch branches skip Steps 1a-6 and no skip Steps 2-6 remains`、`Step 1: --resume detection routes through Step 1a`、`XL route: sub-issue assignee warning comes before the fan-out inside the XL route block`、`allowed-tools: gh-issue-assignee.sh and filter-other-assignees.sh are listed`。冒頭の `step1a_section` ヘルパーのコメントにこの Issue 番号を足す
- `tests/assignee-check.bats`: モジュール側の新しい分岐のテストを足す (既存の @test と setup は変更しない)。`$MODULE`・`$MODULE_PATH`・`$PROJECT_ROOT`・`md_section` は既存の setup と helper を使う
- `docs/structure.md`: [Steering Docs sync candidate] Key Files の `modules/assignee-check.md` の行 (`pre-flight assignee check shared by \`/issue\` (existing Issue refinement), \`/spec\`, and \`/code\`, run before the first side effect: ...`) に `/auto` (single-Issue path) を加え、`/auto` では子フェーズの起動より前であることを添える。この行はモジュールの読み手を列挙しており、Key Files の保守規則 (役割・説明が変わったら同じ変更で更新する) の対象
- `docs/ja/structure.md`: [translation sync] 上記の日本語ミラーを同期する (`docs/translation-workflow.md` の Sync Procedure に従う。この行にはコードフェンスがなく、フェンス数は変わらない)。日本語文中の括弧は半角 `()` の前後に半角スペース

**変更不要 (grep・Read で確認済み。測定範囲は `docs/`・`modules/`・`skills/`・`scripts/`・`tests/`・`README.md`、`docs/spec/`・`docs/sessions/` を除く。main の 6d30a6dd 時点):**

- `docs/workflow.md` と `docs/ja/workflow.md`: 121 行目 (`/auto` の開始時の担当の確認) は「`/issue`・`/spec`・`/code` の着手時の確認と同じ選択肢・同じ非対話の扱い」と書いており、手順を一本化した後でも正確。213 行目 (`### Assignee` の「他のメンバーがアサイン済みのとき」) は `/issue N`・`/spec`・`/code` の確認の位置を述べていて、`/auto` は 121 行目で扱っている。どちらも「共有」を主張する書き方ではなく、古くならない
- `docs/guide/workflow.md` の 138 行目: 「`/auto 42` は phase を起動する前に確認する (非対話では警告のみ)」で、挙動は変わらない
- `docs/guide/customization.md` (`auto-assign` の行)・`modules/detect-config-markers.md`・`modules/autonomy-tier.md`・`modules/l0-surfaces.md`: スキル名ではなくスクリプト名・設定名で書いており、呼び出し元の列挙がない (`git grep -n -i "reassign"` で確認)
- `modules/ambiguity-detector.md` の 78 行目 (Assignee takeover): 「`modules/assignee-check.md` の `自分に付け替えて続ける`」という選択肢の定義の参照で、呼び出し元の列挙ではない
- `skills/issue/SKILL.md`・`skills/spec/SKILL.md`・`skills/code/SKILL.md`: 呼び出しの記述は変えない (`PHASE_NAME` がそれぞれ `issue`・`spec`・`code` のまま)
- `.claude/settings.json.template`: 変更しない (`.claude/` 配下は触らないので `git add -f` は不要)

**同期候補の探索結果** (測定範囲: `grep -rl "<keyword>" docs/ tests/ scripts/ modules/`、`docs/spec/`・`docs/sessions/` を含む全ファイル。main の 6d30a6dd 時点):

- キーワード `PHASE_NAME=auto` (この Issue が導入する識別子): 1 件で、`docs/spec/issue-1545-auto-assignee-check-exclusion.md` (使い捨ての Spec) だけ
- [Steering Docs sync candidate] keyword "assignee-check.md" skipped: matched 11 files (no discriminating power)。ただし `docs/spec/`・`docs/sessions/` を除く実体を持つ一致 6 件 (`docs/structure.md`・`docs/ja/structure.md`・`docs/workflow.md`・`docs/ja/workflow.md`・`modules/ambiguity-detector.md`・`tests/assignee-check.bats`) は手で確認済み。上の Changed Files と「変更不要」のとおり
- [Steering Docs sync candidate] keyword "auto" (skills/auto/SKILL.md の裸のスキル名) skipped: no discriminating power
- Listing-side sub-check: スキップ。サブコマンドの追加・削除、ファイルの追加・削除・改名、ディレクトリ構造の変更のいずれもない (既存ファイルの挙動の編集のみ)
- Outbound pointer sync candidate: なし。`modules/assignee-check.md` の参照先 (`modules/ambiguity-detector.md`・`modules/detect-config-markers.md`・`modules/phase-banner.md`) は、この変更で内容を変える必要がない

## Implementation Steps

1. `modules/assignee-check.md` に `/auto` の呼び出し元としての記述を足す。Changed Files の (a)〜(f) のとおり、冒頭の説明文、Input の `PHASE_NAME`、`## Processing Steps` 冒頭の cwd の文、`### 2.` の中止の行と `PHASE_NAME=auto` 用の中止の通知 (固定文・別のコードフェンス)、`## Notes` の 2 節、Callers 表の行。新しい `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` の形のパスは書かない。既存の固定文言 (3 択の文言と順序、`Do not run any later step`、非対話の警告の書式、結果の語の表) は変えない (→ 受け入れ条件 3, 4)
2. `skills/auto/SKILL.md` の Step 1a の本文を、Changed Files の記述のとおりモジュールの呼び出しに置き換える (after 1)。見出し `### Step 1a: Assignee Check (single-Issue path)` と、Step 1 の `skip Steps 1a–6` (5 か所)・`Proceed to Step 1a, then Step 2 as normal`・Step 4 の XL route の警告・List mode の警告は変えない。置き換えた後に `git grep -n "gh-issue-assignee" skills/auto/SKILL.md` で Step 1a 内の呼び出しが無くなったこと (残るのは `allowed-tools`・XL route・List mode の 3 行)、`git grep -c "付け替え" skills/auto/SKILL.md` が 0 になったことを確認する (→ 受け入れ条件 1, 2)
3. `tests/auto.bats` の Step 1a の節を更新する (after 2)。削除する 5 件の代わりに、次の 4 件の @test を足す。テストは `section="$(step1a_section "$SKILL_FILE")"` の単純な代入で受け、続けて `[ -n "$section" ]` で空でないことを確認する (見出しの改名で空の節に対する否定の検査が通ってしまうのを防ぐ。`docs/tech.md` § BATS Markdown Section Extraction)。否定の検査は `run grep ...` の後に `[ "$status" -ne 0 ]`、またはループ内の `if [ "$status" -eq 0 ]; then echo "..."; false; fi` で書く (→ 受け入れ条件 5)
   - `Step 1a section: reads modules/assignee-check.md with PHASE_NAME=auto`: 節に `${CLAUDE_PLUGIN_ROOT}/modules/assignee-check.md`・`PHASE_NAME=auto`・`ISSUE_NUMBER=$NUMBER`・`NON_INTERACTIVE=true`・`--non-interactive` が含まれる (固定文字列は `grep -qF`)
   - `Step 1a section: does not duplicate the module's procedure`: 節に `gh-issue-assignee.sh`・`AskUserQuestion`・`LOGINS`・`assigned to:`・`"自分に付け替えて続ける"`・`"付け替えずに続ける"`・`"中止"`・`[non-interactive mode]`・`Skipping high-stakes action`・`unassigned` のどれも含まれない
   - `Step 1a section: keeps the /auto-specific outcomes (continue, abort without child phases)`: 節に `` `continue` ``・`` `abort` ``・`Do not run any later step`・`run-*.sh`・`no label transition` が含まれる
   - `Step 1a section: checks only the XL parent`: 節に `XL parent` と `Step 4` が含まれる
4. `tests/assignee-check.bats` にモジュール側のテストを足す (after 1。2・3 と並行して進めてよい)。次の 3 件の @test (→ 受け入れ条件 3, 4)
   - `module: Input accepts PHASE_NAME auto`: `md_section "$MODULE" "## Input"` で受け、`PHASE_NAME` の行に `` `auto` `` が含まれる
   - `module: defines an abort notice for PHASE_NAME auto that says no child phase was started`: `md_section "$MODULE" "### 2."` で受け、`PHASE_NAME=auto`・`フェーズは起動しておらず`・`/auto {ISSUE_NUMBER} を再実行してください` が含まれる
   - `module: the Callers table lists every SKILL.md that reads the module, including auto`: `md_section "$MODULE" "### Callers"` で受け、`skills/*/SKILL.md` のうち `$MODULE_PATH` を含むものがすべて表に載っていること、および `skills/auto/SKILL.md` が載っていること (`for` ループは `mapfile` を使わない。bash 3.2 互換)
5. `docs/structure.md` の `modules/assignee-check.md` の行と、日本語ミラー `docs/ja/structure.md` の対応する行を更新する (1〜4 と並行して進めてよい)。英語は「`/issue` (existing Issue refinement), `/spec`, `/code`, and `/auto` (single-Issue path)」と「(for `/auto`, before any child phase starts)」、日本語は「`/issue` (既存 Issue の精査)・`/spec`・`/code`・`/auto` (単一 Issue の経路)」と「(`/auto` は子 phase の起動より前)」の趣旨 (→ ドキュメントの整合。受け入れ条件には対応しない)

## Verification

### Pre-merge

- <!-- verify: grep "assignee-check.md" "skills/auto/SKILL.md" --> `skills/auto/SKILL.md` の Step 1a が `modules/assignee-check.md` を読んで担当確認を行う形になっている
- <!-- verify: rubric "skills/auto/SKILL.md の Step 1a から、modules/assignee-check.md と重複する手順 (結果の語の読み取り、LOGINS の切り出し、3 択の選択肢の文言と順序、非対話の警告の書式) が除かれ、/auto 固有の差分 (子フェーズを起動しないこと、中止時に /auto 用の文言を出すこと) だけが残っている" --> Step 1a には `/auto` 固有の差分だけが残り、モジュールと重複する手順は除かれている
- <!-- verify: rubric "modules/assignee-check.md の Input の PHASE_NAME が auto を受け付け、auto の場合のメッセージ (中止時に子フェーズを起動していないことを示す文言など) が定義されている" --> `modules/assignee-check.md` が `PHASE_NAME=auto` を受け付け、`/auto` 用のメッセージを持つ
- <!-- verify: file_contains "modules/assignee-check.md" "skills/auto/SKILL.md" --> `modules/assignee-check.md` の Callers 表に `skills/auto/SKILL.md` の行が追加されている
- <!-- verify: rubric "tests/auto.bats の Step 1a に関するテストが、gh-issue-assignee.sh の status / reassign を Step 1a が直接呼ぶことの検証ではなく、Step 1a が modules/assignee-check.md を読む形であることの検証に更新されている" --> <!-- verify: file_contains "tests/auto.bats" "assignee-check.md" --> `tests/auto.bats` の Step 1a のテストが、モジュール呼び出しの形に合わせて更新されている
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion,status --jq 'if .[0].status != \"completed\" then \"in_progress\" else .[0].conclusion end'" "success" --> CI (test.yml の Run bats tests) が通る (patch route)

### Post-merge

- なし (Issue 本文に Post-merge の条件はない)

## Notes

### 設計判断 (非対話モードでの自動解決)

Issue の振り返りが `/spec` に委ねた 2 点 (docs の「共有」記述を Changed Files に含めるか、Step 1a にどこまで要約を残すか) を含む。

- **Step 1a に 3 択の文言を残さない** (`/issue`・`/spec`・`/code` の呼び出し部分は 3 択の文言を要約として載せているが、`/auto` は載せない): 受け入れ条件 2 が「3 択の選択肢の文言と順序」と「非対話の警告の書式」を Step 1a から除くことを求めている。#1544 が要約を載せたのは、SKILL.md の rubric が呼び出し部分を見るためだった。この Issue の目的は文言の複製をなくすことなので、`/auto` では文言を一切載せず、モジュールへの参照とパラメータだけにする。要約の「ask / warn」という大枠も載せない (言い換えが残ると、複製が再び生まれる入口になる)
- **中止の通知は Step 1a ではなくモジュールに定義する**: 受け入れ条件 3 が、`auto` の場合のメッセージをモジュールが持つことを求めている。Step 1a が持つのは「モジュールが `PHASE_NAME=auto` 用に出す通知で終了し、子フェーズを起動しない」という `/auto` 固有の差分だけ。通知の第 1 行を `PHASE_NAME` で差し替える穴あきの 1 つの文面にせず、`auto` 用を別の固定文にした (LLM が逐語で出しやすく、bats でも固定文を検査できる)。2 行目はほぼ同じ文面の重複になるが、1 行で許容する
- **docs は `docs/structure.md` と日本語ミラーだけ更新する**: `docs/structure.md` の `modules/assignee-check.md` の行はモジュールの読み手を列挙しており、Key Files の保守規則の対象で、`/auto` が加わると事実と合わなくなる。`docs/workflow.md` の 2 か所は上の「変更不要」のとおり、手順を一本化した後でも正確なので触らない (触ると Changed Files が 1 ファイル増える。Size への影響は下の「規模の見積もり」)
- **`tests/assignee-check.bats` にモジュール側のテストを足す**: モジュールの新しい分岐 (`auto` の中止の通知) と Callers 表の行は、モジュールの構造テストの置き場所である `tests/assignee-check.bats` で検査する。`tests/auto.bats` は受け入れ条件 5 のとおり Step 1a がモジュールを読む形かどうかの検査に絞る。Callers 表のテストは `auto` だけでなく「モジュールを読む SKILL.md がすべて表に載る」とし、次に呼び出し元が増えたときにも行の追加漏れを検出できるようにした (モジュール自身が「新しい呼び出し元ができたら行を足す」と定めている)
- **挙動が変わる点 (受け入れる)**: Step 1a と モジュールは文言・規則がすでに食い違っており、一本化によって `/auto` はモジュールの規則に揃う。(1) `LOGINS` の切り出し: 最初の ` (` の前まで (Issue 本文が挙げた食い違い)。(2) `AskUserQuestion` が使えないとき: 現行の Step 1a は `--non-interactive` と同じ 2 行の Skip 層の警告を出すが、モジュールは 1 行 (`担当者を確認できませんでした (Issue #{ISSUE_NUMBER} は {LOGINS} にアサインされています)。assignee は変更せず続行します`) を出す。どちらも「付け替えずに続行する」ことは同じで、メッセージの文面だけが変わる。(3) 現行の Step 1a は各メッセージを「コードフェンスの中に日本語で」出すよう指示していたが、モジュールはこの指示を持たない。これらは Issue の目的 (文言や判定規則のずれをなくす) そのものなので、`/auto` 側の旧い文面は残さない
- **モジュールを読めない場合の fail-open は足さない**: `/issue`・`/spec`・`/code` の呼び出しも、モジュールの Read の失敗を扱っていない。モジュールは `/auto` と同じプラグインのディレクトリにあり、他の「Read and follow」のモジュール (`modules/phase-banner.md` など) と同じ前提で動く。Step 1a にだけ個別の退避を書くと、複製が再び生まれる
- **Batch Mode と XL の子 Issue の警告はこの Issue の範囲外**: List mode・Resume mode・XL route の警告は `gh-issue-assignee.sh status` を直接呼ぶ「警告のみ・確認しない」処理で、モジュールの「確認して付け替え・続行・中止」とは別の機能。Issue 本文も Step 1a だけを対象にしている。Callers 表の Position 列に「Batch Mode と XL の子 Issue はこのモジュールを呼ばない」と書いて、範囲を明示する

### Issue 本文と既存実装の矛盾

検出されなかった。背景に書かれた事実をすべてコードで確認した: (1) `skills/auto/SKILL.md` の Step 1a が結果の語の読み取り・3 択・非対話の警告・中止の通知を直接持つ (112〜155 行目。末尾の空行を含めて 44 行)。(2) `modules/assignee-check.md` が `LOGINS` を「`assigned to: ` の後から最初の ` (` の前まで」と定義している (47 行目)。(3) Step 1a が「the login list in the stderr line `Info: issue #N is assigned to: <logins>`」とだけ書き、括弧書きを除く規則がない (124 行目)。(4) #1545 の Spec Notes (281 行目) が、モジュールとの置き換えを `/verify` の振り返りに委ねている。(5) #1544 の Spec の review retrospective (305 行目) と Phase Handoff (322 行目) が、`LOGINS` の規則を揃えるよう申し送っている。(6) モジュールの Input の `PHASE_NAME` は `issue`・`spec`・`code` (12 行目)、Callers 表は 3 行 (`skills/issue/SKILL.md`・`skills/spec/SKILL.md`・`skills/code/SKILL.md`)。(7) `tests/auto.bats` の Step 1a のテストは 614〜677 行目で、`gh-issue-assignee.sh status` と `reassign` を直接検査している。

### fail-safe critical の判定

fail-safe critical に当たる (基準 (a): 担当の確認は `/auto` を続行するか中止するかを決める関門で、失敗時は続行する fail-open の設計)。ただしこの Issue は関門の論理を足さず、同じ論理を持つ 2 つの手順を 1 つにするだけである。期待する挙動はモジュールに 1 か所で定義済みで、Step 1a はそれを再定義も弱めもしない。

- 入力が空・大きい: `STATUS` が「結果なし」になる場合は、モジュールの 1 行を出して続行する (`/auto` を止めない)
- 特殊文字: `LOGINS` は表示専用で、シェルのコマンドには入れない (モジュールの規則。Step 1a の旧い文面にも同じ規則があった)
- 依存コマンドの失敗: ヘルパーの欠如・結果が読めない・`reassign` の失敗・`AskUserQuestion` の失敗は、すべて続行する (fail-open。理由: assignee の機能の失敗でフェーズを止めない、という #1542 の方針)。止めるのは利用者の明示の `中止` だけ

### 監査・調査型の Issue か

監査・調査型ではない (重複した手順を 1 つにする変更で、複数の既存項目を分類して判断の根拠を残す成果物はない)。

### 新規テストケース要件 (Step 13 は light で省略されるため、ここに記録)

新しい分岐は、(1) モジュールの `PHASE_NAME=auto` 用の中止の通知と Callers 表の行、(2) Step 1a の `continue` / `abort` の扱い。受け入れ条件 6 (CI の bats) は、既存スイートが PASS することだけでなく、次の新規テストケースを追加したうえでスイートが PASS することを前提とする: `tests/assignee-check.bats` の `module: Input accepts PHASE_NAME auto`・`module: defines an abort notice for PHASE_NAME auto that says no child phase was started`・`module: the Callers table lists every SKILL.md that reads the module, including auto`、`tests/auto.bats` の `Step 1a section: reads modules/assignee-check.md with PHASE_NAME=auto`・`Step 1a section: does not duplicate the module's procedure`・`Step 1a section: keeps the /auto-specific outcomes (continue, abort without child phases)`・`Step 1a section: checks only the XL parent`。実装前の FAIL の見込み: `auto.bats` の 4 件はすべて現行の Step 1a で FAIL する。`assignee-check.bats` の Input と中止の通知の 2 件も FAIL する。Callers 表のテストは、`auto` の行の検査の部分で FAIL する (一般形の部分は `auto` がまだモジュールを読まないので実装前は PASS する)。

LLM が実行する層 (Step 1a の実際の表示) は構造テスト (配線と固定文言) までで、bats では確認できない。`skills/spec/skill-dev-constraints.md` § LLM-assisted Skill Phase Test Strategy の分担 (決定論の層は実行テスト、LLM の層は構造テスト) に従う。

### bats の入力形式と書き方の注意

- **入力**: `tests/auto.bats` は `skills/auto/SKILL.md` の `### Step 1a:` から次の `### ` 見出しの手前までの Markdown (`md_section "$1" "### Step 1a:"`)。`tests/assignee-check.bats` は `modules/assignee-check.md` の `## Input`・`### 2.`・`### Callers` の各節 (`md_section "$MODULE" "<見出しの先頭>"`)。`### 2.` は見出しの先頭の `### 2.` に一致する (`### 2. Another member is assigned (STATUS is other)`)
- **節の受け方**: `section="$(...)"` の単純な代入で受ける。`run step1a_section ...` や `grep ... <<< "$(...)"` や `step1a_section ... | grep ...` は、見出しが見つからない (終了ステータス 1) ことを捨てるので、否定の検査では使わない (`docs/tech.md` § BATS Markdown Section Extraction)
- **否定の検査**: 最終行ではない `[[ ... ]]` と `! grep ...` は、失敗してもテストが FAIL しない (または bash 3.2 で ok と報告される)。`run grep ...` の後に `[ "$status" -ne 0 ]`、またはループ内の `if [ "$status" -eq 0 ]; then echo "..."; false; fi` で書く。`scripts/check-bare-bracket-assertions.sh` の対象にならない形にする
- **固定文字列**: `${CLAUDE_PLUGIN_ROOT}`・`$NUMBER`・`{ISSUE_NUMBER}` を含む照合は、`grep -qF` と単一引用符で書き、シェルによる展開を避ける
- **日本語の固定文言**: `tests/` は `scripts/check-language-convention.py` の対象外だが、コメントは英語で書く

### 規模の見積もり (Step 18 の再評価に使う)

Changed Files は 6 件 (内訳: モジュール 1、SKILL.md 1、テスト 2、`docs/` 1、翻訳ミラー 1)。ファイル数の軸は、翻訳ミラー (`modules/doc-checker.md` が `docs/{lang}/` を「`/doc translate` が生成する翻訳出力で、実装対象ではない」として扱う) を除いた 5 件で M。複雑さの補正は、減算要因が「既存の Read and follow のモジュール呼び出し (`/issue`・`/spec`・`/code` が既に使う形) への横展開で、正味では文面が減る」、加算要因はなし (スクリプトの論理変更なし。モジュールの変更は `/issue`・`/spec`・`/code` の挙動を変えない) で、差し引き -1 段階の S。triage 時点の S と同じ。CI の条件 (受け入れ条件 6) が patch route の `gh run list` 形式で書かれているのと整合する。

(測定範囲: Changed Files の数え方は `modules/size-workflow-table.md` の Axis 1。`docs/workflow.md` と `docs/ja/workflow.md` を Changed Files に加えると 6 件で L → M になり、route が pr に変わって受け入れ条件 6 の形と合わなくなる。上の「docs は `docs/structure.md` と日本語ミラーだけ更新する」の判断は、その docs が事実として古くならないことを根拠にしており、Size の都合ではない。)

### 測定

- `skills/auto/SKILL.md` の Step 1a: 44 行 (`### Step 1a:` の見出しから、次の `### Step 2:` の手前まで。`awk '/^### Step 1a:/{f=1} /^### Step 2:/{f=0} f' skills/auto/SKILL.md | wc -l`)。main の 6d30a6dd 時点
- `skills/auto/SKILL.md` の `gh-issue-assignee.sh` を含む行: 7 行 (5 行目の `allowed-tools`、Step 1a の 116・118・121・141 行目、XL route の 410 行目、List mode の 1300 行目)。置き換え後は 3 行 (`allowed-tools`・XL route・List mode) になる見込み。`付け替え` を含む行: 5 行 (すべて Step 1a)。置き換え後は 0 行。測定範囲: `skills/auto/SKILL.md` のみ (`grep -n`)
- `modules/assignee-check.md` の `PHASE_NAME`: 3 行 (12 行目の Input、76 行目の中止の通知の 2 行目、83 行目の非対話の警告)。76・83 行目は `/{PHASE_NAME} {ISSUE_NUMBER}` の形で、`auto` を入れると `/auto N` になり、変更不要 (Tag/enum の新しい値の消費者の確認: 測定範囲は `grep -n 'PHASE_NAME' modules/assignee-check.md`。他のモジュールの `PHASE_NAME` は別のパラメータ)
- 既存の `tests/auto.bats` は 48 件の @test。うち Step 1a の節は 6 件 (614〜677 行目) で、置き換えるのはそのうち 5 件

### 実行する確認コマンド (`/code` が実装後に実行する)

`bats tests/auto.bats tests/assignee-check.bats tests/auto-batch.bats tests/auto-xl-concurrency.bats`、`bats tests/` 全体 (`bats --jobs 4 tests/`)、`python3 scripts/validate-skill-syntax.py skills/` (`validate_modules_scripts_in_allowed_tools` を含む)、`bash scripts/check-allowed-tools.sh`、`bash scripts/check-forbidden-expressions.sh`、`bash scripts/check-translation-sync.sh` (`docs/structure.md` と `docs/ja/structure.md` が IN_SYNC)、`git diff -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py`、`bash scripts/check-bare-bracket-assertions.sh`

### その他

- **Pre-merge 項目数**: この Spec の Pre-merge は 6 件で、SPEC_DEPTH=light の目安 (5 件) を超える。Issue 本文の `## Acceptance Criteria > Pre-merge` を verify command ごと転記する規則 (件数の一致検査を含む) を優先した。Implementation Steps は目安内の 5 件にまとめた
- **文字列照合の verify command の語**: 受け入れ条件 1 の `grep "assignee-check.md" "skills/auto/SKILL.md"` と 受け入れ条件 4 の `file_contains "modules/assignee-check.md" "skills/auto/SKILL.md"`、受け入れ条件 5 の `file_contains "tests/auto.bats" "assignee-check.md"` の語は、どれも現時点では 0 件で、実装が導入する (Step 1a のモジュールのパス、Callers 表の行、更新したテスト)。実装前は FAIL、実装後は PASS になる向きで、常時 PASS にはならない。`grep` の語に BRE のメタ文字 (`\|` など) は含まれない
- **コストの高い・不可逆な Implementation Step はない**: `spec-approval-needed` マーカーは付けない。外部サービスへのログインも要らない。Smoke Test は省略した (実 GitHub への書き込みを伴う確認は Issue の assignee を変更し通知を発生させるため入れない。`/auto` の実機の表示は構造テストの範囲外で、手順自体は #1544・#1545 の Post-merge の対象)
- **英語のみにするファイル**: `skills/`・`modules/`・`scripts/` に追記する散文に CJK 文字を入れない (inline code・二重引用符・単一引用符・コードフェンスの中は検出対象外。二重引用符は複数行にまたがると効かないので、1 行で閉じる)
- **コミット前の確認**: 新規ファイルはない (`git add` は変更したファイルの明示指定でよい)
