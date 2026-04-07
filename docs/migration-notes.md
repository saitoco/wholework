# Migration Notes

---

## Issue #8: Project Utilities and Skill Runner Scripts

13 scripts and 10 bats test files were migrated. All Japanese text (comments, error messages, usage text, test names) was translated to English. No breaking interface changes were made.

### Per-Script Interface Changes

#### get-issue-size.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: $0 <issue-number>"` → `"Usage: $0 <issue-number>"`
- `"エラー: Issue番号は正の整数である必要があります: $NUMBER"` → `"Error: Issue number must be a positive integer: $NUMBER"`

#### get-issue-type.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: $0 <issue-number>"` → `"Usage: $0 <issue-number>"`
- `"エラー: Issue番号は正の整数である必要があります: $NUMBER"` → `"Error: Issue number must be a positive integer: $NUMBER"`
- Help text (`--help`) translated to English

#### get-sub-issue-graph.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: get-sub-issue-graph.sh <親Issue番号>"` → `"Usage: get-sub-issue-graph.sh <parent-issue-number>"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"循環依存が検出されました。"` → `"Circular dependency detected."`

#### log-permission.sh
**Interface changes**: None

Comments translated to English. No user-facing messages (this script outputs JSON only).

#### opportunistic-search.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: 不明なオプション: $1"` → `"Error: Unknown option: $1"`
- `"エラー: スキル名は1つだけ指定してください"` → `"Error: Only one skill name may be specified"`
- `"使い方: $0 <スキル名> [--dry-run]"` → `"Usage: $0 <skill-name> [--dry-run]"`

#### triage-backlog-filter.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: --limit オプションには数値が必要です"` → `"Error: --limit option requires a numeric value"`
- `"エラー: --assignee オプションにはユーザー名が必要です"` → `"Error: --assignee option requires a username"`
- `"エラー: 不明なオプション: $1"` → `"Error: Unknown option: $1"`

#### run-code.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-code.sh <issue番号> ..."` → `"Usage: run-code.sh <issue-number> ..."`
- `"エラー: --patch/--pr は同時に指定できません"` → `"Error: --patch and --pr cannot be specified together"`
- `"エラー: --base にはブランチ名が必要です"` → `"Error: --base requires a branch name"`
- `"エラー: 不正なオプション: $1"` → `"Error: Invalid option: $1"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"エラー: SKILL.md が見つかりません"` → `"Error: SKILL.md not found"`
- `"エラー: SKILL.md のフロントマターが見つかりません"` → `"Error: SKILL.md frontmatter not found"`

#### run-issue.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-issue.sh <issue番号>"` → `"Usage: run-issue.sh <issue-number>"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"エラー: 不正な引数: $*"` → `"Error: Unexpected arguments: $*"`

#### run-merge.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-merge.sh <PR番号>"` → `"Usage: run-merge.sh <pr-number>"`
- `"エラー: PR番号は数値である必要があります"` → `"Error: PR number must be numeric"`

#### run-review.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-review.sh <PR番号>"` → `"Usage: run-review.sh <pr-number>"`
- `"エラー: PR番号は数値である必要があります"` → `"Error: PR number must be numeric"`

#### run-spec.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-spec.sh <issue番号> [--opus]"` → `"Usage: run-spec.sh <issue-number> [--opus]"`
- `"エラー: 不正なオプション: $1"` → `"Error: Invalid option: $1"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`

#### run-verify.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-verify.sh <Issue番号> ..."` → `"Usage: run-verify.sh <issue-number> ..."`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"エラー: --base にはブランチ名が必要です"` → `"Error: --base requires a branch name"`
- `"エラー: 不正なオプション: $1"` → `"Error: Invalid option: $1"`
- `"エラー: verify が VERIFY_FAILED マーカーを出力しました"` → `"Error: verify output contained VERIFY_FAILED marker"`

#### run-auto-sub.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-auto-sub.sh <sub-issue番号> ..."` → `"Usage: run-auto-sub.sh <sub-issue-number> ..."`
- `"エラー: --base にはブランチ名が必要です"` → `"Error: --base requires a branch name"`
- `"エラー: 不正なオプション: $1"` → `"Error: Invalid option: $1"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"patch ルートは main への直接コミットのため順次実行（ロック取得待機中...）"` → `"Patch route commits directly to main, running sequentially (waiting for lock...)"`
- `"エラー: patch ロック取得タイムアウト"` → `"Error: Patch lock acquisition timeout"`
- `"patch ロック取得:"` → `"Patch lock acquired:"`
- `"verify FAIL: git pull --ff-only で同期後にリトライします"` → `"verify FAILED: syncing with git pull --ff-only and retrying"`
- `"エラー: issue #N の Size が設定されていません"` → `"Error: Size is not set for issue #N"`
- `"エラー: issue #N は XL です。"` → `"Error: issue #N is XL."`
- Various phase labels translated: `"--- spec フェーズ: ..."` → `"--- spec phase: ..."`
- `"エラー: 不明な Size"` → `"Error: Unknown Size"`
- Various PR-related messages translated

### Test Migration Notes

All 10 bats test files were migrated with the following changes:
- `@test` names: Japanese → English (required to avoid bats parse errors with multibyte characters)
- Assertion strings: Updated to match new English error messages
- `PROJECT_ROOT` path resolution: Uses `"$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` pattern, which works correctly in worktree environments
- Test logic: Unchanged (same mock patterns, same behavioral assertions)

---

## Issue #7: GitHub API Utility Scripts

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
