# browser-adapter

Browser verification adapter.

## Purpose

Provides a tool-agnostic abstraction layer for executing browser verification commands (`browser_check` / `browser_screenshot`). Auto-detects available tools, converts to tool-specific commands, and delegates execution.

Caller: `modules/verify-executor.md`

## Input

The following information is passed from the caller:

- **Command type**: `browser_check` or `browser_screenshot`
- **URL**: Target URL for verification (`{{base_url}}` is resolved by caller)
- **Arguments**: Additional arguments depending on command type
  - `browser_check`: `selector` (CSS selector), `expected_text` (optional)
  - `browser_screenshot`: `description` (criteria for screenshot judgment)

## Processing Steps

### Step 1: URL Security Check

Read `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md` and execute the URL security constraint check following its processing steps. Return UNCERTAIN if constraints are not met (include detailed reason).

### Step 2: Tool Detection

Detect available tools in the following priority order. Use the first tool found.

| Priority | Tool | Detection Method |
|---------|------|----------------|
| 1 | browser-use CLI | Run `command -v browser-use` in Bash; detected if exit code is 0 |
| 2 | Playwright MCP | Use ToolSearch with `select:mcp__plugin_playwright_playwright__browser_navigate` / `browser_snapshot` / `browser_take_screenshot` / `browser_close`; detected only if all 4 are available |
| 3 | Not detected | If neither of the above is available (or only some Playwright MCP tools are detected) |

**When not detected**: Return UNCERTAIN. Clearly state in detail why detection failed (including missing Playwright MCP tool names): "No browser automation tool detected (browser-use CLI: not installed, Playwright MCP: insufficient required tools or unavailable)".

### Step 3: Basic Authentication Setup

If Basic authentication is required for preview or production environments, get credentials from the following environment variables:

- `PREVIEW_BASIC_USER`: Basic authentication username
- `PREVIEW_BASIC_PASS`: Basic authentication password

If these environment variables are set, attach authentication credentials in Step 4's tool-specific execution. Do NOT output credential information (`PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS`) in logs or verification result notes (mask as `****`). If environment variables are not set, connect without authentication.

### Step 4: Tool-Specific Execution

Execute according to the command conversion table below based on the detected tool.

#### browser-use CLI

> **Note**: The following command system is a provisional spec based on official browser-use CLI documentation (docs.browser-use.com, as of 2026-03). Commands and arguments may change with tool version updates. Check official documentation and update if errors occur during execution.

**`browser_check` execution steps:**

1. Open page with `browser-use open "<url>"`
   - With Basic auth: Do not embed credentials in URL; establish auth session in advance with `browser-use eval` before opening page. **Do NOT write `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` values directly in the command line string** (use environment variable references or temp files to pass the `Authorization` header so credentials don't appear in process list, shell history, or logs)
2. Wait for the selector element with `browser-use wait selector "<selector>"` (FAIL if element not found)
3. Get page text with `browser-use get text`
4. If `expected_text` is specified, confirm it is included in the retrieved text
5. Close session with `browser-use close`

**`browser_screenshot` execution steps:**

1. Open page with `browser-use open "<url>"`
   - With Basic auth: Do not embed credentials in URL; establish auth session in advance with `browser-use eval` before opening page. **Do NOT write `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` values directly in the command line string** (use environment variable references or temp files to pass the `Authorization` header so credentials don't appear in process list, shell history, or logs)
2. Generate temp file path and save screenshot to that path
   - Example (shell): `screenshot_path="$(mktemp /tmp/verify-screenshot-XXXXXX.png)"`
   - Example (browser-use): `browser-use screenshot "$screenshot_path"`
3. Read screenshot image at `"$screenshot_path"` using the Read tool, and AI visually judges based on `description`
4. Delete temp file after judgment (`rm -f "$screenshot_path"`)
5. Close session with `browser-use close`

#### Playwright MCP

**`browser_check` execution steps:**

1. Open URL with `browser_navigate`
   - With Basic auth: Attach `Authorization: Basic <base64(user:pass)>` to the `extraHTTPHeaders` option (do NOT use `http://user:pass@...` format — prevents scheme downgrade and URL corruption with `:` `@` in credentials)
2. Get DOM snapshot with `browser_snapshot`
3. Confirm specified selector element exists and contains `expected_text` (if `expected_text` is omitted, only verify selector existence)
4. Close browser with `browser_close`

**`browser_screenshot` execution steps:**

1. Open URL with `browser_navigate`
   - With Basic auth: Attach `Authorization: Basic <base64(user:pass)>` to the `extraHTTPHeaders` option (do NOT use `http://user:pass@...` format — prevents scheme downgrade and URL corruption with `:` `@` in credentials)
2. Take screenshot with `browser_take_screenshot`
3. AI visually judges based on `description` (best-effort due to subjective elements)
4. Close browser with `browser_close`

### Step 5: Return Result

Return the execution result as one of:

- **PASS**: Verification condition was met
- **FAIL**: Verification condition was not met (include detailed reason)
- **UNCERTAIN**: Cannot be automatically determined (tool not detected, URL security constraint violation, tool execution error, etc.; include detailed reason)

## Output

- **Result**: PASS / FAIL / UNCERTAIN
- **Details**: Description of verification result (include reason for FAIL / UNCERTAIN)

## Token budget

Claude Opus 4.7 supports images up to **2576 px** on the long edge (~3.75 MP), compared to 1568 px in earlier models. At full resolution, each image costs up to **4,784 tokens/image** — approximately 3× the token cost of a 1568 px image.

**Downsampling guidance**: When token budget is constrained (e.g., many screenshots in a single verify run or a cost-sensitive pipeline), downsample before passing the screenshot to the model:

- For UI layout and text legibility checks: 1280 px on the long edge is typically sufficient.
- For pixel-level detail or small text: use the full 2576 px resolution.
- When using Playwright MCP's `browser_take_screenshot`, the screenshot width can be controlled via `browser_resize` before capture.

No scale-factor conversion is needed: Opus 4.7 returns pointing and bounding-box coordinates in actual pixels (1:1 mapping).
