# lighthouse-adapter

Lighthouse verification adapter.

## Purpose

Provides an abstraction layer for executing Lighthouse score verification commands (`lighthouse_check`). Auto-detects Lighthouse CLI and executes score verification, returning results.

Caller: `modules/verify-executor.md` (via `modules/adapter-resolver.md`)

## Input

The following information is passed from the caller:

- **Command type**: `lighthouse_check`
- **URL**: Target URL for verification (`{{base_url}}` is resolved by caller)
- **Arguments**:
  - `category`: Verification category (e.g., `performance`, `accessibility`, `best-practices`, `seo`)
  - `min_score`: Minimum passing score (integer 0-100)

## Processing Steps

### Step 1: CLI Detection

Run `which lighthouse` in Bash to confirm Lighthouse CLI is present.

- **Not detected**: Return UNCERTAIN. State in detail: "Lighthouse CLI not found (`which lighthouse` failed). Install Lighthouse: `npm install -g lighthouse`".

### Step 2: Lighthouse Execution

Run the following command in Bash (timeout: 120 seconds):

```
lighthouse "URL" --output=json --quiet --chrome-flags="--headless --no-sandbox" --only-categories="category"
```

If execution error (non-zero exit code), return UNCERTAIN. State in detail: "Lighthouse execution failed: {error content}".

### Step 3: Score Evaluation

Get `categories.{category}.score` from the JSON output (0-1 scale).

- **If field not retrieved**: Return UNCERTAIN. State in detail: "Score for category `{category}` not found in JSON output".
- **If score retrieved**: Multiply by 100 and convert to integer, then compare with min_score:
  - Score ≥ min_score → **PASS** (include actual score in details)
  - Score < min_score → **FAIL** (include actual score and min_score in details)

## Output

- **Result**: PASS / FAIL / UNCERTAIN
- **Details**: Description of verification result (include reason for FAIL / UNCERTAIN)

## Notes

**High-resolution model support**: Claude Opus 4.7 supports images up to **2576 px** on the long edge. If visual verification is integrated into Lighthouse workflows in the future, screenshots at up to 2576 px can be passed directly — each image costs up to **4,784 tokens/image** at full resolution. No scale-factor conversion is required (coordinates are 1:1 with actual pixels on Opus 4.7).
