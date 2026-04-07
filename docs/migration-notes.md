# Migration Notes: GitHub API Utility Scripts (Issue #7)

This document records interface changes made during migration of GitHub API utility scripts from claude-config to wholework.

## Summary

8 scripts and 8 bats test files were migrated. All Japanese text (comments, error messages, usage text, test names) was translated to English. No breaking interface changes were made.

## Per-Script Interface Changes

### gh-graphql.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: 不明なクエリ名: $name"` → `"Error: unknown query name: $name"`
- `"エラー: --cache-ttl オプションには数値が必要です"` → `"Error: --cache-ttl requires a numeric value"`
- `"エラー: クエリが空です"` → `"Error: empty query"`
- `"使い方: ..."` → `"Usage: ..."`
- All other error messages similarly translated

### gh-issue-comment.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: Issue番号は正の整数である必要があります"` → `"Error: issue number must be a positive integer"`
- `"エラー: ファイルが見つかりません"` → `"Error: file not found"`
- `"エラー: 本文が空です"` → `"Error: empty body"`
- `"エラー: Issue #N へのコメント投稿に失敗しました"` → `"Error: failed to post comment to issue #N"`

### gh-issue-edit.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: Issue番号は正の整数である必要があります"` → `"Error: issue number must be a positive integer"`
- `"エラー: ファイルが見つかりません"` → `"Error: file not found"`
- `"エラー: 本文が空です"` → `"Error: empty body"`
- `"エラー: インデックスが範囲外です"` → `"Error: index out of range"`
- `"エラー: インデックスを指定してください"` → `"Error: please specify indices"`
- `"エラー: --check または --uncheck を指定してください"` → `"Error: please specify --check or --uncheck"`
- `"エラー: Issue #N の本文更新に失敗しました"` → `"Error: failed to update issue #N body"`

### gh-label-transition.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: Issue番号が必要です"` → `"Error: issue number is required"`
- `"エラー: Issue番号は正の整数である必要があります"` → `"Error: issue number must be a positive integer"`
- `"エラー: 不正なフェーズです"` → `"Error: invalid phase"`

### gh-check-blocking.sh
**Interface changes**: Fallback path resolution changed

The `~/.claude/scripts/gh-graphql.sh` fallback path was removed. The new path resolution is:
1. Check `$PATH` for `gh-graphql.sh` (enables test mocking)
2. Fall back to `$SCRIPT_DIR/gh-graphql.sh` (same directory)

This makes the script self-contained within the repository without depending on external `~/.claude/scripts/` installations.

Error messages translated to English:
- `"エラー: 不明な引数"` → `"Error: unknown argument"`
- `"エラー: Issue 番号が指定されていません"` → `"Error: issue number is required"`
- `"エラー: Issue #N の取得に失敗しました"` → `"Error: failed to fetch issue #N"`
- `"警告: Issue #N が見つからない..."` → `"Warning: issue #N not found; skipping..."`

### gh-extract-issue-from-pr.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: PR番号が必要です"` → `"Error: PR number is required"`
- `"エラー: PR番号は正の整数である必要があります"` → `"Error: PR number must be a positive integer"`
- `"エラー: PR #N の取得に失敗しました"` → `"Error: failed to fetch PR #N"`

### gh-pr-merge-status.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: PR 番号が必要です。"` → `"Error: PR number is required."`
- `"エラー: PR 番号は正の整数で指定してください"` → `"Error: PR number must be a positive integer"`

### gh-pr-review.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: PR番号は正の整数である必要があります"` → `"Error: PR number must be a positive integer"`
- `"エラー: ファイルが見つかりません"` → `"Error: file not found"`
- `"エラー: レビュー本文が空です"` → `"Error: empty review body"`
- `"エラー: line comments JSON が不正です"` → `"Error: invalid line comments JSON"`
- `"エラー: リポジトリ情報の取得に失敗しました"` → `"Error: failed to get repository info"`

## Test Migration Notes

All bats test files were migrated with the following changes:
- `@test` names: Japanese → English (required to avoid bats parse errors with multibyte characters)
- Assertion strings: Updated to match new English error messages
- `PROJECT_ROOT` path resolution: Uses `"$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` pattern, which works correctly in worktree environments
- Test logic: Unchanged (same mock patterns, same behavioral assertions)
