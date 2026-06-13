---
type: domain
skill: triage
---

# AC Verify Command Integrity Audit

This Domain file defines the verify command audit patterns for the `/triage` skill.
Used in: Step 7 (Single Issue Execution) and Bulk Execution Step 3 substep 8.

## Purpose

Detect defective `<!-- verify: ... -->` patterns in Issue AC sections before they
propagate to the `/verify` phase and produce false PASSes or false FAILs.

Proven value: In the 2026-06-13 `/auto` session, triage caught verify command defects
in 3 of 14 Issues (21%) — preventing downstream quality failures.

## Processing Steps

1. Extract all `<!-- verify: ... -->` comments from the issue body
2. For each extracted verify command, check against the patterns below
3. Collect all findings
4. If any findings exist, post a single audit comment to the Issue (see ## Non-Destructive Audit Behavior)
5. If no findings, skip silently — do not post an empty comment

## Patterns

### Pattern 1: grep 引数順誤り (Reversed grep Arguments)

Detect: `grep "path/to/file" "pattern"` — a path appears as the first argument
instead of the search pattern. This is the 引数順（引数の順序）誤り anti-pattern.

Indicators that the first argument is a path (not a pattern):
- Ends with a recognized file extension: `.md`, `.sh`, `.py`, `.yml`, `.yaml`, `.json`, `.txt`
- Contains `/` (path separator) — path-like string

Example of incorrect grep 引数順:
```
<!-- verify: grep "skills/triage/SKILL.md" "some pattern" -->
```

Correct form (pattern first, path second):
```
<!-- verify: grep "some pattern" "skills/triage/SKILL.md" -->
```

Fix: swap the two arguments so the search pattern comes first.

### Pattern 2: 常時 PASS な verify command (Always-PASS Command)

Detect: A `file_contains` or `grep` verify command whose search string already
exists in the target file on the `main` branch — before this PR lands.

If the string is already present, the command always returns PASS regardless of
whether the PR's change is correct. It provides no verification signal.

Detection approach:
- Run the grep/file_contains check against the current `main` branch
- If the result is already PASS, flag as 常時 PASS (always-PASS)

Fix options:
- Choose a string that will appear only after the change lands
- Switch to `section_not_contains` or `file_not_contains` to assert removal instead

### Pattern 3: 常時 FAIL な verify command (Always-FAIL Command)

Detect: A `file_contains` or `grep` verify command whose search string has already
been removed from the target file on `main` — before this PR lands.

If the string is already absent, the command always returns FAIL regardless of
the PR's content. It will block the PR unnecessarily.

Detection approach:
- Run the grep/file_contains check against the current `main` branch
- If the result is already FAIL, flag as 常時 FAIL (always-FAIL)

Fix: Update the expected string to match what the implementation will actually produce.

### Pattern 4: patch route × `gh pr checks` 不整合

Detect: Issues with Size XS or S (patch route) whose AC uses
`github_check "gh pr checks"`.

The patch route commits directly to `main` without creating a PR. Therefore,
`gh pr checks` will never find a matching pull request and the check always FAILs.

Size information is available from Step 6 (Size Assignment) when this Step 7 runs.

Fix: Replace `github_check "gh pr checks"` with a `github_check "gh run list"` form,
for example:
```
github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"
```

If multiple workflow files exist under `.github/workflows/`, add `--workflow=<filename>`
to target the specific workflow.

### Pattern 5: Destructive Command Safety Check

Detect: verify commands that contain destructive operations, such as:
- `rm`, `mv`, `cp` (filesystem mutations)
- `gh issue close`, `gh issue delete`, `gh issue edit`
- `gh pr merge`, `gh pr close`
- Any command that modifies external state as a side effect

Verify commands are executed by the `/verify` skill as acceptance tests. They should
be read-only. Destructive commands in verify context can cause irreversible side
effects on Issues, PRs, or the filesystem.

Fix: Remove the destructive command from the verify context and mark the AC line as
`verify-type: manual` so a human performs the check instead.

## Non-Destructive Audit Behavior

This audit is **non-destructive**: triage does NOT auto-edit the Issue body.

When problems are detected, triage posts a comment to the Issue with the findings and
suggested fixes. The user then decides whether and how to update the Issue body.
This avoids destructive behavior in cases where `/issue` may regenerate the AC.

**Post the audit comment** only when at least one pattern match is found.
If no patterns match, skip without posting.

### Comment Format Template

```
⚠️ Triage AC audit: verify command に問題があります

- AC: `<!-- verify: grep "skills/triage/SKILL.md" "some pattern" -->`
  - Pattern: grep の引数順誤り（第 1 引数がパス様文字列）
  - 修復案: `<!-- verify: grep "some pattern" "skills/triage/SKILL.md" -->`

- AC: `<!-- verify: github_check "gh pr checks" "Run bats tests" -->`
  - Pattern: patch route（Size S）× `gh pr checks` 不整合
  - 修復案: `<!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" -->`
```

### Posting the Comment

```bash
mkdir -p .tmp
# Write comment body to .tmp/triage-audit-comment-$NUMBER.md using the Write tool
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $NUMBER .tmp/triage-audit-comment-$NUMBER.md
rm -f .tmp/triage-audit-comment-$NUMBER.md
```
