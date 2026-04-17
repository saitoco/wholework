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

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件に `verify:` コマンドが全条件に付与されており、自動検証率100%を達成。
- `file_not_contains` / `file_contains` による具体的な jq パターン指定で、意図が明確に検証可能だった。

#### design
- Spec の実装手順（ファイル名・行番号・変更内容）が正確で、実装との乖離なし。
- patch route（直接 main コミット）の判断は適切。変更規模（2ファイル・数行）に対して PR オーバーヘッドは不要だった。

#### code
- 単一クリーンコミット（fixup/amend なし）で実装完了。設計からの逸脱なし。
- テスト置換（excludes → includes）が設計通りに実施された。

#### review
- patch route のため PR レビューなし。変更規模・リスクを考慮すると適切な判断。

#### merge
- 直接 main へのコミット。競合なし、CI 影響（`triage-backlog-filter.bats`）なし。

#### verify
- CI の `run-auto-sub.bats` 失敗（Issue #219 関連）が本 Issue の検証に影響しないことを正確に識別できた。
- ローカルテスト実行で `triage-backlog-filter.bats` 全8テストのパスを確認し、CI失敗が無関係であることを担保できた。
- `github_check` に `gh run list` 形式（patch route 互換）を使用したことで、PR 不在でも適切に検証できた。

### Improvement Proposals
- N/A
