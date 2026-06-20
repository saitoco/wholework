# detect-config-markers

Shared module for detecting configuration values in `.wholework.yml`.

## Purpose

Parse and extract configuration values from `.wholework.yml` at the project root and provide them as variables that each skill can reference uniformly. Designed so that adding a new configuration item requires only adding a row to the marker definition table in this file.

For user-facing documentation and the SSoT key reference, see [docs/guide/customization.md](../docs/guide/customization.md).

## Input

Information provided by the calling skill: none (directly reads `.wholework.yml` from the project root)

## Processing Steps

Skills that Read this file should detect configuration values following the steps below.

### 1. Load .wholework.yml

Read `.wholework.yml` from the project root using the Read tool.

- If `.wholework.yml` does not exist: Set all variables to their default values (boolean variables to `false`, `PRODUCTION_URL` to `""`), and end the procedure

### 2. Interpret YAML Keys

From the loaded content, search for each YAML key in the marker definition table below and extract values.

**Marker Definition Table (fixed mappings):**

| YAML Key | Variable | Value When `true` | Value When `false`/Unset |
|----------|----------|------------------|------------------------|
| `copilot-review` | `HAS_COPILOT_REVIEW` | `true` | `false` |
| `claude-code-review` | `HAS_CLAUDE_CODE_REVIEW` | `true` | `false` |
| `coderabbit-review` | `HAS_CODERABBIT_REVIEW` | `true` | `false` |
| `review-bug` | `SKIP_REVIEW_BUG` | `false` (enabled) | `false`-treated as true. If `review-bug: false` then `SKIP_REVIEW_BUG=true` |
| `opportunistic-verify` | `HAS_OPPORTUNISTIC_VERIFY` | `true` | `false` |
| `skill-proposals` | `HAS_SKILL_PROPOSALS` | `true` | `false` |
| `session-auto-rename` | `HAS_SESSION_AUTO_RENAME` | `true` | `false` |
| `steering-hint` | `HAS_STEERING_HINT` | `true` | `true` (default true; `false` when `steering-hint: false`) |
| `production-url` | `PRODUCTION_URL` | URL string (extract value as-is) | `""` |
| `spec-path` | `SPEC_PATH` | Path string (extract value as-is) | `docs/spec` |
| `steering-docs-path` | `STEERING_DOCS_PATH` | Path string (extract value as-is) | `docs` |
| `capabilities.browser` | `HAS_BROWSER_CAPABILITY` | `true` | `false` |
| `capabilities.visual-diff` | `HAS_VISUAL_DIFF_CAPABILITY` | `true` | `false` |
| `capabilities.workflow` | `HAS_WORKFLOW_CAPABILITY` | `true` | `false` |
| `capabilities.mcp` | `MCP_TOOLS` | Comma-separated tool name list | `""` |
| `watchdog-timeout-seconds` | `WATCHDOG_TIMEOUT_SECONDS` | Integer string (extract as-is; use `1800` if ≤0 or non-numeric) | `1800` (see `scripts/watchdog-defaults.sh` `WATCHDOG_TIMEOUT_DEFAULT`) |
| `watchdog-timeout-spec-seconds` | `WATCHDOG_TIMEOUT_SPEC_SECONDS` | Integer string (extract as-is; use phase-specific default if ≤0 or non-numeric) | `""` (unset; falls through to global key or phase default `1800`) |
| `watchdog-timeout-code-seconds` | `WATCHDOG_TIMEOUT_CODE_SECONDS` | Integer string (extract as-is; use phase-specific default if ≤0 or non-numeric) | `""` (unset; falls through to global key or phase default `1800`) |
| `watchdog-timeout-review-seconds` | `WATCHDOG_TIMEOUT_REVIEW_SECONDS` | Integer string (extract as-is; use phase-specific default if ≤0 or non-numeric) | `""` (unset; falls through to global key or phase default `2000`) |
| `watchdog-timeout-merge-seconds` | `WATCHDOG_TIMEOUT_MERGE_SECONDS` | Integer string (extract as-is; use phase-specific default if ≤0 or non-numeric) | `""` (unset; falls through to global key or phase default `600`) |
| `watchdog-timeout-issue-seconds` | `WATCHDOG_TIMEOUT_ISSUE_SECONDS` | Integer string (extract as-is; use phase-specific default if ≤0 or non-numeric) | `""` (unset; falls through to global key or phase default `600`) |
| `permission-mode` | `PERMISSION_MODE` | String value (extract value as-is) | `"auto"` |
| `verify-max-iterations` | `VERIFY_MAX_ITERATIONS` | Integer string (extract as-is; use `3` if ≤0, non-numeric, or >20) | `3` |
| `auto-max-concurrent` | `AUTO_MAX_CONCURRENT` | Integer string (extract as-is; use `5` if ≤0 or non-numeric) | `5` |
| `patch-lock-timeout` | `PATCH_LOCK_TIMEOUT_SECONDS` | Integer string (extract as-is; use `300` if ≤0 or non-numeric) | `300` (used by `scripts/worktree-merge-push.sh`) |
| `retro-proposals-upstream` | `RETRO_PROPOSALS_UPSTREAM` | String value (extract value as-is; upstream repository in `owner/repo` format) | `""` |
| `verify-ignore-paths` | `VERIFY_IGNORE_PATHS` | Newline-separated glob pattern list | `""` |
| `autonomy` | `AUTONOMY_TIER` | Tier string extracted as-is (`L1`/`L2`/`L3`) | `L1` |
| `auto-retry-on-fail.enabled` | `AUTO_RETRY_ENABLED` | `true` | `false` |
| `auto-retry-on-fail.max_iterations` | `AUTO_RETRY_MAX_ITERATIONS` | Integer string (extract as-is; use `3` if ≤0 or non-numeric) | `3` |
| `auto-retry-on-fail.budget_tokens` | `AUTO_RETRY_BUDGET_TOKENS` | Integer string (extract as-is; use `500000` if ≤0 or non-numeric) | `500000` |
| `recoveries-auto-fire.enabled` | `RECOVERIES_AUTO_FIRE_ENABLED` | `true` | `false` |
| `recoveries-auto-fire.threshold` | `RECOVERIES_AUTO_FIRE_THRESHOLD` | Integer string (extract as-is; use `3` if ≤0 or non-numeric) | `3` |

