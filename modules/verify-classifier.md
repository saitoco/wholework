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
| `auto` | An acceptance check (`<!-- verify: ... -->`) is actually attached | File existence check, grep pattern match, test execution |
| `opportunistic` | Condition text matches the pattern "verify X when `/skill-name` is run" | "Confirm doc impact check runs when `/spec` is executed" |
| `manual` | Does not match either of the above | "Confirm no dialog appears", "Visual browser verification" |

### Tag Assignment Example

```markdown
### Post-Merge
- [ ] <!-- verify: command "bats tests/..." --> All bats tests PASS <!-- verify-type: auto -->
- [ ] Confirm test file search is included when `/spec` runs <!-- verify-type: opportunistic -->
- [ ] User visually confirms no confirmation dialog appears <!-- verify-type: manual -->
```

### Constraint: Required Rule When Using auto Type

When assigning `<!-- verify-type: auto -->` to a condition, a `<!-- verify: ... -->` hint **must be present**.

- `verify-type: auto` is assigned only to conditions that have a hint (a `auto` without a hint is equivalent to skipping verification, which contradicts user expectations)
- If a hint cannot be provided, classify as `opportunistic` or `manual` instead

## Output

Assign the `<!-- verify-type: auto|opportunistic|manual -->` tag to the end of each post-merge condition. Place the tag one half-width space before the line break at the end of the condition text.
