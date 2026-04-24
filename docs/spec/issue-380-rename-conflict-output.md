# Issue #380: scripts: worktree-merge-push.sh の conflict_output 変数を conflict_files にリネーム

## Overview

`scripts/worktree-merge-push.sh` では Issue #378 の対応で `git grep -l '^<<<<<<'` に変更された。`git grep -l` はファイル名リストを返す（行番号なし）が、変数名 `conflict_output` はそのままで残っており、内容と命名が乖離している。

`conflict_output` を `conflict_files` にリネームして内容と命名を一致させる。

## Changed Files

- `scripts/worktree-merge-push.sh`: 変数名 `conflict_output` → `conflict_files` にリネーム（行 90-91）— bash 3.2+ 互換（変数参照のみ）

## Implementation Steps

1. `scripts/worktree-merge-push.sh` の行 90-91 で `conflict_output` を `conflict_files` にリネーム（→ AC1, AC2）
   - 行 90: `conflict_output=$(git grep -l '^<<<<<<' 2>/dev/null || true)` → `conflict_files=$(git grep -l '^<<<<<<' 2>/dev/null || true)`
   - 行 91: `if [[ -n "$conflict_output" ]]; then` → `if [[ -n "$conflict_files" ]]; then`

## Verification

### Pre-merge

- <!-- verify: grep "conflict_files" "scripts/worktree-merge-push.sh" --> `scripts/worktree-merge-push.sh` の変数名が `conflict_files` に変更されている
- <!-- verify: file_not_contains "scripts/worktree-merge-push.sh" "conflict_output" --> `conflict_output` の参照がすべて削除されている
- <!-- verify: command "bash -c 'cd /tmp && git init test-rename-$$; cd test-rename-$$; echo test > f.txt; git add f.txt; git commit -m init; bash $(git rev-parse --show-toplevel 2>/dev/null || echo .)/scripts/worktree-merge-push.sh --help 2>&1 || true; cd /tmp; rm -rf test-rename-$$'" --> スクリプトが構文エラーなく起動できる

### Post-merge

- `scripts/worktree-merge-push.sh` の `conflict_files` が正しく動作することを `/auto` 実行等で確認する
