# Issue #107: verify: Step 2 PR Search Query Fix

## Overview

`/verify` Step 2 は `gh pr list --search "$ISSUE_NUMBER"` でマージ済みPRを検索しているが、数値の部分一致により誤マッチが発生する（例: Issue #70 を検索すると、"70" を含む別のPR #91 がマッチ）。`closes #$ISSUE_NUMBER` という明示的なIssue参照形式に変更することで誤マッチを防ぐ。

## Reproduction Steps

1. Issue #70 に対して `/verify` を実行
2. Step 2 が `gh pr list --search "70"` を実行
3. タイトルや本文に "70" を含む別のPR（例: PR #91 のタイトル "Issue #88: Add title drift check..."）が誤ってマッチ
4. 誤ったPRから `base_ref` を取得し、本来とは異なるベースブランチが使われる可能性がある

## Root Cause

`gh pr list --search "$ISSUE_NUMBER"` は数値を全文検索するため、Issue番号が他のPRのテキスト中に含まれる場合に誤マッチする。`closes #N` など明示的なIssue参照パターンで検索すれば、関連PRのみをターゲットにできる。

Wholeworkは`closes #N`をPR本文の標準キーワードとして使用しており（SKILL.md行252）、この形式での検索が適切。

## Changed Files

- `skills/verify/SKILL.md`: Step 2の `--search "$ISSUE_NUMBER"` を `--search "closes #$ISSUE_NUMBER"` に変更

## Implementation Steps

1. `skills/verify/SKILL.md` の73行目 `PR_NUMBER=$(gh pr list --search "$ISSUE_NUMBER" --state merged --json number --jq ".[0].number")` を `PR_NUMBER=$(gh pr list --search "closes #$ISSUE_NUMBER" --state merged --json number --jq ".[0].number")` に変更する (→ 受け入れ基準A)

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/verify/SKILL.md" "### Step 2: Detect and Update Base Branch" "closes #" --> `skills/verify/SKILL.md` Step 2 の PR検索クエリが `closes #` などIssue参照を明示した形式に更新されている

### Post-merge

- `/verify 107` で検証がPASSすること

## Notes

- Issue本文のAuto-Resolved Ambiguity Pointsより: `closes #$ISSUE_NUMBER` を一次パターンとして採用（SKILL.md既存行252でも `closes #N` が標準として使われており、GitHubの推奨キーワードと一致）
- `gh pr list --search` はGitHubの全文検索APIにクエリを渡すため、`"closes #107"` は"closes #1070"等に部分マッチしないよう単語境界が期待される。実害が生じる確率は低い

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
