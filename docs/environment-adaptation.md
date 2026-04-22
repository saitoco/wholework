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
permission-mode: bypass       # Permission mode for /auto subprocess (bypass or auto)
spec-path: custom/specs       # Spec file save location (default: docs/spec)
steering-docs-path: custom/docs  # Steering Documents directory (default: docs)
capabilities:
  browser: true               # Browser-based verification available
  mcp:                        # Available MCP tools
    - mf_list_quotes
    - mf_list_invoices
  invoice-api: true           # Custom capability → HAS_INVOICE_API_CAPABILITY=true
```

Design rationale: MCP session availability and tool installation state can vary at runtime. Static declarations ensure reproducible behavior.

For details on each configuration field, see the marker definition table in `modules/detect-config-markers.md`.

## Layer 2: Detection (detect-config-markers + ToolSearch + CLI detection)

Reads Layer 1 declarations; dynamically detects any missing information in-session.

### Detection Mechanisms

| Mechanism | Detection Target | Used By |
|-----------|----------------|---------|
| `detect-config-markers.md` (fixed mappings) | Known flags in `.wholework.yml` → environment variables | `/review`, `/verify`, `/issue` |
| `detect-config-markers.md` (dynamic mapping) | Any `capabilities.{name}: true` → `HAS_{UPPERCASE_NAME}_CAPABILITY` variable | All skills that Read `detect-config-markers.md` |
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
| Directory-scan | `.wholework/domains/{skill}/` Glob | Project-local domain files (loaded when files exist) |

### Domain File Frontmatter Schema

Each bundled Domain file declares its identity and load condition via YAML frontmatter at the top of the file:

```yaml
---
type: domain
skill: {skill_name}   # single skill name or array (when shared across multiple skills)
load_when:
  file_exists_any: [path1, path2]  # file/directory existence (OR evaluation)
  marker: {yaml_key}                # YAML key in .wholework.yml (true check)
  capability: {name}                # capabilities.{name}: true check
  arg_starts_with: {prefix}         # ARGUMENTS leading string check
  spec_depth: {level}               # /spec SPEC_DEPTH condition (full/light)
