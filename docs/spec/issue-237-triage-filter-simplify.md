# Issue #237: triage-backlog-filter: 除外条件を `triaged` ラベルのみに簡素化

## Overview

`scripts/triage-backlog-filter.sh` の jq フィルタから `phase/*` ラベル除外条件を除去し、`triaged` ラベル不在のみに簡素化する。現在の2条件 AND フィルタ（`triaged` 不在 AND `phase/*` 不在）を1条件（`triaged` 不在のみ）に変更することで、`phase/issue` 等を持ちながら `triaged` が欠落した Issue が bulk triage から漏れる問題を構造的に解消する。

## Changed Files

- `scripts/triage-backlog-filter.sh`: jq フィルタ（line 62-64）から `and (.labels | map(.name) | any(startswith("phase/")) | not)` を除去 — bash 3.2+ compatible (変更なし)
- `tests/triage-backlog-filter.bats`: `@test "excludes issues with phase/* labels"` (line 116-131) を `@test "includes issues with phase/* labels when not triaged"` に置換

## Implementation Steps

1. `scripts/triage-backlog-filter.sh` line 62-64 の jq フィルタを変更：`and` と `(.labels | map(.name) | any(startswith("phase/")) | not)` を除去し、`(.labels | map(.name) | index("triaged") | not)` のみ残す (→ 検収 1, 2)

2. `tests/triage-backlog-filter.bats` line 116-131 の `@test "excludes issues with phase/* labels"` を削除し、以下の新テストに置換する (→ 検収 3, 4, 5)：
   - テスト名: `"includes issues with phase/* labels when not triaged"`
   - テストデータ: `phase/verify` / `phase/code` ラベルを持つが `triaged` なし Issue を含み、`triaged` 付き Issue を別途含む
   - アサーション: `phase/*` 付き untriaged Issue が出力に含まれること、`triaged` 付き Issue が出力から除外されること

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/triage-backlog-filter.sh" "any(startswith(\"phase/\"))" --> `triage-backlog-filter.sh` から `phase/*` 除外 jq 条件が除去されている
- <!-- verify: file_contains "scripts/triage-backlog-filter.sh" "index(\"triaged\")" --> `triaged` ラベル不在チェックは維持されている
- <!-- verify: file_not_contains "tests/triage-backlog-filter.bats" "excludes issues with phase" --> 旧テスト `excludes issues with phase/* labels` が除去または置換されている
- <!-- verify: file_contains "tests/triage-backlog-filter.bats" "phase/" --> 新テストケースで `phase/*` 付き Issue を含むサンプルデータがテストされている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" --> bats テストが全てパスする

### Post-merge

- 次回 `/triage` bulk 実行で `phase/issue` + `triaged` 欠落な既存 Issue (#220 / #221 / #222 等) がピックアップされる

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
