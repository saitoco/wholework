# verify-executor

Parse and execute verify commands.

## Purpose

Parse verify commands (`<!-- verify: ... -->`) attached to Issue acceptance criteria, execute the corresponding verification processing, and return results.

## Input

The following information is passed from the caller:

- **Verify command list**: List of acceptance conditions containing `<!-- verify: ... -->` (condition text and verification command pairs)
- **Execution mode**: `safe` or `full`
  - `safe`: Do not execute `command` hints; return UNCERTAIN (for `/review`). If a PR number is provided, attempt CI reference fallback
  - `full`: Also execute `command` hints (for `/verify`)
- **PR number** (optional): PR number. Used for CI reference fallback for `command` hints in safe mode

## Processing Steps

1. Parse each verify command, extracting the command name and arguments
2. **Resolve `{{base_url}}` placeholder**: If verify command URLs contain `{{base_url}}`, the calling skill is expected to have already resolved it to the actual URL before passing. verify-executor does not interpret the placeholder and uses the URL as received (if unresolved `{{base_url}}` remains, treat as UNCERTAIN).

2a. **Process `--when` modifier**: If the check arguments include `--when="shell_condition"`, process as follows:
   1. Extract `--when="shell_condition"` from the argument string, separating it from the main command arguments
   2. Execute `shell_condition` in Bash (timeout: 10 seconds)
   3. Exit code 0 (condition met) → Execute the main command normally in Step 3 and beyond
   4. Exit code != 0 (condition not met) → Return **SKIPPED**. Syntax errors and timeouts are all treated as condition not met (no distinction)

   The `--when` modifier is executed in both safe and full modes. Reason: the intended use of `--when` is side-effect-free environment checks like `which`/`test -n`/`command -v`, and blocking it would defeat its purpose.

   **Behavior in safe mode**: When the `--when` condition is met, the main command is subject to the usual safe/full mode restrictions. `--when` being met does not relax safe restrictions (`--when` and safe/full are independent judgments).

   When no `--when` modifier is present, proceed to Step 3 as before.

3. Execute verification according to the translation table below:

