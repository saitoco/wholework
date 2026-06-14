---
type: domain
skill: code
domain: skill-dev
load_when:
  file_exists_any: [scripts/validate-skill-syntax.py]
applies_to_proposals:
  file_patterns:
    - skills/code/SKILL.md
    - scripts/validate-skill-syntax.py
  content_keywords:
    - SKILL.md
    - validate-skill-syntax
    - skill-dev
    - ${CLAUDE_PLUGIN_ROOT}
  rewrite_target:
    - from: skills/code/SKILL.md
      to: skills/code/skill-dev-validation.md
---

# Skill Development Validation (/code supplement)

This file is loaded only in skill development repositories where `scripts/validate-skill-syntax.py` exists.

## Processing Steps

Run skill syntax validation locally:

```bash
python3 scripts/validate-skill-syntax.py skills/
```

This is equivalent to the CI `validate-syntax` job and detects invalid `allowed-tools` patterns or YAML frontmatter syntax errors before reaching CI. If validation fails, fix the issues before continuing (same as test failures).

## jq compute Logic: Dedicated Bats Test Cases

When implementing shell + jq scripts that contain compute logic — such as `. as $var` binding, `tonumber` numeric conversion, ISO8601/epoch transformation, or pipe-context variable scoping — add **dedicated bats test cases** that directly assert input → expected output.

These internal bugs are invisible to verify commands (`grep`, `file_contains`, `rubric`) because they only check file structure, not runtime computation. At least one bats case per compute function must assert the calculated result.

### Principle

> For any jq compute logic (numeric conversion, timestamp arithmetic, context variable binding), add a bats test that feeds a controlled input and asserts the exact expected output. This runs in parallel with AC mechanical checks (grep / file_contains) and validates computation correctness independently.

### Known Failure Patterns

The following patterns have caused silent bugs where all structural verify commands passed but computed output was wrong:

| Pattern | Symptom | Root Cause |
|---------|---------|-----------|
| `THROUGHPUT` metric always `N/A` | ISO8601 timestamp (`2026-06-14T22:00:00Z`) passed to `tonumber` fails silently because the `Z` suffix is non-numeric | Use `gsub("Z$";"") | tonumber` or `fromdate` instead of bare `tonumber` for ISO8601 strings |
| `VERIFY_RESIDUALS` always empty | After `select(...)` filter in a jq pipe, `. ` refers to the filtered element but the outer context (full object) is lost | Bind the full input with `. as $root` before filtering; reference `$root` where the full object is needed (jq context loss) |

### Example: Input → Expected Output Assertion

```bash
@test "compute_throughput: ISO8601 timestamp parses correctly" {
  local input='{"start":"2026-06-14T22:00:00Z","end":"2026-06-14T23:00:00Z","count":120}'
  local result
  result=$(echo "$input" | jq -r '
    (.end | gsub("Z$";"") | fromdateiso8601) as $end_ts |
    (.start | gsub("Z$";"") | fromdateiso8601) as $start_ts |
    if $end_ts > $start_ts then
      ((.count / (($end_ts - $start_ts) / 3600)) | floor | tostring) + "/hr"
    else "N/A" end
  ')
  assert_output "120/hr"
}
```

Add one test per compute function. Name the test with the metric or function name so failures are immediately identifiable.
