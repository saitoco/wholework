# Issue #12: verify: Replace `command "bats ..."` hints with `github_check` after CI setup

## Overview

Template/guideline files use `command "bats ..."` as the recommended pattern for bats test verification in acceptance criteria examples. Now that CI workflow (`.github/workflows/test.yml`) is in place (Issue #9), migrate these examples to `github_check` which works reliably in safe mode without local execution or CI Reference Fallback inference.

**Target pattern**: `command "bats tests/..."` → `github_check "gh pr checks" "Run bats tests"`

CI job key: `bats`, display name: `Run bats tests` (from `.github/workflows/test.yml` lines 8-9).

**Out of scope**: Closed Issue specs (issue-7, -8, -9) are historical records — not modified. The CI Reference Fallback documentation in `verify-executor.md` (lines 94-126) describes existing `command` hint handling and stays as-is.

## Changed Files
- `skills/issue/SKILL.md`: change `command "bats"` example in Acceptance Criteria Writing Guide (line 378-384)
- `skills/issue/spec-test-guidelines.md`: change `command "bats"` examples (lines 19, 45, 49) and update individual test file section guidance (lines 36-41)
- `modules/verify-classifier.md`: change `command "bats"` example in Tag Assignment Example (line 31)
- `modules/verify-executor.md`: change `command "bats"` example in Output Format table (line 136)

## Implementation Steps

1. **`skills/issue/SKILL.md`** — update Acceptance Criteria Writing Guide example (→ acceptance criteria B, D)
   - Line 378: change heading text from "use `command` hints for verification" to "use `github_check` hints for verification"
   - Line 384: `command "bats tests/scripts/test-name.bats"` → `github_check "gh pr checks" "Run bats tests"`

2. **`skills/issue/spec-test-guidelines.md`** — update bats test recommendation examples (→ acceptance criteria C, E)
   - Line 19 (example entry): `command "bats tests/scripts/test-name.bats"` → `github_check "gh pr checks" "Run bats tests"`
   - Lines 36-41: update section heading from "Specifying individual test files in `command` hints" to "Using `github_check` for CI-based bats verification". Update rationale text to explain that `github_check` directly references CI job status, eliminating the need for individual file specification
   - Lines 44-49: replace `command "bats"` code block examples with `github_check` examples

3. **`modules/verify-classifier.md`** — update Tag Assignment Example (→ acceptance criteria F)
   - Line 31: `command "bats tests/..."` → `github_check "gh pr checks" "Run bats tests"`

4. **`modules/verify-executor.md`** — update Output Format example (→ acceptance criteria G)
   - Line 136: change table row from `command "bats tests/"` to `github_check "gh pr checks" "Run bats tests"` with updated Details text

## Verification

### Pre-merge
- <!-- verify: file_exists ".github/workflows/test.yml" --> CI workflow exists (prerequisite)
- <!-- verify: grep "github_check" "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` bats test example updated to `github_check` pattern
- <!-- verify: grep "github_check" "skills/issue/spec-test-guidelines.md" --> `skills/issue/spec-test-guidelines.md` bats test examples updated to `github_check` pattern
- <!-- verify: section_not_contains "skills/issue/SKILL.md" "## Acceptance Criteria Writing Guide" "command \"bats" --> SKILL.md Acceptance Criteria Writing Guide section has no remaining `command "bats` pattern
- <!-- verify: section_not_contains "skills/issue/spec-test-guidelines.md" "# " "command \"bats" --> spec-test-guidelines.md has no remaining `command "bats` pattern
- <!-- verify: grep "github_check" "modules/verify-classifier.md" --> `modules/verify-classifier.md` example updated to `github_check` pattern
- <!-- verify: grep "github_check" "modules/verify-executor.md" --> `modules/verify-executor.md` Output Format example updated to `github_check` pattern

## Notes

- `github_check` requires a PR context (PR number) to check CI job status. For patch routes (direct main commits), `github_check "gh pr checks"` is not applicable. However, template examples primarily target PR-based workflows (size M/L) where CI checks are available.
- The `command "bats ..."` pattern remains valid and documented in the CI Reference Fallback section of `verify-executor.md` as a fallback mechanism. This issue only changes the *recommended* example pattern, not the underlying infrastructure.
- The CI Reference Fallback section (verify-executor.md lines 94-126) and its `command "bats tests/setup-labels.bats"` → `test-scripts` job mapping example are not modified — they document the existing fallback behavior for `command` hints.
