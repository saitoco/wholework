# verify-patterns

Accuracy guidelines for verify command patterns.

## Purpose

This file provides guidelines for managing the quality of verify command patterns (`<!-- verify: ... -->`) in acceptance criteria. Callers: `/issue`, `/spec`.

## Input

Information provided by the calling skill:

- Acceptance criteria text
- Target file paths (when creating grep/file_contains patterns)

## Processing Steps

Skills that Read this file should design verify command patterns following these guidelines.

### 1. False Positive Patterns and How to Avoid Them

| Pattern | Problem | How to Avoid | Example |
|---------|---------|-------------|---------|
| Using `grep` to verify multi-line content | `grep` matches only single lines. Multi-line content (JSON schemas, YAML, multi-paragraph text) will FAIL if keywords are split across lines | Use `file_contains` to verify one representative keyword at a time | ❌ `grep "new_title.*type.*size"` → ✅ `file_contains "path" "new_title"` + `file_contains "path" "type"` + `file_contains "path" "size"` |
| Requiring multiple keywords on the same line with `grep` | `grep "A.*B.*C"` only matches when A, B, C are on the same line. FAIL if spread across multiple lines | Split into separate `grep` hints per keyword | ❌ `grep "add.*remove.*label-change"` → ✅ `grep "add" "path"` + `grep "remove" "path"` + `grep "label-change" "path"` |
| `file_not_contains` for negation expressions | Negative phrasing ("do not use", "remove") can still contain the string being checked, causing false positives | Use verb+context combinations to verify specific context | ❌ `file_not_contains "file" "Task subagent"` → ✅ `file_not_contains "file" "to subagent"` or `file_not_contains "file" "using subagent"` |
| Simple numeric patterns | Plain numbers without context can match unintended lines (e.g., `grep "30"` matches non-timeout lines) | Use context-rich patterns instead of bare numbers | ❌ `grep "30" "config.json"` → ✅ `grep "timeout: 30000" "config.json"` |
| Interference with example code in docs | `file_not_contains` can falsely match text in "bad example" code fences in documentation | Account for code fence interference when designing patterns | ❌ `file_not_contains` that matches a bad-example code block → ✅ use a pattern targeting only the actual config section |
| `file_not_contains` false negatives due to full-file matching | `file_not_contains` searches the entire file, so text remaining in retrospectives, backgrounds, or code fence examples causes false negatives (occurred in #509) | Use `section_not_contains` to scope search to a specific section. `section_not_contains "path" "## Heading" "text"` limits the search to within the specified markdown heading | ❌ `file_not_contains "issue.md" "old-command"` (fails if reference text remains in retrospective) → ✅ `section_not_contains "issue.md" "## Acceptance Criteria" "old-command"` |
| Matching across markdown table columns with `grep` | In markdown tables, column headers (e.g., `Spec`) and cell values (e.g., `not required`) are on different lines, so cross-column grep patterns like `grep "XS.*spec.*not-required"` will FAIL (occurred in #608) | (1) Only grep for keywords that appear on the same line; (2) use `section_contains` for multi-column verification | ❌ `grep "XS.*spec.*not-required" "modules/size-workflow-table.md"` → ✅ `grep "XS.*patch" "modules/size-workflow-table.md"` + `section_contains "modules/size-workflow-table.md" "## Table" "not required"` |
| Using full-width brackets in `section_contains` / `section_not_contains` search text | These commands use fixed-string substring matching. Full-width brackets (`（` `)`) will FAIL if implementation uses half-width brackets (`(` `)`) (occurred in #627) | Use **half-width ASCII characters and brackets** in search text. Match the actual character format used in the implementation | ❌ `section_contains "SKILL.md" "## Completion Report" "patch（XS）"` → ✅ `section_contains "SKILL.md" "## Completion Report" "patch (XS)"` |
| Using count aggregation in `command` hints (`grep \| wc -l`, `test $(grep -c ...) -ge N`, etc.) | Hard to correlate with CI jobs; becomes UNCERTAIN in `/review` safe mode. Dedicated commands like `file_contains` cannot express count verification (occurred in #364) | Move count-based verification to post-merge `verify-type: opportunistic` instead of pre-merge `command` hints. Consider replacing with representative keyword existence checks (`grep` or `file_contains`) | ❌ `command "test $(grep -rl 'pattern' dir \| wc -l) -ge 5"` → ✅ Move to post-merge with `verify-type: opportunistic`, or verify with `grep "pattern" "path"` per representative file |
| Logic direction mismatch between acceptance condition and PASS criteria | Using `grep` (match = PASS) for "must not exist" conditions inverts the logic (occurred in #512) | Confirm whether the acceptance condition is positive (must exist) or negative (must not exist). Use negation commands (`file_not_contains` / `file_not_exists`) for negative conditions | ❌ `grep "^context:" "file"` (checking for absence but match = PASS) → ✅ `file_not_contains "file" "context:"` |
| Missing required arguments in `command` hints | `command "python3 scripts/validate-skill-syntax.py"` without required arguments causes the command itself to exit with code 1 (occurred in #626) | Include the complete command with all required arguments. Verify required arguments from help or existing examples | ❌ `command "python3 scripts/validate-skill-syntax.py"` → ✅ `command "python3 scripts/validate-skill-syntax.py skills/"` |
| Verifying regex implementation pattern strings with `grep` | Regex patterns (e.g., `Step [0-9]+\.[0-9]+`) will FAIL if implementation uses equivalent but different notation (e.g., `\d+\.\d+`) (occurred in #593) | Grep for the function name using the regex, not the pattern string itself. Function names are stable verification targets | ❌ `grep "Step [0-9]+\\.[0-9]+" "scripts/validate-skill-syntax.py"` → ✅ `grep "validate_decimal_steps" "scripts/validate-skill-syntax.py"` |
| Using `section_contains` / `file_contains` for OR search | Both commands use fixed-string matching; `|` is treated as a literal character, not OR. Passing `"patA|patB"` searches for the exact string `"patA|patB"` — it does not match `patA` or `patB` individually (occurred in #72) | Split OR conditions into separate commands, one per pattern | ❌ `section_contains "f" "## H" "A|B"` → ✅ `section_contains "f" "## H" "A"` + `section_contains "f" "## H" "B"` (same for `file_contains`) |

### 2. Prefer `grep` Over `file_contains` for Text Presence Checks

When verifying text presence, prefer `grep` (regex match) over `file_contains` (fixed string match).

| Aspect | `file_contains` | `grep` |
|--------|-----------------|--------|
| Match method | Fixed string (substring) | Regex match |
| Tolerance for variations | Low (requires exact string as in implementation) | High (flexible with `.*` etc.) |
| Recommended for | Simple existence checks for fixed strings (variable names, URLs, etc.) | Natural language text, comments, documentation content |

Examples of variations and how to handle them:
- Spec: "duplicate detection" → Implementation: "detect duplicates", "detecting duplications"
- ❌ `file_contains "path" "duplicate detection"` — does not match "detect duplicates"
- ✅ `grep "detect.*duplic" "path"` — matches either phrasing

Decision criteria (for single-line text verification):
- **Use `grep`**: natural language text, comments, documentation content at the single-line level
- **Use `file_contains`**: variable names, function names, URLs, paths and other mechanical fixed strings
- **For multi-line content**: outside this section's scope; use `file_contains` with representative keywords per existing guidelines

### 3. Pre-Check Target File Format (Cross-Referencing)

**Literal string requirement for `section_contains`/`file_contains`:**

`section_contains` and `file_contains` use fixed-string matching. The keyword must be literally present in the target implementation file for the command to PASS. When a verify command FAILs because the literal string is absent from the file, the correct fix is to **add the missing text to the implementation** — not to rewrite the hint. Rewriting the hint is appropriate only when the keyword was incorrectly specified (miscalibrated hint).

When designing `grep`/`file_contains` patterns, follow this cross-reference procedure.

**Cross-Reference Procedure:**

1. Read or Grep the target file to verify the actual format
2. Cross-check that the pattern matches the intended line
3. For `file_not_contains`, check for unintended matches elsewhere in the file (code fences, inline code, etc.), especially for residual-check purposes

**Points to Check:**

- Backtick-wrapped (`` `xxx` ``), code fence, and HTML comment content can cause unexpected matches or mismatches
- Example: writing `file_contains "CLAUDE.md" "/review"` — if CLAUDE.md contains `/review` wrapped in backticks as `` `/review` ``, the pattern will match. If it's inside a code fence, the context may differ from the intent

**Cross-Reference for New Code Additions:**

For new code additions, the target text does not yet exist in the file, so the post-implementation string format must be predicted to design the grep pattern. Divergence between predicted and actual format causes the verify command to miss the intended code.

Concrete divergence example (case statement patterns):
- If a new query `get-issue-id` is implemented in a case statement, the actual form is `get-issue-id)`
- ❌ `grep "query get-issue-id"` — no line containing `query` exists in the case statement
- ✅ `grep "get-issue-id)" "path"` — matches the actual case statement format

Prediction procedure:
1. Read or Grep existing code patterns in the target file (case statements, function definitions, variable declarations, etc.)
2. Predict whether the added code will follow the same format (e.g., confirm existing case entry format and judge new entries will follow the same)
3. Confirm the grep pattern will match the predicted format before finalizing the hint

**Design-Time Cross-Reference (`/spec` skill):**

When creating `grep` hints at design time, cross-check that matching text actually exists in the target file. This prevents rework from format mismatches after implementation.

- After creating a `grep "pattern" "path"` hint, verify the target file actually contains text matching the pattern
- If not present, revise the pattern or explicitly note that it will be verified after implementation

### 4. Case Consistency in grep Hints

When verifying identifiers (variable names, function names, constant names) with `grep`/`file_contains`, write them in exactly the same case as the implementation.

| Target | Convention | How to Handle |
|--------|-----------|---------------|
| Shell script variables | Uppercase (e.g., `CREATED_LINKS`) | Write in uppercase |
| Python function/variable names | snake_case (e.g., `validate_verify_commands`) | Write in the exact same form as implementation |
| Constant names | UPPER_SNAKE_CASE (e.g., `KNOWN_VERIFY_COMMAND_TYPES`) | Write in uppercase |

**Examples:**
- ❌ `grep "created_links" "script.sh"` — shell scripts use uppercase variables, so no match
- ✅ `grep "CREATED_LINKS" "script.sh"` — correct form matching shell script conventions

**Procedure:** Read or Grep the target file to confirm the actual casing of identifiers, then use that exact form in the pattern.

**`file_contains` is case-sensitive — match keyword casing to implementation:**

`file_contains` uses fixed-string matching and is **case-sensitive**. When verifying natural language keywords (e.g., description text, section headings, comments), ensure the keyword in the verify command exactly matches the case used in the implementation.

- ❌ `file_contains "SKILL.md" "partial description"` — FAIL if implementation writes "Partial description" (uppercase P)
- ✅ Use **lowercase** keywords in `file_contains` only when the implementation is confirmed to use lowercase

**Best practice:** When writing a `file_contains` hint with a lowercase keyword, confirm that the implementation also writes it in lowercase. If the implementation may use sentence-start capitalization or mixed case, prefer `grep` with a flexible pattern (e.g., `grep "[Pp]artial description"`) over `file_contains`.

### 5. Verify Commands When Adding New Command Types to Documentation

For issues involving documentation changes such as adding new command types to verify command tables, recommend combining `grep` for existence checks with `section_contains` to also verify the correctness of description text (purpose, guidance wording, etc.).

**Background**: `grep` is effective for checking keyword presence, but cannot verify that the keyword is used in the correct section and context. Adding `section_contains` extends verification coverage to functional correctness within a specific section.

**Recommended Pattern (example):**

```
<!-- verify: grep "new_command" "modules/xxx.md" -->
<!-- verify: section_contains "modules/xxx.md" "### Relevant Section Heading" "new_command" -->
```

- Use `grep` to confirm the command name or keyword exists
- Use `section_contains` to confirm the description text is present within the target section

**Concrete example using `section_contains`:**

```
- [ ] <!-- verify: grep "file_not_exists" "modules/verify-patterns.md" --> `file_not_exists` command has been added
- [ ] <!-- verify: section_contains "modules/verify-patterns.md" "### 1." "file_not_exists" --> Guideline section contains `file_not_exists` description
```

### 6. Verification Target Files for Module-Delegated Processing

When a skill (`skills/*/SKILL.md`) delegates part of its processing to a shared module (`modules/*.md`), specify the **delegate module file directly** as the `grep` / `file_contains` target in verify commands.

**Background**: Skill files contain only the delegation instruction ("Read module and follow it"), while actual processing logic (warning messages, error handling, etc.) is written in the delegate module. Grepping the skill file can cause false positives when delegation instruction text or other contextual keywords unintentionally match (occurred in #775).

**Recommended Pattern:**

- When the logic to verify (message text, processing steps, etc.) is implemented in the delegate module:
  - ✅ `grep "warning" "modules/worktree-lifecycle.md"` — directly verifies the delegate module
  - ❌ `grep "warning" "skills/spec/SKILL.md"` — skill file contains only delegation instruction, not the actual warning logic

**Decision Procedure:**

1. Identify the logic (message text, error handling, etc.) that the acceptance condition verifies
2. Determine whether that logic is directly written in the skill file or delegated to a module
3. If delegated, specify the delegate module file as the `grep` / `file_contains` target

### 7. GitHub Actions Workflow Changes — Combine file_contains and github_check

When `.github/workflows/*.yml` is a change target in an Issue, `file_contains` alone cannot detect GitHub Actions configuration errors (e.g., missing required options). This was discovered in the #73 (DCO introduction) verify retrospective: `file_contains ".github/workflows/dco.yml" "tim-actions/dco"` PASSed despite the CI failing due to a missing `commits: required: true` setting.

**Recommended pattern:**

Combine `file_contains` (config content existence) with `github_check "gh run list"` (CI execution result):

```
<!-- verify: file_contains ".github/workflows/dco.yml" "tim-actions/dco" --> Configuration content exists
<!-- verify: github_check "gh run list --workflow=dco.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI run succeeded
```

**Role of each verify command:**

| Command | Role | What it detects |
|---------|------|-----------------|
| `file_contains` | Config content existence | Confirms the workflow file contains the intended action/step |
| `github_check "gh run list"` | CI execution result | Detects misconfiguration (missing required options, invalid syntax, etc.) that `file_contains` cannot catch |

**Note on `gh run list` vs `gh pr checks`:**

For patch route Issues (no PR), `gh pr checks` is not available. Always use `gh run list` for CI result verification. See `${CLAUDE_PLUGIN_ROOT}/modules/verify-classifier.md` for details.

### 8. Policy change Issues — Verify Old Policy Deletion with file_not_contains

When an Issue involves replacing an existing policy with a new one (e.g., changing error handling strategy, changing fallback behavior), verify commands must confirm not only that the new policy text is present but also that the old policy text has been removed.

**Background**: Policy change PRs frequently leave residual old policy text as inline comments or surrounding context outside the directly changed lines. CI and tests cannot detect such residual text — only human review can catch it (occurred in #208).

**Recommended Pattern:**

Add `file_not_contains` (or `section_not_contains`) alongside `file_contains` to verify deletion of old policy keywords:

```
<!-- verify: file_contains "skills/code/SKILL.md" "auto-resolve" -->  New policy is present
<!-- verify: file_not_contains "skills/code/SKILL.md" "exit with non-zero" -->  Old policy keyword deleted
```

**Concrete example — replacing "exit with error" with "auto-resolve":**

```markdown
## Acceptance Criteria

### Pre-merge (auto-verified)
- [ ] <!-- verify: file_contains "skills/code/SKILL.md" "auto-resolve" --> New policy description is present
- [ ] <!-- verify: file_not_contains "skills/code/SKILL.md" "exit with non-zero" --> Old policy keyword has been removed
```

**When to use `section_not_contains` instead of `file_not_contains`:**

If the old policy keyword may legitimately appear elsewhere in the file (e.g., in background sections, retrospectives, or "bad example" code fences), use `section_not_contains` to limit the scope:

```
<!-- verify: section_not_contains "skills/code/SKILL.md" "## Error Handling" "exit with non-zero" -->
```

**Decision procedure:**

1. Identify the old policy keywords that the change is supposed to remove (e.g., "exit with non-zero", "abort immediately")
2. Check whether those keywords may legitimately remain elsewhere in the file (retrospectives, background, bad-example code fences)
3. If a file-wide check is safe: use `file_not_contains`
4. If scope must be limited to a specific section: use `section_not_contains "path" "## Heading" "keyword"`

### 9. When to Use `rubric` vs hard-pattern

`rubric` is designed for acceptance conditions where hard-pattern commands are structurally weak.

**Use `rubric` when:**

| Category | Why hard-pattern fails | Example |
|----------|----------------------|---------|
| Semantic equivalence | Wording may vary without changing meaning; `file_contains` requires exact string | `rubric "Documentation adequately explains the rubric command behavior"` |
| Subjective evaluation | UI quality, UX, readability — no fixed string to match | `rubric "The error message is clear and actionable"` |
| Multi-line conceptual presence | An idea expressed across paragraphs; `grep` only matches single lines | `rubric "The module covers all three return values"` |
| Full-width / half-width variation | Japanese content may use either form; `file_contains` is exact-match | `rubric "The section is written in Japanese"` |
| Behavioral intent | The condition is about runtime behavior, not file content | `rubric "The grader adopts an adversarial stance as described in the issue"` |

**Use hard-pattern (`file_contains`, `grep`, etc.) when:**

- The implementation must contain a specific literal string (model ID, command name, flag value, URL)
- CI determinism is required (the condition must never be UNCERTAIN due to LLM variance)
- The condition is purely structural (file exists, section heading present)

**Selection guideline:**

If you can write the exact string the implementation will contain, prefer hard-pattern.
If the condition is about meaning, intent, quality, or natural-language content where exact strings are uncertain, prefer `rubric`.

**Two-phase verification with `rubric`:**
When `verify: rubric` is declared in an acceptance condition, the grader runs at both pre-merge and post-merge phases. During `/review` (safe mode, pre-merge), the rubric grader executes and its PASS/FAIL/UNCERTAIN result appears in the review comment — enabling early detection of semantic gaps before the PR is merged. During `/verify` (full mode, post-merge), the same grader runs again and updates the acceptance condition checkbox.

**Combining `rubric` with supplementary `file_contains` / `section_contains`:**

When using `rubric` and the implementation file and section are predictable in advance, add `file_contains` or `section_contains` as a supplementary check alongside `rubric`. This compensates for LLM variance in semantic judgment by providing a mechanical structural safety net: `rubric` verifies semantic quality (meaning and completeness); the supplementary check independently confirms that the target keyword exists in the expected location.

When to apply:
- The target implementation file is known (not TBD or contingent on implementation choices)
- The target section heading is predictable in advance
- The `rubric` condition involves natural language content in a specific file section

When NOT to apply:
- The implementation location is unknown or developer-determined
- The `rubric` condition is purely behavioral (runtime behavior, not file content)

Recommended pattern:

```
<!-- verify: rubric "description of semantic quality expected" -->
<!-- verify: section_contains "path/to/file.md" "## Target Section" "representative keyword" -->
```

Example:

```markdown
- [ ] <!-- verify: rubric "modules/verify-patterns.md §9 includes guidance on combining rubric with file_contains as supplementary verification" --> Combination guidance is present
- [ ] <!-- verify: section_contains "modules/verify-patterns.md" "### 9." "file_contains" --> §9 contains the keyword `file_contains`
```

The `section_contains` check catches cases where content was added to the wrong section or omitted entirely — false positives that `rubric` alone may miss due to LLM variance.

## Output

Design verify commands following these guidelines and apply them to acceptance criteria.
