---
type: project
ssot_for:
  - adapter-authoring-guide
---

English | [日本語](../ja/guide/adapter-guide.md)

# Adapter Authoring Guide

A step-by-step guide for creating project-specific capability adapters for Wholework.

This guide is **self-contained**: Claude Code can create a new adapter by reading only this file.
No access to the Wholework source repository is required.

## Overview

Wholework's adapter pattern lets you integrate project-specific capabilities — MCP servers,
CLI tools, external services — into the Wholework workflow (`/issue`, `/code`, `/verify`).

An adapter is a Markdown file that follows a unified contract. Wholework resolves adapters
using a 3-layer priority order, so you can add project-specific behavior without modifying
the Wholework plugin itself.

---

## Prerequisites

### Declare capabilities in `.wholework.yml`

Place `.wholework.yml` at the project root and declare which capabilities are available.

```yaml
# .wholework.yml
capabilities:
  browser: true               # Browser-based verification available
  mcp:                        # MCP tools available in this project
    - my_service_list_items
    - my_service_create_item
```

**`capabilities.browser`** — set to `true` when a browser automation tool
(`browser-use` CLI or Playwright MCP) is available. Required for `browser_check` /
`browser_screenshot` verify commands to run.

**`capabilities.mcp`** — list MCP tool names available in this project session.
Required for `mcp_call` verify commands. Wholework uses the declared list to propose
`mcp_call` acceptance conditions in `/issue` and to execute them in `/verify`.

> If `.wholework.yml` does not exist or the capability is not declared,
> Wholework falls back to dynamic detection (ToolSearch / `command -v`).
> Explicit declaration provides reproducible behavior regardless of session state.

---

## Adapter Resolution

Wholework resolves adapters using a **3-layer priority order**:

| Priority | Layer | Path |
|----------|-------|------|
| 1 | Project-local | `.wholework/adapters/{capability}-adapter.md` |
| 2 | User-global | `~/.wholework/adapters/{capability}-adapter.md` |
| 3 | Bundled default | `${CLAUDE_PLUGIN_ROOT}/modules/{capability}-adapter.md` |

Wholework searches in this order and uses the **first file found**.

- **Project-local** (`.wholework/adapters/`) — per-project override. Checked into the
  project repository. Use this for MCP servers or project-specific CLI tools.
- **User-global** (`~/.wholework/adapters/`) — applies across all projects for the user.
  Use this for personal CLI preferences.
- **Bundled default** — ships with Wholework. Covers `browser` and `lighthouse`
  out of the box.

To add a new capability, create the adapter file at the project-local path:

```
.wholework/
└── adapters/
    └── my-service-adapter.md
```

---

## Adapter Contract Template

Every adapter must follow this contract. Copy the template below and fill in the
capability-specific details.

The template contains all three required sections:
**Detection**, **Tool-specific Execution**, and **Return Result**.

```markdown
# {capability} adapter

## Purpose

{Description of what this adapter does and what capability it provides}

Caller: `modules/verify-executor.md` (via `modules/adapter-resolver.md`)

## Input

The caller provides the following:

- **Command type**: {list of supported verify commands, e.g., `my_service_list`}
- **Arguments**: {arguments per command}

## Processing Steps

### Step 1: Tool Detection

Detect available tools in the following priority order. Use the first tool found.

| Priority | Tool | Detection Method |
|----------|------|-----------------|
| 1 | {Tool A} | Run `command -v tool-a` in Bash; detected if exit code is 0 |
| 2 | {MCP tool} | Use ToolSearch with `select:{mcp_tool_name}`; detected if available |
| 3 | Not detected | None of the above available |

**When not detected**: Return UNCERTAIN with a detailed explanation.

### Step 2: Tool-specific Execution

Execute according to the detected tool.

#### {Tool A}

**Execution steps for `{command_type}`:**

1. Run the initialization or authentication step
2. Invoke the tool with the provided arguments
3. Inspect the output and determine PASS / FAIL / UNCERTAIN

#### {MCP tool}

**Execution steps for `{command_type}`:**

1. Call `{mcp_tool_name}` with the provided arguments
2. Inspect the response and determine PASS / FAIL / UNCERTAIN

### Step 3: Return Result

Return the result as one of:

- **PASS**: Verification condition satisfied
- **FAIL**: Verification condition not satisfied (include detailed reason)
- **UNCERTAIN**: Cannot determine automatically (tool not found, execution error, etc.)

## Output

- **Result**: PASS / FAIL / UNCERTAIN
- **Detail**: Description of the verification result

## Reference Marker

The caller that has Read this file must include the following marker in its final output:

`[ref:{capability}-adapter:{random-4-char-alphanum}]`
```

