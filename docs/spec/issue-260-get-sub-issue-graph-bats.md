# Issue #260: tests: Add bats tests for get-sub-issue-graph.sh

## Overview

`scripts/get-sub-issue-graph.sh` is the backbone of XL orchestration (`/auto` parallel
sub-issue execution). It contains complex jq-based JSON parsing logic (topological sort,
cycle detection, orphaned-dependency filtering), but has no corresponding bats test file.
This issue adds `tests/get-sub-issue-graph.bats` covering the main code paths identified
in the issue: normal graph, cycle detection, orphaned dependency, and empty graph.

## Changed Files

- `tests/get-sub-issue-graph.bats`: new file — bats tests for happy path (linear chain),
  cycle detection, orphaned dependency ignored, empty graph, and input validation;
  bash 3.2+ compatible
- `docs/structure.md`: update tests/ count from `(33 files)` to `(35 files)` (currently
  34 .bats files exist; adding this file brings the total to 35)
- `docs/ja/structure.md`: update tests count from `（33 ファイル）` to `（35 ファイル）`

## Implementation Steps

1. Create `tests/get-sub-issue-graph.bats` — mock `gh-graphql.sh` via
   `WHOLEWORK_SCRIPT_DIR`; add the following `@test` cases (→ acceptance criteria 1–5):
   - `"success: empty graph outputs empty arrays"` — nodes:[], expect `execution_order:[]`
   - `"success: linear chain A to B"` — 101 independent, 102 blocked by 101;
     expect execution_order `[[101],[102]]`
   - `"success: orphaned blocked_by is filtered out"` — 101 blocked by 999 (not in
     sub-issues); expect 101 treated as independent
   - `"error: cycle detection exits non-zero"` — 101 blocked by 102, 102 blocked by 101;
     expect non-zero exit status
   - `"error: no arguments"` — expect exit 1, output contains "Usage"
   - `"error: non-numeric argument"` — expect exit 1, output contains "Error"

2. Update `docs/structure.md` line containing `(33 files)` → `(35 files)`;
   update `docs/ja/structure.md` line containing `33 ファイル` → `35 ファイル`
   (after step 1 is complete)

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/get-sub-issue-graph.bats" --> `tests/get-sub-issue-graph.bats` が作成されている
- <!-- verify: grep "@test" "tests/get-sub-issue-graph.bats" --> 少なくとも 1 つ以上の `@test` ケースを含む
- <!-- verify: grep "cycle\|circular" "tests/get-sub-issue-graph.bats" --> サイクル（循環依存）検出のテストケースが含まれている
- <!-- verify: grep "empty" "tests/get-sub-issue-graph.bats" --> 空グラフ（サブ Issue なし）のテストケースが含まれている
- <!-- verify: command "bats tests/get-sub-issue-graph.bats" --> 追加した bats テストがすべて PASS

### Post-merge

- 次回 XL Issue の `/auto` 実行時にサブ Issue 依存解決が期待通り動くことを確認

## Notes

**bats test input data format:**
Mock `gh-graphql.sh` reads `MOCK_GRAPHQL_RESPONSE` env var and echoes it.
The JSON structure the real API returns (and the mock must replicate):
```json
{
  "data": {
    "repository": {
      "issue": {
        "subIssues": {
          "nodes": [
            {
              "number": 101,
              "title": "Sub 1",
              "state": "OPEN",
              "blockedBy": { "nodes": [] }
            }
          ]
        }
      }
    }
  }
}
```
blockedBy nodes format: `{"number": N}` (number field only; state is not used by the script).

**Structure.md count discrepancy:** `docs/structure.md` currently says "33 files" but there
are already 34 `.bats` files in `tests/`. Adding this file brings the total to 35. Both
English and Japanese mirror files need updating.

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件は `file_exists`、`grep`、`command` の verify ヒントを完備しており、自動検証率が高い設計になっていた。
- `<!-- verify-type: manual -->` の post-merge 条件（XL フロー実行確認）は次回 `/auto` 実行時まで手動確認が必要な性質であり、適切に分離されている。

#### design
- 設計（Spec）は実装と齟齬なく対応。6 件の `@test` ケースが Spec の Implementation Steps に明示されており、verify 結果と整合。

#### code
- パッチルート（PR なし、`closes #260` を直接コミット）での実装。commit 2件（実装 + コードレトロ）で完結しており、リワークなし。
- `bats` テスト全 6 件 PASS。設計で想定した正常グラフ・サイクル・孤立依存・空グラフの各ケースを網羅。

#### review
- PR なし（パッチルート）のため正式レビューなし。テスト自体の内容は bats 実行で直接検証済み。

#### merge
- 直接 main コミット。コンフリクトなし。

#### verify
- 全 5 件の pre-merge 条件が PASS。CI ランなし（ローカル bats 実行で代替）。
- Post-merge の manual 条件が残存するため `phase/verify` ラベルを付与。次回 XL Issue 実行後に `/verify 260` を再実行して完了させること。

### Improvement Proposals
- N/A
