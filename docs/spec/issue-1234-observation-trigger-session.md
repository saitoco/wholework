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
