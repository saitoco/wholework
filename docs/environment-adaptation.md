---
type: project
ssot_for:
  - environment-adaptation-architecture
---

English | [日本語](ja/environment-adaptation.md)

# Environment Adaptation Architecture

## Overview

An architecture for running the same skill definitions across environments with different tool configurations. Composed of four layers.

```
Layer 1: Declaration    Statically define "what is available" in .wholework.yml
Layer 2: Detection      Determine environment capabilities from declarations or in-session detection
Layer 3: Disclosure     Core/Domain separation — load only the logic needed
Layer 4: Execution      safe/full mode branching + adapter delegation
```

## Layer 1: Declaration (`.wholework.yml`)

A YAML file placed at the project root. Declares the capabilities and tools available in the project.

```yaml
# .wholework.yml
copilot-review: true          # GitHub Copilot review integration
coderabbit-review: true       # CodeRabbit AI review integration
opportunistic-verify: true    # Opportunistic verification (auto-run post-merge conditions)
skill-proposals: true         # Skill proposal feature
capabilities:
  browser: true               # Browser-based verification available
  mcp:                        # Available MCP tools
    - mf_list_quotes
    - mf_list_invoices
```

Design rationale: MCP session availability and tool installation state can vary at runtime. Static declarations ensure reproducible behavior.

For details on each configuration field, see the marker definition table in `modules/detect-config-markers.md`.

## Layer 2: Detection (detect-config-markers + ToolSearch + CLI detection)

Reads Layer 1 declarations; dynamically detects any missing information in-session.

### Detection Mechanisms

| Mechanism | Detection Target | Used By |
|-----------|----------------|---------|
| `detect-config-markers.md` | Each flag in `.wholework.yml` → environment variables | `/review`, `/verify`, `/issue` |
| `ToolSearch` | MCP tool availability in session | `/issue` (no declaration), `verify-executor` (on `mcp_call` execution) |
| `command -v` | CLI tool availability | `browser-adapter` (browser-use CLI), `lighthouse-adapter` (lighthouse) |

### MCP Tool Detection: Declaration-first Fallback

Applied when `/issue` proposes `mcp_call` verify commands:

```
1. MCP_TOOLS is non-empty (declared)  → trust declaration, skip ToolSearch
2. MCP_TOOLS is empty (not declared)  → dynamic detection via ToolSearch
3. Neither detected                   → do not propose mcp_call hint
```

## Layer 3: Disclosure Control (Core/Domain Separation)

Keeps the SKILL.md core lightweight; environment-dependent logic (Domain) is loaded conditionally.

### Decision Criterion

"Is this logic needed for projects that do not use the target tool or project type?" → If No, extract it as a Domain file.

### Extraction Patterns

| Pattern | Condition Check | Example |
|---------|----------------|---------|
| Marker-detection | Value in `.wholework.yml` | `external-review-phase.md` (Read when `copilot-review: true`) |
| File-existence | Presence of a specific file | `skill-dev-recheck.md` (Read when `validate-skill-syntax.py` exists) |

### Domain Files (exhaustive)

| File | Skill | Load Condition | Domain |
|------|-------|---------------|--------|
| `skills/spec/figma-design-phase.md` | `/spec` | UI design requirements auto-detected | UI/Design |
| `skills/spec/codebase-search.md` | `/spec` | `SPEC_DEPTH=full` | Depth-based codebase investigation |
| `skills/spec/external-spec.md` | `/spec` | External spec dependencies present | External document reference |
| `skills/review/external-review-phase.md` | `/review` | `copilot-review`, `claude-code-review`, or `coderabbit-review` is true | External review tool integration |
| `skills/review/skill-dev-recheck.md` | `/review` | `validate-skill-syntax.py` exists | Skill development project-specific |
| `skills/issue/spec-test-guidelines.md` | `/issue` | `validate-skill-syntax.py` exists | Skill development test recommendations |
| `skills/verify/browser-verify-phase.md` | `/verify` | `HAS_BROWSER_CAPABILITY=true` | Browser verification |
| `skills/issue/mcp-call-guidelines.md` | `/issue` | `MCP_TOOLS` non-empty | MCP tool detection |

## Layer 4: Execution (verify-executor + adapter)

Executes verification commands. Tool-specific processing is delegated to adapters.

### safe/full Mode Branching

| Mode | Used By | Characteristics |
|------|---------|----------------|
| `safe` | `/review` | External command execution restricted; fallback to CI reference |
| `full` | `/verify` | All commands executable |

### Command-by-Environment Table

| Verification Command | safe mode | full mode |
|---------------------|-----------|-----------|
| `file_exists`, `grep`, `section_contains`, etc. | Executable | Executable |
| `http_status`, `html_check`, `api_check` | Executable with URL security check | Unrestricted |
| `command`, `build_success` | UNCERTAIN (CI fallback) | Execute |
| `lighthouse_check` | UNCERTAIN | Delegate to `lighthouse-adapter.md` via adapter-resolver; CLI detection inside adapter |
| `browser_check`, `browser_screenshot` | UNCERTAIN | Capability declaration check (`HAS_BROWSER_CAPABILITY`), then delegate via adapter-resolver; returns UNCERTAIN if not declared |
| `mcp_call` | UNCERTAIN | ToolSearch + read-only restriction |

### Adapter Pattern

An adapter encapsulates a capability (e.g., `browser`). It selects the tool-specific implementation using a 3-layer resolution order (see `modules/adapter-resolver.md`):

