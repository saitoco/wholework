# Issue #1518: review/verify: rubric grader をサブエージェントで起動した場合の停止手順を追加

## Overview

`modules/verify-executor.md` は rubric の grader の入力・判定の姿勢を定めているが、起動のしかたを定めていない。そのため grader がサブエージェント (teammate) として起動されると、名前も停止の手順も無く、`/review` や `/verify` が終わった後もセッションに残る。#1478 が `/review` の Step 10 に入れた「名前 + 結果受領直後の `TaskStop`」の対象 6 種に、Step 8 の rubric grader は入っていない。

この Issue では、#1478 と同じ 2 点を grader に入れる。

1. grader をサブエージェントとして起動するときの名前 (`rubric-grader-$NUMBER`、複数なら `-{n}`) を決める
2. 判定を受け取った直後にその grader だけを `TaskStop(task_id: ...)` で止める。判定が得られなかった grader も止める。停止はベストエフォートで、失敗しても判定や後続の処理を止めない

手順の正本は `modules/verify-executor.md` に置く。このモジュールは `/review` (safe モード) のほか `/verify`・`/code`・`/auto` (full モード) も読むので、1 か所に書けば全呼び出し元に届く。`skills/review/SKILL.md` の「Sub-agent Names and Stop」は grader の名前を一覧に足し、正本を指す。

変更するファイルは `modules/verify-executor.md`、`skills/review/SKILL.md`、`docs/tech.md`、`docs/ja/tech.md` の 4 つ (frontmatter の `allowed-tools` は変更しない。理由は Notes を参照)。

## Reproduction Steps

1. rubric の受入条件を複数持つ Issue の PR に対して `/review <PR>` を実行する (対話セッション、または対話セッションからの fork 実行)
2. Step 8 が `modules/verify-executor.md` を safe モードで読み、rubric の grader をサブエージェントとして起動する。モジュールに名前の定めが無いので、モデルがその場で名付ける (下流の実例: `rubric-grader-<PR>`、説明 `Rubric grading AC 1-12, 14`)
3. `/review` が完了した後も、grader は `ListAgents` に `roster` のまま残る。下流の実例 (2026-10-12) では約 11 時間後も残っており、手動の `TaskStop` で消した

## Root Cause

- **起動のしかたが未定義**: `modules/verify-executor.md` の rubric の行と「Rubric Command Semantics」は、grader の入力範囲・敵対的な姿勢・戻り値を定めているが、サブエージェントとして起動するときの名前と停止を定めていない (`grep -c "rubric-grader" modules/verify-executor.md` が 0、`grep -c "TaskStop" modules/verify-executor.md` が 0)
- **#1478 の対象外**: `skills/review/SKILL.md` の「Sub-agent Names and Stop」は Step 10 の `Task(...)` だけを一覧にしており、Step 8 の grader には触れていない (`grep -c -i "grader" skills/review/SKILL.md` が 0)
- **完了しても teammate が自動では消えない場合がある**: 対話セッションで teammate として起動されたサブエージェントは、`/review` の完了後も `ListAgents` に残りうる (下流の実例)。結果を使った後のエージェントも、結果が返らなかったエージェントも、`TaskStop` で止めるまで残りうる
- **呼び出し元が複数**: モジュールは `/verify` (full) も `/code`・`/auto` (full) も読む。`/review` だけに停止を書いても、それらでは残りうる

