# Issue #737: test: add bats coverage for scripts/get-sub-issue-progress.sh

## Overview

`scripts/get-sub-issue-progress.sh` は `/audit progress <XL-parent>` の sub-issue 集約を担うスクリプトで、GraphQL で sub-issue list と blockedBy relation を取得する。dedicated test ファイル不在で、parent 不在 / sub-issue 0 件 / blockedBy 解決 / state classification (Done/In progress/Blocked/Stale/Pending) の動作保証が薄い。

`tests/audit-progress.bats` に一部テストが存在するが、ファイル名が script 名と対応しておらず dedicated test file とは見なされない。本 Issue では `tests/get-sub-issue-progress.bats` を新規作成し canonical な dedicated test ファイルを設ける。

## Changed Files

- `tests/get-sub-issue-progress.bats`: 新規作成 — `scripts/get-sub-issue-progress.sh` の dedicated bats テストファイル (4 件以上の @test; bash 3.2+ 互換)
- `docs/structure.md`: `tests/` ファイル数カウント `(80 files)` → `(81 files)` に更新
- `docs/ja/structure.md`: `（80 ファイル）` → `（81 ファイル）` に更新 (translation sync)

## Implementation Steps

1. `tests/get-sub-issue-progress.bats` を新規作成する。`tests/audit-progress.bats` と同じ mock パターン (`WHOLEWORK_SCRIPT_DIR` + `MOCK_DIR/gh-graphql.sh`) を採用する。以下の 4 件の @test を含める (→ AC 1, 2, 3):
   - `parent not found: returns empty title and empty sub_issues` — mock response: `{"data":{"repository":{"issue":null}}}` → exit 0、`parent.title = ""`、`sub_issues = []`
   - `sub-issue 0 items: returns empty sub_issues array` — mock response: nodes=[] → exit 0、`sub_issues` length = 0
   - `blockedBy resolved: CLOSED blockedBy item is included in output` — sub-issue の blockedBy に state=CLOSED のアイテムが存在 → exit 0、`blockedBy[0].state = "CLOSED"`
   - `state classification fields: returns labels and blockedBy for Done/In-progress/Blocked/Stale/Pending` — 5 件の sub-issue (CLOSED/OPEN+phase-label/OPEN+open-blockedBy/OPEN+stale-verify/OPEN+no-label) → exit 0、各フィールドが正しく返却される

2. `docs/structure.md` の `(80 files)` を `(81 files)` に変更する (→ doc consistency)

3. `docs/ja/structure.md` の `（80 ファイル）` を `（81 ファイル）` に変更する (→ translation sync)

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/get-sub-issue-progress.bats" --> direct test ファイルが新規作成されている
- <!-- verify: grep "@test" "tests/get-sub-issue-progress.bats" --> テストケース (@test) が含まれる
- <!-- verify: command "bats tests/get-sub-issue-progress.bats" --> 追加した bats テストすべて green
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI bats 全件 green

### Post-merge

- `tests/get-sub-issue-progress.bats` に最低 4 件以上の @test が存在し、以下のシナリオをカバーしている: parent 不在 / sub-issue 0 件 / blockedBy 解決 / state classification (Done/In progress/Blocked/Stale/Pending) <!-- verify-type: opportunistic -->
- 次回 `get-sub-issue-progress.sh` を変更する Issue で direct test が regression を検出することを観察 <!-- verify-type: manual -->

## Notes

- `tests/audit-progress.bats` は `get-sub-issue-progress.sh` を対象とするテスト 4 件を既に含む。新規ファイルと重複するシナリオもあるが、canonical なファイル名 (`get-sub-issue-progress.bats`) で dedicated test ファイルを設けることが本 Issue の目的。`tests/audit-progress.bats` の取り扱い (移行・削除) は別途判断。
- `scripts/get-sub-issue-progress.sh` の `set -euo pipefail` 環境において jq が null issue を受け取った場合の挙動: `null.subIssues.nodes` は jq で null を返し、`null // []` で空配列になるため、parent 不在テストは exit 0 を期待できる。
- Auto-Resolve (Issue コメントより引き継ぎ):
  - AC #2 の verify command: `grep "@test"` を使用 (count-based な件数確認は post-merge opportunistic に移動)。
  - `tests/audit-progress.bats` の取り扱い: 追加のみ (削除・rename なし) の最小リスク方針。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (Auto-Resolve Log): AC #2 の verify command を `file_contains` → `grep "@test"` に変更した旨、および `tests/audit-progress.bats` の取り扱いを scope 外とした旨を記録 / https://github.com/saitoco/wholework/issues/737#issuecomment-4759737715
