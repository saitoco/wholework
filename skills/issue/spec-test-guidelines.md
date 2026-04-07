# Behavior Test Recommendation Guidelines (/issue supplement)

This file is loaded only in skill development repositories where `scripts/validate-skill-syntax.py` exists.

## Behavior Test Recommendation Guidelines

For changes in the following categories, include **bats behavior tests** in acceptance criteria (pre-merge) in addition to static checks (`file_exists`, `grep`):

| Change target | Why testing is needed | What to test |
|--------------|----------------------|-------------|
| **scripts/ scripts** | Script logic errors affect the entire workflow | Argument handling, file operations, error handling |
| **hooks configuration** (the `hooks` section in settings.json) | Hook errors block tool execution | Matcher patterns, stdout/stderr handling, exit codes |
| **allowed-tools changes** (SKILL.md `allowed-tools`) | Misconfiguration prevents tool execution; security risk | Permission pattern matching |
| **Environment setup scripts** (install.sh, etc.) | Errors can corrupt user environments | Install/uninstall behavior |
| **Scripts called via skills** | Claude Code Bash tool quirks (escaping, etc.) can cause runtime failures | bats unit tests (pre-merge) + `command` acceptance check via real invocation (post-merge) |

**Example acceptance criteria entry:**
```markdown
- [ ] <!-- verify: command "bats tests/scripts/test-name.bats" --> All bats tests pass
```

**Test file location:**
- Place under `tests/` (follow existing bats test patterns if any)

**Supplementary: bats tests vs. `command` acceptance checks**

bats tests (in mock environments) cannot detect all integration-level issues. For example, the Claude Code Bash tool escaping exclamation marks with backslashes (Issue #249) does not occur in bats with mock `gh` — it only appears during real API calls.

`command` acceptance checks run via the Claude Code Bash tool during `/verify`, so they function as integration tests. For scripts invoked via skills, add a `command` hint in the post-merge section to validate real-environment behavior:

```markdown
### Post-merge
- [ ] <!-- verify: command "scripts/target-script.sh args" --> Real invocation succeeds
```

## Specifying individual test files in `command` hints

In `command` hints, prefer specifying **individual test files** over integrated commands (e.g., `python3 scripts/validate-skill-syntax.py skills/`):

**Reason:** When CI reference fallback occurs in `/review` safe mode, integrated commands make it harder to identify the corresponding CI job. Specifying individual test files makes the mapping to CI jobs explicit, improving automated verification reliability.

**Recommended pattern (individual test file):**

```markdown
- [ ] <!-- verify: command "bats tests/validate-skill-syntax.bats" --> Skill syntax validation tests all pass
```

```markdown
- [ ] <!-- verify: command "bats tests/scripts/test-name.bats" --> All bats tests pass
```

**Pattern to avoid (integrated command):**

```markdown
<!-- avoid: integrated commands make CI job mapping unclear -->
- [ ] <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> Syntax validation passes
```

## Boundary value test case recommendations

When testing scripts that take numeric or string arguments, always include **boundary values** in addition to normal values. Missing boundary tests can cause unexpected production behavior or security risks (per review feedback on gh-label-transition.sh, Issue #854).

### Numeric argument boundary values

| Test case | Reason |
|-----------|--------|
| `0` | 0 is not a positive integer. Verify scripts expecting issue/line numbers of 1+ reject 0 |
| Negative (e.g., `-1`) | Verify negative numbers are correctly rejected |
| Empty string (`""`) | Equivalent to missing argument |
| Non-numeric (e.g., `"abc"`) | Verify numeric validation works |

**bats example (issue number validation):**

```bash
@test "issue number 0 is rejected" {
  run scripts/gh-label-transition.sh 0 code
  [ "$status" -ne 0 ]
}

@test "negative issue number is rejected" {
  run scripts/gh-label-transition.sh -1 code
  [ "$status" -ne 0 ]
}

@test "empty issue number is rejected" {
  run scripts/gh-label-transition.sh "" code
  [ "$status" -ne 0 ]
}

@test "non-numeric issue number is rejected" {
  run scripts/gh-label-transition.sh "abc" code
  [ "$status" -ne 0 ]
}
```

### String argument boundary values

| Test case | Reason |
|-----------|--------|
| Empty string (`""`) | Verify required argument empty check works |
| Space only (`" "`) | Behavior varies depending on whether trimming is applied |
| Unexpected value (enum args) | Verify error handling for values outside the allowed set |

**bats example (enum argument validation):**

```bash
@test "invalid phase label is rejected" {
  run scripts/gh-label-transition.sh 123 invalid-phase
  [ "$status" -ne 0 ]
}

@test "empty phase label is rejected" {
  run scripts/gh-label-transition.sh 123 ""
  [ "$status" -ne 0 ]
}
```

### Checklist (for Spec creation)

When designing script tests, verify:

- [ ] If numeric args: added test cases for `0`, negatives, non-numeric?
- [ ] If string args: added test cases for empty string and unexpected values?
- [ ] Added test case for missing required arguments?
- [ ] Added test cases for max/min (upper/lower bounds)?

## Specifying individual changed skills in validate-skill-syntax.py

In `validate-skill-syntax.py` acceptance checks, prefer specifying individual changed skills rather than all of `skills/`:

Specifying all of `skills/` can cause false failures due to unrelated issues (e.g., merge conflict remnants in other issues' skills).

**Recommended pattern (individual changed skills only):**

```markdown
- [ ] <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/<name>/SKILL.md" --> Syntax validation passes
```

Or for multiple changed skills:

```markdown
- [ ] <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/<name1>/SKILL.md skills/<name2>/SKILL.md" --> Syntax validation passes
```

Directory-level specification is also supported:

```markdown
- [ ] <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/<name>" --> Syntax validation passes
```
