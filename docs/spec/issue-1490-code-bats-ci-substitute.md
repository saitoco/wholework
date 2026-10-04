# Issue #1490: code: patch route で bats が無いとき CI 結果で bats AC を代替確認する

## Overview

`/code` の patch route で、実行環境に bats が無いとき、`bats tests/` 型の pre-merge AC を、push したコミットの CI 結果で確定できるようにする。

現状、bats が無い環境の `/code` は `command "bats tests/..."` 型の AC を確認できず、(a) 未チェックのまま `/verify` に渡す、(b) `awk` / `grep -F` の近似で済ませる、のどちらかになり、確認が `/verify` に先送りされる (件数と事例は Issue 本文の Background)。pr route では `/review` が PR の CI を参照する (`modules/verify-executor.md` § "CI Reference Fallback") が、patch route には PR が無く、同じ経路が無い。

方針は次の 3 点。いずれも `skills/code/SKILL.md` の変更で、script と module は増やさない。

- **Step 10**: bats が無い (`command -v bats` が何も出力しない) とき、bats を実行する `command` AC を verify-executor の対象から外す。チェックせず `BATS_DEFERRED_ACS` として Step 14 に持ち越す。ローカルの近似 (`awk` / `grep -F`) は AC の根拠にしない
- **Step 14 (patch route の push 後)**: push したコミットの CI run を `gh run list` で特定し、`gh run watch` で完了を待つ (Bash ツールの 10 分上限の内側)。bats ジョブ単位の結論が `success` のときだけ AC をチェックする。実行中のまま・結果不明は未チェックで `/verify` に委ね、失敗は未チェックのまま報告して先へ進む
- **frontmatter**: `allowed-tools` に `gh run list:*` / `gh run watch:*` / `git rev-parse:*` を足す

## Changed Files

- `skills/code/SKILL.md`:
  - frontmatter の `allowed-tools`: `gh run view:*,` の直後に `gh run list:*, gh run watch:*,` を、`git merge-base:*,` の直後に `git rev-parse:*,` を足す
  - Step 10: (a) `**CI verification AC exclusion (route-agnostic):**` の `**patch or operate route**` の bullet にある `(it happens in Step 11)` を、push が Step 14 で起きる旨の記述に直す (新手順と矛盾するため。Notes 参照)。(b) その段落の 2 つの bullet の直後、``**Resolving `{{base_url}}` to localhost**:`` の直前に、`**bats-absent AC exclusion (patch route only):**` の段落を足す
  - Step 14: `**patch route (merge-to-main pattern):**` の段落 (`Follow "Exit: merge-to-main section". After push completes, transition the label ...`) の直後、`**patch route (XS/S common)**:` の直前に、`**CI-based bats AC confirmation (patch route, only when Step 10 deferred bats ACs):**` のブロックを足す。`**patch route (XS/S common)**:` の文は、このブロックが発火した場合はその後に Implementation Complete コメントを投稿するよう直す
- `tests/code.bats`: `step14_section` の抽出関数と新規テストを、既存の `# Language convention pre-commit check (Issue #1484)` ブロックの後に追加する (一覧は Implementation Step 3)
- `docs/workflow.md`: ``### 3. `/code` — Implementation`` の節で、``On completion, patch route posts an `## Implementation Complete` summary comment ...`` の段落の直後に 1 段落を足す
- `docs/ja/workflow.md`: 同じ段落の日本語版を、`完了時、patch route は ...` の段落の直後に足す (翻訳同期。`docs/translation-workflow.md`)
- [Steering Docs sync candidate] keyword "code" (`skills/code/SKILL.md` から導いた裸のスキル名) skipped: matched 1245 files (no discriminating power)。測定範囲: `grep -rl "code" docs/ tests/ scripts/ modules/` (全ファイル種別、`docs/spec/` と `docs/sessions/` を含む)
- [Steering Docs sync candidate] keyword "BATS_DEFERRED_ACS" (この Issue が導入する名前): 他の file にヒットなし (0 files、`docs/ tests/ scripts/ modules/ skills/`)。新規の手順変数で、他の文書に写す先は無い
- [Steering Docs sync candidate] keyword "Implementation Complete" (この Issue が触れる patch route の完了コメントの見出し): 履歴 (`docs/spec/` `docs/sessions/` `docs/reports/` `docs/stats/`) を除くと `docs/workflow.md` と `docs/ja/workflow.md` の 2 files で、上に挙げた
- [Outbound pointer sync candidate] なし: 追加する本文が指す先 (`modules/verify-executor.md` § "CI Reference Fallback"、`modules/verify-classifier.md` § "Patch Route CI Verification Note"、`modules/execution-context.md` § "Re-invocation Guarantee and Notification-Dependent Waiting"、`modules/ci-failure-classifier.md`) は、この Issue の変更で内容を変える必要が無い。確認内容は Notes
- Listing-side sub-check: 発火しない (subcommand の追加・削除なし、file の追加・削除・改名なし、ディレクトリ構成の変更なし)。`docs/structure.md` と `README.md` は対象外
- 変更しない (確認済み):
  - `modules/verify-executor.md` / `modules/verify-classifier.md` / `modules/verify-patterns.md` / `modules/test-runner.md` / `modules/execution-context.md`: 参照するだけ。`verify-executor.md` の CI Reference Fallback は「PR 番号が無ければ CI 参照は行わない」と自分の範囲を断っており (safe mode の fallback)、patch route の新手順 (commit キーの CI 参照) とは別の経路なので矛盾しない
  - `.github/workflows/test.yml`: job 名 (`Run bats tests`) と構造を確認しただけ。workflow の変更は CI Dependency Minimum Override (Size M 以上) を引き起こすため触らない
  - `docs/structure.md` / `README.md` / `CLAUDE.md` / `docs/guide/*.md`: `/code` の patch route の内部手順を述べる箇所が無い (`grep -nE 'patch|Implementation Complete|CI'` で `README.md` と `CLAUDE.md` は 0 件、`docs/guide/workflow.md` は `--patch` の使い方のみ)
  - `scripts/validate-skill-syntax.py` / `scripts/check-allowed-tools.sh`: 変更しない。検査器は script path と tool 名を見るだけで `gh` のサブコマンドは見ない (Notes 参照)

