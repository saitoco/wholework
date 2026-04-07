---
name: review-type-weighting
description: Centrally manages Type-specific emphasis point tables for review agents (review-bug / review-light / review-spec)
type: module
---

# review-type-weighting module

## Purpose

Centrally manages the Type-specific emphasis point tables shared by the three agents (review-bug, review-light, review-spec), preventing divergence risk from duplicate definitions.

## Input

The following variable is available from the calling agent:

- `Type`: Issue Type (`Bug` / `Feature` / `Task` / empty string)

## Processing Steps

Refer to the section matching the calling agent name and apply the Type-specific emphasis point table.

### ## review-bug

When `Type=` is passed in the prompt, confirm the following emphasis points **in addition to** normal bug detection. When Type is empty string or not set, execute only normal bug detection (maintain current behavior).

| Type | Additional Emphasis Points | Specific Checks |
|------|--------------------------|----------------|
| Bug | Presence of regression tests (SHOULD level) | Check for test file additions or updates corresponding to the fix. If no tests are added, output as a SHOULD-level suggestion: "Consider adding regression tests" (not MUST) |
| Feature | Error handling in new code | Whether error handling (try-catch, exit code checks, etc.) is included in newly added code paths |
| Task | Equivalence of refactoring | For refactoring not intended to change behavior, verify that behavior has not actually changed |
| Unset | None | Normal bug detection only |

### ## review-light

When `Type=` is passed in the prompt, apply the following weighting during the 4-perspective check. When Type is empty string or not set, check all 4 perspectives with equal weight (maintain current behavior).

| Type | Emphasis Perspectives | Specific Additional Checks |
|------|----------------------|--------------------------|
| Bug | Perspective 2 (edge cases) + regression tests | Whether the fix addresses the root cause, whether regression tests are added (SHOULD level) |
| Feature | Perspective 1 (spec divergence) + Perspective 2 (edge cases) | Coverage of acceptance criteria, boundary value handling |
| Task | Perspective 1 (spec divergence) | Confirmation that behavior has not changed, maintenance of existing tests |
| Unset | None | Check all 4 perspectives with equal weight |

### ## review-spec

When `Type=` is passed in the prompt, confirm the following emphasis points **in addition to** normal spec divergence checks. When Type is empty string or not set, execute only normal checks (maintain current behavior).

| Type | Additional Emphasis Points | Specific Checks |
|------|--------------------------|----------------|
| Bug | Whether fix addresses root cause | Whether the fix addresses the root cause rather than the symptom (workaround) |
| Feature | Edge case coverage, boundary value handling | Coverage of acceptance criteria, whether boundary values (0 items, max values, empty strings, etc.) are handled |
| Task | Behavioral equivalence, maintenance of existing tests | Confirmation that behavior has not changed in refactoring, whether all existing tests are maintained |
| Unset | None | Normal spec divergence check only |

## Output

The calling agent applies Type-specific emphasis points based on the table in the referenced section.
