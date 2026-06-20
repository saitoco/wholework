---
type: domain
skill: issue
domain: skill-dev
load_when:
  file_exists_any: [scripts/validate-skill-syntax.py]
applies_to_proposals:
  file_patterns:
    - skills/issue/SKILL.md
    - skills/*/SKILL.md
  content_keywords:
    - SKILL.md
    - bats
    - spec
    - test
    - skill-dev
  rewrite_target:
    - from: skills/issue/SKILL.md
      to: skills/issue/spec-test-guidelines.md
---

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
| **Scripts called via skills** | Claude Code Bash tool quirks (escaping, etc.) can cause runtime failures | bats unit tests (pre-merge) + `command` verify command via real invocation (post-merge) |

**Example acceptance criteria entry:**

PR route (Size M/L):
```markdown
- [ ] <!-- verify: github_check "gh pr checks" "Run bats tests" --> All bats tests pass (PR route)
```

patch route (Size XS/S):
```markdown
- [ ] <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) all jobs pass (patch route)
```

**Test file location:**
- Place under `tests/` (follow existing bats test patterns if any)

**Supplementary: bats tests vs. `command` verify commands**

bats tests (in mock environments) cannot detect all integration-level issues. For example, the Claude Code Bash tool escaping exclamation marks with backslashes (Issue #249) does not occur in bats with mock `gh` — it only appears during real API calls.

`command` verify commands run via the Claude Code Bash tool during `/verify`, so they function as integration tests. For scripts invoked via skills, add a `command` hint in the post-merge section to validate real-environment behavior:

```markdown
### Post-merge
- [ ] <!-- verify: command "scripts/target-script.sh args" --> Real invocation succeeds
```

## Using `github_check` for CI-based bats verification

For bats test verification, use `github_check` hints which directly reference CI job status. This works reliably in safe mode without local execution or CI Reference Fallback inference.

**Reason:** `github_check` explicitly references the CI job by name, providing more reliable automated verification than `command` hints which require CI Reference Fallback inference in safe mode.

**Recommended patterns:**

PR route (Size M/L):
```markdown
- [ ] <!-- verify: github_check "gh pr checks" "Run bats tests" --> All bats tests pass (PR route)
```

patch route (Size XS/S):
```markdown
- [ ] <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) all jobs pass (patch route)
```

**Route selection:** Size XS/S → patch route → use `gh run list` form; Size M/L → PR route → use `gh pr checks` form. For detailed routing logic (UNCERTAIN handling when PR_NUMBER is absent, etc.), see `modules/verify-classifier.md` § Patch Route CI Verification Note.

**Pattern to avoid (requires local execution or fallback inference):**

```markdown
<!-- avoid: requires local bats execution or CI Reference Fallback inference in safe mode -->
- [ ] <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> Syntax validation passes
```

## Verify commands for SKILL.md and module file changes

When acceptance criteria include conditions that verify the content of SKILL.md or module files (e.g., "new step added", "option described"), `grep` or `file_contains` verify commands can be applied to post-merge conditions as well — not just pre-merge.

**When to apply:**
- Post-merge conditions that check SKILL.md text content
- Post-merge conditions that check module file (`modules/*.md`) additions or changes
- Conditions like "feature X is documented" or "guideline Y is described in SKILL.md"

**Recommended patterns:**

Using `grep` (simple keyword search):
```markdown
- [ ] <!-- verify: grep "keyword" "skills/foo/SKILL.md" --> Feature X is documented in SKILL.md
```

Using `file_contains` (substring match — preferred when checking a specific phrase):
```markdown
- [ ] <!-- verify: file_contains "skills/foo/SKILL.md" "expected phrase" --> Feature X is described
```

Using `section_contains` (section-scoped search — useful when the phrase could appear elsewhere):
```markdown
- [ ] <!-- verify: section_contains "modules/foo.md" "## Section Name" "expected text" --> Section contains expected content
```

**Background:** Post-merge conditions that involve SKILL.md or module file content were often left without verify commands, requiring manual review. Since these files are text-based and their changes are deterministic, `grep` and `file_contains` can automate these checks reliably.

**Note:** `file_contains` and `section_contains` are available as verify command types alongside `grep`. Use `section_contains` when the target phrase is expected only within a specific section to avoid false positives from other occurrences.

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

In `validate-skill-syntax.py` verify commands, prefer specifying individual changed skills rather than all of `skills/`:

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

## AC Design Guidelines for PoC and Measurement Issues

For spike / PoC / measurement-type Issues, the AC must explicitly state whether **実測 (actual measurement — execute and measure)** or **試算 (estimation — design analysis / calculation is sufficient)** is expected. Omitting this distinction allows the code phase to silently narrow scope from "run and measure" to "analyze and estimate" without any machine-detectable signal.

### Definitions

| Term | Meaning |
|------|---------|
| **実測** | The code phase must actually run the target process and capture measurement artifacts (logs, result files, timing data, etc.) |
| **試算** | Design-level analysis or back-of-envelope calculation is sufficient; the code phase may substitute a PoC or architectural analysis |

### Pattern: 実測 required

When actual execution and measurement are required, include a `file_exists` verify command for the measurement artifact alongside the keyword/content check. Do not rely on keyword `grep` alone — it cannot detect scope narrowing from run→estimate.

```markdown
- [ ] <!-- verify: file_exists ".tmp/spike-result.md" --> Measurement artifact exists (confirms actual execution)
- [ ] <!-- verify: grep "実測" "docs/spec/issue-N-title.md" --> Spec records measured result
```

The `file_exists` check is the machine-verifiable signal that execution actually occurred. Without it, a keyword grep of "実測" passes even if the implementation only contains analysis text.

### Pattern: 試算 acceptable

When estimation or design analysis is sufficient, mark the AC explicitly so the code phase can make the scope decision openly rather than silently:

```markdown
- [ ] <!-- verify: grep "試算" "docs/spec/issue-N-title.md" --> Spec records estimation approach (試算可: code phase may substitute design analysis)
```

Include the phrase "試算可" in the AC text to signal that code-phase scope narrowing is an explicit, delegated choice — not a silent deviation.

### Anti-pattern: keyword grep only

```markdown
<!-- avoid: keyword grep alone cannot detect run→estimate scope narrowing -->
- [ ] <!-- verify: grep "PoC|比較|fan-out" "docs/spec/issue-N-title.md" --> PoC result described
```

A grep for output-related keywords will pass whether the implementation ran anything or only wrote analysis text. Always pair keyword checks with `file_exists` for measurement artifacts when 実測 is required.

## base/head 比較 bats テスト

When testing `git diff`-based comparison logic with bats, the PRE_EXISTING (both FAIL) and CLEAN (both PASS) scenarios may produce identical content on the base and head branches. Because `git commit` does not allow 空コミット (empty commits), these scenarios cause `git commit` to fail with "nothing to commit, working tree clean".

To prevent this, add a branch-specific marker file (e.g., `skills/marker-${branch}.md`) to each branch fixture so that every `git commit` has at least one changed file:

```bash
_setup_feature_branch() {
  local branch="$1"
  git checkout -b "$branch"
  echo "" > "skills/marker-${branch}.md"
  git add "skills/marker-${branch}.md"
  git commit -m "Add marker for $branch"
}
```

### When the marker file pattern is needed

| Scenario | base content | head content | 空コミット risk |
|----------|-------------|-------------|-----------------|
| PRE_EXISTING (both FAIL) | has FORBIDDEN string | has FORBIDDEN string | Yes — identical content |
| CLEAN (both PASS) | no FORBIDDEN string | no FORBIDDEN string | Yes — identical content |
| NEW_FAILURE | no FORBIDDEN string | has FORBIDDEN string | No — content differs |
| FIXED | has FORBIDDEN string | no FORBIDDEN string | No — content differs |

### Applicability

Apply this pattern when designing test fixtures for git diff-based comparison scripts (`pre-merge-check.sh` and future diff-based scripts). For NEW_FAILURE and FIXED scenarios the base and head branches differ by definition, so no marker file is required. Adding one is harmless for consistency, but it is only mandatory for PRE_EXISTING and CLEAN scenarios.