| Verification Command | Processing |
|---------------------|-----------|
| `file_exists "path"` | Run `test -f "path"` in Bash |
| `file_not_exists "path"` | Run `test ! -f "path"` in Bash |
| `dir_exists "path"` | Run `test -d "path"` in Bash |
| `dir_not_exists "path"` | Run `test ! -d "path"` in Bash |
| `file_contains "path" "text"` | Search for "text" in "path" using Grep |
| `file_not_contains "path" "text"` | Search with Grep and confirm no match |
| `grep "pattern" "path"` | Regex match using Grep. **PASS when match is found**. To assert absence (no match), use `file_not_contains` instead |
| `command "cmd"` | **Mode-dependent**: `safe` → attempt CI reference fallback (see below); return UNCERTAIN if no match. `full` → execute command in Bash (timeout: 60 seconds; exit code 0 = success) |
| `json_field "path" ".key" "value"` | Read file, parse JSON, and confirm field value |
| `section_contains "path" "heading" "text"` | Read file and confirm fixed string "text" is present within the specified markdown heading section (from the specified heading line to just before the next heading of the same or higher level, or end of file) |
| `section_not_contains "path" "heading" "text"` | Read file and confirm fixed string "text" is NOT present within the specified markdown heading section |
| `symlink "path" "target"` | Run `test -L "path"` + `readlink "path"` in Bash |
| `http_status "URL" "CODE"` | **Mode-dependent**: In safe mode, run URL security check from `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`. Safe mode blocks private IPs (`127.0.0.0/8`, `10.0.0.0/8`, etc.), external URLs are executed with curl. `full` → no restrictions; run `curl -s --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" "URL"` in Bash and confirm output matches "CODE" |
| `html_check "URL" "selector" "--exists"` / `html_check "URL" "selector" "--count=N"` | **Mode-dependent**: In safe mode, run URL security check from `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`. Safe mode blocks private IPs; external URLs executed with curl + pup. `full` → no restrictions; first check `which pup` (UNCERTAIN if not installed). If pup exists, run `curl -s --connect-timeout 5 --max-time 10 "URL" \| pup "selector"`; for `--exists` confirm output is not empty; for `--count=N` confirm `pup "selector" --number` output matches N |
| `api_check "URL" "jq_expression" "expected_value"` | **Mode-dependent**: In safe mode, run URL security check from `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`. Safe mode blocks private IPs; external URLs executed with curl + jq. `full` → no restrictions; run `curl -s --connect-timeout 5 --max-time 10 "URL" \| jq -r 'jq_expression'` and confirm output matches "expected_value" |
| `http_header "URL" "Header-Name" "expected_value"` | **Mode-dependent**: In safe mode, run URL security check from `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`. Safe mode blocks private IPs; external URLs executed with curl. `full` → no restrictions; run `curl -s --connect-timeout 5 --max-time 10 -I "URL"` (HEAD request), extract "Header-Name" value from response headers and compare with "expected_value" (case-insensitive header name match, fixed-string value comparison) |
| `http_redirect "source_URL" "expected_destination" "expected_status"` | **Mode-dependent**: In safe mode, run URL security check from `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`. Safe mode blocks private IPs; external URLs executed with curl. `full` → no restrictions; run `curl -s --connect-timeout 5 --max-time 10 -o /dev/null -w "%{redirect_url} %{http_code}" "source_URL"` (no redirect following) and confirm redirect destination URL and HTTP status code match |
| `build_success "CMD"` | **Mode-dependent**: `safe` → return UNCERTAIN (to prevent arbitrary command execution). `full` → execute build command in Bash (timeout: 120 seconds; exit code 0 = success) |
| `lighthouse_check "URL" "category" "min_score"` | **Mode-dependent**: `safe` → return UNCERTAIN (to prevent external command execution). `full` → Read `${CLAUDE_PLUGIN_ROOT}/modules/adapter-resolver.md`, resolve adapter by capability name `lighthouse`, and delegate. Pass command type `lighthouse_check` and arguments `url`, `category`, `min_score` |
| `browser_check "url" "selector" ["expected_text"]` | **Mode-dependent**: `safe` → return UNCERTAIN (to prevent browser operations). `full` → Read `${CLAUDE_PLUGIN_ROOT}/modules/adapter-resolver.md`, resolve adapter by capability name `browser`, and delegate processing. Pass command type `browser_check` and arguments `url`, `selector`, `expected_text` |
| `browser_screenshot "url" "description"` | **Mode-dependent**: `safe` → return UNCERTAIN. `full` → Read `${CLAUDE_PLUGIN_ROOT}/modules/adapter-resolver.md`, resolve adapter by capability name `browser`, and delegate. Pass command type `browser_screenshot` and arguments `url`, `description`. Best-effort due to subjective elements |
| `mcp_call "tool_name" "description"` | **Mode-dependent**: `safe` → return UNCERTAIN (to prevent external API calls). `full` → Use ToolSearch with `select:<tool_name>` (tool_name in `server_name__tool_name` fully qualified format, no spaces) to find the tool, and **only** call MCP tools clearly identified as read-only verification. Do not call tools with any possibility of writes, deletions, or external transmissions; return UNCERTAIN (with reason). Also return UNCERTAIN if ToolSearch is unavailable or tool call is blocked by permissions (include detailed reason). Evaluate result against description using AI judgment for PASS/FAIL. Return UNCERTAIN if tool not found (include detailed reason). Best-effort due to subjective elements. For the rationale of using ToolSearch directly (bypassing the adapter layer), see the Adapter Pattern section in `docs/environment-adaptation.md` |
| `github_check "gh_command" "expected_value"` | **Mode-dependent**: In safe mode, use allowlist approach. Allowlist: `gh issue view`, `gh pr view`, `gh pr checks`, `gh api` (no `--method` or `--method GET`). If allowlist matches → run `gh_command` in Bash and confirm output contains `expected_value` (if `expected_value` is omitted, confirm output is non-empty). If not in allowlist → return UNCERTAIN. `full` → no restrictions; run `gh_command` in Bash (timeout: 30 seconds) |

4. Treat syntax errors (unknown command names, missing arguments, etc.) as UNCERTAIN
5. Classify each condition's verification result:
   - **PASS**: Condition is met
   - **FAIL**: Condition is not met
   - **UNCERTAIN**: Cannot be automatically determined (safe mode command, syntax error, etc.)
   - **SKIPPED**: Environment condition (`--when`) was not met; skipped execution
6. Organize results according to the output format

### Basic Authentication Support

For Basic authentication in `browser_check` / `browser_screenshot`, refer to the browser adapter's Processing Steps (Step 3: Basic Authentication Setup) resolved via `${CLAUDE_PLUGIN_ROOT}/modules/adapter-resolver.md`. Auth info retrieval, attachment, and masking using `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` environment variables are managed centrally in the browser-adapter.

### Differentiation Between `http_status` / `html_check` / `api_check` / `build_success` / `lighthouse_check` / `github_check` and `command`

`http_status`, `html_check`, `api_check`, `build_success`, `lighthouse_check`, and `github_check` are specialized commands for web app, build, and GitHub state verification. Key differentiators from `command`:

