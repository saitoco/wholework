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

3. **Resolve custom verify command handlers**: Before looking up the translation table, check whether the command name is a custom handler:

   a. **Built-in priority check**: If the command name matches a built-in command in the translation table below (e.g., `file_exists`, `grep`, `section_contains`), also Glob `.wholework/verify-commands/{name}.md`; if a shadowing handler file is found, output a warning in the Details column (e.g., "Warning: custom handler `file_exists.md` ignored — built-in takes priority"). Then use the built-in processing directly. Skip custom handler lookup in step b.

   b. **Custom handler lookup** (only for non-built-in command names): Glob `.wholework/verify-commands/{name}.md` where `{name}` is the command name from the verify comment. Perform this scan on each verify-executor invocation (no caching).

   c. **Handler found**: Read the handler Markdown file. Check for a safe-mode declaration in the handler (a line near the top of the file in the form `**Safe mode:** compatible` or `**Safe mode:** uncertain`):
      - Declared `compatible` → execute in both safe and full modes following the handler's Processing Steps
      - Declared `uncertain` or not declared → in safe mode, return UNCERTAIN; in full mode, execute following the handler's Processing Steps

      Also read the `**Permission:**` declaration if present (a line near the top of the file in the form `**Permission:** always_allow` or `**Permission:** always_ask`). Record the declared value for the caller's use. If the declaration is absent, default is `always_ask` (conservative).

   d. **Handler not found**: Return UNCERTAIN (no built-in match and no custom handler file found).

   e. *(Collision warning is handled in step a above.)*

   f. **Result format**: Custom handlers must return one of PASS, FAIL, or UNCERTAIN. The handler's Processing Steps describe the verification logic; execute them and map the outcome to these three values.

4. Execute verification according to the translation table below:

