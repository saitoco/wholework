# Issue #177: bats tests CI Run Time (~9min) Reduction

## Overview

GitHub Actions `test.yml` の bats tests ステップが約 540 秒かかっている。2026-04-14 に `bats --jobs 4` による並列化を試みたが、`tests/get-issue-priority.bats`・`tests/get-issue-size.bats` 等で race condition が発生してリバート済み（commits `d1e6d06`, `63895ae`）。

原因: `scripts/gh-graphql.sh` がキャッシュディレクトリ `.tmp/gh-graphql-cache` をプロジェクトルートからの相対パスで使用しており、並列実行される複数のテストファイルが同一ディレクトリを同時に read/write/delete する。

対策: `gh-graphql.sh` に `GH_GRAPHQL_CACHE_DIR` 環境変数サポートを追加し、各テストの `setup()` で `BATS_TEST_TMPDIR` 配下のキャッシュパスを設定することで state を test-local に隔離する。隔離完了後、`bats --jobs $(nproc)` を再導入する。

## Changed Files

- `scripts/gh-graphql.sh`: `CACHE_DIR` のデフォルト値を `GH_GRAPHQL_CACHE_DIR` 環境変数で上書き可能にする
- `tests/get-issue-priority.bats`: `setup()` に `GH_GRAPHQL_CACHE_DIR` 設定を追加、`rm -rf "$PROJECT_ROOT/.tmp/gh-graphql-cache"` を除去
- `tests/get-issue-size.bats`: 同上
- `tests/get-issue-type.bats`: 同上（`teardown()` の `rm -rf` 除去のみ）
- `tests/gh-graphql.bats`: ファイルレベルの `CACHE_DIR` 変数を `setup()` 内の `BATS_TEST_TMPDIR` ベースの定義に移行
- `.github/workflows/test.yml`: `bats tests/` → `bats --jobs $(nproc) tests/`

## Implementation Steps

1. `scripts/gh-graphql.sh` の 25 行目を変更: `CACHE_DIR=".tmp/gh-graphql-cache"` → `CACHE_DIR="${GH_GRAPHQL_CACHE_DIR:-.tmp/gh-graphql-cache}"` (→ 受入基準 A: fixture 隔離)

2. `tests/get-issue-priority.bats` と `tests/get-issue-size.bats` を更新（after 1）(→ 受入基準 A):
   - `setup()`: `cd "$PROJECT_ROOT"` の直後に `export GH_GRAPHQL_CACHE_DIR="$BATS_TEST_TMPDIR/gh-graphql-cache"` を追加。コメント付きの `rm -rf "$PROJECT_ROOT/.tmp/gh-graphql-cache"` 行を除去
   - `teardown()`: `rm -rf "$PROJECT_ROOT/.tmp/gh-graphql-cache"` を除去（`BATS_TEST_TMPDIR` が自動クリーンアップされるため不要）
   - ループ内の `rm -rf "$PROJECT_ROOT/.tmp/gh-graphql-cache"`: `rm -rf "$GH_GRAPHQL_CACHE_DIR"` に置換（同一 Issue 番号で別レスポンスをテストするため、ループ内のキャッシュクリアは引き続き必要）

3. `tests/get-issue-type.bats` を更新（after 1）(→ 受入基準 A):
   - `setup()`: `export GH_GRAPHQL_CACHE_DIR="$BATS_TEST_TMPDIR/gh-graphql-cache"` を追加、`rm -rf "$PROJECT_ROOT/.tmp/gh-graphql-cache"` を除去
   - `teardown()`: `rm -rf "$PROJECT_ROOT/.tmp/gh-graphql-cache"` を除去

4. `tests/gh-graphql.bats` を更新（after 1）(→ 受入基準 A):
   - ファイルレベルの `CACHE_DIR="$PROJECT_ROOT/.tmp/gh-graphql-cache"`（142 行目）を除去
   - `setup()` に追加:
     ```bash
     export GH_GRAPHQL_CACHE_DIR="$BATS_TEST_TMPDIR/gh-graphql-cache"
     CACHE_DIR="$GH_GRAPHQL_CACHE_DIR"
     export CACHE_DIR
     ```

5. `.github/workflows/test.yml` を更新（after 2, 3, 4）(→ 受入基準 B):
   - `run: bats tests/` → `run: bats --jobs $(nproc) tests/`

## Verification

### Pre-merge

- <!-- verify: grep "GH_GRAPHQL_CACHE_DIR" "scripts/gh-graphql.sh" --> `gh-graphql.sh` が `GH_GRAPHQL_CACHE_DIR` 環境変数を参照している
- <!-- verify: grep "bats --jobs" ".github/workflows/test.yml" --> `test.yml` に `bats --jobs` が含まれている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> PR CI の bats tests ステップが success（並列実行下で全件 pass）
- <!-- verify: file_exists ".github/workflows/test.yml" --> `.github/workflows/test.yml` が存在する

### Post-merge

- 本対応後の直近 3 回の main CI 実行時間が対応前平均（約 540 秒）より有意に短縮されていることを GitHub Actions 履歴で確認

## Notes

- 隔離対象は `gh-graphql.sh` が `--cache` フラグ使用時に書き込む `.tmp/gh-graphql-cache` のみ。`MOCK_DIR` は既に `BATS_TEST_TMPDIR/mocks` でテストローカル
- `tests/get-issue-priority.bats` および `tests/get-issue-size.bats` のループ内 `rm -rf` は、同一 Issue 番号（101）で異なる `MOCK_GRAPHQL_RESPONSE` をテストするために必要。除去不可。変更先: `rm -rf "$GH_GRAPHQL_CACHE_DIR"`
- `bats --jobs N` の N: ubuntu-latest は 2 vCPU（`nproc`=2）。動的適応のため `$(nproc)` を採用
- `gh-check-blocking.bats`, `gh-pr-merge-status.bats`, `opportunistic-search.bats` も `cd "$PROJECT_ROOT"` を使用しているが、これらは `gh-graphql.sh` の `--cache` を呼ばないため race condition なし。変更不要
