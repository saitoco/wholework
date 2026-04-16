# Issue #196: test: gh-label-transition.sh に bats テストを追加

## Overview

`scripts/gh-label-transition.sh` に対する bats テストを追加する Issue。調査の結果、`tests/gh-label-transition.bats` は Issue #183 のマージ（2026-04-15 12:49 JST）時点ですでに 16 テストが存在し、すべて PASS している。

Post-merge 条件「phase/issue → ... → phase/done の遷移パターンが検証されている」を確認したところ、`phase/done` への遷移を検証する専用サクセステスト（`--add-label phase/done` が gh に渡されることを確認するテスト）が存在しない。spec / code / verify は専用テストを持つが、done は idempotent テストでのみ使用されている（基本的な正常遷移は検証していない）。`phase/issue` への専用テストも同様に存在しないが、Post-merge 条件の起点（→ issue）は既存テストカバレッジと重複するため today の対象外とする。

## Changed Files

- `tests/gh-label-transition.bats`: `@test "success: transition to done phase"` を追加 — bash 3.2+ 互換

## Implementation Steps

1. `tests/gh-label-transition.bats` の既存 "success: transition to verify phase" テスト（行 73–78）の直後に `@test "success: transition to done phase"` を追加する。既存パターンに従い、デフォルトモック（`gh issue view` が空を返す通常フロー）を使用し、以下を検証する:
   - `status` が 0
   - `GH_CALL_LOG` に `issue edit` + `--add-label phase/done` + `--remove-label phase/issue` が含まれる
   （→ 受入条件：テストが PASS する）

## Verification

### Pre-merge

- <!-- verify: test -f tests/gh-label-transition.bats --> `tests/gh-label-transition.bats` が存在する
- <!-- verify: bats tests/gh-label-transition.bats --> テストが PASS する

### Post-merge

- phase/issue → phase/spec → phase/code → phase/verify → phase/done の遷移パターンが検証されている

## Notes

**実装前との状態の矛盾（自動解決）**: Issue 本文の背景「bats テストが存在しないことを確認」という前提は現在のコードと矛盾している。`tests/gh-label-transition.bats` は Issue #183 のマージ（commit 86d702f, 2026-04-15 12:49 JST）ですでに作成されており、Issue #196 の作成（2026-04-15 23:04 JST）より約 10 時間前から存在する。

自動解決方針: 既存 16 テスト（正常遷移・存在しないラベル・既存ラベル保持）はすべて PASS しており Issue の主目的は達成済みと判断。Post-merge 条件で明示されている `phase/done` への遷移のみ専用サクセステストが欠けているため、1 件のテストケースを追加して Post-merge 条件を明示的に満たす。