## Implementation Steps

1. `skills/code/SKILL.md` の frontmatter と Step 10 を編集する (→ AC1)
   - frontmatter の `allowed-tools` (1 行): `gh pr checks:*, gh run view:*, python3:*, bats:*` を `gh pr checks:*, gh run view:*, gh run list:*, gh run watch:*, python3:*, bats:*` に、`git branch:*, git merge-base:*, gh pr create:*` を `git branch:*, git merge-base:*, git rev-parse:*, gh pr create:*` にする
   - Step 10 の `**patch or operate route**` の bullet の `(it happens in Step 11)` を `(the push happens in Step 14's merge-to-main exit; Step 11 only commits)` にする。アンカー: `the push happens in Step 14`
   - Step 10 の CI verification AC exclusion の 2 つの bullet の直後に、次の段落を足す (字面どおり。英語のみ。半角 `!` を含めない):

````markdown
**bats-absent AC exclusion (patch route only):** when ROUTE is `patch`, check whether bats is installed before running verify-executor:

```bash
command -v bats
```

If nothing is printed (bats is not installed, which is typical of a headless execution environment), a pre-merge `command` AC whose command runs `bats` against files under `tests/` (for example `command "bats tests/foo.bats"`) cannot be evaluated here. Exclude every such AC from this Step's verify-executor pass and **do not check it off**: leave it as `- [ ]` (not in the checkbox-flip loop of result branch 1 below, not counted toward "all PASS"), and keep the list (index and condition text) as `BATS_DEFERRED_ACS` for the "CI-based bats AC confirmation" block in Step 14. A local approximation (for example `awk` / `grep -F` assertions standing in for the test body) is fine as your own early sanity check, but it is not evidence for the AC and must not be the basis for checking it off. Note the deferral in Step 12's Code Retrospective (`### Design Gaps/Ambiguities`) and Phase Handoff `### Deferred Items` as "pending post-push CI confirmation (Step 14)". When bats is installed, or on any other route, this exclusion does not apply and those ACs run in the verify-executor pass as usual.
````

   - Step 10 のアンカー (テストが見る): `bats-absent AC exclusion` / `command -v bats` / `BATS_DEFERRED_ACS` / `do not check it off` / `is not evidence for the AC` / `the push happens in Step 14`
2. (after 1) `skills/code/SKILL.md` の Step 14 に、CI による代替確認のブロックを足す (→ AC1, AC2, AC3)
   - 挿入位置は Changed Files のとおり。`**patch route (XS/S common)**:` の文は ``After push completes (and after the CI-based bats AC confirmation above, when it fired), post an `## Implementation Complete` summary comment ...`` に直す
   - 次のブロックを足す (字面どおり。`<...>` は実行時に値を字面で代入するプレースホルダ。Step 9 の `bats --jobs <N> tests/` と同じ流儀):

