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
| `VERIFY_RESIDUALS` always empty | After `select(...)` filter in a jq pipe, `. ` refers to the filtered element but the outer context (full object) is lost | Bind the full input with `. as $root` before filtering; reference `$root` where the full object is needed (jq context loss). A deeper structural cause was found in #900: the original design computed residuals from a `phase_start`/`phase_complete` (`phase=="verify"`) event diff, but `/verify` is a wrapper-less Skill invocation that never emits those events in production — the diff was always an empty-set-minus-empty-set, independent of the jq context-loss bug. Fixed by replacing the event-diff computation with a live `phase/verify` label lookup integrated into the existing per-issue GitHub state lookup loop. |

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

## Bash `grep` Exit Code Handling

When using `grep` in shell scripts, be aware of the three distinct exit codes:

- **exit code 0**: one or more lines matched
- **exit code 1**: no match found (not an error — grep ran successfully but found nothing)
- **exit code 2**: file or regex error (grep could not run)

### Principle

> `grep ... || true` suppresses all non-zero exit codes, including exit code 2 (file/regex error). When the intent is only to treat "no match" as success, handle exit code 2 explicitly rather than absorbing all failures silently.

**Bad**: exit code 2 is absorbed alongside exit code 1

```bash
grep -v "^${target_date}" "$INPUT" > tmpfile || true
```

**Good**: only exit codes 0 and 1 are accepted; exit code 2 triggers abort

```bash
grep -v "^${target_date}" "$INPUT" > tmpfile
rc=$?
case $rc in
  0|1) ;;  # 0=match, 1=no-match (both acceptable)
  *) echo "grep error: $rc" >&2; exit 1 ;;
esac
```

### Example

`scripts/auto-events-rollup.sh` cleanup section — origin of this principle (surfaced in PR #644 review of issue #638):

```bash
# Original (problematic): exit code 2 silently absorbed
grep -v "^${target_date}" "$INPUT" > tmpfile || true

# Fixed: explicit rc check so file-read errors are not swallowed
grep -v "^${target_date}" "$INPUT" > tmpfile
rc=$?
case $rc in
  0|1) ;;
  *) echo "grep error: $rc" >&2; exit 1 ;;
esac
```

## PROJECT_ROOT Anchoring Pattern

When creating a new bats test file, always define `PROJECT_ROOT` once at the top level of the file using `BATS_TEST_FILENAME`:

```bash
PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
```

**Why**: bats tests may be invoked from any working directory (e.g., the repo root, the `tests/` directory, or a CI runner working directory). Relative paths like `../scripts/my-script.sh` break as soon as the invocation directory changes. `BATS_TEST_FILENAME` is always the absolute path to the test file itself, so anchoring from it is portable regardless of invocation directory.

Derive all file paths from `PROJECT_ROOT`:

```bash
# Content-assertion test
PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
TARGET="$PROJECT_ROOT/modules/some-module.md"

@test "some-module: ## Purpose section exists" {
    grep -q "## Purpose" "$TARGET"
}

# Script execution test
PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/my-script.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
}
```

**Starting point**: copy `tests/_template.bats` as the basis for every new bats test file. The template defines `PROJECT_ROOT` correctly and includes a live sanity check that guards against future path anchoring regressions.

## Mock の副作用整合性

When a bats mock is declared as `:` (no-op) and test assertions depend on observable side effects — such as file writes, network calls, or state mutations — CI may produce unexpected failures even when local tests pass. This divergence occurs because the no-op mock does not reproduce the real function's 観測可能な副作用 (observable side effects) that the assertions require.

### Principle

> When a mock replaces a function whose observable side effects are asserted in the same test, the mock must reproduce those side effects. A no-op (`:`) mock is only safe when no assertion in the test depends on the side effect produced by the real function.

**Check perspectives when writing bats tests for new helper scripts:**

- If the test asserts **file writes** (e.g., appending JSON to a log file), does the mock write the same structure to the same path to reproduce the 観測可能な副作用?
- If the test asserts **network calls** or **external state**, does the mock simulate the expected response or side effect?
- If the test asserts **state mutations** (e.g., exit codes, environment variable changes), does the mock produce those mutations?
- If a no-op mock is used, verify that **no assertion in the same test** depends on the observable side effect of the real function.

### Example

`emit-event.sh` / `AUTO_EVENTS_LOG` (Issue #630) — local PASS / CI FAIL:

The bats test for `emit-event.sh` mocked `emit_event` as `:` (no-op), but test assertions verified that `AUTO_EVENTS_LOG` contained specific JSON entries. Because the no-op mock did not write to `AUTO_EVENTS_LOG`, the assertion failed in CI while passing locally (environment timing differences masked the failure locally).

**Root cause**: mock declared as no-op (`:`) while assertions checked the file-write side effect.

**Fix**: replace the no-op with a mock that writes a JSON stub to `AUTO_EVENTS_LOG`:

```bash
emit_event() {
  echo '{"event":"stub"}' >> "$AUTO_EVENTS_LOG"
}
export -f emit_event
```

This reproduces the observable side effect required by the assertions while keeping mock output controlled and deterministic.