| Verification Command | Processing | Permission |
|---------------------|-----------|-----------|
| `file_exists "path"` | Run `test -f "path"` in Bash | `always_allow` |
| `file_not_exists "path"` | Run `test ! -f "path"` in Bash | `always_allow` |
| `dir_exists "path"` | Run `test -d "path"` in Bash | `always_allow` |
| `dir_not_exists "path"` | Run `test ! -d "path"` in Bash | `always_allow` |
| `file_contains "path" "text"` | Search for "text" in "path" using Grep | `always_allow` |
| `file_not_contains "path" "text"` | Search with Grep and confirm no match | `always_allow` |
| `files_not_contain "glob_pattern" "text"` | Expand glob_pattern with Glob tool; search each matched file for "text" using Grep; PASS if no files contain it, FAIL listing files that match. If no files match the glob, PASS. Safe-mode compatible. | `always_allow` |
| `grep "pattern" "path"` | Regex match using Grep. **PASS when match is found**. To assert absence (no match), use `file_not_contains` instead. **Matching is case-sensitive by default**: match the exact case of the implementation text. When the case is uncertain, use bracket notation (e.g., `[Nn]o heading matched`) | `always_allow` |
| `command "cmd"` | **Mode-dependent**: `safe` → attempt CI reference fallback (see below); return UNCERTAIN if no match. `full` → execute command in a bash subprocess (`bash -c 'cmd'`; timeout: 60 seconds; exit code 0 = success). **Note**: The command always runs in a bash subprocess regardless of the user's default shell. Shell-dependent glob patterns (e.g., `**` with zsh globstar) behave as bash glob, which may produce unexpected results. Use `find` for cross-shell compatible file enumeration (e.g., `find tests -name '*.bats'` instead of `tests/**/*.bats`). **Note**: `nproc` is Linux-only and not available on macOS. Use the portable one-liner `$(nproc 2>/dev/null \|\| sysctl -n hw.logicalcpu)` instead (macOS alternative: `sysctl -n hw.logicalcpu`). Example: `bats --jobs $(nproc 2>/dev/null \|\| sysctl -n hw.logicalcpu) tests/*.bats` | `always_ask` |
| `json_field "path" ".key" "value"` | Read file, parse JSON, and confirm field value | `always_allow` |
| `section_contains "path" "heading" "text"` | Read file and confirm fixed string "text" is present within the specified markdown heading section (from the specified heading line to just before the next heading of the same or higher level, or end of file). The heading argument uses **partial match**: the "heading" string only needs to appear anywhere within the heading line (after stripping leading `#` symbols and spaces), so `"Next Steps"` matches both `## Next Steps` and `## 🧭 Next Steps`. If no heading matches the given "heading" argument, return UNCERTAIN with a diagnostic message in the Details column: `No heading matched "{heading}". Candidate headings: "{H1}", "{H2}", ...` (up to 3 candidate headings from the file's actual headings, in document order). | `always_allow` |
| `section_not_contains "path" "heading" "text"` | Read file and confirm fixed string "text" is NOT present within the specified markdown heading section. Uses the same heading **partial match** rule as `section_contains`. If no heading matches, return UNCERTAIN with the same diagnostic message as `section_contains`: `No heading matched "{heading}". Candidate headings: "{H1}", "{H2}", ...` (up to 3 candidates). | `always_allow` |
| `symlink "path" "target"` | Run `test -L "path"` + `readlink "path"` in Bash | `always_allow` |
| `http_status "URL" "CODE"` | **Mode-dependent**: In safe mode, run URL security check from `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`. Safe mode blocks private IPs (`127.0.0.0/8`, `10.0.0.0/8`, etc.), external URLs are executed with curl. `full` → no restrictions; run `curl -s --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" "URL"` in Bash and confirm output matches "CODE" | `always_ask` |
| `html_check "URL" "selector" "--exists"` / `html_check "URL" "selector" "--count=N"` | **Mode-dependent**: In safe mode, run URL security check from `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`. Safe mode blocks private IPs; external URLs executed with curl + pup. `full` → no restrictions; first check `which pup` (UNCERTAIN if not installed). If pup exists, run `curl -s --connect-timeout 5 --max-time 10 "URL" \| pup "selector"`; for `--exists` confirm output is not empty; for `--count=N` confirm `pup "selector" --number` output matches N | `always_ask` |
| `api_check "URL" "jq_expression" "expected_value"` | **Mode-dependent**: In safe mode, run URL security check from `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`. Safe mode blocks private IPs; external URLs executed with curl + jq. `full` → no restrictions; run `curl -s --connect-timeout 5 --max-time 10 "URL" \| jq -r 'jq_expression'` and confirm output matches "expected_value" | `always_ask` |
| `http_header "URL" "Header-Name" "expected_value"` | **Mode-dependent**: In safe mode, run URL security check from `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`. Safe mode blocks private IPs; external URLs executed with curl. `full` → no restrictions; run `curl -s --connect-timeout 5 --max-time 10 -I "URL"` (HEAD request), extract "Header-Name" value from response headers and compare with "expected_value" (case-insensitive header name match, fixed-string value comparison) | `always_ask` |
| `http_redirect "source_URL" "expected_destination" "expected_status"` | **Mode-dependent**: In safe mode, run URL security check from `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`. Safe mode blocks private IPs; external URLs executed with curl. `full` → no restrictions; run `curl -s --connect-timeout 5 --max-time 10 -o /dev/null -w "%{redirect_url} %{http_code}" "source_URL"` (no redirect following) and confirm redirect destination URL and HTTP status code match | `always_ask` |
| `build_success "CMD"` | **Mode-dependent**: `safe` → return UNCERTAIN (to prevent arbitrary command execution). `full` → execute build command in Bash (timeout: 120 seconds; exit code 0 = success) | `always_ask` |
| `lighthouse_check "URL" "category" "min_score"` | **Mode-dependent**: `safe` → return UNCERTAIN (to prevent external command execution). `full` → Read `${CLAUDE_PLUGIN_ROOT}/modules/adapter-resolver.md`, resolve adapter by capability name `lighthouse`, and delegate. Pass command type `lighthouse_check` and arguments `url`, `category`, `min_score` | `always_ask` |
| `browser_check "url" "selector" ["expected_text"]` | **Mode-dependent**: `safe` → return UNCERTAIN (to prevent browser operations). `full` → Read `${CLAUDE_PLUGIN_ROOT}/modules/adapter-resolver.md`, resolve adapter by capability name `browser`, and delegate processing. Pass command type `browser_check` and arguments `url`, `selector`, `expected_text` | `always_ask` |
| `browser_screenshot "url" "description"` | **Mode-dependent**: `safe` → return UNCERTAIN. `full` → Read `${CLAUDE_PLUGIN_ROOT}/modules/adapter-resolver.md`, resolve adapter by capability name `browser`, and delegate. Pass command type `browser_screenshot` and arguments `url`, `description`. Best-effort due to subjective elements | `always_ask` |
| `mcp_call "tool_name" "description"` | **Mode-dependent**: `safe` → return UNCERTAIN (to prevent external API calls). `full` → Use ToolSearch with `select:<tool_name>` (tool_name in `server_name__tool_name` fully qualified format, no spaces) to find the tool, and **only** call MCP tools clearly identified as read-only verification. Do not call tools with any possibility of writes, deletions, or external transmissions; return UNCERTAIN (with reason). Also return UNCERTAIN if ToolSearch is unavailable or tool call is blocked by permissions (include detailed reason). Evaluate result against description using AI judgment for PASS/FAIL. Return UNCERTAIN if tool not found (include detailed reason). Best-effort due to subjective elements. For the rationale of using ToolSearch directly (bypassing the adapter layer), see the Adapter Pattern section in `docs/environment-adaptation.md` | `always_ask` |
| `github_check "gh_command" "expected_value"` | **Mode-dependent**: In safe mode, use allowlist approach. Allowlist: `gh issue view`, `gh pr view`, `gh pr checks`, `gh api` (no `--method` or `--method GET`). If allowlist matches → run `gh_command` in Bash. If output contains `in_progress` → **PENDING** (detail: "CI job is in_progress; re-verify after CI completes"). Otherwise, confirm output contains `expected_value` (if `expected_value` is omitted, confirm output is non-empty). If not in allowlist → return UNCERTAIN. `full` → no restrictions; run `gh_command` in Bash (timeout: 30 seconds). Same `in_progress` detection applies in full mode | `always_ask` |
| `rubric "text"` | **Mode-independent**: invoke grader in both `safe` and `full` modes (`always_allow` — no side effects; see "Safe mode behavior" below). Invoke grader with adversarial system prompt; pass Issue body, git diff, and any files explicitly named in "text" as input; return PASS, FAIL, or UNCERTAIN; FAIL includes a natural-language gap description. Spec files are not passed to the grader. | `always_allow` |

### Rubric Command Semantics

`rubric "text"` performs semantic-level acceptance condition judgment via an LLM grader with an adversarial stance.

**Grader input scope:**
- Issue body (Background, Purpose, Acceptance Criteria sections)
- `git diff` of the implementation
- Files explicitly named in the rubric "text" argument

Spec files are not passed to the grader. This enforces the Issue=WHAT / Spec=HOW separation: graders assess whether the implementation satisfies the stated acceptance condition (WHAT), not whether it follows the implementation plan (HOW). Passing Spec to the grader would introduce confirmation bias toward the plan.

**Adversarial stance:**
The grader system prompt explicitly instructs adversarial judgment: enumerate gaps strictly, prefer UNCERTAIN over PASS when ambiguous. This guards against the bias of an LLM judging its own outputs favorably.

**Return values:**
- `PASS` — implementation satisfies the acceptance condition
- `FAIL` — implementation does not satisfy the condition; includes a natural-language description of the gap
- `UNCERTAIN` — cannot be determined (safe mode, insufficient evidence, etc.)

**Safe mode behavior:**
`rubric` invokes the grader in both `safe` and `full` modes. The `always_allow` permission declaration (#276) confirms that the grader has no side effects and is safe for automatic execution — the same guarantee that allows `file_exists`, `grep`, and `section_contains` to run in safe mode. Restricting `rubric` to full mode while declaring it `always_allow` would be a Permission-Mode inconsistency. As a result, `/review` Step 8 (which calls verify-executor in safe mode) now runs the rubric grader, enabling semantic acceptance condition judgment at pre-merge time.

**Responsibility boundary with Step 3 AI judgment fallback:**
Step 3 AI judgment is an implicit, opportunistic fallback for conditions that lack a `<!-- verify: ... -->` hint. `rubric` is an explicit opt-in declared at Issue creation time. Use `rubric` when you want semantic judgment to be a first-class verification path, not a fallback.

**Managed Agents migration intent:**
`always_allow` permission is set on `rubric` for 1:1 portability to Anthropic Managed Agents `permission_policy` in a future migration.

### Permission Semantics and Managed Agents Mapping

The `Permission` column in the translation table and the `**Permission:**` declaration in custom handlers use the same two values:

- `always_allow` — read-only, no side effects; maps to `permission_policy: always_allow` in Managed Agents
- `always_ask` — execution, external calls, or side effects; maps to `permission_policy: always_ask` in Managed Agents

This semantics is designed for 1:1 portability to Anthropic Managed Agents `permission_policy` in a future migration. Actual enforcement based on the declared permission is out of scope for the current implementation; the table records intent only.

5. Treat syntax errors (unknown command names, missing arguments, etc.) as UNCERTAIN
6. Classify each condition's verification result:
   - **PASS**: Condition is met
   - **FAIL**: Condition is not met
   - **UNCERTAIN**: Cannot be automatically determined (safe mode command, syntax error, etc.)
   - **SKIPPED**: Environment condition (`--when`) was not met; skipped execution
   - **PENDING**: CI job is in_progress; temporary execution state, re-verify after CI completes
7. Organize results according to the output format

### Basic Authentication Support

For Basic authentication in `browser_check` / `browser_screenshot`, refer to the browser adapter's Processing Steps (Step 3: Basic Authentication Setup) resolved via `${CLAUDE_PLUGIN_ROOT}/modules/adapter-resolver.md`. Auth info retrieval, attachment, and masking using `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` environment variables are managed centrally in the browser-adapter.

### Differentiation Between `http_status` / `html_check` / `api_check` / `build_success` / `lighthouse_check` / `github_check` and `command`

`http_status`, `html_check`, `api_check`, `build_success`, `lighthouse_check`, and `github_check` are specialized commands for web app, build, and GitHub state verification. Key differentiators from `command`:

- **`command`**: General-purpose command execution. Returns UNCERTAIN in safe mode (may use CI reference fallback). Only executed in full mode. Commands run in a bash subprocess (`bash -c`); avoid shell-dependent glob patterns (e.g., `**`) and use `find` for reliable file enumeration
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
   - Related job status is **IN_PROGRESS** → **PENDING** (detail: "CI job is in_progress; re-verify after CI completes")
   - Related job is **incomplete** (QUEUED, etc.) → **UNCERTAIN** (detail: "CI incomplete")
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
- PENDING: N items
- SKIPPED: N items
```