`````markdown
**CI-based bats AC confirmation (patch route, only when Step 10 deferred bats ACs):**

Fire condition: ROUTE is `patch`, the push above has completed, and `BATS_DEFERRED_ACS` from Step 10's bats-absent AC exclusion is non-empty. Otherwise skip this block entirely (no CI wait). Step 10 could not confirm those ACs because the commit that produces the CI run did not exist yet; now that it is pushed, the CI bats job's result stands in for the missing local bats run. Emit a progress line first so the watchdog resets its silence counter:

```bash
echo "progress: Confirming bats ACs against CI for issue #$NUMBER..."
```

1. **Resolve the pushed head SHA** as its own plain command (not via `$(...)`, which the worktree isolation guard refuses), then substitute the printed value literally in the commands below:

   ```bash
   git rev-parse origin/$BASE_BRANCH
   ```

   Do not use the worktree-local `HEAD`. A push gets one CI run, keyed on its head commit (here the retrospective commit), never on the implementation commit (`modules/verify-classifier.md` § "Patch Route CI Verification Note").
2. **Identify the bats job**: find the workflow under `.github/workflows/` whose job runs `bats`, and note the workflow file name and that job's `name:` (the job id when `name:` is absent), e.g. `test.yml` and `Run bats tests` in this repository. Apply the identity rule of `${CLAUDE_PLUGIN_ROOT}/modules/verify-executor.md` § "CI Reference Fallback (safe mode + PR number present)" (run command containment): the job's bats target (e.g. `tests/`) must contain each deferred AC's `bats` target, and an AC whose target is not contained stays unchecked. If no workflow runs `bats`, stop here: leave every deferred AC unchecked and report "no CI job runs bats; deferred to /verify".
3. **Find the run for the pushed commit**:

   ```bash
   gh run list --workflow=<workflow-file> --commit <SHA> --event push --limit 1 --json databaseId,status,conclusion
   ```

   All three filters are required: `--commit` alone also returns unrelated runs on the same SHA (for example issue-event automation workflows). If the result is `[]`, the run may not be registered yet; repeat the same command up to 2 more times as separate calls (no `sleep` loop), and if it is still empty treat it as "no run found" (see the table below).
4. **Wait for the run** (skip this when step 3 already reports `completed`), in the foreground with Bash `timeout: 600000` and never `run_in_background: true` (see Step 9's execution surface constraint):

   ```bash
   gh run watch <run-id> --compact --interval 30
   ```

   This repository's CI run takes roughly 3 to 5 minutes (189 to 277 seconds over the 25 most recent `main` runs, measured 2026-10-04), well inside the ceiling. `gh run watch` returns only when the whole run completes, including unrelated jobs, so a stalled unrelated job can hold it until the ceiling. If the tool backgrounds the command at the ceiling, treat the wait as ended and continue; never wait for its completion notification (`modules/execution-context.md` § "Re-invocation Guarantee and Notification-Dependent Waiting"). Do not use the watch's exit status as the verdict: it is run-level, which is why `--exit-status` is omitted.
5. **Read the bats job's own result**, however step 4 ended:

   ```bash
   gh run view <run-id> --json jobs --jq '.jobs[] | select(.name == "<bats job name>") | {status, conclusion}'
   ```

   The job's own result is the verdict: not the workflow run's (it also reflects unrelated jobs) and not a single step's (this repository's bats step is `continue-on-error`, and a serial re-run step decides the job's final result).
6. **Branch on the result (exhaustive)**:

   | Result of step 5 | Handling |
   |------------------|----------|
   | `status` is `completed` and `conclusion` is `success` | Confirmed. Check off each deferred AC that passed step 2's identity rule, using the checkbox procedure of Step 10 result branch 1 (if fetching the Issue body fails, skip the check-off and leave the ACs unchecked). In the Implementation Complete comment's `### Tests`, record: bats not run locally (unavailable), confirmed by CI job `<name>` (run URL, short SHA): success. |
   | `status` is `completed` and `conclusion` is anything else (`failure`, `cancelled`, `timed_out`, ...) | CI failure. Leave the ACs unchecked. Do not try to fix, revert, or force-push from here: the commit is already on the base branch, and continuing lets `/verify` re-evaluate the ACs and reopen the Issue on FAIL (classifying CI infrastructure failures is left to `modules/ci-failure-classifier.md` in `/verify`). Record the job name, conclusion, and run URL in `### Tests` and in the completion message, then continue to the comment and label transition below; do not exit non-zero. |
   | `status` is not `completed` (`queued` / `in_progress`), no run was found, the job is absent from the run, or any command above failed or returned unparsable output | Still running or unknown. Leave the ACs unchecked, deferred to /verify; do not wait further and do not re-run the wait. Record "CI result pending at /code time; bats ACs deferred to /verify" in `### Tests`, then continue. |

   Only a completed job with conclusion `success` ever checks an AC. Every other outcome leaves it `- [ ]`, so partial evidence can never produce a false PASS.
