# detect-config-markers

Shared module for detecting configuration values in `.wholework.yml`.

## Purpose

Parse and extract configuration values from `.wholework.yml` at the project root and provide them as variables that each skill can reference uniformly. Designed so that adding a new configuration item requires only adding a row to the marker definition table in this file.

## Input

Information provided by the calling skill: none (directly reads `.wholework.yml` from the project root)

## Processing Steps

Skills that Read this file should detect configuration values following the steps below.

### 1. Load .wholework.yml

Read `.wholework.yml` from the project root using the Read tool.

- If `.wholework.yml` does not exist: Set all variables to their default values (boolean variables to `false`, `PRODUCTION_URL` to `""`), and end the procedure

### 2. Interpret YAML Keys

From the loaded content, search for each YAML key in the marker definition table below and extract values.

**Marker Definition Table (exhaustive):**

| YAML Key | Variable | Value When `true` | Value When `false`/Unset |
|----------|----------|------------------|------------------------|
| `copilot-review` | `HAS_COPILOT_REVIEW` | `true` | `false` |
| `claude-code-review` | `HAS_CLAUDE_CODE_REVIEW` | `true` | `false` |
| `coderabbit-review` | `HAS_CODERABBIT_REVIEW` | `true` | `false` |
| `review-bug` | `SKIP_REVIEW_BUG` | `false` (enabled) | `false`-treated as true. If `review-bug: false` then `SKIP_REVIEW_BUG=true` |
| `opportunistic-verify` | `HAS_OPPORTUNISTIC_VERIFY` | `true` | `false` |
| `skill-proposals` | `HAS_SKILL_PROPOSALS` | `true` | `false` |
| `production-url` | `PRODUCTION_URL` | URL string (extract value as-is) | `""` |
| `capabilities.browser` | `HAS_BROWSER_CAPABILITY` | `true` | `false` |
| `capabilities.mcp` | `MCP_TOOLS` | Comma-separated tool name list | `""` |

**YAML Parsing Rules:**
- Interpret each line in `key: value` format
- Boolean values determined by `true` / `false` (case-insensitive)
- `review-bug` has inverse mapping: `review-bug: false` → `SKIP_REVIEW_BUG=true` (skip bug detection), `review-bug: true` → `SKIP_REVIEW_BUG=false` (bug detection enabled)
- `production-url` is treated as URL string with quotes removed
- If key does not exist, use default value
- Comment lines (lines starting with `#`) are ignored
- Nested values under `capabilities:` section are interpreted as `capabilities.{key}`. Both inline hash format (`capabilities: { browser: true }`) and block format (`capabilities:\n  browser: true`) are supported. If `capabilities:` section is undefined, all capability variables are `false`
- `capabilities.mcp` is written in list format (`- tool_name`) and converted to comma-separated string (e.g., `["mf_list_quotes", "mf_list_invoices"]` → `"mf_list_quotes,mf_list_invoices"`). Inline list format (`[tool1, tool2]`) is not supported in the initial implementation. If `capabilities.mcp` is undefined or an empty list, `MCP_TOOLS=""`

## Output Format

Provide detection results as the following variables to the calling skill:

```
HAS_COPILOT_REVIEW: true if copilot-review: true is set (default: false)
HAS_CLAUDE_CODE_REVIEW: true if claude-code-review: true is set (default: false)
HAS_CODERABBIT_REVIEW: true if coderabbit-review: true is set (default: false)
SKIP_REVIEW_BUG: true if review-bug: false is set (default: false)
HAS_OPPORTUNISTIC_VERIFY: true if opportunistic-verify: true is set (default: false)
HAS_SKILL_PROPOSALS: true if skill-proposals: true is set (default: false)
PRODUCTION_URL: URL string extracted from production-url (default: "")
HAS_BROWSER_CAPABILITY: true if capabilities.browser: true is set (default: false)
MCP_TOOLS: tool name list from capabilities.mcp (comma-separated, default: "")
```
