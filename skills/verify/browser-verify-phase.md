# Browser Verification Phase (Domain File)

Prerequisite: Read `~/.claude/modules/detect-config-markers.md` before reading this file and have `HAS_BROWSER_CAPABILITY` already fetched.

This file is only loaded when `HAS_BROWSER_CAPABILITY=true`. `HAS_BROWSER_CAPABILITY` is fetched from `~/.claude/modules/detect-config-markers.md` and enabled by declaring `capabilities.browser: true` in `.wholework.yml`.

## Inside Step 2: Browser Verification Command Processing Flow

Browser verification commands (`browser_check`, `browser_screenshot`) are only executed in full mode (UNCERTAIN in safe mode). Execution steps:

1. Use ToolSearch to search for `select:mcp__plugin_playwright_playwright__browser_navigate` and confirm MCP Playwright tools are available
2. Read `~/.claude/modules/browser-verify-security.md` and run the URL security constraint check (if constraints are not met, treat as UNCERTAIN)
3. Only execute if MCP Playwright is available and the URL is safe:
   - Open the specified URL with `browser_navigate`
   - `browser_check`: fetch DOM with `browser_snapshot` and verify element existence/text at the specified selector
   - `browser_screenshot`: take a screenshot with `browser_take_screenshot` and have the AI make a visual judgment based on the description
   - After verification, close the browser with `browser_close`
4. If MCP Playwright is unavailable or the URL does not meet security constraints: report as UNCERTAIN (include detailed reason)

## Inside Step 4: Browser-Verifiable Case Exclusion

**Browser-verifiable case exclusion**: Conditions with browser verification commands (`browser_check`, `browser_screenshot`) can be verified with a headless browser in environments where MCP Playwright is available, so they are excluded from the "cannot auto-verify" classification. In environments where MCP Playwright is unavailable, treat as UNCERTAIN.
