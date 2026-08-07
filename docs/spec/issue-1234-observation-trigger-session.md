# Issue #1234: observation-trigger: --session を追加し /auto から実行文脈を伝播

## Overview

`/auto` の Event-based observation scan は `observation-trigger.sh --event auto-run` を `--facts-file` 無指定で呼ぶため、`opportunistic-search.sh` の `resolve_run_facts()` は `collect-run-facts.sh` を引数なしで実行する。この場合のセッション解決順序は `AUTO_SESSION_ID` env var → `.tmp/auto-session-current` pointer file だが、並行セッション下ではこの pointer file が上書きされる (#1075)。実測 (session `33233-1786023637`) では、fail-open (ゲート無効化) と別セッションの facts を掴む両方の失敗モードが確認され、`when=` 実行文脈ゲートが正規経路で機能していなかった。

本 Issue は `--session <id>` を `observation-trigger.sh` → `opportunistic-search.sh` → `collect-run-facts.sh` へ明示的に伝播させ、`skills/auto/SKILL.md` の呼び出し側で `SESSION_ID` を渡すことでこの伝播ギャップを解消する。`--session` 未指定時は既存の解決順序 (env var → pointer file → fail-open) を維持し後方互換を保つ。親 Issue #1118 の AC 2 (`when=route:operate` ゲートの観察) はこの Issue の着地が前提になっている。

## Changed Files
- `scripts/observation-trigger.sh`: `--session <id>` オプションを追加し、既存の `--facts-file` / `--context-file` と同じ受け渡し形で `opportunistic-search.sh` へ透過的に渡す。bash 3.2+ compatible (既存の case 文パターンを踏襲、新規 bash4+ 依存なし)
- `scripts/opportunistic-search.sh`: `--session <id>` オプションを追加し、`resolve_run_facts()` 内で `--facts-file` 優先・`--session` 次点・無指定時は既存の引数なし呼び出しにフォールバックする 3 分岐に変更。bash 3.2+ compatible
- `skills/auto/SKILL.md`: XL/single route (`### Step 5: Completion Report` 内、observation scan 呼び出し) と batch route (`### Batch Completion Report` 内、同呼び出し) の計 2 箇所で `--event auto-run` 呼び出しに `--session <literal SESSION_ID value from step 1>` を追加
- `modules/observation-trigger.md`: Trigger Interface の引数テーブルと「Arguments table addition (both scripts)」テーブルに `--session <id>` の行を追加 (Steering Docs sync candidate 相当 — `docs/`/`tests/`/`scripts/` を対象とする機械的 grep チェックの対象外である `modules/` 配下だが、両スクリプト自身のコメントがこのファイルを参照ドキュメントとして名指ししているため、直接調査で発見し追加する)
- `tests/observation-trigger.bats`: 既存の `--facts-file` / `--context-file` 向け "forwarding:" テスト対 (L130-142) と同型で `--session` の forwarding テストを追加
- `tests/opportunistic-search.bats`: `resolve_run_facts()` が `--session` を `collect-run-facts.sh --session <id>` へ引き渡すこと、および `--facts-file` 同時指定時は `--facts-file` が優先されることを検証するテストを追加。既存の `collect-run-facts.sh` モック (setup() L37-41) を、`gh` モックの `gh-list-args.txt` ロギング (L17-24) と同様に呼び出し引数をログするよう拡張する

## Implementation Steps

1. `scripts/observation-trigger.sh` に `--session <id>` のパース (`--facts-file` と同じ必須引数チェック) を追加し、値が非空のとき `SEARCH_ARGS+=(--session "$SESSION_ID")` として `opportunistic-search.sh` へ転送する (既存の `--context-file`/`--facts-file` の条件付き追加パターンと同型) (→ acceptance criteria 1)
2. `scripts/opportunistic-search.sh` に `--session <id>` のパースを追加し `SESSION_ARG` に保持する。`resolve_run_facts()` の facts 解決部を次の3分岐に変更する: `FACTS_FILE` が非空ならそれを使用 (既存動作を維持し優先順位を保つ) → そうでなく `SESSION_ARG` が非空なら `"${SCRIPT_DIR}/collect-run-facts.sh" --session "$SESSION_ARG" 2>/dev/null || true` を実行 → どちらも空なら既存どおり `"${SCRIPT_DIR}/collect-run-facts.sh" 2>/dev/null || true` を無引数実行 (この最終分岐が現状のまま残ることが `--session` 未指定時の後方互換 — `collect-run-facts.sh` 自身の `AUTO_SESSION_ID` env var → `.tmp/auto-session-current` → fail-open ラダーがそのまま働く) (→ acceptance criteria 2, 3, 6)
3. `skills/auto/SKILL.md` の2箇所 — `### Step 5: Completion Report` 内 (XL/single route observation scan 呼び出し) と `### Batch Completion Report` 内 (batch route observation scan 呼び出し) — の `Run ${CLAUDE_PLUGIN_ROOT}/scripts/observation-trigger.sh --event auto-run` を `Run ${CLAUDE_PLUGIN_ROOT}/scripts/observation-trigger.sh --event auto-run --session <literal SESSION_ID value from step 1>` に変更する。同ファイル内で既に使われている `--session-id=<literal SESSION_ID value from step 1>` (Skill(wholework:verify) dispatch 向け) と同じ literal 埋め込み方式を踏襲する (→ acceptance criteria 4, 5)
4. `modules/observation-trigger.md` の Trigger Interface 引数テーブル (`--facts-file <path>` 行の直後) と「Arguments table addition (both scripts)」テーブルに、Step 1-2 で実装した挙動を説明する `--session <id>` 行を追加する (parallel with 1, 2, 3)
5. `tests/observation-trigger.bats` に `--session` forwarding テスト (既存 `--facts-file` テスト対と同型)、`tests/opportunistic-search.bats` に `resolve_run_facts()` の `--session` → `collect-run-facts.sh --session` 引き渡しテストと `--facts-file` 優先テストを追加する。後者のテストが引数を検証できるよう `collect-run-facts.sh` モックを拡張し、呼び出し引数をログファイルへ記録するようにする (after 1, 2) (→ acceptance criteria 7, 8)

## Verification

### Pre-merge
- <!-- verify: file_contains "scripts/observation-trigger.sh" "--session" --> `observation-trigger.sh` が `--session` オプションを受け付ける
- <!-- verify: file_contains "scripts/opportunistic-search.sh" "--session" --> `opportunistic-search.sh` が `--session` オプションを受け付ける
- <!-- verify: rubric "scripts/opportunistic-search.sh の resolve_run_facts() が、--session で渡された id を collect-run-facts.sh --session へ引き渡している。--facts-file が同時指定された場合は --facts-file を優先する既存の優先順位が維持されている" --> `--session` が `collect-run-facts.sh` へ引き渡され、`--facts-file` 優先が維持されている
- <!-- verify: section_contains "skills/auto/SKILL.md" "Step 5: Completion Report" "--event auto-run --session" --> `skills/auto/SKILL.md` の XL/single route (L745 付近) の observation scan 呼び出しに `--session` が含まれている
- <!-- verify: section_contains "skills/auto/SKILL.md" "Batch Completion Report" "--event auto-run --session" --> `skills/auto/SKILL.md` の batch route (L1215 付近) の observation scan 呼び出しに `--session` が含まれている
- <!-- verify: rubric "--session 未指定時に従来どおり AUTO_SESSION_ID env var → .tmp/auto-session-current → fail-open の順で解決される後方互換が、テストまたは実装コメントで確認できる" --> `--session` 未指定時の後方互換が維持されている
- <!-- verify: command "bats tests/observation-trigger.bats" --> `tests/observation-trigger.bats` が PASS する
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (bats テスト) が pass する

### Post-merge
- 次に `/auto` が完走した際の observation scan で、`collect-run-facts.sh` が当該セッションの `session_id` を返し、`when=` ゲートが `run facts unavailable` 警告なしに評価されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **SPEC_DEPTH=light 自動判定**: Size=S (patch route) のため `--light`/`--full` 未指定でも light に auto-detect。Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) は light のためスキップ。Issue 本文の "Auto-Resolved Ambiguity Points" も「なし」と明記済み
- **Simplicity rule 超過**: Pre-merge Verification は 8 items で light 上限 (5) を超過するが、Issue body の Acceptance Criteria (8 items、triage で verify command 修正済み) を verbatim コピーする Verify command sync rule (`modules/verify-patterns.md` §18) を優先し全量を転写した。既存 Spec (issue-600, issue-1062, issue-163 等) と同じ扱い。Implementation Steps は 5 件に収まるようグルーピングした
- **Patch route 検証**: Size=S、`.wholework.yml` に `always-pr` 未設定 (`ALWAYS_PR=false`) のため patch route。AC 8 は triage 時点で既に `github_check "gh run list ..." "success"` 形式に修正済み (`gh pr checks` 不整合は発生しない) — 本 Spec 作成時点での自動修正は不要
- **`modules/observation-trigger.md` 追加の経緯**: Step 10 の Steering Docs sync candidate check は `docs/`/`tests/`/`scripts/` を対象とする機械的 grep であり `modules/` 配下は対象外だが、`scripts/opportunistic-search.sh` 自身のコメントが `--facts-file`/`when=` の挙動について "See modules/observation-trigger.md § Condition Check Gate (when=)" と明記しているため、直接調査で発見し Changed Files に追加した
- **「変更不要」と判定したファイル (grep で事前確認済み)**: `docs/structure.md`・`docs/guide/customization.md` (スクリプトの一般的な説明のみで CLI フラグ単位の記述なし) / `docs/migration-notes.md` (private repo → public repo 移行時点の履歴記録であり `ssot_for: migration-interface-changes` は当該移行の Interface Changes 追跡用、本 Issue のような通常の機能変更の対象ではない) / `scripts/claude-watchdog.sh` (`--event watchdog-kill` 呼び出しで `--facts-file` も渡しておらず、`--session` も同様に不要と判断) / `scripts/get-config-value.sh` (コメント内の言及のみ) / `tests/verify.bats` (`opportunistic-search.sh --event` という文字列が別ドキュメント節に含まれるかを見るテストで CLI 引数とは無関係)
- **bash 互換性**: `scripts/observation-trigger.sh` / `scripts/opportunistic-search.sh` はいずれも既存の `case` 文ベースの引数パースを踏襲するため bash 3.2+ (macOS system bash) 互換を維持する

