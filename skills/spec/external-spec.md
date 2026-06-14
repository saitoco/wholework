---
type: domain
skill: spec
---

# External Specification Check

## Purpose

Check external specifications for commands, APIs, libraries, etc. and return a summary of the specification information needed for implementation.

## Input

The caller provides the following information in the prompt:

- **Investigation target**: the specification to check (command name, API name, library name, tool name, etc.)
- **Verification aspects**: the information to look for (usage, options, constraints, compatibility, etc.)
- **Reference URL**: official documentation URL if known (optional)

## Processing Steps

1. If the target is a library or framework, prioritize Context7 MCP:
   a. Resolve the library ID with `resolve-library-id`
   b. Fetch the latest docs with `get-library-docs`
   c. If sufficient information is obtained, proceed to step 5
2. If Context7 has insufficient information or the target is not registered, fall back
3. If a reference URL is provided, fetch the documentation via WebFetch
4. If no reference URL, search for official docs via WebSearch (e.g., `{target} official documentation`, `{target} API reference`)
5. Extract information related to the verification aspects from the obtained content
6. Fetch additional pages via WebFetch as needed
7. Organize results according to the output format

## JSON I/O Spec Check

When the spec involves JSON input/output with external systems (hook output, MCP tool responses, API requests/responses, etc.), do not rely on changelogs or release notes alone. Always reference the **official docs' JSON schema section** and explicitly document the following in the Spec's "Uncertainties" or "Notes":

### Checklist

1. **必須フィールド一覧** (required keys) — list all fields that must be present
2. **enum / 値制約** (value constraints) — especially discriminator fields (e.g., `hookEventName` that identifies which event type)
3. **省略時の挙動** (behavior when omitted) — does a missing field cause an error or is it silently ignored?
4. **追加可能なオプションフィールド** (available optional fields) — document extension room

Include a **minimal complete example** in the Spec's Implementation Steps so implementors can reference it directly. Example for a Claude Code hook:

```json
{
  "hookEventName": "UserPromptSubmit",
  "hookSpecificOutput": {
    "sessionTitle": "example-session"
  }
}
```

### Reference Table

| Use case | Docs to check |
|----------|--------------|
| Claude Code hooks | `docs.anthropic.com/en/docs/claude-code/hooks` Hook output JSON schema |
| MCP tool implementation | MCP spec ToolResult schema |
| GitHub API integration | GitHub REST/GraphQL API reference |

## External API Integration Checklist

Apply this checklist when the Issue involves calling an external API and processing its responses.

1. **Actual response format samples** — Collect real response samples from the actual API (not only the official specification), especially for attributes where the actual format may diverge from the official spec (e.g., `dateTime` attributes: official `YYYY-MM-DD;HH:MM:SS` vs. actual `YYYYMMDD;HH:MM:SS`; numeric attributes: scale, separator, trailing zeros). Include at least one minimal XML or JSON actual response sample in the Spec's Implementation Steps.
2. **Abnormal/error response code list** — Enumerate all known non-normal error codes the API may return (including throttle codes, in-progress codes, and any partner-guide-documented codes). For each code, document the handling policy: **retry** (call again with backoff) / **non-failure exit** (treat as success and stop) / **exception throw** (raise and propagate).
3. **Test coverage for actual format patterns** — Datetime and numeric conversion utilities that parse actual API responses must have test cases covering all actual format patterns observed in real responses, not only patterns documented in the official specification.

## Output Format

```markdown
## External Specification Results

### Target
- **Name**: name of the investigation target
- **Version**: verified version (if identifiable)

### Specification Summary

Concise answer to the verification aspects.

### Constraints and Notes

Constraints and compatibility issues to be aware of during implementation.

### Reference URLs
- [Document title](URL)
```
