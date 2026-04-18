# Issue #254: scripts/run-auto-sub: PATCH_LOCK_DIR を /tmp/ から .tmp/ へ移動

## Overview

`scripts/run-auto-sub.sh` の PATCH_LOCK_DIR が `/tmp/claude-auto-patch-lock-${LOCK_HASH}` を使用しており、`docs/product.md` Non-Goals（一時ファイルは `.tmp/` を使用）に違反している。`.tmp/` はリポジトリ固有ディレクトリのため LOCK_HASH による識別は不要となり、`PATCH_LOCK_DIR="${REPO_ROOT}/.tmp/claude-auto-patch-lock"` に変更してコードを簡素化する。

## Reproduction Steps

`/audit drift` (2026-04-19) で検出。`scripts/run-auto-sub.sh:44` に `PATCH_LOCK_DIR="/tmp/claude-auto-patch-lock-${LOCK_HASH}"` が残存している。

## Root Cause

PATCH_LOCK_DIR の初期設計が Non-Goals（`.tmp/` 使用方針）策定前の実装であり、プロジェクトルール整備後に見直されなかった。LOCK_HASH（リポジトリパスの cksum）は `/tmp/` 配下での別リポジトリとの衝突回避のために必要だったが、`.tmp/` はリポジトリ固有ディレクトリのため不要となる。`.tmp/` に移動することで Non-Goals との整合が回復し、コードが簡素化される。

## Changed Files

- `scripts/run-auto-sub.sh`: `LOCK_HASH` 計算行を削除、`PATCH_LOCK_DIR` を `"${REPO_ROOT}/.tmp/claude-auto-patch-lock"` に変更、`acquire_patch_lock()` 内に `mkdir -p "$(dirname "$PATCH_LOCK_DIR")"` を追加 — bash 3.2+ 互換
- `tests/run-auto-sub.bats`: teardown の LOCK_HASH 計算・rmdir パスを更新、PATCH_LOCK テストのモック run-code.sh とアサーションのパスを更新 — bash 3.2+ 互換

## Implementation Steps

1. `scripts/run-auto-sub.sh` 修正:
   - `LOCK_HASH=$(echo "$REPO_ROOT" | cksum | awk '{print $1}')` 行を削除
   - `PATCH_LOCK_DIR="/tmp/claude-auto-patch-lock-${LOCK_HASH}"` を `PATCH_LOCK_DIR="${REPO_ROOT}/.tmp/claude-auto-patch-lock"` に変更
   - `acquire_patch_lock()` 内の `while ! mkdir "$PATCH_LOCK_DIR"` 直前に `mkdir -p "$(dirname "$PATCH_LOCK_DIR")"` を追加
   （→ 受入条件 1, 2）

2. `tests/run-auto-sub.bats` 修正:
   - **teardown**: `LOCK_HASH=$(echo "$BATS_TEST_TMPDIR/test-repo" | cksum | awk '{print $1}')` を削除、`rmdir "/tmp/claude-auto-patch-lock-${LOCK_HASH}"` を `rmdir "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"` に変更
   - **PATCH_LOCK テスト**: LOCK_HASH 計算行（2箇所）を削除、モック run-code.sh 内の `[ -d "/tmp/claude-auto-patch-lock-${LOCK_HASH}" ]` を `[ -d "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock" ]` に変更、アサーション `[ ! -d "/tmp/claude-auto-patch-lock-${LOCK_HASH}" ]` を `[ ! -d "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock" ]` に変更
   （→ 受入条件 3, 4, 5）

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/run-auto-sub.sh" "/tmp/claude-auto-patch-lock" --> `scripts/run-auto-sub.sh` の PATCH_LOCK_DIR が `/tmp/` を参照していない
- <!-- verify: grep "\.tmp/claude-auto-patch-lock" "scripts/run-auto-sub.sh" --> `scripts/run-auto-sub.sh` の PATCH_LOCK_DIR が `.tmp/` 配下に変更されている
- <!-- verify: file_not_contains "tests/run-auto-sub.bats" "/tmp/claude-auto-patch-lock" --> `tests/run-auto-sub.bats` の PATCH_LOCK パス参照が `/tmp/` を使用していない
- <!-- verify: grep "\.tmp/claude-auto-patch-lock" "tests/run-auto-sub.bats" --> `tests/run-auto-sub.bats` が `.tmp/` ロックパスを参照している
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> bats テストがすべてパスする

### Post-merge

- 再度 `/audit drift` を実行し、この finding が検出されなくなることを確認

## Notes

- 非インタラクティブモードにて実行。Issue body の `## Auto-Resolved Ambiguity Points` に記録された自動解決方針（Option A: コード変更、LOCK_HASH 削除）をそのまま採用。
- `.tmp/` ディレクトリの事前作成（`mkdir -p`）は `acquire_patch_lock()` 内で行うことで、ロック取得タイミングと `.tmp/` 作成を一箇所に集約する。