- **`command`**: General-purpose command execution. Returns UNCERTAIN in safe mode (may use CI reference fallback). Only executed in full mode
- **`http_status`**: Specialized for HTTP response code verification. In safe mode, runs URL security check (`${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`) and blocks private IPs; external URLs verified with curl. Timeout prevents connection blocking (connect: 5s, total: 10s)
- **`html_check`**: Specialized for HTML structure verification. curl + pup with CSS selector evaluation. Can run in safe mode with URL security check. UNCERTAIN if `pup` is not installed
- **`api_check`**: Specialized for JSON API response verification (GET only). curl + jq for field extraction and comparison. Can run in safe mode with URL security check
- **`build_success`**: Specialized for build command success verification. Only executed in full mode. Timeout is 120 seconds (`command` is 60 seconds)
- **`lighthouse_check`**: Specialized for Lighthouse score verification. Only executed in full mode. Delegates to `lighthouse-adapter.md` via adapter-resolver, which handles CLI detection
- **`github_check`**: Specialized for GitHub state verification. In safe mode, only read-only commands (`gh issue view`, `gh pr view`, `gh pr checks`, `gh api` GET) are executed via allowlist. Non-allowlist items return UNCERTAIN

**Safe mode handling:**
- `http_status` / `html_check` / `api_check`: Can run in safe mode with URL security check. Private IP access is blocked; external URLs executed with curl (see `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md` for blocking policy)
- `build_success` / `command`: Return UNCERTAIN in safe mode (to prevent arbitrary command execution risk). Intended for use with `/verify` (full mode)
- `lighthouse_check`: Returns UNCERTAIN in safe mode (to prevent external command execution risk). Intended for use with `/verify` (full mode)
- `github_check`: Can run in safe mode via allowlist. Only `gh issue view`, `gh pr view`, `gh pr checks`, `gh api` (GET) are allowed. Write operations (`gh issue create`, `gh pr merge`, etc.) are blocked and return UNCERTAIN

### CI Reference Fallback (safe mode + PR number present)

When processing `command` hints in safe mode with a PR number provided:

1. Get CI status with `gh pr view "$PR_NUMBER" --json statusCheckRollup`
2. Match the `command` hint content (command name, test file paths, etc.) against CI job names and workflow names (inference-based)
   - Example: `command "bats tests/setup-labels.bats"` → `test-scripts` job
3. Determine based on match result:
   - Related job is **SUCCESS** → **PASS** (detail: "Alternative verification via CI job `job-name` success")
   - Related job is **FAILURE** → First determine if failure is due to CI infrastructure (step 3a)
   - Related job is **incomplete** (PENDING, etc.) → **UNCERTAIN** (detail: "CI incomplete")
   - Cannot **identify** corresponding job → **UNCERTAIN** (detail: "Could not identify corresponding CI job")

3a. **CI infrastructure failure determination** (for FAILURE jobs):

Get detailed job information via `gh api` and check for the following patterns:

| Pattern | How to Check |
|---------|-------------|
| Empty steps (`steps: []`) | `steps` field is an empty array |
| Timeout (`cancelled` + execution time exceeded) | `conclusion: cancelled` and `started_at` to `completed_at` is close to the time limit |
| Runner error (`The runner has received a shutdown signal`, etc.) | Runner error recorded in job logs or `steps[].name` |
| Network error (`Unable to download`, `ECONNREFUSED`, etc.) | Dependency download failure recorded in job logs |

- **Determined to be infrastructure-caused**: Ignore CI result and execute the `command` hint locally
  - Local execution succeeds → **PASS** (detail: "Alternative verification via local test due to CI infrastructure failure")
  - Local execution fails → **FAIL** (test code itself has a problem)
  - No `command` hint exists → **UNCERTAIN** (detail: "CI infrastructure failure detected but no corresponding command hint")
- **Not infrastructure-caused**: **UNCERTAIN** (detail: "CI job `job-name` failed")

**Note**: `command` execution is normally prohibited in safe mode, but is permitted locally only when determined to be CI infrastructure-caused (limited scope). In full mode, `command` execution is already possible, so the same fallback applies.

**Note**: If no PR number is provided, CI reference is not performed and UNCERTAIN is returned as before.

## Output Format

```markdown
## Verify Command Execution Results

| # | Condition | Verification Command | Result | Details |
|---|-----------|---------------------|--------|---------|
| 1 | Summary of condition text | `file_exists "path"` | PASS | File exists |
| 2 | Summary of condition text | `github_check "gh pr checks" "Run bats tests"` | PASS | CI job `Run bats tests` succeeded |
| 3 | Summary of condition text | `file_contains "file" "text"` | FAIL | Text not found |

### Summary
- PASS: N items
- FAIL: N items
- UNCERTAIN: N items
- SKIPPED: N items
```
