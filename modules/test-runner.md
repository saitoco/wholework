# test-runner

Quality check execution and result analysis module.

## Purpose

Execute project quality checks (type checking, lint, build, tests), analyze results, and return a pass/fail summary. Each check is auto-detected; treat errors the same as test failures (fix then continue).

## Input

The following information is passed from the caller:

- **Test command**: Test command to run (auto-detected if omitted)
- **Test target**: Specific test file or directory (all tests if omitted)
- **Context**: What change this test is for (optional, improves result analysis accuracy)

## Processing Steps

### Step 0: Quality Checks (type checking, lint, build)

Execute quality checks in the following order. Each check is auto-detected; treat errors the same as test failures (fix then continue).

1. **Type check**: Run `npx tsc --noEmit` if `tsconfig.json` exists
2. **Lint**: Run `npm run lint` if `package.json` exists and `node -e "console.log(require('./package.json').scripts?.lint || '')"` confirms a lint script
3. **Build check**: Run `npm run build` if `package.json` exists and `node -e "console.log(require('./package.json').scripts?.build || '')"` confirms a build script

**Note**: If `package.json` does not exist, SKIP lint and build checks.

Execution order: **type check → lint → build → test**

### Step 1: Test Auto-Detection

1. If no test command is specified, auto-detect in the following priority order:
   - `playwright.config.ts` / `playwright.config.js` → `npx playwright test`
   - `vitest.config.ts` / `vitest.config.js` → `npx vitest run`, or `vite.config.ts` / `vite.config.js` with test config → `npx vitest run`
   - `cypress.config.ts` / `cypress.config.js` → `npx cypress run`
   - `.bats` files in `tests/` directory → `bats tests/` (defensive guard: only triggers when `[ -d tests ]` AND `.bats` files exist; if `tests/` is absent this branch is skipped automatically)
   - `test` script in `package.json` → `npm test`
   - `test` target in `Makefile` → `make test`
   - `pytest.ini` / `pyproject.toml` → `pytest`
   - If not detected → return "Test framework not detected"

   **Note**: If Vitest and npm test coexist (`vitest.config.ts` / `vitest.config.js` exists and `package.json` also has a `test` script), prioritize Vitest.

   **Defensive guard for `bats tests/`**: The bats branch presupposes that the `tests/` directory exists at the project root. If a caller (e.g., `/code` Behavioral Change Detection) forces a full-suite execution, it must precede the invocation with `[ -d tests ]` — without the guard, `bats` would fail with an opaque "no such file" error. Auto-detection here is already implicitly guarded because the `.bats` glob returns empty when `tests/` is absent.

   **Parallel execution for whole-suite bats runs**: whenever the resolved command is `bats tests/` — whether auto-detected above or forced by a caller (e.g. `/code` Behavioral Change Detection) — prefer the parallel form. Resolve the job count as a separate, literal step first — a `$(...)` command substitution inside the `bats` invocation itself is refused by this project's worktree isolation guard when the caller is running inside a worktree session (which `/code` and `/review` both always are):

   ```bash
   nproc 2>/dev/null || sysctl -n hw.logicalcpu
   ```

   Then substitute the printed value literally (not via `$(...)`) into the `bats` command:

   ```bash
   bats --jobs <N> tests/
   ```

   A serial whole-suite run can exceed the Bash tool's 10-minute ceiling, and a command that does is moved to the background automatically — in an execution surface without a re-invocation guarantee that turns into a silent no-op (Issue #1213). `nproc` is Linux-only; the `sysctl` fallback keeps the form portable to macOS.

   **Fallback when `--jobs` is unavailable**: bats-core implements `--jobs` on top of GNU `parallel`. If the invocation fails with a message naming `parallel` (e.g. `Cannot execute "N" jobs without GNU parallel`), this is a tooling-availability gap, not a test failure — do not enter Tier 0 / test-failure recovery for it. Do not simply re-run the whole suite as one serial `bats tests/` — that is exactly the form that overruns the ceiling (Issue #1213). Instead, split the run into multiple smaller serial invocations that each stay well inside the ceiling (e.g. one `bats <dir>/*.bats` call per test-file group), and note in the phase output that the suite ran as sharded serial batches because GNU `parallel` was unavailable, so a subsequent ceiling overrun is attributable.

### Step 2: Test Execution

1. Execute the test command in Bash. Default timeout: 120 seconds. If the caller specifies an
   explicit timeout (e.g. `/code` Step 9's execution surface constraint for full-suite runs), use
   the caller's value instead — a full bats suite exceeds the 120s default.

   **The caller's timeout cannot exceed 600000 ms (10 minutes) — that is the Bash tool's ceiling.**
   A command that runs past it is moved to the background automatically, so an explicit timeout
   does not by itself keep the command in the foreground. Commands that risk approaching the
   ceiling must be shortened instead (for a full bats suite: run it in parallel, see the Parallel
   execution note in Step 1). See Issue #1213 for the incident this rule generalizes from.

**Note (execution surfaces without a re-invocation guarantee)**: When the calling skill is running
in an execution surface without a re-invocation guarantee (headless `claude -p` via
`--non-interactive` in `ARGUMENTS`, a fork-executed Skill, the Workflow tool path, or a sub-agent/
background Bash spawned from any of those — see `modules/execution-context.md` § "Re-invocation
Guarantee and Notification-Dependent Waiting" for the exhaustive list and rationale), always run
the test command in the **foreground** — do not dispatch it with `run_in_background: true` and end
the turn waiting for a completion notification. Interactive-mode behavior (background execution +
await notification) is unaffected by this constraint.

### Step 3: Result Analysis

1. Parse the output and extract:
   - Number of passing tests
   - Number of failing tests
   - Number of skipped tests
   - Names and error content of failing tests

### Step 4: Organize Results

1. Organize results according to the output format

## Output Format

```markdown
## Quality Check Results

### Overall Result
- **Judgment**: PASS / FAIL
  - FAIL condition: If any of type check, lint, build, or tests FAIL
  - PASS condition: If all are PASS or SKIP

### Type Check
- **Command**: `npx tsc --noEmit` / SKIP (not applicable)
- **Result**: PASS / FAIL / SKIP

### Lint
- **Command**: `npm run lint` / SKIP (not applicable)
- **Result**: PASS / FAIL / SKIP

### Build
- **Command**: `npm run build` / SKIP (not applicable)
- **Result**: PASS / FAIL / SKIP

### Test Results
- **Command**: `bats --jobs N tests/` / `bats <dir>/*.bats` (sharded serial fallback) / Test framework not detected
- **Overall**: PASS / FAIL
- **Passed**: N items
- **Failed**: N items
- **Skipped**: N items

### Failure Details

(Only if failures exist. Include failures from type check, lint, build, and tests.)

**1. [Type Check/Lint/Build/Test] Failure Content**
- File: file path (if applicable)
- Error:
  ```
  error output
  ```
- Likely cause: brief analysis of error content
```