## Consumed Comments
- saito (MEMBER, first-class): triage フェーズの Issue Retrospective。タイトル正規化 (体言止め)、AC 8 の `github_check` 修正 (patch route 対応) と AC 4/5 の `section_contains` 修正 (見出し不一致・`--session-id` 部分文字列誤マッチの回避) を記録。両修正は現行の Issue 本文 AC に既に反映済みで、本 Spec の Verification はその反映後の内容を検証コマンド同期ルールに従い転写した — https://github.com/saitoco/wholework/issues/1234#issuecomment-5212780239

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — the `review-light` agent (Perspective 1: Spec Deviation) confirmed the PR diff matches this Spec's Implementation Steps closely: `--session <id>` propagates `observation-trigger.sh` → `opportunistic-search.sh` → `collect-run-facts.sh --session <id>` exactly as planned, `--facts-file` priority and no-argument backward compatibility are preserved, and both `skills/auto/SKILL.md` call sites received the literal `SESSION_ID` embedding.

### Recurring issues

Two independent tooling bugs surfaced while executing this review, both out of this PR's own scope but worth follow-up:

- `scripts/gh-issue-edit.sh --checkbox <indices>` counts every `- [ ]`/`- [x]`-shaped line in the raw Issue body, including one quoted inside a fenced code block in the Background section (a verbatim quote of parent Issue #1118's own AC 2). This produced an off-by-one: `--checkbox 1,2,3,4,5,6,7 --check` marked the quoted decoy line instead of the real AC 7, requiring a manual `--uncheck`/`--check` correction pass. Any `/review` or `/verify` run against an Issue body that quotes another Issue's checklist in a code block is at risk of the same drift.
- `scripts/gh-pr-review.sh`'s self-review 422 fallback (`grep -qi "request changes on your own pull request"` against captured `gh api` stderr) never triggers in practice: `gh api ... --method POST --input - 2>&1 >/dev/null` only captures `gh: Unprocessable Entity (HTTP 422)`, not the detailed JSON error body (`errors: ["Review Can not request changes on your own pull request"]`) that the grep pattern needs. Every `/review` run where the PR author and the authenticated `gh` account are the same user (a normal occurrence for solo-maintained repos) hits this silently-broken fallback and fails Step 11 outright unless manually worked around, as happened here.

### Acceptance criteria verification difficulty

AC 8 (`<!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" -->`) could not be verified in `/review` safe mode: `github_check`'s safe-mode allowlist covers `gh run view` but not `gh run list`, so the condition returned UNCERTAIN regardless of actual CI state. Separately, the condition's target (the latest run on `main`, not on the PR branch) reads as an odd choice for a Pre-merge condition — worth a closer look at `/verify` time to confirm whether checking `main`'s CI post-merge was the intended semantics or a spec-authoring slip that should have targeted the PR branch instead (duplicating what Step 9's own CI status check already covers).

