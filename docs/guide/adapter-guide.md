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

**`preview-url-command`** — a related but distinct mechanism: a project-local *script*
(not an adapter contract `.md` file) that resolves `PREVIEW_URL`, for hosting providers
that never create a GitHub deployment (e.g. AWS Amplify Hosting). The declared command is
executed via `bash -c` by the shared resolver `scripts/resolve-preview-env.sh` (Issue
#1428), which both `scripts/run-review.sh`'s preview-wait gate and `/review`'s own Step
8.0 Fast path (when invoked directly as a skill) call — a single guard implementation
(timeout, output validation) shared by both call sites. Place the script under
`.wholework/adapters/` (e.g. `.wholework/adapters/resolve-preview-url.sh`) alongside your
other adapters for discoverability, and declare it with
`preview-url-command: ".wholework/adapters/resolve-preview-url.sh {pr}"` in
`.wholework.yml`. This does **not** go through the 3-layer Adapter Resolution below — the
resolver is a plain script path declared directly in the config key, not an adapter
contract `.md` file resolved via "Read and follow".
See [`docs/guide/customization.md`](customization.md) § "Resolving `PREVIEW_URL`" for the
full contract (fallback behavior, `{pr}` substitution, coverage scope).

**`preview-basic-auth-command`** — the same mechanism as `preview-url-command` above, for
resolving `PREVIEW_BASIC_USER`/`PREVIEW_BASIC_PASS` instead of `PREVIEW_URL`. Place the script
under `.wholework/adapters/` alongside your other adapters and declare it with
`preview-basic-auth-command: ".wholework/adapters/resolve-preview-basic-auth.sh {pr}"` in
`.wholework.yml`. Like `preview-url-command`, this does **not** go through the 3-layer Adapter
Resolution below — it is a plain script path declared directly in the config key, invoked by
`scripts/run-review.sh` via `bash -c`. See [`docs/guide/customization.md`](customization.md) §
"Automating Basic Auth credential resolution with `preview-basic-auth-command`" for the full
contract.

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

## Preview URL / Basic Auth Command Recipes

The `preview-url-command` and `preview-basic-auth-command` keys (see "Prerequisites" above)
each expect a project-local script under `.wholework/adapters/`. This section provides
copy-paste starting points for two common cases.

> These scripts are **not** code that Wholework itself tests or maintains — they are
> documentation samples for you to copy into your own project's `.wholework/adapters/`
> and adapt as needed, the same "provider adapters stay project-side" boundary the
> Adapter Resolution section above draws for capability adapters.

### `preview-url-command` — AWS Amplify Hosting (production-proven)

AWS Amplify Hosting never creates a GitHub Deployments API record, so the default
Deployments-API polling in `scripts/run-review.sh` never resolves `PREVIEW_URL` for
Amplify-hosted previews (see "Automating `PREVIEW_URL` resolution" above). This recipe
extracts the preview URL from the `aws-amplify-*` bot's PR comment instead — no AWS
credentials are required.

Prerequisites: `gh` CLI authenticated, `jq` (only needed if you extend the script;
the version below relies on `gh`'s built-in `--jq` support).

**`.wholework/adapters/resolve-preview-url.sh`**:

```bash
#!/usr/bin/env bash
# Resolves the AWS Amplify Hosting preview URL for a PR by extracting it from the
# aws-amplify-* bot's PR comment. No AWS credentials required.
set -euo pipefail

PR_NUMBER="${1:?Usage: resolve-preview-url.sh <pr-number>}"

gh pr view "$PR_NUMBER" --json comments \
  --jq '.comments[] | select(.author.login | test("^aws-amplify")) | .body' \
  | grep -oE 'https://[A-Za-z0-9.-]+\.amplifyapp\.com[^[:space:])"'"'"']*' \
  | head -n1
```

Declare it in `.wholework.yml`:

```yaml
capabilities:
  pr-preview: true
preview-url-command: ".wholework/adapters/resolve-preview-url.sh {pr}"
```

This recipe has been exercised in real usage against a downstream project's Amplify-hosted
previews, extracting the `*.amplifyapp.com` URL from the bot comment without AWS credentials.

### `preview-basic-auth-command` — generic CI secret template (illustrative, unproven)

Unlike the Amplify recipe above, this template has **no confirmed production track record** —
`preview-basic-auth-command` itself is a newer key with no adopted implementation yet. It is a
provider-agnostic illustration, not a recipe tied to a specific hosting provider: it reads
CI-injected secret environment variables and prints them in `username:password` format. Treat
it as a starting point to rewrite against your project's actual secret source (a secrets
manager, a password-manager CLI, etc.) rather than as a ready-to-use script.

**`.wholework/adapters/resolve-preview-basic-auth.sh`**:

```bash
#!/usr/bin/env bash
# Illustrative template only — not exercised in production. Reads CI-injected secret
# environment variables and prints them in `username:password` format. Replace the
# env-var read below with your project's actual secret source.
set -euo pipefail

if [ -z "${WHOLEWORK_PREVIEW_BASIC_USER:-}" ] || [ -z "${WHOLEWORK_PREVIEW_BASIC_PASS:-}" ]; then
  echo "resolve-preview-basic-auth.sh: WHOLEWORK_PREVIEW_BASIC_USER/WHOLEWORK_PREVIEW_BASIC_PASS not set" >&2
  exit 1
fi

echo "${WHOLEWORK_PREVIEW_BASIC_USER}:${WHOLEWORK_PREVIEW_BASIC_PASS}"
```

Declare it in `.wholework.yml`:

```yaml
capabilities:
  pr-preview: true
preview-basic-auth-command: ".wholework/adapters/resolve-preview-basic-auth.sh {pr}"
```

If the CI secrets are unavailable, the script exits non-zero, matching
`preview-basic-auth-command`'s documented failure fallback (both variables left unset,
existing unauthenticated fallback preserved).

As more providers accumulate production-proven `preview-url-command` recipes, or a
production-proven `preview-basic-auth-command` implementation emerges, add them as
additional subsections here, grouped by key and by provider.

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
