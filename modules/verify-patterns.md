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
| Distance rules with upper-bound-only notation (e.g., "XX% 以内") | 下限 (lower bound) is unspecified; implementation may omit the lower bound check entirely, allowing out-of-range values through (detected as SHOULD in review when Spec only states "XX% 以内") | Write distance rules in the form "A 以上かつ B 以下" to make both lower and upper bounds explicit. This allows verify commands to check both directions | ❌ Spec: "類似度 80% 以内" → Implementation: `score <= 0.8` only (missing `>= 0` check) → ✅ Spec: "類似度 0% 以上かつ 80% 以下" → Implementation covers both bounds |
| Missing required arguments in `command` hints | `command "python3 scripts/validate-skill-syntax.py"` without required arguments causes the command itself to exit with code 1 (occurred in #626) | Include the complete command with all required arguments. Verify required arguments from help or existing examples | ❌ `command "python3 scripts/validate-skill-syntax.py"` → ✅ `command "python3 scripts/validate-skill-syntax.py skills/"` |
| Verifying regex implementation pattern strings with `grep` | Regex patterns (e.g., `Step [0-9]+\.[0-9]+`) will FAIL if implementation uses equivalent but different notation (e.g., `\d+\.\d+`) (occurred in #593) | Grep for the function name using the regex, not the pattern string itself. Function names are stable verification targets | ❌ `grep "Step [0-9]+\\.[0-9]+" "scripts/validate-skill-syntax.py"` → ✅ `grep "validate_decimal_steps" "scripts/validate-skill-syntax.py"` |
| Using `section_contains` / `file_contains` for OR search | Both commands use fixed-string matching; `|` is treated as a literal character, not OR. Passing `"patA|patB"` searches for the exact string `"patA|patB"` — it does not match `patA` or `patB` individually (occurred in #72) | Split OR conditions into separate commands, one per pattern | ❌ `section_contains "f" "## H" "A|B"` → ✅ `section_contains "f" "## H" "A"` + `section_contains "f" "## H" "B"` (same for `file_contains`) |
| Including shell quoting / variable references in `file_contains` / `section_contains` search strings for script invocations | When verifying a script call like `"$SCRIPT_DIR/get-config-value.sh" permission-mode auto`, specifying the search string with surrounding quotes or variable references (e.g., `get-config-value.sh permission-mode auto`) FAILs because `.sh` is followed by `"` in the actual code, breaking the fixed-string match (occurred in #385) | For script invocation patterns, use only the **argument substring** as the search string. This avoids false negatives from shell quoting differences (`"`, `'`) and variable reference variants (`$SCRIPT_DIR/`, `${CLAUDE_PLUGIN_ROOT}/`, bare path) | ❌ `file_contains "scripts/foo.sh" "get-config-value.sh permission-mode auto"` (FAIL when actual code is `"$SCRIPT_DIR/get-config-value.sh" permission-mode auto`) → ✅ `file_contains "scripts/foo.sh" "permission-mode auto"` (matches regardless of quoting/variable form) |

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

**CI verify command scope design (PR route):**

`github_check "gh pr checks"` checks all CI status on the PR — including test results from jobs unrelated to the PR's changes. If pre-existing failing tests on `main` are present, they appear in `gh pr checks` output, causing false FAILs that require human judgment to determine whether the failure is within scope (observed in #695 and #702).

Preferred pattern 1 — specific workflow (scope limited to a single workflow file):

```
<!-- verify: github_check "gh run list --workflow=<specific>.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" -->
```

Preferred pattern 2 — direct test execution (scope limited to a single test file):

```
<!-- verify: command "bats tests/<specific>.bats" -->
```

**Usage criteria:**

| Verify command | Scope | When to use |
|----------------|-------|-------------|
| `gh pr checks` | Entire PR — all CI jobs | When all CI jobs must pass together (e.g., release gate); accept out-of-scope failure risk |
| `gh run list --workflow=<specific>.yml` | Single workflow file | When only a specific workflow's success matters; avoids pre-existing failures in unrelated jobs |
| `gh run view ... --json jobs --jq '.jobs[] \| select(.name=="<job>").conclusion'` | Single named job within a workflow | When unrelated jobs in the same workflow have pre-existing failures; scoped to one job, no false positives from other jobs |
| `command "bats tests/<specific>.bats"` | Single test file | When testing a specific bats file directly; fully decoupled from CI state |

**Job-level conclusion sub-form (github_check variant):**

When a multi-job workflow contains pre-existing failures in unrelated jobs (e.g., a `Forbidden Expressions check` job that fails on `main`), the workflow-level `gh run list` form returns a non-`success` conclusion and causes false FAILs even when the target job itself passed.

Use the job-level form to reference only the specific job that the AC is designed to verify:

```
<!-- verify: github_check "gh run view $(gh run list --workflow=ci.yml --limit=1 --json databaseId --jq '.[0].databaseId') --json jobs --jq '.jobs[] | select(.name==\"Run bats tests\").conclusion'" "success" -->
```

This form uses `gh run view` with `--json jobs` to extract the conclusion of a single named job. Because `gh run view` is in the `github_check` safe mode allowlist, this command executes in both safe and full modes. Unrelated job failures do not affect the result.

**Fallback guidance:** When `gh pr checks` must be used (e.g., whole-CI gate), write "all CI green" explicitly in the AC text to clarify that the condition covers the full CI. This signals that handling of out-of-scope failures (e.g., pre-existing failures on `main`) is delegated to the verify phase reviewer.

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

**Manually-input dependent placeholder fields:**

When a rubric AC verifies a field that is automatically inserted but whose value depends on manual input (e.g., `stop_loss`, form placeholders, or fields left blank for human completion), the rubric description must explicitly state both behaviors:

- The **field is inserted** (structural presence is automatic)
- The **value is an empty placeholder** when manual input has not yet been provided

Without this explicit description, the rubric grader may interpret "field is automatically filled" as requiring a non-empty value — causing false FAIL for implementations that correctly leave the field as a blank placeholder pending manual input.

**Template:**

```
rubric "{field} フィールドとして挿入されるが手動入力未完時は空欄 placeholder"
```

**Correct vs ambiguous phrasing:**

| AC phrasing | Risk | Explanation |
|------------|------|-------------|
| ❌ `rubric "{field} が自動入力される"` | FAIL risk | Implies a non-empty value; grader may FAIL a correct blank placeholder |
| ✅ `rubric "{field} フィールドとして挿入されるが手動入力未完時は空欄 placeholder"` | Robust | Explicitly covers both field presence and blank-pending-input; grader PASS is unambiguous |

### 10. Opportunistic Post-Merge Conditions — Attach Verify Commands and Prefer auto Classification

When writing post-merge conditions that are mechanically verifiable, attach a `<!-- verify: ... -->` verify command and classify them as `verify-type: auto` rather than `verify-type: opportunistic`.

**Background**: Conditions tagged `verify-type: opportunistic` without a verify command fall into "Items Requiring User Verification" in `/verify` output and are excluded from automatic consumption in `/auto` runs. This was observed in #365, where post-merge conditions could not be automatically consumed because they lacked verify commands.

**Priority rule: `auto` over `opportunistic`**

If a post-merge condition can be verified mechanically — file existence, text content, CI result — attach a verify command and omit the `verify-type: opportunistic` tag (the default classification is `auto` when a verify command is present). Reserve `verify-type: opportunistic` only for conditions that genuinely require runtime observation or human judgment that cannot be expressed as a mechanical check.

**Decision procedure:**

1. For each post-merge condition, ask: "Can this be verified with a `grep`, `file_contains`, `github_check`, or similar command?"
2. If yes: attach the verify command; omit `verify-type: opportunistic` (defaults to `auto`)
3. If no: retain `verify-type: opportunistic` without forcing an inaccurate verify command

**Examples:**

| Condition | Avoid | Prefer |
|-----------|-------|--------|
| "New section heading exists in docs" | No verify command → `verify-type: opportunistic` (manual) | `grep "^### Target Heading" "docs/..."` → `verify-type: auto` |
| "CI workflow passes after merge" | `verify-type: opportunistic` (manual) | `github_check "gh run list --workflow=ci.yml ..."` → `verify-type: auto` |
| "Feature works correctly in real usage" | — | `verify-type: opportunistic` (human judgment required) |

**Recommended pattern for mechanically verifiable post-merge conditions:**

```
- [ ] <!-- verify: grep "pattern" "path" --> Condition description
```

Omitting `verify-type: opportunistic` when a verify command is attached is correct — conditions with verify commands are classified as `auto` by default.

### 11. Manual AC Quick Reference — Replace with automatable/rubric

When an acceptance condition is tagged `<!-- verify-type: manual -->`, check if it can be replaced with an automatable verify command before finalizing. Use the table below as a quick reference:

| Pattern often written as `manual` | Replacement candidate | Example |
|-----------------------------------|-----------------------|---------|
| Command X succeeds | `command "X"` / `build_success "X"` | `build_success "npm run build"` |
| URL X returns expected response | `http_status "URL" "200"` / `html_check` / `api_check` | `http_status "https://example.com/api" "200"` |
| Component / feature is coherent (semantic check) | `rubric "..."` | `rubric "The new component renders without errors and matches the design spec"` |
| Output file is generated | `file_exists "path"` | `file_exists "dist/bundle.js"` |
| File contains expected content | `file_contains "path" "keyword"` | `file_contains "config.json" "feature_flag"` |

If a replacement is possible, update the verify command in both the Spec and the Issue body AC. Combining `rubric` with `file_contains`/`section_contains` is also effective (see §9).

### 12. Indirect Reflection Pattern — Classify as post-merge manual or command type

When the acceptance condition involves functionality implemented through an intermediate function (e.g., `to_markdown()`) that is automatically reflected in a target script without directly modifying it, pre-merge `rubric` verify commands become UNCERTAIN.

**Background**: In Issues that add features (e.g., column additions) to a target script (e.g., `daily_routine.py`) without directly editing it, the diff does not include the target script. The rubric grader judges "no code change" and returns UNCERTAIN (this false-UNCERTAIN risk arises whenever an indirect-reflection pattern propagates changes automatically without modifying the target script).

**Classification rule:**

| Condition type | Verify command to use | Reason |
|---------------|----------------------|--------|
| AC for indirect-reflection pattern | `command "bin/target-script 2>&1 \| grep keyword"` or post-merge `verify-type: manual` | Target script is absent from diff; `rubric` becomes UNCERTAIN |
| Direct code change AC | `rubric` / `file_contains` / `grep` | Target file is in diff; hard-pattern and rubric both work |

**Detection criteria for indirect reflection:**

An AC falls under this pattern when ALL of the following apply:
1. The target script (the one whose behavior changes) is not directly modified in this Issue
2. The change is propagated automatically via an intermediate function or data structure
3. The AC verifies runtime behavior of the unmodified target script

**Recommended pattern:**

```markdown
- [ ] <!-- verify: command "python3 bin/daily_routine.py 2>&1 | grep new_column_name" --> New column appears in output
```

Or classify as post-merge manual when live runtime execution is unavailable in CI:

```markdown
- [ ] New column appears in `daily_routine.py` output <!-- verify-type: manual -->
```

**Decision procedure:**

1. Identify whether the target script is in the diff — if not, this is an indirect-reflection AC
2. If indirect: use `command "bin/target-script 2>&1 | grep keyword"` for mechanical verification
3. If CI cannot execute the command: classify as `verify-type: manual` (post-merge)
4. Do NOT use pre-merge `rubric` for indirect-reflection ACs — the grader cannot observe the diff-absent file and will return UNCERTAIN

### 13. Recommended pre-verify flow for cron workflows

When a post-merge acceptance condition depends on a cron-scheduled workflow's output (logs, generated files), the condition will always FAIL immediately after merge because the cron job has not yet run. Running `/verify` before manually triggering the workflow produces false FAILs for all cron-dependent conditions.

**Recommended pre-verify flow for cron workflows:**
1. After merge, run `workflow_dispatch` (with `dry_run: false`) to produce the expected output
2. Verify the run succeeded: `gh run list --workflow=<name>.yml --limit=1`
3. Then run `/verify <issue-number>`

**Background**: cron-dependent post-merge ACs fail immediately after merge because the scheduled job has not executed yet. Triggering `workflow_dispatch` simulates the first scheduled run and satisfies the pre-condition for all downstream verify commands. This pattern was confirmed in practice (see also Issue #490 for related guidance).

**Add a corresponding manual condition in the Issue AC:**

```markdown
- [ ] Trigger workflow once via `workflow_dispatch` before the first cron run and verify it completes successfully <!-- verify-type: manual -->
```

**When to apply this pattern:**

| Scenario | Apply? |
|----------|--------|
| Post-merge AC verifies cron workflow output (logs, generated files, event records) | Yes — trigger `workflow_dispatch` before `/verify` |
| Post-merge AC verifies static file content or config changes | No — no workflow execution dependency |
| Pre-merge AC for non-cron CI checks | No — use `github_check "gh pr checks"` or `github_check "gh run list"` |

**Decision procedure:**

1. Identify whether any post-merge AC condition depends on a cron workflow's execution output
2. If yes: add a `<!-- verify-type: manual -->` AC to trigger `workflow_dispatch` before running `/verify`
3. Order the manual AC before the automated cron-output ACs so the human step completes first
4. In the `/verify` pre-run checklist, note that `workflow_dispatch` must be triggered before verify

### 14. Infra Shutdown Issues — Attach verify commands to URL Accessibility ACs

When an Issue involves infrastructure shutdown (service deletion, deployment stop, etc.) and its acceptance criteria include URL accessibility confirmation, always attach a `<!-- verify: ... -->` verify command.

**Background**: In downstream real-world usage, URL accessibility ACs for infra-shutdown Issues lacked verify commands. As a result, `/verify` could not cover them automatically and the check fell back to manual confirmation. URL accessibility checks are mechanically verifiable and should be automated.

**Command selection guideline:**

| Scenario | Preferred command | Example |
|----------|-----------------|---------|
| HTTP response is returned (4xx, 5xx, redirect, etc.) | `http_status "URL" "CODE"` | `http_status "https://example.com/api" "404"` |
| Connection fails completely (service fully deleted) | `command "curl -sI URL 2>&1 \| grep ..."` | `command "curl -sI https://example.com 2>&1 \| grep 'Could not resolve'"` |

**Priority rule: Use specialized commands when HTTP response is available.**

If the service returns any HTTP response (even 4xx/5xx error codes), use `http_status` — it is more precise than `command "curl ..."` because it checks the status code directly without parsing curl output.

Fall back to `command "curl -sI URL 2>&1 | grep ..."` only when the service is completely unreachable (DNS failure, connection refused with no HTTP response).

**Recommended patterns:**

```
<!-- verify: http_status "https://example.com/api" "404" --> URL returns 404 after service stop
<!-- verify: http_status "https://example.com" "503" --> URL returns 503 during maintenance
<!-- verify: command "curl -sI https://deleted.example.com 2>&1 | grep -E 'Could not resolve|Connection refused'" --> Service is completely unreachable after deletion
```

**Decision procedure:**

1. Identify whether the acceptance condition includes URL accessibility confirmation
2. Determine the expected post-shutdown behavior:
   - HTTP response returned (even 4xx/5xx) → use `http_status "URL" "CODE"`
   - Complete connection failure (no HTTP response) → use `command "curl -sI URL 2>&1 | grep ..."` with an appropriate pattern
3. If the expected status code is uncertain at spec time, use `rubric "URL returns an error response (4xx or 5xx) after service shutdown"` and add `http_status` once the expected code is known

### 15. Async External-Commit Area — Verify Command Patterns

When an Issue's artifact lives under a path managed by an external tool that commits asynchronously (e.g., Obsidian Git, Logseq Sync, IDE auto-commit), `file_exists` is structurally weak: the file may be on disk but not yet committed, causing `file_exists` to return UNCERTAIN at `/verify` runtime.

**Root cause**: `file_exists` checks only whether the file is present on disk. For external-tool-managed paths, the commit happens asynchronously and may not have landed by the time `/verify` runs — leading to UNCERTAIN results that resolve on re-run.

**Recommended verify command priority (choose the highest available):**

| Priority | Command | When to use |
|----------|---------|-------------|
| 1 | `git_committed "<path>"` | Recommended. PASS when path is tracked by git; resilient to async commit timing |
| 2 (current) | `command "git ls-files --error-unmatch <path>"` | Available now. Exits non-zero if the path is not tracked by git; PASS means git knows about the file |
| 3 (fallback) | `<!-- verify-type: manual -->` | Use when safe mode (`/review`) must not reach git — e.g., path is write-protected or git invocation is forbidden in the review environment |

**Pattern to use today (`command` alternative):**

```
<!-- verify: command "git ls-files --error-unmatch vault/2024-11-15-standup.md" -->
```

`git ls-files --error-unmatch` exits 0 when the path is tracked, non-zero otherwise. Under full-mode verify (`/verify`), this is mechanically verified. Under safe-mode verify (`/review`), `command` hints become UNCERTAIN — apply priority 3 (`verify-type: manual`) as a fallback for safe mode.

**Checkpoint for Spec/Issue authors:**

Before writing verify commands for file-existence conditions, check:

1. Is the artifact path under a directory managed by Obsidian, Logseq, an IDE auto-save, or any other tool that commits asynchronously?
2. If yes: replace `file_exists "<path>"` with `command "git ls-files --error-unmatch <path>"` (or `git_committed` once Issue #460 is merged).
3. If safe-mode (`/review`) compatibility is also required: add `<!-- verify-type: manual -->` as a supplementary fallback so reviewers know to check manually.

**Example (before and after):**

```
❌ file_exists "vault/daily/2024-11-15.md"
   → UNCERTAIN if Obsidian Git has not committed yet

✅ command "git ls-files --error-unmatch vault/daily/2024-11-15.md"
   → PASS when file is tracked by git; FAIL when absent or untracked
```

### 16. Migration / Rename / Path-change Issues — Apply file_not_contains to Both SKILL.md and Script Layers

When an Issue involves migration, renaming, or path changes, SKILL.md (markdown skill definition) and bash scripts (implementation side) often both contain the same path references. A `file_not_contains` verify command applied only to SKILL.md will PASS even if the old path remains in the implementation script — creating a blind spot that only surfaces during `/review`.

**Background (real example)**: Issue #772 AC8 `file_not_contains "skills/auto/SKILL.md" "docs/reports/loop-state-"` passed, but the same old path remained in `scripts/append-loop-state-heartbeat.sh` (the implementation counterpart). This was not detected until the review phase (commit d0a9288).

**Root cause**: CI cannot detect old path residuals in scripts (outside test coverage). Explicit `file_not_contains` ACs are the only automated detection mechanism.

**Recommended pattern — apply file_not_contains to both layers symmetrically:**

```
<!-- verify: file_not_contains "skills/auto/SKILL.md" "docs/reports/old-path-" -->
<!-- verify: file_not_contains "scripts/append-loop-state-heartbeat.sh" "docs/reports/old-path-" -->
```

Both the SKILL.md side and the implementation script side must be covered.

**Detection procedure when designing Spec ACs for migration Issues:**

1. Run `grep -rn 'old-path' .` (substitute the actual old path string) to enumerate all files that reference the old path
2. For each matching file, check whether it is under `skills/` (SKILL.md), `scripts/` (bash script), or `modules/` (shared module)
3. Add a `file_not_contains` verify command for each layer found — do not apply only to SKILL.md

**Note**: Script-side old path residuals are not covered by CI or unit tests. Only explicit `file_not_contains` ACs catch them automatically before merge.

### 17. Docs/Code Consistency — Verify Key Behavior Keywords in Both Layers

When a docs file (e.g., `docs/guide/customization.md`) and its implementing code file (e.g., `skills/verify/SKILL.md`) are both changed in the same Issue, verify that key behavior keywords match across both layers. Without this check, terminology mismatches (e.g., "silently ignored" in docs vs. warning output in code) go undetected until the review or verify phase (real example: Issue #783).

**Background**: In Issue #783, `docs/guide/customization.md` described a behavior as "silently ignored" while `skills/verify/SKILL.md` actually emitted a warning. The mismatch was caught only during review because no AC verified keyword consistency between the two files.

**When to apply:**

Apply this pattern when ALL of the following are true:

1. The Issue's changed files include both a docs file and an implementation file (skill, script, or module)
2. The docs file describes specific behavior using keywords (e.g., "silently ignored", "warning", "skip", "fallback")
3. The implementation file is expected to exhibit the same behavior

**Recommended pattern — exact keyword match (use `grep`):**

When the same keyword must appear literally in both files:

```
<!-- verify: grep "silently ignored" "docs/guide/customization.md" -->
<!-- verify: grep "silently ignored" "skills/verify/SKILL.md" -->
```

Both layers must contain the same keyword string. If the implementation uses a different but equivalent phrase, this pattern will FAIL and surface the inconsistency before merge.

**Recommended pattern — semantic consistency only (use `rubric`):**

When the docs and implementation may use different phrasing for the same behavior:

```
<!-- verify: rubric "docs/guide/customization.md の挙動説明と skills/verify/SKILL.md の実装が意味的に一致している (例: 'silently ignored' vs 警告なし)" -->
```

Use `rubric` when exact string matching is too strict but semantic alignment must still be confirmed.

**Decision procedure:**

1. Identify all docs files and implementation files in the Issue's change set
2. For each docs file, extract key behavior-describing keywords (e.g., "warning", "skip", "fallback", "ignored", "disabled")
3. For each keyword, grep the corresponding implementation file:
   - Keyword found: add `grep "keyword" "docs-file"` + `grep "keyword" "impl-file"` as paired verify commands
   - Keyword absent from implementation: add `rubric "..."` for semantic consistency check
4. If no behavior keywords are present in docs (e.g., only structural changes): skip this pattern

**Example AC for a docs+skills change Issue:**

```markdown
- [ ] <!-- verify: grep "warning" "docs/guide/customization.md" --> docs describes warning behavior
- [ ] <!-- verify: grep "warning" "skills/verify/SKILL.md" --> implementation emits warning (consistency check)
```

## Output

Design verify commands following these guidelines and apply them to acceptance criteria.