---

## Workflow Integration Example

This section shows how to design acceptance criteria that use `mcp_call` verify commands,
using an MCP-based invoice service as a concrete example.

### Scenario

A project integrates an invoice MCP server with tools `invoice_list` and `invoice_create`.
The `.wholework.yml` declares:

```yaml
capabilities:
  mcp:
    - invoice_list
    - invoice_create
```

### Acceptance criteria in the Issue body

When `/issue` detects the declared MCP tools, it proposes `mcp_call` conditions
in the acceptance criteria section. Example:

```markdown
## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] <!-- verify: mcp_call "invoice_list" {} "items" --> `invoice_list` returns a list with an `items` field
- [ ] <!-- verify: file_exists "src/invoice-handler.ts" --> Invoice handler module is created

### Post-merge

- [ ] <!-- verify: mcp_call "invoice_create" {"title": "Test"} "id" --> `invoice_create` returns a response with an `id` field
```

**`mcp_call` syntax:**
```
mcp_call "{tool_name}" {json_args} "{expected_field_or_string}"
```

- `tool_name` — MCP tool name as declared in `.wholework.yml`
- `json_args` — JSON object passed to the tool (use `{}` for no arguments)
- `expected_field_or_string` — field name or string that must appear in the response

### Creating the adapter

To enable `/verify` to run these conditions, create the project-local adapter:

**`.wholework/adapters/invoice-adapter.md`** — follow the contract template above.

In Step 1 (Tool Detection), check for the MCP tools via ToolSearch:
```markdown
| 1 | invoice MCP | ToolSearch `select:invoice_list,invoice_create`; detected if both are available |
```

In Step 2 (Execution), translate `mcp_call "invoice_list" {} "items"` to:
- Call `invoice_list` MCP tool with `{}`
- Inspect response for `items` field → PASS if present, FAIL otherwise

---

## Claude Code Prompt Template

Use the following prompt to ask Claude Code to create an adapter for your project.
Replace the placeholders and paste the prompt into Claude Code.

### Prompt

```
Please create a Wholework adapter for the {SERVICE_NAME} capability in this project.

Read the adapter authoring guide first:
https://raw.githubusercontent.com/saitoco/wholework/main/docs/guide/adapter-guide.md

Then create `.wholework/adapters/{capability}-adapter.md` following the contract template
in the guide. The adapter should support the following verify commands:

- `{command_1}` — {description of what it verifies}
- `{command_2}` — {description of what it verifies}

Available tools for this capability:
- MCP tool: `{mcp_tool_name}` (or CLI: `{cli_tool_name}`)

Also update `.wholework.yml` to declare the capability:

capabilities:
  {capability_key}: true   # or list MCP tool names

After creating the adapter, show me an example acceptance condition I can add
to an Issue for pre-merge verification.
```

### Filled example (invoice MCP server)

```
Please create a Wholework adapter for the invoice service in this project.

Read the adapter authoring guide first:
https://raw.githubusercontent.com/saitoco/wholework/main/docs/guide/adapter-guide.md

Then create `.wholework/adapters/invoice-adapter.md` following the contract template
in the guide. The adapter should support the following verify commands:

- `mcp_call "invoice_list"` — verifies the invoice list API returns a valid response
- `mcp_call "invoice_create"` — verifies invoice creation returns an id field

Available tools for this capability:
- MCP tools: `invoice_list`, `invoice_create`

Also update `.wholework.yml` to declare the capability:

capabilities:
  mcp:
    - invoice_list
    - invoice_create

After creating the adapter, show me an example acceptance condition I can add
to an Issue for pre-merge verification.
```

---

## Further Reading

The following documents provide deeper background on the adapter pattern and the
environment adaptation architecture. They are **not required** to create an adapter —
this guide is self-contained — but are useful if you want to understand the internals
or extend the bundled adapters.

- **`docs/environment-adaptation.md`** (Wholework repo) — Full explanation of the
  4-layer environment adaptation architecture (Declaration → Detection → Disclosure →
  Execution). Covers `detect-config-markers.md`, the `--when` modifier, and the
  inter-layer relationship diagram.

- **`modules/browser-adapter.md`** (Wholework repo) — Reference implementation of a
  bundled adapter. Demonstrates multi-tool detection (browser-use CLI vs. Playwright MCP),
  command conversion tables, Basic authentication handling, and security constraints.
  Use as a concrete example when authoring your own adapter.
