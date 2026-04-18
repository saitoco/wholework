# Issue #251: tests/run-auto-sub: make PATCH_LOCK per-test by using BATS_TEST_TMPDIR as REPO_ROOT

## Overview

`tests/run-auto-sub.bats` の全 13 テストが `setup()` で mock git の `rev-parse --show-toplevel` を `/tmp/test-repo` 固定値で返しているため、全テストが同一の `PATCH_LOCK_DIR` を共有する。`bats --jobs $(nproc)` 並行実行時にロックの競合が発生し、test 200 (`PATCH_LOCK: lock dir is created during code execution and released after for Size XS`) が断続的に FAIL する。

mock が返す REPO_ROOT を bats が自動生成する `$BATS_TEST_TMPDIR/test-repo` に変更することで、各テストが独立した `PATCH_LOCK_DIR` を持つようにして race condition を排除する。プロダクションコード（`scripts/run-auto-sub.sh`）は変更しない。

## Reproduction Steps

1. `bats --jobs $(nproc) tests/run-auto-sub.bats` を複数回実行する
2. 並行実行タイミングによって test 200 が `[ -f "$LOCK_CHECK_FILE" ]` (line 270) で断続的に FAIL する

## Root Cause

`setup()` 内 mock git (line 76) が全テストで同じ `/tmp/test-repo` を返すため、`run-auto-sub.sh:43-44` で計算される `LOCK_HASH` が全 13 テストで同一になる。並行実行時に他テストの `teardown()` が `rmdir` でロックを削除した後に test 200 の run-code.sh が実行されると、`ls /tmp/claude-auto-patch-lock-*` でロックが見つからず `LOCK_CHECK_FILE` が未作成となり assertion が FAIL する。

## Changed Files

- `tests/run-auto-sub.bats`: 4 箇所修正（bash 3.2+ 互換）
  - `setup()` mock git: ハードコード `/tmp/test-repo` を `${BATS_TEST_TMPDIR}/test-repo` に変更
  - `teardown()`: LOCK_HASH 計算を `$BATS_TEST_TMPDIR/test-repo` ベースに変更
  - test 200 mock run-code.sh: glob `ls /tmp/claude-auto-patch-lock-*` を特定パスの存在チェックに変更
  - test 200 assertion: LOCK_HASH 計算を `$BATS_TEST_TMPDIR/test-repo` ベースに変更

## Implementation Steps

1. `setup()` の mock git ヒアドキュメント (lines 73-84) を修正:
   - `<<'MOCK'` → `<<MOCK` に変更（変数展開を有効化）
   - `echo "/tmp/test-repo"` → `echo "${BATS_TEST_TMPDIR}/test-repo"` に変更
   - ヒアドキュメント内の `$1`、`$3`、`$4` はスクリプト実行時変数なので `\$1`、`\$3`、`\$4` にエスケープ
   (→ 受け入れ基準 2 件目: `/tmp/test-repo` 除去、1 件目: `BATS_TEST_TMPDIR` 追加)

2. `teardown()` の LOCK_HASH 計算 (line 115) を修正:
   - `echo "/tmp/test-repo"` → `echo "$BATS_TEST_TMPDIR/test-repo"` に変更
   (→ 受け入れ基準 2 件目)

3. test 200 の mock run-code.sh ヒアドキュメント (lines 258-263) を修正:
   - ヒアドキュメント直前に `LOCK_HASH=$(echo "$BATS_TEST_TMPDIR/test-repo" | cksum | awk '{print $1}')` を追加
   - `<<'MOCK'` → `<<MOCK` に変更（変数展開を有効化）
   - `ls /tmp/claude-auto-patch-lock-* 2>/dev/null && echo "LOCK_EXISTS" > "$LOCK_CHECK_FILE" || true` を `[ -d "/tmp/claude-auto-patch-lock-${LOCK_HASH}" ] && echo "LOCK_EXISTS" > "\$LOCK_CHECK_FILE" || true` に変更
   - `echo "$@" >> "$RUN_CODE_LOG"` → `echo "\$@" >> "\$RUN_CODE_LOG"` にエスケープ
   (→ 受け入れ基準 3 件目: `/tmp/claude-auto-patch-lock-` glob 除去)

4. test 200 の assertion (line 274) を修正 (after 3):
   - `LOCK_HASH=$(echo "/tmp/test-repo" | cksum | awk '{print $1}')` → `LOCK_HASH=$(echo "$BATS_TEST_TMPDIR/test-repo" | cksum | awk '{print $1}')` に変更
   (→ 受け入れ基準 2 件目)

5. `bats --jobs $(nproc) tests/run-auto-sub.bats` を実行して全 13 テストが PASS することを確認 (after 1-4)
   (→ 受け入れ基準 4 件目)

## Verification

### Pre-merge

- <!-- verify: file_contains "tests/run-auto-sub.bats" "BATS_TEST_TMPDIR" --> mock git の `rev-parse --show-toplevel` 出力がテスト固有ディレクトリ（`$BATS_TEST_TMPDIR` 配下）を返す
- <!-- verify: file_not_contains "tests/run-auto-sub.bats" "/tmp/test-repo" --> ハードコードされた `/tmp/test-repo` 参照が除去されている
- <!-- verify: file_not_contains "tests/run-auto-sub.bats" "/tmp/claude-auto-patch-lock-" --> ハードコードされた lock パス（glob 含む）が除去され、テスト固有 hash 由来のパスに置き換わっている
- <!-- verify: command "bats --jobs $(nproc) tests/run-auto-sub.bats" --> 並行実行で全 13 テストが PASS する

### Post-merge

- main にマージ後、直近 20 件の CI 実行で test 200 の flaky 失敗が観測されないことを確認

## Notes

- `teardown()` で cleanup する lock パスも `$BATS_TEST_TMPDIR/test-repo` ベースに統一する必要がある（Step 2）。`teardown()` は各テスト終了後に呼ばれるため、per-test の `BATS_TEST_TMPDIR` が利用可能
- test 200 の mock run-code.sh はグローバルな setup() 内の mock を上書きするが、LOCK_HASH はそのテスト固有の `$BATS_TEST_TMPDIR` から計算するため独立性が保たれる
- `BATS_TEST_TMPDIR` は bats が各テスト開始前に設定する環境変数で、`teardown()` でも同じ値が利用可能
