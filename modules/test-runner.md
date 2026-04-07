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
   - `.bats` files in `tests/` directory → `bats tests/`
   - `test` script in `package.json` → `npm test`
   - `test` target in `Makefile` → `make test`
   - `pytest.ini` / `pyproject.toml` → `pytest`
   - If not detected → return "Test framework not detected"

   **Note**: If Vitest and npm test coexist (`vitest.config.ts` / `vitest.config.js` exists and `package.json` also has a `test` script), prioritize Vitest.

### Step 2: Test Execution

1. Execute the test command in Bash (timeout: 120 seconds)

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
- **Command**: `bats tests/` / Test framework not detected
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