`````

   - Step 14 のアンカー (テストが見る): `CI-based bats AC confirmation` / `git rev-parse origin/$BASE_BRANCH` (かつ `$(git rev-parse` を含まない) / `gh run list --workflow=<workflow-file> --commit <SHA> --event push` / `gh run watch <run-id> --compact --interval 30` / `select(.name == "<bats job name>")` / `Still running or unknown` / `deferred to /verify` / `CI failure` / `do not exit non-zero` / `Only a completed job with conclusion`
   - fail-safe 重要度の境界条件 (Notes の判定): (a) 空入力 = `gh run list` が `[]` → 再試行 2 回の後に「run なし」として未チェックのまま委ねる。(b) 大きな入力 = `--limit 1` と `--json` の絞り込み、`gh run watch` は `--compact --interval 30` で出力を抑える。(c) 特殊文字 = job 名は jq の文字列リテラルとして渡し、一致しなければ「job が run に無い」として委ねる (日本語など多バイトの job 名も UTF-8 のまま一致する)。(d) 依存コマンドの失敗 (`git rev-parse`、`gh run list`、`gh run watch`、`gh run view`、Issue 本文の取得、出力の解釈不能) = すべて未チェックのまま委ねる。AC のチェックについては fail-closed (偽の PASS が危険側、`/verify` が最後の砦)、phase の進行については fail-open (abort も非 0 終了もしない)
   - 実装後、Allowed-tools Pre-commit Check (`${CLAUDE_PLUGIN_ROOT}/scripts/check-allowed-tools.sh skills/`) と `validate-skill-syntax.py` (Step 9 の追加検証) を通す。追記した本文は英語のみ (CI の `language-convention` job が検査する)、半角 `!` を含めない
3. (after 1, 2) `tests/code.bats` に新規テストを追加する (→ AC1, AC2, AC3 の決定的な裏付け)
   - 既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/code.bats` に下記 10 件) を追加したうえでスイートが PASS すること。`step10_section` は既存の関数を使い、`step14_section` を同じ形で足す: `awk '/^### Step 14:/{found=1} found && /^### / && !/^### Step 14:/{exit} found{print}' "$1"`
     1. `SKILL.md allowed-tools pre-approves gh run list, gh run watch and git rev-parse for the bats CI confirmation`: SKILL.md の先頭 6 行 (`head -6`) に `gh run list:*` / `gh run watch:*` / `git rev-parse:*` が含まれる
     2. `Step 10 excludes bats command ACs when bats is absent on patch route`: `step10_section` に `bats-absent AC exclusion` / `command -v bats` / `BATS_DEFERRED_ACS` が含まれる
     3. `Step 10 bats-absent exclusion leaves the AC unchecked and rejects approximations as evidence`: `step10_section` に `do not check it off` / `is not evidence for the AC` が含まれる
     4. `Step 10 CI AC exclusion places the patch route push in Step 14`: `step10_section` に `the push happens in Step 14` が含まれる
     5. `Step 14 documents the CI-based bats AC confirmation with gh run list and gh run watch`: `step14_section` に `CI-based bats AC confirmation` / `gh run watch <run-id> --compact --interval 30` / `BATS_DEFERRED_ACS` が含まれる
     6. `Step 14 CI confirmation resolves the pushed head SHA as a separate literal step`: `step14_section` に `git rev-parse origin/$BASE_BRANCH` が含まれ、`$(git rev-parse` は含まれない
     7. `Step 14 CI confirmation filters the run by workflow, commit and push event`: `step14_section` に `gh run list --workflow=<workflow-file> --commit <SHA> --event push` が含まれる
     8. `Step 14 CI confirmation reads the bats job conclusion rather than the workflow level result`: `step14_section` に `select(.name == "<bats job name>")` / `Only a completed job with conclusion` が含まれる
     9. `Step 14 CI confirmation defers to verify when CI is still running and handles CI failure without exiting`: `step14_section` に `Still running or unknown` / `deferred to /verify` / `CI failure` / `do not exit non-zero` が含まれる
     10. `Step 14 CI confirmation runs after the push and before the Implementation Complete comment`: `step14_section` 内で `CI-based bats AC confirmation` の行番号が `Implementation Complete comment (patch route, before label transition)` の行番号より小さい (どちらかが見つからないときは FAIL)
   - assertion の書き方は Notes の「新規テスト」に従う (`grep -qF ... || false`)。実装前 (SKILL.md が変更前の状態) に全 10 件が FAIL することを確認する (`/code` Step 8 の New Verification-Test Pre-implementation FAIL Check)。bats が無い環境では、`git show HEAD:skills/code/SKILL.md | grep -cF '<アンカー>'` が 0 件であることで代替し、実装後は `grep -cF` で各アンカーが 1 件以上あることを確認する
4. (parallel with 1, 2, 3) ドキュメントを同期する (→ 受入条件なし。SHOULD レベルの整合)
   - `docs/workflow.md` の ``### 3. `/code` — Implementation`` で、`## Implementation Complete` の段落の直後に次の段落を足す:

     ```markdown
     When bats is not installed in the execution environment (typical of a headless run), patch route cannot run `command "bats tests/..."` acceptance conditions locally, and Step 10 leaves them unchecked rather than judging them on a local approximation. After the push, `/code` waits (within the Bash tool's 10-minute ceiling) for the CI run of the pushed commit and, when that run's bats job succeeds, checks those conditions on the strength of the job's result; if the job fails, or CI is still running or does not report, they stay unchecked and `/verify` re-evaluates them.
     ```

   - `docs/ja/workflow.md` の同じ位置に日本語版を足す。括弧は半角で前後に半角スペースを入れる (グローバル規約)。例:

     ```markdown
     bats が実行環境に無い場合 (非対話の headless 実行など)、patch route は `command "bats tests/..."` 型の受入条件をローカルで実行できません。`/code` はこれらをローカルでの近似で判定せず、Step 10 では未チェックのまま残します。push 後に、push したコミットの CI run を (Bash ツールの 10 分上限の範囲で) 待ち、その run の bats ジョブが成功した場合に限り、ジョブの結果を根拠にこれらの条件をチェックします。ジョブが失敗した場合、または CI が実行中・結果を報告しない場合は未チェックのまま残り、`/verify` が再評価します。
     ```

   - 実装後に `bash scripts/check-translation-sync.sh` で `docs/ja/workflow.md` が IN_SYNC になることを確認する (commit 後にだけ正確)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md に、patch route で bats が実行環境に無いとき、push したコミットを含む CI run (gh run list / gh run watch) の bats ジョブ結果で bats tests/ 型の command AC を代替確認する手順が記載されている" --> bats 不在時に CI 結果で代替確認する手順が `/code` にある