---
```

When multiple `load_when` keys are specified, all conditions are evaluated with AND semantics. Unspecified keys are ignored. The `load_when` block may be omitted entirely for Domain files whose load condition is runtime-detected inside the file body.

### Domain Files (exhaustive)

| File | Skill | Load Condition | `load_when` | Domain |
|------|-------|---------------|-------------|--------|
| `skills/spec/figma-design-phase.md` | `/spec` | UI design requirements auto-detected | _(none — runtime-detected)_ | UI/Design |
| `skills/spec/codebase-search.md` | `/spec` | `SPEC_DEPTH=full` | `spec_depth: full` | Depth-based codebase investigation |
| `skills/spec/external-spec.md` | `/spec` | External spec dependencies present | _(none — runtime-detected)_ | External document reference |
| `skills/review/external-review-phase.md` | `/review` | `copilot-review`, `claude-code-review`, or `coderabbit-review` is true | `marker: [copilot-review, claude-code-review, coderabbit-review]` | External review tool integration |
| `skills/review/skill-dev-recheck.md` | `/review` | `validate-skill-syntax.py` exists | `file_exists_any: [scripts/validate-skill-syntax.py]` | Skill development project-specific |
| `skills/issue/spec-test-guidelines.md` | `/issue` | `validate-skill-syntax.py` exists | `file_exists_any: [scripts/validate-skill-syntax.py]` | Skill development test recommendations |
| `skills/verify/browser-verify-phase.md` | `/verify` | `HAS_BROWSER_CAPABILITY=true` | `capability: browser` | Browser verification |
| `skills/issue/mcp-call-guidelines.md` | `/issue` | `MCP_TOOLS` non-empty | `capability: mcp` | MCP tool detection |
| `skills/doc/translate-phase.md` | `/doc` | `translate` subcommand | `arg_starts_with: translate` | Translation generation |
| `.wholework/domains/{skill}/*.md` | `/spec`, `/code`, `/review` | Directory scan (files exist in `.wholework/domains/{skill}/`) | _(N/A — unconditional when present)_ | Project-local (user-defined) |

**Bundled Domain files** are discovered by the `domain-loader` module via Glob of `${CLAUDE_PLUGIN_ROOT}/skills/{SKILL_NAME}/*.md`. For each file, the module checks the `type: domain` frontmatter field; files without it are skipped. If `load_when:` is present, the module evaluates all typed keys with AND semantics and loads the file only when all conditions are true. If `load_when:` is absent, the file is loaded unconditionally (backward compatible).

**Project-local Domain files** are discovered via directory scan: at skill startup, the `domain-loader` module Globs `.wholework/domains/{skill}/*.md` and reads all found files in alphabetical order. Unlike bundled Domain files which support conditional loading via `load_when:`, project-local Domain files are loaded unconditionally when present — placing a `.md` file in the directory is sufficient to activate it. This mechanism is implemented in `modules/domain-loader.md` and invoked by `/spec`, `/code`, and `/review` skills.

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

#### Adapter Pattern Application Requirements

Adapters are valuable when multiple implementation choices must be abstracted — for example, `browser` (browser-use CLI vs Playwright MCP) or `lighthouse` (CLI detection), where tool selection, command translation, and fallback branching are required.

#### Why `mcp_call` Does Not Use an Adapter

`mcp_call` uses ToolSearch directly and bypasses the adapter layer. The reason: ToolSearch is the only detection and invocation mechanism for MCP tools within a Claude session. Unlike `browser` or `lighthouse`, there is no choice between multiple implementations, so adding an adapter layer would increase complexity without any functional benefit.

#### Future Extension Policy

If pre/post processing customization is needed in the future (e.g., argument transformation, result normalization), it should be added as a hook mechanism (e.g., `.wholework/hooks/mcp-pre.sh`) rather than an adapter. This is outside the current implementation scope.

### Custom Verify Command Handlers

A mechanism for adding project-local custom verification commands. Place a Markdown handler file at `.wholework/verify-commands/{name}.md` to register a custom verify command named `{name}`.

#### Declaration Path

```
.wholework/verify-commands/{name}.md
```

No capability declaration is required. Placing the file is sufficient to activate the handler.

#### Name Resolution Convention

The command name in `<!-- verify: {name} "arg" -->` is matched against the handler filename (without extension). Example: `<!-- verify: api-contract "endpoint" -->` resolves to `.wholework/verify-commands/api-contract.md`.

**Built-in priority**: If `{name}` matches a built-in command (e.g., `file_exists`, `grep`), the built-in is always used and the handler file is ignored with a warning.

#### Handler Contract

Custom handler files follow a four-section Markdown structure (same as adapter contracts):

```markdown
# {name} verify command handler

**Safe mode:** compatible   ← or "uncertain" (see below)
**Permission:** always_allow   ← or "always_ask" (see below)

## Purpose

{Description of what this handler verifies}

## Input

- **Arguments**: {arguments accepted by this command}

## Processing Steps

{Step-by-step verification logic — executed by the LLM when this handler is resolved}

## Output

- **Result**: PASS / FAIL / UNCERTAIN
- **Detail**: Description of verification result
```

#### Result Format

Custom handlers must return one of:

- **PASS**: Verification condition satisfied
- **FAIL**: Verification condition not satisfied (include detailed reason)
- **UNCERTAIN**: Cannot be determined automatically (include detailed reason)

#### Safe Mode Self-Declaration

Each handler self-declares its safe-mode compatibility near the top of the file:

| Declaration | Behavior |
|-------------|----------|
| `**Safe mode:** compatible` | Handler executes in both safe and full modes |
| `**Safe mode:** uncertain` | Handler returns UNCERTAIN in safe mode; executes only in full mode |
| (not declared) | Treated as `uncertain` — returns UNCERTAIN in safe mode |

Use `compatible` only for side-effect-free checks (file reads, static analysis, etc.). Use `uncertain` for any handler that calls external services or executes shell commands.

#### Permission Self-Declaration

Each handler self-declares its permission requirement near the top of the file:

| Declaration | Behavior |
|-------------|----------|
| `**Permission:** always_allow` | Command confirmed side-effect-free; always permitted without user confirmation |
| `**Permission:** always_ask` | Command has side effects or calls external services; user confirmation required before execution |
| (not declared) | Treated as `always_ask` (conservative default) |

Use `always_allow` only when the handler is fully read-only with no external writes or mutations. This declaration is designed for 1:1 mapping to Anthropic Managed Agents `permission_policy` in a future migration.

#### Relationship to Adapter Pattern

Custom verify command handlers differ from adapters in a key way: handlers are designed for a single implementation with no tool-selection branching. The adapter pattern (see `### Adapter Pattern` below) adds value when multiple tool implementations must be abstracted. Handlers are simpler — one handler file, one verification approach — and do not require the 3-layer resolution order that adapters use.

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
verify-executor (Layer 4) ─→ .wholework/verify-commands/*.md (project-local custom handlers)
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