The Base Branch Conflict Pre-check (Step 10) proved its value here: it flagged a real adjacency risk between this PR's `--session` hunks and `origin/main`'s Issue #1220 `resolve_filtered_context()` hunks in `scripts/opportunistic-search.sh`. The risk did not materialize (`git merge origin/main` auto-resolved cleanly with no conflict markers, confirmed by re-running both affected bats files), but treating the flag as a MUST and resolving it by actually merging and re-testing — rather than dismissing it as a false positive — is the correct default when the pre-check's adjacency heuristic cannot itself prove a real merge would be clean.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC gate (`check-pre-merge-ac.sh`) found all 8 conditions `[x]` at merge time — AC 8, left `[ ]`/UNCERTAIN at the end of the review phase, was resolved before this merge ran, so no override marker was needed
- `gh pr merge --squash --delete-branch` succeeded but its local-branch deletion step failed because an unrelated active worktree (`.claude/worktrees/code+issue-1234`) still checked out `worktree-code+issue-1234`; resolved by deleting the remote branch directly (`git push origin --delete worktree-code+issue-1234`) and leaving the unrelated local worktree/branch untouched rather than force-removing another session's in-progress work
- Squash commit `9004ae05` merged cleanly to `main`; no conflict resolution was needed at this phase

### Deferred Items
- The two tooling bugs recorded in `## review retrospective` § Recurring issues (`gh-issue-edit.sh --checkbox` fenced-code-block off-by-one; `gh-pr-review.sh` self-review 422 fallback never matching) remain unfiled — still worth triage as follow-up Issues
- The local branch `worktree-code+issue-1234` and its worktree at `.claude/worktrees/code+issue-1234` were left in place (still in use by another session) even though the remote counterpart is now deleted — no action needed unless that session's work turns out to be stale