- <!-- verify: rubric "追加された手順が、CI がまだ実行中の場合の扱い (待つか、未チェックのまま /verify に委ねるか) と、CI 失敗時の扱いを明記している" --> CI 実行中・失敗時の扱いが明記されている
- <!-- verify: grep "gh run watch" "skills/code/SKILL.md" --> `skills/code/SKILL.md` が `gh run watch` に言及している

### Post-merge

- bats の無い環境で patch route の Issue を `/code` したとき、`bats tests/` 型の AC が CI 結果をもとにチェックされることを観察する <!-- verify-type: opportunistic -->

## Notes

- **配置の判断 (Step 10 に除外、Step 14 に手順。補助文書には出さない)**: 手順を `skills/code/` の補助文書 (Domain file) に出す案は採らない。`docs/tech.md` の Progressive disclosure の基準 (その tool を使わない project にも要るか) では bats 固有の手順は補助文書向きだが、(1) AC1 の rubric は「`skills/code/SKILL.md` に手順が記載されている」を、AC3 は `skills/code/SKILL.md` への `grep "gh run watch"` を求めており、手順が補助文書にあると AC の文言を満たさない。(2) 発火条件 (patch route かつ bats 不在かつ持ち越し AC あり) を満たさない実行では CI 待機が 0 コストで、増えるのは SKILL.md の約 55 行 (893 行に対し約 6%) だけ。Issue の AC は `/spec` では変えられない (要件は `/issue` が確定済み)
- **Issue の自動解決事項への回答** (Issue 本文の `## Auto-Resolved Ambiguity Points` の 4 件):
  - 実施タイミング = push 後。patch route の push は Step 11 ではなく Step 14 の merge-to-main exit で起きる (Step 11 は commit まで) ため、手順は Step 14 に置く。Issue 本文の「Step 11 以降」と矛盾はしないが、具体的な位置は Step 14
  - 「bats が無い」の判定 = `command -v bats` が何も出力しない。既存の CLI 検出 (`modules/browser-adapter.md` と `modules/visual-diff-adapter.md` の `command -v browser-use`、`skills/issue/SKILL.md` の `--when="command -v lighthouse"`、scripts の `command -v timeout`) と同じ形で、新しい検出方式は導入しない。`bats --version` は `bats:*` が既に allowed-tools にある利点があるが、既存の検出パターンに揃えることを優先した。`command -v` は `modules/browser-adapter.md` (`/verify` と `/review` が読む) でも、どの SKILL.md も `command:*` を `allowed-tools` に挙げないまま実行している (Step 9 の `nproc 2>/dev/null || sysctl ...` も同様)
  - CI 実行中の扱い = 待つ (Bash ツールの 10 分上限の内側)。待ちきれなかった場合 (上限到達、run 未登録、ジョブ不在、コマンド失敗) は未チェックで `/verify` に委ねる。待つ案を採ったのは、CI が 189〜277 秒 (測定範囲: `gh run list --workflow=test.yml --branch main --limit 25` の `updatedAt - startedAt`、直近 25 件の `main` push run、全件 success、2026-10-04) で上限の 5 割以下に収まり、委ねるだけの案では `/code` が push した直後は CI がほぼ必ず実行中のため手順がほとんど効かないから
  - `allowed-tools` = `gh run list:*` / `gh run watch:*` を足す。`gh run view:*` と `gh api:*` は既にある。加えて、手順 1 の `git rev-parse` を #1484 の `git merge-base:*` の先例に合わせて `git rev-parse:*` として足す (どの SKILL.md にも `git rev-parse:*` は無いが、`/code` は `git log` なども allowed-tools に挙げずに使っており、足すのは非対話実行での事前承認のため)
