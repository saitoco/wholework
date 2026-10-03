# Issue #1482: auto: phase/verify など spec より先の phase ラベルで始まる Issue の再開経路を Step 3 に定める

## Overview

単一 Issue 経路の `/auto` の Step 3 (`phase/ready` Label Check) は、分岐が `phase/ready` あり / `phase/issue` あり / `phase/*` 無しの 3 つだけで、spec より先に進んだ Issue (`phase/code`・`phase/review`・`phase/merge`・`phase/verify`・`phase/done`) を受け取ったときの動作が定められていない。saito/ops#120 (Size XS、`phase/verify`、残りは Post-merge の manual AC のみ) では、親セッションが手順外の判断で code を飛ばし、Step 4 patch route の verify 部分 (precondition → checkpoint → `Skill(wholework:verify)`) だけを実行した。結果は妥当だったが、仕様上は未定義の動作だった。

この Issue では、Step 3 に次の 3 分岐を追加して、再開の入り口を明文化する。

- `phase/verify`: spec/code/review/merge を飛ばし、route に応じた verify の手順 (precondition → checkpoint → verify) から始める
- `phase/done`: 何もせず、完了済みと報告して終了する
- `phase/code` / `phase/review` / `phase/merge`: spec の dispatch を飛ばして Step 4 へ進み、既存の再開機構 (checkpoint / `reconcile-phase-state.sh`) に委譲する。Issue が `/spec` に委ねた「ラベルごとの具体的な再開手順」は、この Spec の `## Implementation Steps` (Resume entry points の表) で定める

## Reproduction Steps