### Notes for Next Phase
- `/verify 1234` should confirm the post-merge observation condition (`verify-type: observation, event=auto-run, session=next`) — the next `/auto` run's observation scan should show `collect-run-facts.sh` resolving the correct `session_id` without a `run facts unavailable` fail-open warning
- No conflict resolution, test re-runs, or manual AC overrides were needed during this merge — the PR was clean going in

## Verify Retrospective

Pre-merge 8 件全 PASS、Post-merge 1 件 SKIPPED (observation 未発火)。

### 実装の機能は observation を待たずに確認できた

AC 9 は `event=auto-run` 未発火のため SKIPPED だが、`--session` 伝播が実際に効くかは直接実行で確認した。

```
$ bash scripts/collect-run-facts.sh --session 3340-1786079730
{"session_id":"3340-1786079730","mode":"unknown","issues":[]}
```

`session_id` が当該セッションの値で返っており、修正前の実測 (別セッションの facts / `run facts unavailable` fail-open) は解消されている。**observation AC は「実運用で効くこと」を待つ条件であり、「実装が正しいこと」は別途機械的に確認できる** — この 2 つを分けて記録しておくと、observation が長期 SKIPPED でも実装の妥当性は追跡できる。

### `collect-run-facts.sh` の CWD 依存 (本 Issue のスコープ外)

上記実行では `issues: []` / `mode: "unknown"` となり、`opportunistic-search.sh` が 3 番目のガード (`carry no run context`) でゲートを無効化した。原因は `/verify` の worktree CWD から実行したことで、`collect-run-facts.sh` は `.tmp/auto-events.jsonl` を CWD 相対で読むが worktree にはこのファイルが存在しない (gitignored)。

親リポ CWD からは正しく `mode: "single"` と tokens が入る (本セッション前半で実測)。`/auto` の observation scan は親リポ CWD で走るため正規経路では影響しないが、worktree から呼ぶ経路が増えた場合の落とし穴になる。

### AC 8 の semantics 問題 — review の指摘どおりだった

review retrospective が「AC 8 の対象 (`main` の最新 run) は Pre-merge 条件として奇妙、`/verify` 時に確認を」と残していた。確認した結果、**指摘は正しい**。

本 Issue は Size M の pr route なので検証したいのは PR #1246 自身の CI だが、AC 8 は `--branch=main` を指定して main の run を見ている。実測では両方 PASS だったため結果は一致したが、この AC は意図した対象を見ていない。

原因は Size 再評価時に AC 形式が追随しなかったこと:

| 時点 | Size | route | AC 8 の形式 |
|---|---|---|---|
| `/issue` triage | S | patch | `gh run list --branch=main` (patch route の SSoT 推奨形、#1212) |
| `/spec` 再評価 | **M** | **pr** | patch route 形式のまま据え置き |

pr route なら `gh pr checks` が適切で、その形式なら `/review` の safe mode でも判定できた (下記)。

### `gh run list` が safe mode allowlist に含まれない

`/review` は AC 8 を UNCERTAIN と判定した。`modules/verify-executor.md` の `github_check` safe mode allowlist は `gh issue view` / `gh pr view` / `gh pr checks` / `gh api` (GET) / `gh run view` の 5 つで、**`gh run list` が入っていない**。

#1212 が patch route の推奨形を `gh run list --branch=main --limit=1` に一本化したが、この形は `/review` では常に UNCERTAIN になる。patch route の Issue は `/review` を経ないため実害は出にくいが、本 Issue のように Size 再評価で pr route へ移った Issue では review が判定不能になる。

### merge gate が 2 度ブロックし、2 度とも実測で解消した

| 回 | ブロック理由 | 解消 |
|---|---|---|
| 1 | AC 8 未チェック | `gh run list --branch=main` と `gh pr checks 1246` を両方実測 → 両方 PASS → checkbox 更新 |
| 2 | AC 9 未チェック | index の off-by-one に気づき、真の CI AC (index 9) を更新 |

いずれも override ではなく実測で通した。2 回目は下記の off-by-one が原因。

### checkbox index の off-by-one を親セッションも踏んだ

review retrospective が既に記録していた問題 (`gh-issue-edit.sh --checkbox` が fenced code block 内の checkbox も数える) を、親セッションも merge 時に踏んだ。Background に引用した親 Issue #1118 の AC 2 が index 1 を占め、Pre-merge AC が 2〜9 にずれていた。

`--checkbox 8` を実行した際に「AC 8 をチェックしたのに gate は #9 が未チェックと言う」という食い違いが生じ、原因特定に merge 2 往復を要した。**gate のエラーメッセージが index しか出さない**ことも一因:

```
Error: 1 unchecked pre-merge acceptance conditions on issue #1234.
```

`/merge` SKILL の Step 1 は interactive mode の「Present and decide」で `#<index> <text>` を出力する規定があるので、非対話モードの `decision=blocked` パスでも同じ情報を出せば即座に特定できた。

対応 Issue は **#1071** (`issue: fenced code block 内の checkbox を AC 列挙から除外`、OPEN) が既存。review が「remain unfiled」と記録していたが、実際には #1071 でカバーされている。

### PR 検索の誤ヒット (#1202 の実例)

`/verify` Step 2 の `gh pr list --search "closes #1234" --state merged` が 2 件返し、`.[0]` として**無関係な #1247 が採用された**。PR #1247 の本文に `/auto 1234` と `#1234` が含まれる (本 Issue の code phase 失敗を実測記載したため) ことで、全文検索が "closes" と "#1234" を別々にマッチさせている。

今回は両 PR とも `base_ref: main` で実害なし。`scripts/gh-extract-issue-from-pr.sh` は `closes` を正しく解決するため、#1202 の対応方針 (検索結果を `closes` で突き合わせる) がそのまま解になる。

### Improvement Proposals

- **Size 再評価時に CI 検証 AC の形式が route に追随しない** — triage が patch route 形式で設定した AC が、spec の Size 再評価 (S → M) 後も据え置かれ、pr route なのに `main` の run を見る状態になった。あわせて **`gh run list` が `github_check` safe mode allowlist に含まれない**ため `/review` で判定不能になる。2 点セットで #1212 (patch route の形式、着地済み) / #1229 (Step 10 の評価タイミング、未着手) の隣接領域だが、いずれとも別軸。#1229 に着手する際に同時に扱えるため、独立起票せず本節に記録する (Tier 2)
- **`collect-run-facts.sh` の CWD 依存** — `.tmp/auto-events.jsonl` を CWD 相対で読むため worktree から呼ぶと run context が空になる。正規経路では影響しないが、#1239 (opportunistic mode への `--facts` 導入) が worktree 内から facts を必要とする設計になった場合に顕在化しうる。#1239 の設計時に確認すべき制約として本節に記録する (Tier 3)
- **checkbox index の off-by-one** — 既存 #1071 でカバー済み。ただし本セッションでは **gate のエラーメッセージに条件テキストがない**ことが原因特定を遅らせた (merge 2 往復)。#1071 に着手する際、`/merge` の非対話モード `decision=blocked` パスにも `#<index> <text>` を出力する改善を併せて検討すると効果が高い (Tier 3、#1071 へのコメントで補足済みとはしない — 本節の記録に留める)
- **PR 検索の誤ヒット** — 既存 #1202 でカバー済み。実測ケースとして同 Issue にコメントで追記する
