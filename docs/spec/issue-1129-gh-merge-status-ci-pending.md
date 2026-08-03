# Issue #1129: gh-pr-merge-status: CI 実行中を failing と区別し ci_pending を返す

## Overview

`scripts/gh-pr-merge-status.sh` は `gh pr view --json mergeable,mergeStateStatus` の `mergeStateStatus` が `UNSTABLE` のとき、無条件に `reason: ci_failing` を返す。しかし GitHub の `UNSTABLE` は「必須チェックが失敗した」場合と「必須チェックがまだ実行中」の場合の両方を含む粗い分類であり、呼び出し側 (`skills/merge/SKILL.md` Step 1) はこの2つを区別できず、CI 実行中の PR を CI 失敗として扱ってしまう。本 Issue は `gh pr checks` の check 単位の状態を追加参照して `ci_pending` (実行中) と `ci_failing` (失敗) を区別し、`/merge` に CI 完了待ちの再判定経路を追加する。

## Reproduction Steps

1. PR の必須チェックが 1 件以上 `IN_PROGRESS` (失敗 0 件) の状態で `scripts/gh-pr-merge-status.sh <PR番号>` を実行する
2. `gh pr view --json mergeable,mergeStateStatus` は `mergeStateStatus: UNSTABLE` を返す (GitHub は「必須チェック未完了」と「失敗」のどちらもこの値で表す)
3. 現行実装 (`scripts/gh-pr-merge-status.sh:85-86`) は `STATE == "UNSTABLE"` を無条件に `{"reason": "ci_failing", "ci_status": "failing"}` として出力するため、実行中であるにもかかわらず CI 失敗と誤判定される
4. 実例 (PR #1121 / Issue #1109): 7 件 SUCCESS + 2 件 IN_PROGRESS (失敗 0 件) の状態で `{"mergeable": false, "reason": "ci_failing", "ci_status": "failing"}` が返った。CI 完了後に再実行すると `{"mergeable": true, "reason": "clean", "ci_status": "success"}` に変わった

## Root Cause

`scripts/gh-pr-merge-status.sh` の判定は `gh pr view --json mergeable,mergeStateStatus` の `mergeStateStatus` という単一シグナルにのみ依存している。`UNSTABLE` は GitHub 側で「1件以上の必須チェックが未完了、または失敗」を意味する集約値であり、実行中/失敗を区別する情報を持たない。区別するには check 単位の状態 (`gh pr checks --json state,bucket`) を追加参照する必要がある。`bucket` フィールドは `pass`/`fail`/`pending`/`skipping`/`cancel` に正規化された値で、`scripts/wait-ci-checks.sh` が既にこの方式で CI 完了待ちを実装している (`docs/structure.md:212`)。

`skills/merge/SKILL.md` Step 1 側は `ci_failing` を含む `conflicts` 以外の全ての `reason` を "Other" 分岐 (AskUserQuestion / 非対話時は自動解決) にまとめており、CI 実行中でも待機せず先に進んでしまう。

## Changed Files

- `scripts/gh-pr-merge-status.sh`: `STATE == "UNSTABLE"` 分岐を拡張。`gh pr checks "$PR" --json state,bucket` を追加取得し、`bucket == "fail"` が1件以上あれば `ci_failing` (実行中チェック残存より優先)、0件かつ `bucket == "pending"` が1件以上あれば新規の `reason: ci_pending` / `ci_status: pending` を返す。どちらも0件の場合 (UNSTABLE なのに fail/pending 双方0件という GitHub 側の同期ラグを想定) は安全側で `ci_failing` にフォールバックする — bash 3.2+ compatible
- `skills/merge/SKILL.md`: Step 1 item 3 の分岐リストに `reason=ci_pending` の枝を追加 (conflicts の直後、Other の直前に挿入)。`${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh "$NUMBER"` で CI 完了を待ってから `gh-pr-merge-status.sh` を再実行し、新しい結果でこの分岐リストを再評価する。合わせて frontmatter の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh:*` を追加する (現状未許可 — 未追加のまま呼び出すと非対話モードで権限プロンプトによりブロックされる)
- `tests/gh-pr-merge-status.bats`: `make_gh_mock` ヘルパーを拡張し、`gh pr checks` 呼び出しへの任意のチェック JSON 応答 (第3引数、省略時 `[]`) を指定できるようにする。pending のみのケースと fail 混在ケースを区別する新規テスト2件を追加する — bash 3.2+ compatible (bats)

## Implementation Steps

1. `scripts/gh-pr-merge-status.sh` の `UNSTABLE` 分岐を拡張する (→ acceptance criteria AC1, AC2)。既存の `elif [[ "$STATE" == "UNSTABLE" ]]; then` ブロック内で `gh pr checks "$PR" --json state,bucket 2>/dev/null` を実行し (失敗時は空配列 `[]` にフォールバック)、`jq` で `bucket == "fail"` の件数と `bucket == "pending"` の件数を数える。fail 件数 > 0 なら既存の `ci_failing` 応答を維持 (実行中チェックが残っていても failing を優先)、fail == 0 かつ pending 件数 > 0 なら `{"mergeable": false, "reason": "ci_pending", "ci_status": "pending", "review_status": "unknown"}` を新規出力、どちらも0件なら安全側フォールバックとして既存の `ci_failing` 応答を返す
2. `skills/merge/SKILL.md` Step 1 item 3 の分岐リスト (conflicts の直後) に `reason=ci_pending` の枝を挿入し (after 1) (→ acceptance criteria AC3, AC4)、CI 実行中の場合の待機・再判定手順を記載する: `WHOLEWORK_CI_TIMEOUT_SEC=300 ${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh "$NUMBER"` を実行 (待機を merge phase の watchdog 予算内に収めるため 300 秒に制限 — `WHOLEWORK_REVIEW_PENDING_RETRY_SEC` の 300 秒と同じ考え方) → `gh-pr-merge-status.sh "$NUMBER"` を再実行 → 新しい結果でこの分岐リストを再評価する。ただし再評価してもなお `reason=ci_pending` の場合は待機を繰り返さず "Other" 分岐にフォールスルーする。同時に frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh:*` を追加する
3. `tests/gh-pr-merge-status.bats` を更新する (after 1) (→ acceptance criteria AC5, AC6, AC7)。`make_gh_mock` に第3引数 `checks_json` (デフォルト `[]`) を追加し、生成する `gh` モックスクリプトが `$1 $2` (`pr view` か `pr checks` か) で分岐して応答を返すようにする。新規テスト2件を追加: (a) `bucket: pending` のみのケースで `reason: ci_pending` / `ci_status: pending` を返すことを確認、(b) `bucket: fail` を1件含む (他に `pending` も混在) ケースで `reason: ci_failing` を返すことを確認 (優先順位の検証)。既存の `"success: UNSTABLE state returns mergeable false with reason ci_failing"` テストは `make_gh_mock "MERGEABLE" "UNSTABLE"` (第3引数省略 → checks は `[]`) のままで fail=0/pending=0 のフォールバック分岐を通り無変更で PASS する

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/gh-pr-merge-status.sh が CI の実行中状態を failing とは別の値 (pending 相当) として出力する実装になっている。失敗が 1 件以上ある場合は実行中チェックが残っていても failing を優先する判定順序が実装されている" --> `gh-pr-merge-status.sh` が pending と failing を区別する
- <!-- verify: file_contains "scripts/gh-pr-merge-status.sh" "ci_pending" --> `gh-pr-merge-status.sh` に `ci_pending` の値が実装されている
- <!-- verify: rubric "skills/merge/SKILL.md Step 1 の mergeability 分岐に、CI 実行中 (ci_pending 相当) の場合に CI 完了を待って再判定する経路が定義されている" --> `/merge` に CI 待機経路が定義されている
- <!-- verify: section_contains "skills/merge/SKILL.md" "### Step 1: Check PR State" "ci_pending" --> Step 1 セクションに `ci_pending` の分岐が記載されている
- <!-- verify: command "bats tests/gh-pr-merge-status.bats" --> `tests/gh-pr-merge-status.bats` が PASS する
- <!-- verify: rubric "tests/gh-pr-merge-status.bats に、実行中チェックのみのケース (pending) と 失敗を含むケース (failing) を区別する新規テストケースが追加されている" --> pending / failing を区別する新規テストが追加されている
- <!-- verify: file_contains "tests/gh-pr-merge-status.bats" "ci_pending" --> テストファイルに `ci_pending` を検証する新規テストが含まれている

### Post-merge

- CI 実行中の PR に対して `/merge` を実行し、`ci_failing` として中断されずに CI 完了を待って merge に進むことを確認する

## Notes

- **allowed-tools 追加が必要**: `skills/merge/SKILL.md` の `allowed-tools` frontmatter には現状 `${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh:*` が含まれていない (既存の `run-merge.sh` からの呼び出しは `claude -p` 起動前の bash レベルであり、この frontmatter の対象外)。Step 1 内から新たに呼び出すには追加が必須 — 未追加のまま実装すると非対話モードで権限プロンプトによりブロックされる
- **wait-ci-checks.sh のタイムアウトを 300 秒に制限した理由**: `wait-ci-checks.sh` のデフォルトタイムアウト (`WHOLEWORK_CI_TIMEOUT_SEC`) は 1200 秒だが、merge phase の watchdog タイムアウト (`WATCHDOG_TIMEOUT_MERGE_SECONDS`) はデフォルト 600 秒。無制限に待つとセッション全体が watchdog に kill されるリスクがあるため、`/auto` オーケストレーター層の既存の bounded retry 単位 (`WHOLEWORK_REVIEW_PENDING_RETRY_SEC=300`) に合わせて 300 秒に制限した。300 秒待っても pending が解消しない場合は Other 分岐 (非対話時は自動解決で merge を試行) にフォールスルーし、通常の orchestration recovery (Tier 1/2/3) に委ねる
- **既存 consumer への影響なし**: `scripts/run-code.sh:335` と `modules/orchestration-fallbacks.md` も `gh-pr-merge-status.sh` の出力を消費するが、いずれも `reason: conflicts` のみを見ており、`ci_failing`/新規 `ci_pending` 値の追加による影響はない (grep で確認済み)

## Consumed Comments

- saito (MEMBER, first-class): `/issue` フェーズの Issue Retrospective。Background の事実確認結果 (UNSTABLE の無条件 ci_failing 化を実装で確認済み)、CI 待機経路の実装方針 (wait-ci-checks.sh 再利用) と pending/failing 判定データソース (gh pr checks) の Auto-Resolve Log、AC 追加3件 (file_contains/section_contains の機械的セーフティネット) の記録。https://github.com/saitoco/wholework/issues/1129#issuecomment-5161154838

`code` フェーズ: 新規コメントなし (cutoff 以降のコメントなし)。

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜3 を設計通りに実装した。

### Design Gaps/Ambiguities

N/A

### Rework

N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `gh pr checks "$PR" --json state,bucket` を追加参照し、`bucket` の `fail`/`pending` 件数で `ci_failing`/`ci_pending`/フォールバック `ci_failing` を判定する順序 (fail優先) をそのまま実装した (Spec Implementation Step 1 通り)
- `skills/merge/SKILL.md` の `ci_pending` 分岐は `wait-ci-checks.sh` (300秒タイムアウト) の再利用とし、再評価してもなお `ci_pending` なら Other 分岐にフォールスルーする一度きりの待機とした (無限リトライを避ける設計)
- `make_gh_mock` を `gh pr view` / `gh pr checks` で分岐する形に拡張し、第3引数 `checks_json` (デフォルト `[]`) で任意のチェック応答を注入できるようにした。既存の UNSTABLE テストは無変更で fail=0/pending=0 のフォールバック経路を通り PASS した

### Deferred Items
- Post-merge AC (`/merge` 実行時に実際に `ci_pending` を待って merge へ進むことの確認) は post-merge 検証であり本 PR のスコープ外 — `/verify` フェーズで確認する
- None

### Notes for Next Phase
- `/review` では `gh-pr-merge-status.sh` の UNSTABLE 分岐 (fail/pending/フォールバックの3分岐) と `skills/merge/SKILL.md` Step 1 の `ci_pending` 枝の両方が Spec Implementation Steps と一致しているか確認すること
- pre-existing の forbidden-expressions 違反 (`docs/spec/issue-1136-bats-emit-log-isolation.md` の `Issue Spec` 引用) は本 Issue の変更と無関係。既存違反であり本 PR のスコープ外