対処の妥当性: `/issue` Step 12a (#1031) と `/review` Step 10 (#1478) が同じ形 (`name:` と結果受領直後の `TaskStop`、停止はベストエフォート) で対処済み。同じ形を grader に移す。`TaskStop` は権限が不要なので `allowed-tools` への追加は要らない (Notes 参照)。

## Changed Files

- `modules/verify-executor.md`: 2 か所を変更する (shell スクリプトではないので bash 互換の注記は不要)
  - 翻訳表の `rubric "text"` の行: 末尾の `Spec files are not passed to the grader.` の直後に、サブエージェントとして起動したときの名前と停止を指す 1 文を足す。行頭の `rubric "text"`、`**Mode-independent**`、`Spec files are not passed to the grader` は既存の bats が見るので残す
  - `### Rubric Command Semantics`: `**File path resolution in rubric graders (worktree-safe reads):**` ブロックの直後、`**Managed Agents migration intent:**` の直前に、`**Grader sub-agent name and stop:**` ブロックを新設する (名前、停止、判定が得られない場合、ベストエフォート)
- `skills/review/SKILL.md`: 2 か所を変更する (frontmatter の `allowed-tools` は変更しない)
  - Step 8: `Read ... verify-executor.md` の段落の末尾に、grader の名前と停止の正本を指す 1 文を足す
  - `### Sub-agent Names and Stop`: `text` ブロックに grader の 2 行を足し、ブロックの後に grader を扱う段落を足す。見出しは `###` のまま変えない
- `docs/tech.md`: `/review` のサブエージェント記述 (L71) の末尾に、Step 8 の grader も同じ規則に従う旨を 1 文足す [Steering Docs sync candidate]
- `docs/ja/tech.md`: 同じ文を日本語で足す (L62、`docs/translation-workflow.md` の同期手順)
- 変更しない (grep で確認済み): `skills/verify/SKILL.md` (`skill-body-sha` / `skill-body-lines` マーカーを持つので、編集すると再計算が要る。モジュールを読むので `/verify` には届く)、`modules/verify-patterns.md` §9 (grader が pre-merge と post-merge の両方で動くことしか述べていない)、`modules/execution-context.md` (Step 10 を小節名で参照するだけ)、`skills/review/workflow-guidance.md` (Step 10 の Workflow 経路のみ)、`docs/workflow.md` / `README.md` / `docs/structure.md` (grader・サブエージェントの命名に言及が無い。新規ファイル・サブコマンド・ディレクトリの追加も無い)
- [Steering Docs sync candidate] キーワード `rubric-grader` (この Issue が導入する名前): `docs/ tests/ scripts/ modules/` 内の該当は 0 件 (測定コマンド: `grep -rl "rubric-grader" docs/ tests/ scripts/ modules/`)
- [Steering Docs sync candidate] キーワード `verify-executor.md` skipped: matched 190 files (no discriminating power)
- [Steering Docs sync candidate] キーワード `TaskStop`: 7 件 (`docs/ tests/ scripts/ modules/` 内)。`docs/tech.md` と `docs/ja/tech.md` が上記の同期対象。残る 5 件は過去の Spec・セッション記録 (`docs/spec/issue-1031-*`、`issue-1142-*`、`issue-1478-*`、`issue-1481-*`、`docs/sessions/91609-*`) で変更不要
- [Steering Docs sync candidate] キーワード `Sub-agent Names and Stop`: 1 件 (`docs/spec/issue-1478-review-subagent-taskstop.md`、過去の Spec で変更不要)
- [Outbound pointer sync candidate] `modules/verify-executor.md` が指す `modules/verify-patterns.md` §9 は、grader が `/review` (safe) と `/verify` (full) の両方で動くことだけを述べており、起動の手順に触れないので変更不要 (L307-L308 を読んで確認)。`skills/review/SKILL.md` が指す `modules/execution-context.md` と `skills/review/workflow-guidance.md` も、この変更の影響を受けない
- [tests sync candidate] 既存の bats は編集後も次の文字列に依存する: `tests/verify-rubric.bats` は `rubric "text"`、`adversarial`、`Mode-independent`、`Spec files are not passed to the grader`、`Rubric Command Semantics`。`tests/review-rubric-safe.bats` は `### Rubric Command Semantics` の節内の `always_allow` と、`returns UNCERTAIN in safe mode` が**存在しない**こと。`tests/review.bats` に Step 8 / Step 10 のサブエージェントを対象にした assertion は無い。これらを壊さない (実行環境に `bats` が無いので grep で確認する)

## Implementation Steps

1. `modules/verify-executor.md` を変更する。挿入する文面はすべて英語 (→ AC1, AC2)
   - 翻訳表の `rubric "text"` の行の、`Spec files are not passed to the grader.` の直後 (行末の ` | \`always_allow\` |` の前) に、次の 1 文を足す
     ```text
      When the grader is launched as a sub-agent, name it `rubric-grader-$NUMBER` and stop it as soon as its verdict is in hand (see "Grader sub-agent name and stop" below).
     ```
   - `### Rubric Command Semantics` の `**File path resolution in rubric graders (worktree-safe reads):**` ブロックの末尾 (`Calling skills must always make file content explicit before passing it to the grader.` の行) と `**Managed Agents migration intent:**` の間に、次のブロックを空行を挟んで挿入する。見出しにはせず、節内の他のブロックと同じ太字ラベルにする
     ````markdown
     **Grader sub-agent name and stop:**
     The grader is expected to run as a sub-agent, because the adversarial system prompt and the Spec exclusion above both need a context separate from the caller's. When the caller launches the grader as a sub-agent (a `Task(...)` / Agent call), it gives the sub-agent an explicit name and stops it as soon as it is done, so that it does not stay in the session after the calling skill finishes (Issue #1518). Without a stop, a named sub-agent can stay listed in the session (for example as an idle teammate) long after its verdict was used. This applies to every caller of this module: `/review` (safe mode) and `/verify`, `/code`, and `/auto` (full mode).

     - **Name**: `rubric-grader-$NUMBER`, where `$NUMBER` is the calling skill's own number — the PR number in `/review`, the Issue number in `/verify`, `/code`, and `/auto`. When one run launches more than one grader (for example one per condition), give each `rubric-grader-$NUMBER-{n}`, with `{n}` the 1-based launch order, so that no two graders share a name and each can be stopped on its own.
     - **Stop**: as soon as a grader's verdict is in hand, stop that grader alone with `TaskStop(task_id: "rubric-grader-$NUMBER")`, or `TaskStop(task_id: "rubric-grader-$NUMBER-{n}")` for a numbered grader. Do this before using the verdict for anything else, do not wait for the other graders, and do not defer the stops to the end of the calling skill.
     - **No verdict**: a grader whose verdict is not in hand when the caller needs it (empty output, an error, or a background task whose return value carries no verdict) is stopped too — it is the grader most likely to be left behind — and its condition is UNCERTAIN, because the result could not be determined.
     - **Best-effort**: the stop never gates anything. `TaskStop` can fail for reasons outside the caller's control: no running task matches the name because the grader already ended, or the calling skill runs as a fork and the grader is owned by the main session, which refuses the stop. Ignore any such failure: do not retry, do not wait, and do not let it change the verdict or delay the caller's later processing (checkbox updates, result reporting, any later step).
     ````
   - 追加する文面に半角 `!` と `returns UNCERTAIN in safe mode` という並びを入れない。仮名・漢字も入れない

2. (parallel with 1) `skills/review/SKILL.md` を変更する。挿入する文面はすべて英語。`allowed-tools` は変更しない (→ AC3)
   - **Step 8**: `Read \`${CLAUDE_PLUGIN_ROOT}/modules/verify-executor.md\` and follow the "Processing Steps" translation table. Mode: **safe**, ...` の段落の末尾 (`... (note reason such as "corresponding CI job not identified").` の直後) に、次の 1 文を足す
     ```text
      A `rubric` condition's grader, when launched as a sub-agent, is named and stopped as described in "Sub-agent Names and Stop" (Step 10) and in the "Rubric Command Semantics" section of `${CLAUDE_PLUGIN_ROOT}/modules/verify-executor.md`.
     ```
   - **`### Sub-agent Names and Stop`**: `text` ブロックの最後の行 (`TaskStop(task_id: "edge-case-$NUMBER-{n}") ...`) の直後に、次の 2 行を足す (コメント列の揃え方は既存の行に合わせる)
     ```text
     TaskStop(task_id: "rubric-grader-$NUMBER")        # right after the Step 8 rubric grader verdict is in hand (Step 8)
     TaskStop(task_id: "rubric-grader-$NUMBER-{n}")    # right after that grader verdict is in hand, when Step 8 launches several graders (Step 8)
     ```
   - 同じ小節の `A sub-agent whose result was not obtained is stopped too, ...` の段落の直後、`**The stop is best-effort and never gates anything.**` の段落の直前に、次の段落を足す
     ````markdown
     **The Step 8 rubric grader follows the same rule.** It is not a `Task(...)` of this step: Step 8 reads `${CLAUDE_PLUGIN_ROOT}/modules/verify-executor.md`, which is the SSoT for the grader's name and its stop (its "Rubric Command Semantics" section, "Grader sub-agent name and stop"), and the two `rubric-grader` lines above only list the grader so that every sub-agent name `/review` uses is in one place. A grader whose verdict was not obtained is stopped too, and its condition is UNCERTAIN; the "Sub-agent Result Fallback" below covers only the Step 10 sub-agents.
     ````
   - 追加する文面に半角 `!` を入れない。仮名・漢字も入れない。小節の見出し (`### Sub-agent Names and Stop`) とそのレベルは変えない

3. (after 1, 2) Steering 文書を同期する (→ SHOULD: 文書の同期)
   - `docs/tech.md` の L71 (`/review` のサブエージェント記述) の末尾、`... takes over (Issue #1478).` の直後に、次の 1 文を足す
     ```text
      The Step 8 rubric grader, launched through `modules/verify-executor.md`, follows the same rule (name `rubric-grader-$NUMBER`, Issue #1518).
     ```
   - `docs/ja/tech.md` の L62 の末尾、`... 停止する (Issue #1478)。` の直後に、次の 1 文を足す
     ```text
     Step 8 の rubric grader も、`modules/verify-executor.md` 経由で起動されるため、同じ規則 (名前は `rubric-grader-$NUMBER`) で名前を付けて停止する (Issue #1518)。
     ```
   - `/code` は両ファイルを読み、文が既存の記述と食い違わないことを確認してから足す。足した結果が既存の文脈に合わないと判断した場合は、両方を同時に見送る (片方だけ変えない: `docs/translation-workflow.md`)

4. (after 1, 2, 3) 検証する。`skills/verify/SKILL.md` が差分に入っていないこと、`allowed-tools` を変えていないことを確認する (→ AC1-AC3 全体)
   - 変更が意図した 4 ファイル (`modules/verify-executor.md`、`skills/review/SKILL.md`、`docs/tech.md`、`docs/ja/tech.md`) だけであること: `git diff --stat`
   - AC1: `grep -c "rubric-grader" modules/verify-executor.md` が 1 以上。AC3: `sed -n '/^### Sub-agent Names and Stop/,/^### Sub-agent Result Fallback/p' skills/review/SKILL.md | grep -c grader` が 1 以上
   - `modules/verify-executor.md` に `TaskStop(task_id:` があること。`rubric "text"` の行に `rubric-grader` があること
   - 既存の bats が見る文字列の残存 (bats は実行できないので grep): `rubric "text"`、`adversarial`、`Mode-independent`、`Spec files are not passed to the grader`、`Rubric Command Semantics`、`### Rubric Command Semantics` の節内の `always_allow`。そして `returns UNCERTAIN in safe mode` が `modules/verify-executor.md` に**無い**こと
   - `python3 scripts/validate-skill-syntax.py skills/` が成功する (半角 `!` を本文に入れていないこと)
   - `bash scripts/check-forbidden-expressions.sh` と `bash scripts/check-eager-load-capability.sh` が成功する (`modules/verify-executor.md` は eager-load 対象)
   - `/code` の言語規約チェック (`skills/code/language-convention-check.md`) で、`skills/` と `modules/` の追加行に仮名・漢字が無いこと。`skills/review/SKILL.md` L39 の `前景` を含む行には触れない
   - Step 10 の `Task(` 起動箇所と既存の `TaskStop(task_id:` の行 (6 種) を変えていないこと

## Verification

### Pre-merge

- <!-- verify: grep "rubric-grader" "modules/verify-executor.md" --> `modules/verify-executor.md` の rubric の節が、grader をサブエージェントとして起動するときの名前を決めている
- <!-- verify: rubric "modules/verify-executor.md の rubric の節が、grader をサブエージェントとして起動した場合に、判定を受け取った直後に TaskStop(task_id: ...) で止める手順と、停止はベストエフォートで判定や後続の処理を止めないことを書いている" --> grader を止める手順と、停止がベストエフォートであることが書かれている
- <!-- verify: section_contains "skills/review/SKILL.md" "Sub-agent Names and Stop" "grader" --> `/review` の「Sub-agent Names and Stop」が Step 8 の grader に触れている

### Post-merge

- rubric を含む受入条件がある PR で `/review` を実行した後、`ListAgents` に grader の teammate が残っていない <!-- verify-type: opportunistic -->

## Notes

**計測値** (スコープ: 下記の各ファイル・各ディレクトリ、変更前の状態。基点は `main` の `dceaca34`、取得日 2026-10-12)

- `rubric-grader`: リポジトリ全体 (`.git` と `.claude/worktrees` を除く) で 0 件。コマンド: `grep -rln "rubric-grader" . | grep -v -E '^\./\.git/|^\./\.claude/worktrees/'`。`modules/verify-executor.md` と `skills/review/SKILL.md` の 2 ファイルでも 0 件 (Issue の premise と一致)
- `modules/verify-executor.md` の `TaskStop`: 0 件。`skills/review/SKILL.md` の `TaskStop`: 13 件、`grader`: 0 件 (大文字小文字を区別しない: `grep -c -i "grader" skills/review/SKILL.md`)
- AC1 は実装前に FAIL (0 件)、AC3 も実装前に FAIL (`### Sub-agent Names and Stop` の節に `grader` が無い)。どちらも実装前から常時 PASS ではない
- 呼び出し元: `modules/verify-executor.md` を読むのは `/review` (Step 8、safe)、`/verify` (Step 2、full)、`/code` (AC 整合性チェックと Smoke Test、full)、`/auto` (Step 4 の XL 親の横断条件の事前検証、full)。コマンド: `grep -rn "verify-executor" skills modules agents scripts`。`$NUMBER` は `/review` で PR 番号、他の 3 つで Issue 番号。PR と Issue は番号空間を共有するので名前は衝突しない

**Issue 本文との相違**

- なし。Background の主張 (Step 10 の 6 種だけが対象、Step 8 の grader は未定義、`verify-executor.md` は `/verify` も使う) はすべて現状のコードと一致する。実際には `/verify` のほか `/code`・`/auto` も読むので、正本をモジュールに置くのが妥当 (Overview 参照)

**自動解決した判断 (非対話モード)**

- **grader の形: サブエージェントのまま、名前と停止を足す (案 A を採用)**。Issue が `/spec` に委ねた論点。「呼び出し元の文脈でその場で判定する」案 (案 B) は採らない。根拠は次の 3 つ
  - 既存の規則が別の文脈を前提にしている。`Spec files are not passed to the grader` は、Spec を読み込み済みの呼び出し元の文脈では守れない。`adversarial system prompt` も、自分の出力を甘く採点する偏りを避けるためのもの
  - 呼び出し元は独立した文脈ではない。`/code` は実装した本人の文脈で動き、`/verify` は対話セッションで前のフェーズと同じ文脈になりうる。`/review` も Spec と Phase Handoff を読んでいる。その文脈で判定すると、独立した採点にならない
  - Issue 本文、PR の diff、名指しされたファイルを呼び出し元の文脈に取り込むと、文脈が膨らむ。サブエージェントなら判定だけが戻る

  案 B の利点は「起動しないので残らない」ことだが、上の 3 つを失う。この判断は、AC1 の `rubric-grader` という名前が存在し続ける案なので、Issue の AC はそのまま有効 (Issue Retrospective の「案を決めるときに AC も見直すこと」に従い、AC1-AC3 を新しい設計に照らして確認した)
- **モジュールの文面は条件付き (`When the grader is launched as a sub-agent`)**: 起動の形を強制しない。サブエージェント以外の形 (呼び出し元の文脈での判定) を禁止する規則にすると、既存の呼び出し元の挙動を変えてしまい、この Issue の範囲を超える。文面は「サブエージェントが期待される形」であることと、その理由を述べるに留める
- **手順の正本は `modules/verify-executor.md`**: 呼び出し元が 4 スキルあるため。`skills/review/SKILL.md` は一覧に grader を足して正本を指す (Issue の「想定する形」の「一覧に足す (または手順を参照する)」の両方を行う)。`skills/verify/SKILL.md` は変更しない (`skill-body-sha` / `skill-body-lines` マーカーの再計算が要り、モジュールを読むので不要)
- **名前の付け方**: `/review` Step 10 の `review-light-$NUMBER` の形を踏襲し、役割 + 番号にする。単独の grader は `rubric-grader-$NUMBER`、複数のときは各々に `-{n}` (起動順の 1 始まり) を付ける。Issue の例 (`rubric-grader-$NUMBER`、複数なら `-{n}`) と同じ。下流の観測 (`rubric-grader-<PR>`) とも一致する
- **判定が得られなかった grader は止めて、その条件は UNCERTAIN にする**: #1478 の「結果を使わなかったエージェントほど取り残される」を踏襲する。UNCERTAIN は `Return values` の既存の定義 (`cannot be determined`) をそのまま当てはめたもの。代行の判定 (#1481 の Sub-agent Result Fallback の Substitution に相当する) は入れない。grader は独立した採点が目的で、代行は上の根拠 (既存の規則が別の文脈を前提にしていること、呼び出し元が独立した文脈ではないこと) を損なう。Pre-merge の条件が UNCERTAIN のまま残ると `/merge` の AC ゲートが止め、`/review` の再実行で解消する (Step 8 の既存の記述どおり)。トレードオフとして、判定が戻らない状況が続くと `/auto` が止まりうる。実際に観測されたら別 Issue で扱う
- **`allowed-tools` に `TaskStop` を足さない**: `skills/review/SKILL.md` は #1478 で足さずに使っている。権限は不要 (公式の tools-reference で Permission required: No、#1478 で確認)。`modules/verify-executor.md` は frontmatter を持たず、呼び出し元の `allowed-tools` は Bash 系の事前承認なので、`TaskStop` の呼び出しは影響を受けない。allowed-tools の影響連鎖チェックの Case 2 (モジュール変更) は、追加する文面が `scripts/*.sh` のパスを含まないため、ゲートで対象外
- **`docs/tech.md` / `docs/ja/tech.md` を同じ変更で更新する**: tech.md の L71 は `/review` のサブエージェントの停止規則 (#1478) を述べており、grader が同じ規則に従うことを 1 文足す。この記述は #1478 の当時は無く、後の `docs: sync (normalization)` (`b774f31c`) で入ったので、更新しなくても次の `/doc sync` が拾う。それでも同じ変更に含めるのは、停止規則を列挙している文書がここだけで、`/audit drift` に拾われる前に揃えられるため。日本語ミラーは `docs/translation-workflow.md` の手順で同時に更新する
- **新規テストは不要**: 変更は LLM が読む文書のみで、スクリプトに分岐を追加しない (#1478・#1481 と同じ扱い)。既存の bats が見る文字列は Implementation Step 4 で grep により確認する。実行環境に `bats` が無い (`command -v bats` が失敗) ので、既存の bats は実行できない
- **`/review` の `## Non-Interactive Mode Behavior` の Foreground 箇条書きは変更しない**: 今は Step 10 のサブエージェント起動だけを挙げており、Step 8 の grader の起動は挙げていない。grader の結果が戻らない場合の扱いは、この Issue の「判定が得られなかった grader」の規則 (停止して UNCERTAIN) が受ける。Foreground の対象を広げるかは別の論点なので、必要なら別 Issue で扱う
- **監査・調査型の Issue ではない** (判定: no): 既存の項目を分類して根拠を記録する Issue ではなく、手順の追加なので、識別子の存在確認の追加ステップは不要。ただし、挿入する文面が参照する見出し名のうち、`Sub-agent Names and Stop` (`skills/review/SKILL.md` L467)、`Sub-agent Result Fallback` (同 L486)、`Rubric Command Semantics` (`modules/verify-executor.md` L162) は現状のファイルに存在することを確認済み。`Grader sub-agent name and stop` だけがこの Issue が導入する見出し名で、実装後に `grep -n "Grader sub-agent name and stop" modules/verify-executor.md` で存在を確認する
- **ツール検出の方式は新規に導入しない**: `TaskStop` は呼び出すだけで、有無の検出はしない。既存の `/review` Step 10 と同じ扱い
- **Pre-merge の検証項目は 3 件**: Issue の AC と 1:1 (件数は一致、light の上限 5 件以内)

**CI の制約** (`/code` で守る)

- 追加する文言は英語のみ (`scripts/check-language-convention.py` が `skills/`・`modules/` の差分の `+` 行から仮名と漢字を検出する)。`docs/ja/tech.md` は日本語ミラーで、`docs/` はこの検査の対象外
- 半角 `!` を `skills/review/SKILL.md` の本文に入れない (`scripts/validate-skill-syntax.py`)。非推奨用語 (`scripts/check-forbidden-expressions.sh`) を使わない
- `modules/verify-executor.md` は eager-load 対象。capability 固有の記述を混ぜない (`scripts/check-eager-load-capability.sh`)。追加する記述はどのプロジェクトでも rubric を使えば当てはまる内容
- 日本語の文中の括弧は半角 `()` を使い前後に半角スペースを入れる (`docs/ja/tech.md` の追加文)

**外部仕様の確認** (出所と取得日)

- `TaskStop` のスキーマ: `task_id` は「バックグラウンドタスクの ID。agent-team の teammate と名前付きバックグラウンドエージェントは、agent ID または名前でも指定できる」。teammate は agent ID か名前そのもの (`@team` などの接尾辞なし) を渡す。`shell_id` は非推奨。出所: ToolSearch `select:TaskStop` が返したスキーマ (取得日 2026-10-12)
- 名前付きの呼び出しが teammate になる条件、権限不要、同名の挙動: #1478 の Spec の「外部仕様の確認」(取得日 2026-10-03) を踏襲した。公式ドキュメント (https://code.claude.com/docs/en/tools-reference、https://code.claude.com/docs/en/agent-teams、https://code.claude.com/docs/en/sub-agents) の再取得はしていない。この Issue が新たに依存する外部仕様は無く、`TaskStop` のスキーマだけを再確認した

**Uncertainty** (light のためここに記録)

- **`name:` を付けた grader が teammate として起動されうる**: agent teams が有効な対話セッションでは、名前付きの呼び出しは teammate になり、結果がチームのメッセージで返る (#1478 と同じ)。判定が戻らない場合は、この Issue の規則で grader を止めて条件を UNCERTAIN にする。検証方法: Post-merge の opportunistic 条件。影響範囲: Implementation Step 1-2
- **fork 実行ではこの手順が効かない可能性が高い**: 対話セッションからの fork 実行の `/review` では、teammate は main session の所有になり、fork 側の `TaskStop` は拒否されうる (#1481 観測 2、#1478 の Uncertainty)。ベストエフォートとして受け入れる。拒否が常態なら、別 Issue で名前を付けずに停止する案や `maxTurns` の上限を検討する。影響範囲: Implementation Step 1-2
- **同名のエージェントが残っているときの挙動は未検証**: 同一セッションに前回の grader が残った状態で同じ PR を再度 `/review` すると名前が重複する。エラーになるか、サフィックスが付くかは分からない。エラーなら grader の起動が結果なしとなり、この Issue の「判定が得られなかった grader」の規則が受ける。影響範囲: Implementation Step 1-2
- **文面の一致を確認する grep の対象**: AC1 の `rubric-grader`、AC3 の `grader` は、いずれも実装が導入する文字列 (前者は `modules/verify-executor.md`、後者は `skills/review/SKILL.md` の `### Sub-agent Names and Stop` の節内)。実装前は 0 件

**Consumed Comments**: 末尾の `## Consumed Comments` を参照

## Consumed Comments

- saito / MEMBER / first-class / `/issue` の Issue Retrospective (AC3 の heading 引数の修正、Background への premise マーカー追加、grader をサブエージェントにするか呼び出し元でその場で判定するかを Spec で決める旨の申し送り) / https://github.com/saitoco/wholework/issues/1518#issuecomment-6116421788
- 参考: cutoff (`phase/issue` の付与、2026-10-12T02:00:48Z) より前の triage の AC 監査コメント (`section_contains` の heading 引数に先頭の `###` を含めると常時 UNCERTAIN になる指摘) は `/issue` で消費済みで、Issue 本文の AC3 に反映されている
- verify フェーズ (cutoff: `phase/verify` の付与、2026-10-12T02:24:25Z): No new comments since last phase.

## Code Retrospective

### Deviations from Design
- なし。Spec の Implementation Steps 1-3 の挿入文面をそのまま入れた (Step 1 の翻訳表の 1 文、`Grader sub-agent name and stop` ブロック。Step 2 の Step 8 の 1 文、一覧の 2 行、grader 段落。Step 3 の `docs/tech.md` と `docs/ja/tech.md` の 1 文)。

### Design Gaps/Ambiguities
- 実行環境に `bats` が無い (`command -v bats` が失敗) ため、既存の bats (`tests/verify-rubric.bats`、`tests/review-rubric-safe.bats`) は実行できなかった。代わりに、各 bats が見る文字列の残存を grep で確認した (`rubric "text"`、`adversarial`、`Mode-independent`、`Spec files are not passed to the grader`、`Rubric Command Semantics`、節内の `always_allow`、`returns UNCERTAIN in safe mode` が無いこと)。この Issue の Pre-merge の AC に bats の AC は無いので、`BATS_DEFERRED_ACS` は空 (CI での確認 (Step 14) は不要)。
- Behavioral Change Detection は「既存ファイルの変更あり、かつ他の bats が参照」に該当 (`tests/verify-executor.bats` など) したが、bats が無いため全体実行は不可。ドキュメントのみの変更で、スクリプトの分岐は変えていない。

### Rework
- なし。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の挿入文面をそのまま適用し、手順の正本は `modules/verify-executor.md` に置いた。`skills/review/SKILL.md` は一覧に grader 2 行と参照段落を足しただけで、`allowed-tools` と `skills/verify/SKILL.md` は変更していない。
- `docs/tech.md` と `docs/ja/tech.md` は両方に同時に 1 文を足した (片方だけにしない)。

### Deferred Items
- Post-merge の opportunistic 条件 (`/review` 実行後に `ListAgents` へ grader の teammate が残らないこと) は未確認。実際に rubric を含む PR で `/review` を回したときに確認する。

### Notes for Next Phase
- 実行環境に `bats` が無く、既存の bats は実行していない。文字列の残存は grep で確認済み。
- Pre-merge の AC 3 件は `/code` Step 10 でチェック済み。`/verify` では Post-merge の opportunistic 条件だけが残る。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- triage の AC 監査が AC3 の `section_contains` の heading 引数 (`### ...`) による常時 UNCERTAIN を検出し、`/issue` がコメントを消費して修正した。監査コメント → 次フェーズでの修正という非破壊の流れが想定どおり機能した。

#### design
- grader をサブエージェントのまま名前と停止を足す案 (案 A) を、既存規則 (Spec を grader に渡さない、敵対的な姿勢) との整合で選んだ判断は妥当。Issue Retrospective の「案を決めるときに AC も見直す」申し送りも Spec で消化されている。

#### code
- Spec の挿入文面をそのまま適用し、手戻りなし。実行環境に `bats` が無く既存 bats は実行していないが、ドキュメントのみの変更で、文字列の残存は grep で確認済み。

#### review
- patch route のため `/review` は無し。

#### merge
- patch route のため PR merge は無し。main への直接コミット (`1e56bb2d`) で問題なし。

#### verify
- Pre-merge 3 件は `/code` でチェック済みのため既定どおり SKIPPED。Post-merge の opportunistic 条件 1 件は rubric を含む PR の `/review` が必要なため未確認で、`phase/verify` に残した。FAIL / UNCERTAIN は無し。

### Improvement Proposals
- N/A