**Dynamic Capability Mapping:**

Any `capabilities.{name}` boolean key not listed in the table above (except `capabilities.mcp`) is dynamically mapped to `HAS_{UPPERCASE_NAME}_CAPABILITY`. When `true`, the variable is set to `true`; when `false` or unset, it is set to `false`. The `{UPPERCASE_NAME}` is derived by uppercasing the key and replacing hyphens with underscores.

Example: `capabilities.invoice-api: true` → `HAS_INVOICE_API_CAPABILITY=true`

**YAML Parsing Rules:**
- Interpret each line in `key: value` format
- Boolean values determined by `true` / `false` (case-insensitive)
- `review-bug` has inverse mapping: `review-bug: false` → `SKIP_REVIEW_BUG=true` (skip bug detection), `review-bug: true` → `SKIP_REVIEW_BUG=false` (bug detection enabled)
- `steering-hint` has inverse mapping: `steering-hint: false` → `HAS_STEERING_HINT=false` (hint suppressed), unset or `steering-hint: true` → `HAS_STEERING_HINT=true` (default enabled)
- `production-url` is treated as URL string with quotes removed
- `spec-path` and `steering-docs-path` are treated as path strings with quotes removed (same handling as `production-url`)
- `watchdog-timeout-seconds` is treated as an integer: extract the numeric string; if the value is ≤0 or non-numeric, fall back to the default `1800` (see `scripts/watchdog-defaults.sh` `WATCHDOG_TIMEOUT_DEFAULT`) and log a warning
- `verify-max-iterations` is treated as an integer: extract the numeric string; if the value is ≤0, non-numeric, or >20, fall back to the default `3` and log a warning
- `patch-lock-timeout` is treated as an integer: extract the numeric string; if the value is ≤0 or non-numeric, fall back to the default `300` (used by `scripts/worktree-merge-push.sh`)
- `retro-proposals-upstream` is treated as a string (`owner/repo` format) with quotes removed (same handling as `production-url`)
- `verify-ignore-paths` is written in block list format (`- pattern`), parsed the same way as `capabilities.mcp`. Each entry is a glob pattern. Supported: `dir/**` prefix match and simple bash globs (`*`, `?`, `[...]`); intermediate `**` (e.g. `a/**/b`) and negation (`!`) are not supported. If undefined or an empty list, `VERIFY_IGNORE_PATHS=""`
- `autonomy` is one of `L1`, `L2`, or `L3` (case-sensitive). Unset or invalid values (e.g., `autonomy: L9`) fall back to `L1` (safest). See `modules/autonomy-tier.md` for the tier semantics and permission matrix
- `auto-retry-on-fail.*` nested keys are interpreted under the `auto-retry-on-fail:` YAML section: `enabled: true/false`, `max_iterations: <integer>`, `budget_tokens: <integer>`. Both block format (`auto-retry-on-fail:\n  enabled: true`) and flat key format (`auto-retry-on-fail.enabled: true`) are supported. `max_iterations` and `budget_tokens` are treated as integers; use defaults if ≤0 or non-numeric.
- `recoveries-auto-fire.*` nested keys are interpreted under the `recoveries-auto-fire:` YAML section: `enabled: true/false`, `threshold: <integer>`. Both block format (`recoveries-auto-fire:\n  enabled: true`) and flat key format (`recoveries-auto-fire.enabled: true`) are supported. `threshold` is treated as an integer; use default `3` if ≤0 or non-numeric.
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
HAS_SESSION_AUTO_RENAME: true if session-auto-rename: true is set (default: false)
HAS_STEERING_HINT: false if steering-hint: false is set (default: true)
PRODUCTION_URL: URL string extracted from production-url (default: "")
SPEC_PATH: path string extracted from spec-path (default: "docs/spec")
STEERING_DOCS_PATH: path string extracted from steering-docs-path (default: "docs")
HAS_BROWSER_CAPABILITY: true if capabilities.browser: true is set (default: false)
HAS_VISUAL_DIFF_CAPABILITY: true if capabilities.visual-diff: true is set (default: false)
HAS_WORKFLOW_CAPABILITY: true if capabilities.workflow: true is set (default: false)
MCP_TOOLS: tool name list from capabilities.mcp (comma-separated, default: "")
WATCHDOG_TIMEOUT_SECONDS: integer from watchdog-timeout-seconds (default: "1800" (see `scripts/watchdog-defaults.sh` `WATCHDOG_TIMEOUT_DEFAULT`); falls back to "1800" if ≤0 or non-numeric)
WATCHDOG_TIMEOUT_SPEC_SECONDS: integer from watchdog-timeout-spec-seconds (default: "" — unset; resolution handled by load_watchdog_timeout())
WATCHDOG_TIMEOUT_CODE_SECONDS: integer from watchdog-timeout-code-seconds (default: "" — unset; resolution handled by load_watchdog_timeout())
WATCHDOG_TIMEOUT_REVIEW_SECONDS: integer from watchdog-timeout-review-seconds (default: "" — unset; resolution handled by load_watchdog_timeout())
WATCHDOG_TIMEOUT_MERGE_SECONDS: integer from watchdog-timeout-merge-seconds (default: "" — unset; resolution handled by load_watchdog_timeout())
WATCHDOG_TIMEOUT_ISSUE_SECONDS: integer from watchdog-timeout-issue-seconds (default: "" — unset; resolution handled by load_watchdog_timeout())
PERMISSION_MODE: string extracted from permission-mode (default: "auto")
VERIFY_MAX_ITERATIONS: integer from verify-max-iterations (default: "3"; falls back to "3" if ≤0, non-numeric, or >20)
AUTO_MAX_CONCURRENT: integer from auto-max-concurrent (default: "5"; falls back to "5" if ≤0 or non-numeric)
PATCH_LOCK_TIMEOUT_SECONDS: integer from patch-lock-timeout (default: "300"; falls back to "300" if ≤0 or non-numeric)
RETRO_PROPOSALS_UPSTREAM: upstream repository (owner/repo) from retro-proposals-upstream (default: "")
VERIFY_IGNORE_PATHS: newline-separated glob pattern list from verify-ignore-paths (default: "")
AUTONOMY_TIER: tier string from autonomy (default: "L1"; falls back to "L1" if unset or invalid)
AUTO_RETRY_ENABLED: true if auto-retry-on-fail.enabled: true is set (default: false)
AUTO_RETRY_MAX_ITERATIONS: integer from auto-retry-on-fail.max_iterations (default: "3"; falls back to "3" if ≤0 or non-numeric)
AUTO_RETRY_BUDGET_TOKENS: integer from auto-retry-on-fail.budget_tokens (default: "500000"; falls back to "500000" if ≤0 or non-numeric)
RECOVERIES_AUTO_FIRE_ENABLED: true if recoveries-auto-fire.enabled: true is set (default: false)
RECOVERIES_AUTO_FIRE_THRESHOLD: integer from recoveries-auto-fire.threshold (default: "3"; falls back to "3" if ≤0 or non-numeric)
```
