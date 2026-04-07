# MCP Tool Detection and mcp_call Proposal Guidelines (Domain File)

This file is loaded only when `MCP_TOOLS` obtained from `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` is non-empty. If `MCP_TOOLS` is empty, this file is not loaded and `mcp_call` hints are not proposed.

## Declaration Priority (MCP_TOOLS)

Use the `MCP_TOOLS` value obtained from `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` to propose `mcp_call` hints. This file is loaded only when `MCP_TOOLS` is non-empty, so all processing below assumes `MCP_TOOLS` is non-empty:

1. `MCP_TOOLS` is non-empty (declaration present) → propose `mcp_call` hints using the declared tool names. Do not run in-session detection via ToolSearch (trusting the declaration is by design)