- **Issue 本文と実装の食い違い** (light のため記録のみ):
  - Issue 本文は「`skills/code/SKILL.md` 本文に `gh run watch` を書くと `validate-skill-syntax.py` の allowed-tools 整合チェック (CI) が要求する」とするが、実際の検査器は `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` の参照と tool 名 (`KNOWN_TOOLS`) を見るだけで、`gh` のサブコマンドは検査しない (`validate_body_scripts_in_allowed_tools` / `validate_body_tools_in_allowed_tools`)。`allowed-tools` の更新は CI のためではなく、非対話実行 (`claude -p --permission-mode auto`) での事前承認のために要る。結論 (allowed-tools を更新する、専用の AC は足さない) は変わらない。AC の文言は変えない
  - `skills/code/SKILL.md` Step 10 の既存の記述 `(it happens in Step 11)` は、patch route の push が Step 11 で起きるように読め、Step 11 本体の `Push is done in Step 14 Worktree Exit` と食い違う。新手順は push 後の位置を Step 14 とするので、同じ段落の記述を `the push happens in Step 14` に直す (Implementation Step 1)。この文言を固定するテストは他に無い (`grep -rn 'it happens in Step 11' tests/ skills/ modules/ docs/` は `skills/code/SKILL.md` のみ)
- **run の特定 (`--commit` を使う理由と条件)**: `modules/verify-classifier.md` § "Patch Route CI Verification Note" は、`github_check` の verify command に `--commit=<固定の実装 commit の SHA>` や `git rev-parse HEAD` を使う形を退けている (push は head commit にだけ run を作る。実装 commit 自身には run が無い。`/verify` の worktree の `HEAD` は push 済みとは限らない)。同じ note は「`--commit=` を使う場合は push 済みの先頭の SHA (`git rev-parse origin/main`) を先に確定する」と述べており、この手順はその条件を満たす。`/code` は push の直後で、その SHA を確定できる。`--event push` と `--workflow` の併用が要る理由 (`--commit` だけだと `Kanban Automation` など `issues` イベントの run も同じ SHA で返る) は 2026-10-04 に `b774f31c` で実測した (`--limit 10` の上限まで返り、いずれも `event: issues` の `Kanban Automation`)
- **判定の単位 (ジョブ単位)**: workflow run 全体の結論は無関係なジョブ (`Forbidden Expressions check` など) の失敗でも `failure` になる (`modules/verify-patterns.md` §7 の job-level sub-form が既出の問題。#733 / #738 で繰り返し発火)。step 単位も不可: この repo の `Run bats tests` step は `continue-on-error: true` で、並列実行だけの失敗は後続の直列再実行 step が最終結果を決める。したがって bats ジョブ (job) 自身の `status` / `conclusion` を見る。`gh run watch` は run 全体の完了を待つので、無関係なジョブ (例: 2026-08-07 の `macOS shell compatibility` の QUEUED 停滞、`docs/sessions/89790-1786027911-2026-08-07/session.md`) が止まると上限まで待つが、その場合も手順 5 がジョブ単位で読むので、bats ジョブが完了していれば確定できる
- **どの AC を代替できるか**: `modules/verify-executor.md` § "CI Reference Fallback" の同一性確認 (run command containment: CI ジョブの bats の対象 (例 `tests/`) が AC の `bats` の対象を含む) を再利用し、文言を重複させない。含まれない AC は未チェックのまま `/verify` に委ねる
- **fail-safe 重要度の判定: 該当 (ゲート相当)**: 実装対象は Markdown の手順で script は変更しないが、「CI の結果を根拠に AC をチェックするか」を決める手順で、偽の PASS が危険側になる。境界条件は Implementation Step 2 に明記した (空入力、大きな入力、特殊文字、依存コマンドの失敗)。要点: チェックするのは「完了したジョブの結論が `success`」のときだけ。それ以外は全て未チェックのまま `/verify` に委ねる (AC のチェックは fail-closed、phase の進行は fail-open)。CI 失敗でも abort や非 0 終了はしない: コミットは既に base に入った有効な成果物で (`reconcile-phase-state.sh` の `code-patch` の完了判定も push 済みの `closes #N` コミットで成立する)、手順の後ろにある Implementation Complete コメントと `phase/verify` への遷移が行われないまま abort すると、Issue が `phase/code` に取り残され、wrapper も phase の失敗として扱う。`/verify` が AC を再評価して FAIL で reopen する既存の経路に載せる。pr route の Step 13 の escape hatch (「commit と PR は既に有効な成果物で、`/review` が CI 失敗を検出し続ける」) と同じ考え方
- **新規テスト (bats test の入力形式)**: 必要な新規テストケースは Implementation Step 3 の 10 件 (frontmatter 1 件、Step 10 が 3 件、Step 14 が 6 件)。`tests/code.bats` は section 抽出関数 + 文字列一致の構造テストで、入力は `skills/code/SKILL.md` の本文 (`step10_section` / `step14_section` で抽出)。新規の assertion は bare `[[ ... ]]` ではなく `grep -qF ... || false` か `[ ... ] || false` を使う (`skills/code/skill-dev-validation.md` の "Bash 3.2: Bare `[[ ]]` Assertions Do Not Propagate `set -e`")。否定 (`$(git rev-parse` を含まない) は `if grep -qF '...'; then false; fi` の形にする (`modules/test-runner.md` の bats Negation Assertion Pitfall)。`@test` 名は ASCII の英語。パターン検出 script のテスト fixture による自己参照、`WHOLEWORK_SCRIPT_DIR` の mock、新規 script の追加は無いので、それらの確認項目は該当しない
- **挿入本文の事前検証 (2026-10-04)**: Implementation Steps 1・2 の字面どおりの英文を、実ファイルを変えずに一時コピーの `skills/code/SKILL.md` へ適用して確認した。(1) `scripts/validate-skill-syntax.py` は変更前・変更後ともに 0 error / 0 warning。(2) Implementation Step 3 の 10 件の想定 assertion は、変更前は全件 FAIL、変更後は全件 PASS。(3) 挿入文に日本語の文字 (CJK) と非推奨語は無い。挿入は Step 10 が 7 行、Step 14 が 46 行で、`skills/code/SKILL.md` は 893 行から 948 行になる。字面を変える場合は、Implementation Step 1・2・3 に列挙したアンカー文字列を保つこと
- **bats が未インストール**: この環境では `command -v bats` が何も出力しない (2026-10-04 確認。GNU `parallel` も無く、`timeout` はある)。`/code` を同じ種類の環境で実行すると、新規テスト 10 件とスイート全体は実行できない可能性が高い。その場合は Implementation Step 3 のとおり `grep -cF` で各アンカーを直接確認し、bats の実行は push 後の CI の `Run bats tests` job に任せ、Code Retrospective に「bats 未実行」と書く。この Issue 自身の `/code` は変更前の SKILL.md で動くため、この Issue が足す新手順は自分自身には使えない (新規テストの CI 結果の確認は従来どおり)
- **未確認事項 (Uncertainties。検証方法と影響範囲)**:
  - 非 TTY での `gh run watch --compact --interval 30` の出力量: `gh` は非 TTY では画面をクリアしないため、interval ごとに全体を再出力すると想定している (未計測。完了済み run では `Run Test (...) has already completed with 'success'` の 1 行を出して exit 0 になることだけを 2026-10-04 に確認した)。影響範囲は context の消費のみ (判定には影響しない)。対処は `--compact` と interval 30 秒 (CI 約 4 分で最大 10 回程度)。検証は post-merge の opportunistic AC の観察時に出力量を見る。想定より大きければ interval を延ばす follow-up にする
  - push 直後の run の登録遅延: `gh run list` が `[]` を返す時間の長さは未計測。対処は 2 回までの再実行 (各回が別の tool call) の後、「run なし」として委ねる (fail-safe)。影響範囲は手順 3 のみ
  - `--commit` / `--event` / `--workflow` のフラグは gh 2.101.0 (この環境) で実在を確認 (`gh run list --help`)。古い `gh` で未対応の場合はコマンド失敗として扱い、未チェックのまま委ねる (fail-safe)
- **verify command の扱い**: Pre-merge の 3 件は Issue 本文 (SSoT、`modules/verify-patterns.md` §18) をそのまま写した。AC3 の `grep "gh run watch" "skills/code/SKILL.md"` は、実装前は 0 件 (2026-10-04 に `grep -c` で確認) で FAIL、実装後は Step 14 のコードブロックにその文字列が入るので PASS になる。ERE のメタ文字は含まない。AC1 / AC2 の rubric には数値リテラル・定数名が無いので、`file_contains` の併記は要らない。決定的な裏付けは Implementation Step 3 のテスト (アンカー文字列) が担う
- **verify-type の確認**: Post-merge の `opportunistic` は `modules/verify-classifier.md` の定義 (「`/skill-name` を実行したときに X を確認する」形) に合う。確認は、bats の無い環境で patch route の `/code` が走ったとき (`/code` Step 15 の Opportunistic Verification)
- **premise マーカー**: Issue 本文の `<!-- premise: grep_count "gh run watch" "skills/code/SKILL.md" -eq 0 -->` は、この Issue の実装で `skills/code/SKILL.md` に `gh run watch` が入るため必ず失効する (実装前の状態を記録するマーカーとして想定どおり)。post-merge の opportunistic AC を待つ間 Issue は `phase/verify` で open のままなので、`/audit premise` (この repo は `autonomy: L3`) が "Premise Expired" のコメントを自動投稿する可能性がある。想定内で対応不要。Issue 本文のマーカーは Spec からは変更しない
- **Size の再評価**: 確定の Changed Files は 4 件 (`skills/code/SKILL.md`、`tests/code.bats`、`docs/workflow.md`、`docs/ja/workflow.md`)。軸 1 は M (3-5 件)、軸 2 は既存パターンの横展開 (Step 13 の CI 待機、Step 10 の CI AC 除外、`verify-executor.md` の CI Reference Fallback を組み合わせる。script ロジックの変更なし) で -1 となり S。triage 時の Size S から変更なし (patch route)。CI Dependency Minimum Override は該当しない: `.github/workflows/*.yml` を変更せず、手順は CI の結果を読むだけで、どの失敗経路も未チェックのまま委ねる fail-safe なので、手順の不具合が main を壊すことはない (新規テストの誤りは CI で検出され、追加コミットで直せる。構造テストで、アンカーは Spec の字面どおりに書く)
- **その他の確認結果**:
  - 監査・調査型の Issue ではない (新しい手順の実装)
  - 外部 package の追加なし (依存バージョンの確認は不要)。adapter パターンの調査は不要 (verify command は built-in の `rubric` / `grep` のみ)
  - allowed-tools impact chain check: 新規の `scripts/*.sh` も `modules/*.md` の変更も無いので該当しない。`skills/code/SKILL.md` 自身の `allowed-tools` の更新は Implementation Step 1
  - Step 9 の bats 不在時の扱い (ローカル実行が command-not-found になったときの判定) は SKILL.md に明文が無く、この Issue も変えない (対象は AC の確認経路)。実際には Code Retrospective に「bats 未インストールで実行できなかった」と記録して進めている (#1484 など)
  - pr route は対象外。bats が無い pr route では `/review` が PR の CI を参照して確定する (Issue 本文の Background、`modules/verify-executor.md` § "CI Reference Fallback")
  - Phase Handoff との関係: `### Deferred Items` に書いた持ち越し AC は、Read Procedure の Deferred Items staleness check (`modules/phase-handoff.md`) が現在の AC のチェック状態と突き合わせるので、Step 14 で確定した AC が古い記述のまま使われることはない
  - 追記する本文の制約: SKILL.md 本文は半角 `!` を含めない (`validate-skill-syntax.py` の `validate_shell_sensitive_chars`)、`skills/` は英語指定のパスで日本語を含めない (`scripts/check-language-convention.py`)、非推奨語 (`docs/product.md` § Terms の Formerly called) を使わない (`scripts/check-forbidden-expressions.sh`、この Spec も `docs/spec/` として検査される)

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective / https://github.com/saitoco/wholework/issues/1490#issuecomment-5976638245

## Code Retrospective

### Deviations from Design
- なし。Implementation Step 1〜4 を Spec の字面どおりに実装した (frontmatter と Step 10 と Step 14 の挿入文、`tests/code.bats` の新規 10 件、`docs/workflow.md` と `docs/ja/workflow.md` の 1 段落)。

### Design Gaps/Ambiguities
- Spec は `step10_section` を「既存の関数」としていたが、`tests/code.bats` には無かった (他の bats ファイルの定義と取り違えたとみられる)。`step14_section` と同じ形で `tests/code.bats` に新規定義した。テストの内容には影響しない。
- bats 未インストール (`command -v bats` が何も出力しない、GNU `parallel` も無い) のため、新規テスト 10 件とスイート全体はローカルで実行できなかった。Spec の指示どおり、実装前の SKILL.md に対する各アンカーの `grep -cF` が 0 件 (= 新規テストは実装前に FAIL する構造) であること、実装後は 16 アンカーが 1 件以上あり、`$(git rev-parse` が 0 件であることを直接確認した。bats の実行は push 後の CI の `Run bats tests` job に委ねる。
- この Issue の Pre-merge AC には `bats tests/` 型の `command` AC が無いため、Step 10 の bats-absent 除外 (この Issue が足す手順) は対象 0 件で、Step 14 の CI 確認も発火しない (自分自身の手順は、実装前の SKILL.md で動くため使えない)。

### Rework
- なし。

### Verification Notes
- Confirmed pre-implementation FAIL for 10 new test(s) (構造: 各アンカーが変更前の SKILL.md に 0 件。bats の実行そのものは未実施、上記のとおり)。
- `validate-skill-syntax.py` 0 error / 0 warning、`check-forbidden-expressions.sh` 違反なし、`check-language-convention.py` 違反なし (merge base からの diff)。`check-bare-bracket-assertions.sh` の警告は既存テスト由来で、新規テストは `|| false` 形式。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 手順は Spec どおり Step 10 (除外) と Step 14 (push 後の CI 確認) に分けて `skills/code/SKILL.md` に置いた。補助文書へは出していない (AC の rubric / grep が SKILL.md を直接指すため)。
- AC のチェックは「完了した bats job の conclusion が success」のときだけ行い、それ以外は未チェックのまま `/verify` に委ねる (fail-closed)。phase の進行は止めない (fail-open)。

### Deferred Items
- なし。この Issue の Pre-merge AC 1〜3 は Step 10 でチェック済み。Post-merge の opportunistic AC (bats の無い環境の patch route で CI 確認が働くことの観察) は未チェックのまま。

### Notes for Next Phase
- 新規テスト 10 件はローカルの bats で未実行。`/verify` は push 後の CI の `Run bats tests` job の結果を確認すること。
- `gh run watch --compact --interval 30` の非 TTY での出力量は未計測 (Spec の Uncertainties)。次に bats の無い環境で patch route の `/code` が走ったときに観察する。
