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

## Code Retrospective

### Deviations from Design
- Added `github_check` to `KNOWN_VERIFY_COMMANDS` in `scripts/validate-skill-syntax.py`. This was not listed in the Spec's Changed Files, but was required because the validator rejected `github_check` as an unknown verify command. The fix was straightforward (add `'github_check': (2, 2)` to the registry).

### Design Gaps/Ambiguities
- The Spec did not mention that `validate-skill-syntax.py` has a hard-coded allowlist of known verify commands. `github_check` was already documented in `verify-executor.md` but missing from the validator registry, causing CI-equivalent validation to fail after the SKILL.md change.

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Acceptance conditions had clear, machine-verifiable `<!-- verify: ... -->` hints for all 7 conditions.
- `file_exists` was correctly used instead of `grep "github_check" ".github/workflows/test.yml"` for the CI prerequisite (noted in Auto-Resolved Ambiguity Points). Good self-correction.
- `section_not_contains` pattern worked well for verifying absence of the old `command "bats` pattern within specific sections.

#### design
- Spec correctly scoped out closed Issue specs (issue-7, -8, -9) and the CI Reference Fallback section — a sound decision that kept the change minimal and focused.
- The Changed Files section was accurate except for the missing `scripts/validate-skill-syntax.py` entry (captured in Code Retrospective).

#### code
- Patch route (direct main commit) was appropriate for this scoped template-text-only change.
- The unspecced `validate-skill-syntax.py` change was discovered via CI and handled correctly, but could have been caught earlier with a pre-implementation grep of `KNOWN_VERIFY_COMMANDS`.

#### review
- Patch route — no formal PR review. For pure documentation/example text changes, this is acceptable.

#### merge
- Direct commit to main (`747acb2`). Clean, no conflicts.

#### verify
- All 7 conditions PASS on first run. Smooth verification with no FAIL or UNCERTAIN.
- `section_not_contains` proved effective for verifying the absence of old patterns within specific markdown sections.

### Improvement Proposals
- N/A
