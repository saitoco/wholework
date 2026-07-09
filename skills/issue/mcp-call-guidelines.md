---
type: domain
skill: issue
---

# MCP Tool Detection and mcp_call Proposal Guidelines (Domain File)

This file implements the **Declaration-first Fallback** flow defined as the architecture SSoT in `docs/environment-adaptation.md` § Layer 2 ("MCP Tool Detection: Declaration-first Fallback"). `/issue` always reads this file when classifying acceptance criteria — do not gate the read on whether `MCP_TOOLS` is empty or non-empty; the fallback logic below handles both cases.

## Declaration-first Fallback

Follow this 3-step priority order:

1. **`MCP_TOOLS` is non-empty (declared)** → trust the declaration from `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and propose `mcp_call` hints using the declared tool names. Skip in-session detection — do not run ToolSearch (trusting the declaration is by design; see `docs/environment-adaptation.md` § Layer 2).
2. **`MCP_TOOLS` is empty (not declared)** → fall back to dynamic detection: check whether any `mcp__`-prefixed tool names are already visible in the current session context (e.g. via system-reminder tool listings). If any are found, use ToolSearch with `select:<tool_name>` to confirm the tool's existence and read-only nature, then propose `mcp_call` hints using the confirmed tool names.
3. **Neither a declaration nor a dynamically detected tool is found** → do not propose `mcp_call` hints.

This priority order — declared beats dynamic, dynamic beats nothing — mirrors `docs/environment-adaptation.md` § Layer 2 exactly, so that `.wholework.yml` remains the trusted override point while sessions with unregistered MCP tools are no longer silently skipped.
