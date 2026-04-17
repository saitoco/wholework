# verify-classifier

Classification criteria and logic for determining the verifiability type of post-merge conditions.

## Purpose

This file provides classification criteria for assigning `<!-- verify-type: auto|opportunistic|manual -->` tags to each condition in the post-merge acceptance criteria section. Caller: `/issue`. Expected to also be referenced by `/verify` in the future.

## Input

Information provided by the calling skill:

- Each acceptance condition from the post-merge section

## Processing Steps

Skills that Read this file should evaluate each post-merge condition against the classification criteria **in order from top to bottom**, assigning the `<!-- verify-type: TYPE -->` tag of the first matching type.

### Classification Criteria (Priority: auto > opportunistic > manual)

| Type | Criteria | Examples |
|------|---------|---------|
| `auto` | A verify command (`<!-- verify: ... -->`) is actually attached | File existence check, grep pattern match, test execution |
| `opportunistic` | Condition text matches the pattern "verify X when `/skill-name` is run" | "Confirm doc impact check runs when `/spec` is executed" |
| `manual` | Does not match either of the above | "Confirm no dialog appears", "Visual browser verification" |

### Tag Assignment Example

```markdown
### Post-Merge
- [ ] <!-- verify: github_check "gh pr checks" "Run bats tests" --> All bats tests PASS <!-- verify-type: auto -->
- [ ] Confirm test file search is included when `/spec` runs <!-- verify-type: opportunistic -->
- [ ] User visually confirms no confirmation dialog appears <!-- verify-type: manual -->
```

### Constraint: Required Rule When Using auto Type

When assigning `<!-- verify-type: auto -->` to a condition, a `<!-- verify: ... -->` verify command **must be present**.

- `verify-type: auto` is assigned only to conditions that have a verify command (a `auto` without a verify command is equivalent to skipping verification, which contradicts user expectations)
- If a verify command cannot be provided, classify as `opportunistic` or `manual` instead

### Translation File Condition Verification

Conditions that require verifying a translate update (e.g., "Update `docs/ja/tech.md`
to reflect changes") can be automatically verified using `file_contains` or `grep`.
Do not default to `verify-type: manual` for translation conditions — attach a verify
command and classify as `auto`.

**Pattern: `file_contains "docs/ja/xxx.md" "keyword"`**

Pick a keyword that must appear in the translated file after the update:

```markdown
- [ ] Update `docs/ja/tech.md` with the new section
  <!-- verify: file_contains "docs/ja/tech.md" "翻訳後のキーワード" -->
  <!-- verify-type: auto -->
```

Keyword selection tips:
- Use a term that is unique to the added/changed content (a section heading or a key concept)
- Prefer Japanese terms that are unlikely to appear elsewhere in the file

When a keyword cannot be identified, fall back to `grep` with a broader pattern:

```markdown
<!-- verify: grep "translate" docs/ja/tech.md -->
```

### Patch Route CI Verification Note

For Issues implemented via the patch route (direct commit to main, no PR), `github_check "gh pr checks"` **cannot be used** — no PR exists in the patch route.

Use the `github_check "gh run list"` form instead:

```
github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"
```

When `/verify` detects `github_check "gh pr checks"` in an acceptance condition for a patch-route Issue (PR_NUMBER is empty), it treats the condition as UNCERTAIN and recommends switching to the `gh run list` form.

## Output

Assign the `<!-- verify-type: auto|opportunistic|manual -->` tag to the end of each post-merge condition. Place the tag one half-width space before the line break at the end of the condition text.