1. XS の Issue を用意する。`phase/verify` で、残りの受入条件が Post-merge の manual AC だけの状態にする (Spec ファイル無し、verify-fail marker 無し、reopen 履歴無し。saito/ops#120 がこの状態だった)
2. `/auto N` を実行する
3. Step 2a の 3 条件のうち、「verify-fail marker または reopen 後」と「Spec ファイルが存在する」を満たさないので fix-cycle とは判定されず、Step 3 に進む
4. Step 3 には `phase/verify` の分岐が無い。親セッションは手順外の判断で code を飛ばし、Step 4 patch route の verify 部分だけを実行した

## Root Cause

- **Step 3 が spec より先のラベルを列挙していない**: 分岐は `phase/ready` あり / `phase/issue` あり / `phase/*` 無しの 3 つだけで、`phase/code`・`phase/review`・`phase/merge`・`phase/verify`・`phase/done` の扱いが書かれていない。Step 3 のセクション内でのこれら 5 ラベルの出現は、実測で各 0 件 (測定範囲: `skills/auto/SKILL.md` の `### Step 3:` 見出しから `### Step 3a:` 見出しの直前まで。5 ラベルを個別に `grep -cF` で計測)
- **Step 4 に `phase/ready` 無しで入る経路が Step 2a だけ**: Step 2a は verify-fail marker または reopen と、Spec の存在を要する。Spec の無い XS で、marker も reopen も無い `phase/verify` の Issue はどちらにも入れず、Step 3 の未定義領域に落ちる
- **経路間の非対称**: 同じ「spec 完了以降」の判定は、XL / batch 経路 (`scripts/run-auto-sub.sh` L899-922、#977) と、spec 起動の phase-guard (`scripts/run-spec.sh` L48-57) にはすでにある。単一 Issue 経路の Step 3 だけが対応を欠いている。この欠落があるために、`phase/issue` 分岐の `run-spec.sh` を実行しても phase-guard で exit 1 になり、Step 6 のエラー報告に進むか、親セッションが手順外の判断をするかのどちらかになる

対処の妥当性: `docs/workflow.md` の `--resume N` の説明と `skills/auto/SKILL.md` の Checkpoint Design は、現在の phase の authority を「GitHub ラベル + `reconcile-phase-state.sh`」としている。Step 3 に spec より先のラベルの分岐を加えることは、この既存の設計原則を単一 Issue 経路で実装することであり、新しい機構は要らない。

## Changed Files

- `skills/auto/SKILL.md`:
  - `### Step 3: \`phase/ready\` Label Check` (見出しは変更しない): `phase/issue` 分岐の後、`No phase/* labels` 分岐の前に 3 分岐 (`phase/code` / `phase/review` / `phase/merge`、`phase/verify`、`phase/done`) を追加する。同セクションの末尾 (`### Step 3a:` の直前) に、"Resume entry points" の表と、4 つの再開分岐に共通する規則 (Step 2a の優先、`EFFECTIVE_STOP_AT`、XL route、Step 5 の結果表) を追加する
  - `## Checkpoint Design` > `### Stale checkpoint detection` の項目 2: `phase/done` の Label conflict の処理主体に、Step 3 の `phase/done` 分岐を追記する
- `tests/auto.bats`: `step3_section` ヘルパーと、Step 3 の新分岐を検証する `@test` を追加する (bash 3.2+ compatible: `[[ ]]` の assertion には `|| false` を付ける)
- `docs/workflow.md`: `## Orchestration` > `### \`/auto\` — Full Workflow Automation` の `If \`phase/ready\` is absent, ...` で始まる段落に、spec より先の phase からの再開を追記する
- `docs/ja/workflow.md`: 上記の日本語ミラー (`\`phase/ready\` が無い場合 ...` で始まる段落)
- [Steering Docs sync candidate] keyword "auto" skipped: matched 993 files (no discriminating power。測定範囲: `docs/` `tests/` `scripts/` `modules/` の全ファイル。測定コマンド: `grep -rl "auto" docs/ tests/ scripts/ modules/ | wc -l`)。この Issue が導入・変更する config key・marker 名・関数名は無いので、これより優先度の高い keyword は無い
- [doc-checker 由来] Skill の変更に伴う `docs/workflow.md` は上記のとおり Changed Files に含めた。`README.md` の `/auto` の記述 (L13, L47, L55) と `CLAUDE.md` (`/auto` の記述なし) は、phase ラベルに基づく開始条件を述べていないので変更不要 (`grep -n "/auto" README.md CLAUDE.md` で確認)
- [Outbound pointer sync candidate] なし。`skills/auto/SKILL.md` Step 3 が指す `docs/workflow.md` は Changed Files に含め済み。`modules/phase-state.md` は引用だけで内容は変わらない
- 変更不要 (grep で確認済み): `docs/guide/workflow.md` L136 (`If no \`phase/*\` label is set, \`/auto\` starts from issue triage. If no spec exists, it runs \`/spec\` first.` は、新分岐の下でも正しい) と、その日本語ミラー。`docs/product.md` の Terms `/auto` 行 (`auto-runs \`/spec\` when \`phase/ready\` is absent` は、用語集としての要約で、XS の spec 省略もすでに書いていない粒度のため据え置く)

## Implementation Steps

1. `skills/auto/SKILL.md` の Step 3 に、3 分岐・"Resume entry points" の表・共通規則を追加する (→ AC1, AC2, AC3)
   - 位置: 3 分岐は、`phase/issue` 分岐 (`On spec failure, go to Step 6 (error report)` で終わる階層) の直後、`- **No \`phase/*\` labels** (issue triage not done):` の直前に挿入する。表と共通規則は、Step 3 の最後の分岐 (`On issue failure, go to Step 6 (error report)`) の後、`### Step 3a:` の直前に置く。`###` 以上の見出しは追加しない (`section_contains ... "Step 3:"` が見るセクションは、次の同階層以上の見出しまでであるため。`modules/verify-executor.md` の `section_contains` の定義)
   - 追記する英文は次のとおり。語句は調整してよいが、手順 3 のテストが見る語句は残す。追記する行はすべて英語にする (CJK を入れない)。半角 `!` は使わない
     ```markdown
     - **`phase/code`, `phase/review`, or `phase/merge` label present (no `phase/ready`)**: spec has already completed — skip the spec dispatch (the same rule `scripts/run-auto-sub.sh` applies, issue #977) and Step 3a, then proceed to Step 4. Resumption is delegated to Step 4's existing mechanisms and no new one is introduced: GitHub labels plus `reconcile-phase-state.sh` (precondition and completion checks) are the authority for the phase state, and the checkpoint (`auto-checkpoint.sh`) is only a hint for the verify iteration counter. Output "Issue #$NUMBER is at {label} — skipping spec, resuming from {phase}." and enter Step 4 at the item listed for the label under "Resume entry points" below
     - **`phase/verify` label present (no `phase/ready`)**: spec, code, review, and merge have already completed — skip all four and start from verify. Output "Issue #$NUMBER is at phase/verify — skipping spec, code, review, and merge, resuming from verify." and enter Step 4 at the verify items of the current route, as listed under "Resume entry points" below (precondition check → counter increment → checkpoint save → `Skill(wholework:verify)`)
     - **`phase/done` label present**: the Issue is already complete — do not process it. Run `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh delete_single $NUMBER` (a no-op when no checkpoint exists; Step 4's stale-checkpoint check is not reached on this path), output "Issue #$NUMBER is already at phase/done — nothing to run.", and stop without entering Step 3a, Step 4, or Step 5
     ```
     ```markdown
     **Resume entry points (`phase/code`, `phase/review`, `phase/merge`, `phase/verify`):** Step 4 proceeds from the listed item as in a fresh run — each phase keeps its usual precondition check → run → completion check — and the phases before the entry item are not re-run.

     | Label | ROUTE | Enter Step 4 at |
     |---|---|---|
     | `phase/code` | patch / operate | patch route item 1 (code) |
     | `phase/code` | pr | pr route item 1 (code; `run-code.sh` skips itself when the PR already exists) |
     | `phase/review` | pr | pr route items 4-5 (extract the PR number), then continue from item 6 (review) |
     | `phase/merge` | pr | pr route items 4-5 (extract the PR number), then continue from item 9 (merge) |
     | `phase/verify` | patch / operate | patch route item 5 (verify precondition check), after Step 4's `VERIFY_ITERATION_COUNT` initialization |
     | `phase/verify` | pr | pr route item 12 (verify precondition check; output `[4/4] verify`), after Step 4's `VERIFY_ITERATION_COUNT` initialization |

     `phase/review` and `phase/merge` are only reached through the pr route's phases, so use ROUTE=pr for them even when Step 2 derived `patch` from the Size — the patch route would re-implement an Issue whose PR already exists.

     **Rules common to the four resume branches above:**

     - Step 2a takes precedence: it runs before this step and skips Step 3 entirely when it detects a fix-cycle. These branches are reached only when Step 2a did not match, so a `phase/verify` Issue with a verify-fail marker or a reopen after merge (and a Spec) is still resumed from code by Step 2a, as before
     - If `EFFECTIVE_STOP_AT` names a phase earlier than the one being resumed (phase order: spec, code, review, merge, verify), that stop point has already been passed: run nothing, output "Stopped at phase: {EFFECTIVE_STOP_AT} (auto-stop-at={EFFECTIVE_STOP_AT})", and proceed to Step 5 with `STOPPED_AT` set
     - XL route: an XL parent's `phase/*` label is aggregated from its sub-issues (see `docs/workflow.md` § XL Parent Issue Phase Management) and is not a resume point for this invocation, so these branches do not apply — enter Step 4's XL route as before
     - In Step 5's result table, show the skipped phases as skipped (already complete) instead of leaving them out
     ```
   - 表が参照する Step 4 の項目番号は、現行の `skills/auto/SKILL.md` の patch route 項目 1-9 と pr route 項目 1-16 に基づく (patch route: 1 precondition / 2 run-code / 3 completion / 4 XS の retrospective 転記 / 5 verify precondition / 6 counter / 7 checkpoint / 8 verify / 9 結果判定。pr route: 1-3 code / 4-5 PR 番号 / 6-8 review / 9-11 merge / 12 verify precondition / 13 counter / 14 checkpoint / 15 verify / 16 結果判定)。実装時に番号が変わっていないか `grep -n` で再確認し、表を合わせる
2. (after 1) `skills/auto/SKILL.md` の `## Checkpoint Design` > `### Stale checkpoint detection` の項目 2 (`**Label conflict**: ... (handled by \`/auto\` Step 4 initialization — calls \`delete_single\` and resets count to 0)`) に、処理主体として Step 3 の `phase/done` 分岐 (`delete_single` を呼んで終了する) を追記する。Step 4 の初期化は Step 2a (fix-cycle) など Step 3 を通らない経路で引き続き到達するので、削除せず併記する (→ AC2 の整合)
3. (after 1) `tests/auto.bats` に Step 3 の新分岐のテストを追加する (→ AC1, AC2, AC3 の回帰ガード。新規分岐に対する新規テストの要件)
   - 既存の `step3a_section` と同じ形の awk ヘルパー `step3_section` を、`step3a_section` の近くに追加する: `awk '/^### Step 3:/{found=1} found && /^### / && !/^### Step 3:/{exit} found{print}' "$1"`。`Issue #1482` を参照するコメントを付ける
   - `@test` を 6 件追加する。テスト名は既存 (`Step 2a section ...` / `Step 3a section ...`) に合わせて `Step 3 section ...` で始める。assertion は `run step3_section "$SKILL_FILE"` の後に `[[ "$output" == *"..."* ]] || false` の形で書く (`scripts/check-bare-bracket-assertions.sh` の対象外にするため)。見る語句は次のとおり (手順 1 の英文に残す語句)
     - phase/verify の分岐: `phase/verify` label present と `skip all four and start from verify`
     - phase/done の分岐: `phase/done` label present と `nothing to run` と `auto-checkpoint.sh delete_single`
     - phase/code・phase/review・phase/merge の分岐: 3 ラベルの名前と `skip the spec dispatch` と `reconcile-phase-state.sh`
     - Resume entry points: `Resume entry points` と `ROUTE=pr`
     - 共通規則: `Step 2a takes precedence` と `EFFECTIVE_STOP_AT` と `XL route`
     - 既存分岐の維持 (回帰): `phase/ready` label present と `phase/issue` label present と `run-spec.sh`
   - 手順 1 の前は、新分岐の 5 件が失敗し、既存分岐の維持の 1 件だけが通ることを確認する (Step 3 セクション内の 5 ラベルの出現が 0 件であることは、Root Cause のとおり計測済み)
4. (parallel with 1-3) `docs/workflow.md` と `docs/ja/workflow.md` を更新する (→ SHOULD: workflow に影響する doc の同期。`docs/translation-workflow.md` の手順に従う)
   - `docs/workflow.md` の `If \`phase/ready\` is absent, ...` で始まる段落: 先頭の文を `If \`phase/ready\` is absent and the Issue has not progressed past spec, ...` に直す。`If no \`phase/*\` label is set, ...` の文の後、`**Fix-cycle exception**` の前に、`**Resume from a later phase**` の文を足す (`phase/verify` は verify から始める、`phase/done` は何もせず完了済みと報告する、`phase/code` / `phase/review` / `phase/merge` は spec の dispatch を飛ばしてラベルが指す phase から既存の checkpoint / `reconcile-phase-state.sh` で再開する、Step 3)。fix-cycle の文の末尾の `(Step 2a)` を、`Step 3 より前に評価され、再開の規則より優先される` 旨に直す
   - `docs/ja/workflow.md` の対応する段落 (`\`phase/ready\` が無い場合 ...` で始まる段落) に、同じ内容を日本語で反映する。コードブロックは無いので、コードフェンス数の確認 (` ``` ` の数) は不要。新規に足す日本語の括弧は、グローバル規約に従い半角 `()` の前後に半角スペースを入れる (既存文は全角括弧のままで、触らない)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md の Step 3 に、phase/verify ラベルで始まる (phase/ready 無しの) Issue を、spec/code/review/merge を飛ばして verify の手順から処理する分岐が明記されている" --> <!-- verify: section_contains "skills/auto/SKILL.md" "Step 3:" "phase/verify" --> `phase/verify` で始まる場合の分岐が Step 3 に明記されている
- <!-- verify: rubric "skills/auto/SKILL.md の Step 3 に、phase/done ラベルで始まる Issue を処理せずに完了済みとして終了する分岐が明記されている" --> <!-- verify: section_contains "skills/auto/SKILL.md" "Step 3:" "phase/done" --> `phase/done` で始まる場合の分岐が Step 3 に明記されている
- <!-- verify: rubric "skills/auto/SKILL.md の Step 3 で、phase/code・phase/review・phase/merge で始まる Issue の扱い (spec の dispatch をスキップすることと、Step 4 の既存の再開機構への委譲) が明記されている" --> <!-- verify: section_contains "skills/auto/SKILL.md" "Step 3:" "phase/code" --> `phase/code` / `phase/review` / `phase/merge` で始まる場合の扱いが Step 3 に明記されている

### Post-merge

- `phase/verify` で始まり fix-cycle 判定 (Step 2a) に該当しない Issue に `/auto N` を実行したとき、code フェーズが起動されず (`.tmp/auto-events.jsonl` に当該 Issue の code フェーズの `phase_start` が記録されない)、verify が実行される (opportunistic)

## Notes

- **Issue 本文の前提確認 (矛盾なし)**: Background の 3 点を実コードで確認した。(1) Step 2a が該当しない: `skills/auto/SKILL.md` Step 2a の 3 条件のとおり。(2) Step 3 の分岐は 3 つだけ: Step 3 のセクションの内容のとおり。(3) `scripts/run-auto-sub.sh` が `phase/(code|review|merge|verify|done)` で spec の dispatch を飛ばす: L909 のとおり (再現コマンド: `grep -n "phase/(code|review|merge|verify|done)" scripts/run-auto-sub.sh`)。`verify-executor` の `section_contains` は、見出しの部分一致から次の同階層以上の見出しまでをセクションとして見る (`modules/verify-executor.md` の定義)。`### Step 3:` に部分一致する見出しは L235 の 1 つだけで、現状の Step 3 内の `phase/verify` / `phase/done` / `phase/code` の出現は各 0 件。そのため 3 つの `section_contains` は、変更前は FAIL、Implementation Step 1 の後は PASS になる
- **`phase/merge` は実運用では付与されない (Issue 本文との相違ではなく、既存の文書と実装のずれ)**: `docs/workflow.md` の Label Transition Map は `/merge` が開始時に `phase/merge` を付与すると書く。しかし `scripts/gh-label-transition.sh` の許可値は `issue|spec|ready|code|review|verify|done` で `merge` が無く、`skills/merge/SKILL.md` と `scripts/run-merge.sh` にも付与箇所が無い (`git grep -n "phase/merge" -- scripts skills modules` で確認)。ラベル自体は `scripts/setup-labels.sh` に定義があり、`run-spec.sh` の phase-guard と `run-auto-sub.sh` (#977) の対象に含まれる。Issue の指示どおり、この Issue では `phase/merge` もスコープに含める (分岐を足しても害は無く、`run-spec.sh` / `run-auto-sub.sh` の対象ラベルの集合と揃う)。文書側の記述との乖離の解消は今回の範囲外
- **既知の限界: Step 2a の stale marker (Step 3 の新分岐の到達範囲に影響する)**: verify-fail marker はコメントとして残り続け (Issue コメントは append-only)、Step 2a の条件 1 は「marker が存在するか」だけを見る。`skills/verify/SKILL.md` や `modules/` に、後続の成功で marker を失効させる (latest-wins の) 解決は無い。そのため、過去に一度 verify が FAIL してから成功して `phase/done` または `phase/verify` になった Issue は、条件 2 (`phase/code|review|spec` が無い。`phase/done` / `phase/verify` は許容) と条件 3 (Spec がある) を満たせば、Step 3 より先に Step 2a に該当し、新分岐に到達しない。Issue の自動解決ログのとおり、Step 2a が Step 3 より優先する方針は変えない。対処 (marker の失効判定を足すかどうか) は別の Issue で扱う。この Spec では `skills/auto/SKILL.md` に優先関係を明記するだけにとどめる
- **既知の限界: `phase/code` 再開時の operate route 検出**: Step 2 の operate route 検出は `phase/ready` があることを条件にしているため、`phase/code` 以降では走らない。diff-less な Spec を持つ Size M/L の Issue を `phase/code` から再開すると ROUTE=pr になり、`/code` が operate に切り替えて PR を作らないため、pr route 項目 3 の completion check で Step 6 に進みうる。operate は主に XS/S (patch route) の経路なので、実際に起こるのは稀で、今回は対象外とする
- **再開手順の設計判断 (non-interactive: 自動解決。この Spec で定めるよう Issue が委ねた部分)**:
  - 入り口は「ラベルが指す phase」とし、Step 4 の既存の項目をそのまま進める (precondition → run → completion check)。新しい機構は足さない。`reconcile-phase-state.sh` は Step 4 の各 phase の判定にすでに使われており、checkpoint は verify の反復回数 (`VERIFY_ITERATION_COUNT`) の hint としてのみ使う (Checkpoint Design の「reconciler-first / checkpoint-as-hint」と同じ)
  - **採用しなかった案: 入り口の phase の completion check を先に実行して、完了済みなら飛ばす (Observe-first)**。理由: verify の completion signature は `Issue is CLOSED or has phase/done` (`modules/phase-state.md` の Phase Table) で、patch route などで `closes #N` により CLOSED になり、manual AC が残って `phase/verify` に留まる Issue (この Issue の動機そのもの) ですでに真になる。先に見ると、実行したい verify を飛ばしてしまう。code (pr) は `scripts/run-code.sh` L243-255 に既存 PR の idempotency guard があり、先に見る必要が無い。review / merge の再実行コストは許容する (繰り返し高くつくなら、review だけ事前チェックを足す案を別 Issue で検討する)
  - `phase/review` / `phase/merge` は ROUTE=pr に固定する。これらのラベルは pr route の phase でしか付かず、Size から導かれた patch route のまま進めると、PR がある Issue を `run-code.sh --patch` で再実装してしまうため
  - `phase/done` 分岐で `auto-checkpoint.sh delete_single` を呼ぶ。Step 4 の初期化にある stale checkpoint の確認 (`phase/done` なら `delete_single`) に到達しなくなるので、Checkpoint Design の cleanup trigger (`Issue CLOSED / phase/done detected at resume`) を保つため (`delete_single` は checkpoint が無くても no-op: `scripts/auto-checkpoint.sh` の usage コメント)。`auto-checkpoint.sh:*` は `skills/auto/SKILL.md` の `allowed-tools` に済み
  - `EFFECTIVE_STOP_AT` が再開する phase より前を指すときは、何も実行せず stop する。`auto-stop-at: review` を、自動 merge を避ける設定として使う運用 (`docs/workflow.md` の Pipeline control) で、再開によってその設定を越えて merge / verify が走ることを防ぐため
  - XL route は対象外とする。XL 親 Issue の `phase/*` ラベルは sub-issue からの集約で付く (`docs/workflow.md` の XL Parent Issue Phase Management) ので、再開の入り口を示さない。`phase/done` は XL 親にもそのまま当てはまる
  - verify から再開するとき、patch route 項目 4 (XS の issue retrospective の Spec への転記、Step 4b) は再実行しない。Issue が「verify の手順 (precondition → checkpoint → verify) から始める」と指定しているため。必要になれば別 Issue で扱う
  - `phase/spec` ラベルは対象外とする (spec の再 dispatch が正しい挙動、と Issue が確定済み)。現状の Step 3 には `phase/spec` の分岐も無いが、今回は触らない
  - 見出し `### Step 3: \`phase/ready\` Label Check` は変更しない。`section_contains ... "Step 3:"` の部分一致を保ち、`scripts/run-auto-sub.sh` や `tests/run-auto-sub.bats` が文字列として参照する `skills/auto/SKILL.md Step 3` も壊さないため
- **新規テスト (新規分岐ロジック)**: Step 3 に新分岐を追加するので、既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/auto.bats` に `step3_section` ヘルパーと 6 件の `@test`) を追加したうえでスイートが PASS すること。Pre-merge の AC は `rubric` と `section_contains` だけで、bats の `command` の AC が無いため、この要件は Implementation Step 3 で担保する (Issue 本文の AC は変えない)
- **bats テストの入力形式**: テスト対象は `skills/auto/SKILL.md` (Markdown)。`step3_section` は、`### Step 3:` で始まる行から、次の `### ` で始まる行 (`### Step 3a:`) の直前までを標準出力に出す (`### Step 3a:` は `/^### Step 3:/` に一致しないので、セクションの終端として働く)。現状の出力は 29 行 (見出し行を含む。`awk '/^### Step 3:/{found=1} found && /^### / && !/^### Step 3:/{exit} found{print}' skills/auto/SKILL.md | wc -l` で確認)。`bats` が無い実行環境では、同じ awk の抽出と `grep -F` で同等の確認をする
- **言語規約と CI の検査**: `skills/auto/SKILL.md` に追記する行は英語のみにする。`scripts/check-language-convention.py` (CI の `language-convention` job と `/code` の事前確認) は `skills/` `modules/` `scripts/` の diff の追加行にある CJK を検出する。既存の行を編集すると、行全体が追加行になって、元から地の文にあった日本語が検出される (#1481 の教訓)。Step 3 の現行 29 行と Checkpoint Design の項目 2 は日本語を含まない (`grep -nP` で確認済み) が、Step 2a の L197-198 には日本語が残っているので、Step 2a は編集しない。`scripts/check-forbidden-expressions.sh` の対象語 (`docs/product.md` § Terms の旧称の列にある語。`/auto` の旧称を含む) は、追記する英文にも、この Spec にも含めない。「spec の dispatch」のような一般名詞の用法は小文字で書く
- **allowed-tools の影響**: 新規スクリプトの追加も `modules/*.md` の変更も無いので、`allowed-tools` impact chain check の対象外。追記する英文が呼ぶ `auto-checkpoint.sh` / `reconcile-phase-state.sh` / `gh issue view` は、`skills/auto/SKILL.md` の `allowed-tools` に済み
- **audit/investigation-type の判定**: no。既存項目の分類・監査ではなく、未定義だった動作を仕様化する変更であるため
- **UI Design**: 対象外 (UI を伴わない文書・Skill 定義の変更)
- **verify-type の確認**: Post-merge の `opportunistic` は、`modules/verify-classifier.md` の「`verify X when \`/skill-name\` is run`」の形に当たる (`/auto N` を実行したとき、code の `phase_start` が記録されず verify が実行されることを確認する)
- **Consumed Comments**: 下の `## Consumed Comments` を参照

## Consumed Comments

- saito / MEMBER / first-class / `/issue` の Issue Retrospective (非対話モードでの曖昧ポイントの自動解決、受入条件の変更、補足。cutoff は最新の `phase/*` ラベル付与 2026-10-02T23:34:41Z) / https://github.com/saitoco/wholework/issues/1482#issuecomment-5963159669
- クロスフェーズ marker (`type=verify-fail` / `type=preview-ac-unverified`): 該当なし

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1-4 を Spec どおりに実装した。Step 4 の項目番号 (patch route 1-9 / pr route 1-16) は `grep -n` で再確認し、変更されていなかった

### Design Gaps/Ambiguities
- 実行環境に `bats` が無く、`tests/auto.bats` の新規 6 件を直接実行できなかった。Spec の Notes が示す代替 (同じ awk 抽出と `grep -F`) で同等の確認を行い、変更前は新分岐の 5 件が FAIL・既存分岐維持の 1 件が PASS、変更後は 6 件すべて PASS になることを確認した (Confirmed pre-implementation FAIL for 5 new test(s))
- 同じ理由で、`skills/auto/SKILL.md` を参照する他の bats (`run-auto-sub.bats` 等) は実行できていない。追加は Step 3 と Checkpoint Design の 1 行に限られ、他テストが見る文字列 (`skipping dispatch ... per skills/auto/SKILL.md Step 3` はスクリプト出力) は変わらないことを grep で確認した。CI の bats が最終確認になる

### Rework
- 日本語ミラーの Step 2a の括弧は、既存が全角だったが、置換する文を新規に書くため半角 `()` + 前後スペースに揃えた (グローバル規約)。それ以外の手戻りはなし

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Step 3 に 3 分岐 (`phase/code`・`phase/review`・`phase/merge` / `phase/verify` / `phase/done`) と Resume entry points の表・共通規則を Spec の英文どおり追加した。新しい機構は足さず、Step 4 の既存項目に入る形にした
- `phase/done` 分岐は `auto-checkpoint.sh delete_single` を呼んで終了する。Checkpoint Design の Label conflict の処理主体に併記した

### Deferred Items
- Post-merge の opportunistic AC (`phase/verify` の Issue に `/auto N` を実行したとき code の `phase_start` が記録されず verify が実行される) は、実運用で確認する
- Step 2a の stale marker と `phase/code` 再開時の operate route 検出は、Spec の Notes のとおり別 Issue の範囲

### Notes for Next Phase
- 実行環境に `bats` が無く、新規テストは awk と `grep -F` の同等確認だけで、bats 本体は未実行。CI の結果を確認する
- Pre-merge の 3 AC は section_contains (Step 3 内の出現を確認済み) と rubric で、Issue 側のチェックボックスは更新済み