```
1. .wholework/adapters/{capability}-adapter.md   (project-local)
2. ~/.wholework/adapters/{capability}-adapter.md  (user-global)
3. ${CLAUDE_PLUGIN_ROOT}/modules/{capability}-adapter.md      (bundled default)
```

An adapter operates in three steps: detection → command translation → execution delegation.

### Adapter Contract Template

Adapters follow a unified contract. Users can create custom adapters by following this template and placing them at the project-local or user-global path above.

Reference implementation: `modules/browser-adapter.md`. Use this file as a guide when creating new adapters.

#### Required Sections

**1. Detection procedure**

Describe the procedure to auto-detect available tools. When multiple tools are supported, list them in a priority table.

```markdown
### Step N: Tool Detection

Detect available tools in priority order. Use the first tool found.

| Priority | Tool   | Detection Method |
|----------|--------|-----------------|
| 1        | Tool A | detected via `command -v tool-a` |
| 2        | Tool B | search for MCP tools via ToolSearch; detected only if all required tools are available |
| 3        | None   | none of the above available |

**When not detected**: Return UNCERTAIN with a detailed explanation of why detection failed.
```

**2. Command conversion table**

Describe the mapping from acceptance-check notation to tool-specific commands. Create a subsection per detected tool, with numbered steps for each command's execution.

```markdown
### Step N: Tool-specific Execution

#### Tool A

**Execution steps for `command_x`:**

1. Run the initialization command for Tool A
2. Access the target resource
3. Verify the condition
4. Close the session

#### Tool B

**Execution steps for `command_x`:**

1. ...
```

**3. Fallback**

Define behavior when no tool is detected. As a rule, return UNCERTAIN and guide the user to manual verification.

```markdown
### Step N: Return Result

Return the result as one of:

- **PASS**: Verification condition satisfied
- **FAIL**: Verification condition not satisfied (include detailed reason)
- **UNCERTAIN**: Cannot determine automatically (tool not found, execution error, etc. — include detailed reason)
```

#### Optional Sections

**Security constraints** — Describe tool-specific security constraints (e.g., URL filtering, credential masking, SSRF prevention).

**Setup instructions** — Describe installation guides and prerequisites for first-time use.

#### File Structure Template

```markdown
# {capability} adapter

## Purpose

{Description of adapter's role and the abstraction it provides}

Caller: {referencing module/skill}

## Input

The caller provides the following:

- **Command type**: {list of supported commands}
- **Arguments**: {arguments per command}

## Processing Steps

### Step 1: {Security Check (optional)}

{Security constraint verification procedure}

### Step 2: Tool Detection

| Priority | Tool        | Detection Method |
|----------|-------------|-----------------|
| 1        | {Tool A}    | {detection method} |
| 2        | None        | none of the above available |

**When not detected**: Return UNCERTAIN.

### Step 3: Tool-specific Execution

#### {Tool A}

{Command conversion table and execution steps}

### Step 4: Return Result

- **PASS**: Verification condition satisfied
- **FAIL**: Verification condition not satisfied (include detailed reason)
- **UNCERTAIN**: Cannot determine automatically (include detailed reason)

## Output

- **Result**: PASS / FAIL / UNCERTAIN
- **Detail**: Description of verification result

## Reference Marker

The caller that has Read this file must include the following marker in its final output:

`[ref:{adapter-name}:{random-4-char-alphanum}]`
```

### `--when` Modifier (planned, not yet implemented)

A mechanism to set environment gates on individual verification items within acceptance conditions.

```html
<!-- verify: browser_check "url" "h1" --when="command -v browser-use" -->
```

- Condition met (exit 0) → execute the main command
- Condition not met (exit != 0) → SKIPPED (ignored; no manual check required)

While Layers 1–3 control "which parts of a skill to load," `--when` provides environment gates at the level of individual verification items within acceptance conditions.

## Inter-layer Relationships

```
.wholework.yml (Layer 1)
  │
  ├─→ copilot-review ────→ whether /review Reads external-review-phase.md (Layer 3)
  ├─→ coderabbit-review ─→ whether /review Reads external-review-phase.md (Layer 3)
  ├─→ capabilities.mcp ──→ whether /issue proposes mcp_call hints (Layer 2)
  ├─→ capabilities.browser → whether adapter resolves browser (Layer 4)
  └─→ production-url ───→ whether verify-executor resolves {{base_url}} (Layer 4)

ToolSearch (Layer 2) ─→ dynamic MCP tool detection (fallback when not declared)
command -v (Layer 2) ─→ CLI tool availability check (inside adapters, inside --when)
--when (Layer 4) ────→ per-acceptance-condition environment gate (planned)
```

## Extension Guide

### Adding a new capability

1. Create `modules/{capability}-adapter.md` (refer to `modules/browser-adapter.md`)
2. Add the capability to the description in `modules/adapter-resolver.md`
3. Add the new command to the translation table in `verify-executor.md`, delegating via adapter-resolver
4. Add `capabilities.{name}` to the marker table in `modules/detect-config-markers.md`
5. Add to the Key Files table in `docs/structure.md`

### Adding new Domain logic

1. Create `skills/{skill-name}/{domain}-phase.md`
   - List the full paths of all modules this file references at the top of the file (e.g., `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md`). Abbreviated forms (e.g., `detect-config-markers.md` alone) are not allowed. Listing full paths at the top allows callers to know the referenced modules before loading.
2. Add a conditional Read instruction to SKILL.md (marker-detection or file-existence pattern)
3. Add to the Domain Files table in `docs/structure.md`
