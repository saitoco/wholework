# adapter-resolver

Adapter resolution order module.

## Purpose

Receives a capability name (e.g., `browser`), performs a capability declaration check, then identifies the corresponding adapter file using a 3-layer resolution order (project-local → user-global → bundled) and delegates processing. Enables skills to call adapters by capability name alone without being aware of adapter file locations.

## Input

The following information is passed from the caller:

- **Capability name**: Name identifying the adapter (e.g., `browser`). Adapter file name corresponds to `{capability}-adapter.md`
- **Command type**: Command to delegate to adapter (e.g., `browser_check`)
- **Arguments**: Additional arguments depending on command type

## Processing Steps

### Step 1: Capability Declaration Check

Read `~/.claude/modules/detect-config-markers.md` and get capability variables following its processing steps.

Derive the variable name from the capability name (e.g., `browser`) using the naming convention (`HAS_{UPPERCASE_CAPABILITY_NAME}_CAPABILITY`):

- `browser` → `HAS_BROWSER_CAPABILITY`
- `mcp` → `HAS_MCP_CAPABILITY`

Check the variable value:

- **Variable is `true`**: Proceed to next step
- **Variable is `false`** (explicitly disabled in `.wholework.yml`): Return UNCERTAIN. State in detail: "capability `{capability}` is disabled in .wholework.yml, returning UNCERTAIN"
- **Variable unknown** (capability not registered in `detect-config-markers.md` marker table): Skip declaration check and proceed to next step (general CLIs should work without `.wholework.yml` declaration)

### Step 2: 3-Layer Adapter File Resolution

Search for `{capability}-adapter.md` in the following priority order and use the first file found (exhaustive).

| Priority | Resolution | Path | Description |
|---------|-----------|------|-------------|
| 1 | Project-local | `.wholework/adapters/{capability}-adapter.md` | Project-specific override |
| 2 | User-global | `~/.wholework/adapters/{capability}-adapter.md` | User environment-specific config |
| 3 | Bundled | `~/.claude/modules/{capability}-adapter.md` | Default implementation (fallback) |

Existence check procedure for each path:

1. Run `test -f ".wholework/adapters/{capability}-adapter.md"` in Bash; if succeeds, use **project-local**
2. If fails, run `test -f "$HOME/.wholework/adapters/{capability}-adapter.md"` in Bash; if succeeds, use **user-global**
3. If fails, run `test -f "$HOME/.claude/modules/{capability}-adapter.md"` in Bash; if succeeds, use **bundled**
4. If all fail, return UNCERTAIN (state in detail: "`{capability}-adapter.md` not found (not present in project-local: `.wholework/adapters/`, user-global: `~/.wholework/adapters/`, or bundled: `~/.claude/modules/`)")

### Step 3: Delegation to Adapter

Read the resolved adapter file and delegate execution by passing the command type and arguments following its processing steps. Pass all arguments received from the caller (URL, selector, etc.) directly to the adapter. If Read fails, return UNCERTAIN (state in detail: "Failed to Read `{capability}-adapter.md`: {path}").

### Step 4: Return Result

Return the adapter's execution result (PASS / FAIL / UNCERTAIN) as-is to the caller.

## Output

- **Result**: PASS / FAIL / UNCERTAIN (adapter execution result returned as-is)
- **Details**: Resolved adapter file path (for debugging) and verification result description
