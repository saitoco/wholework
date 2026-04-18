---
type: project
ssot_for:
  - customization-entry-points
---

English | [日本語](../ja/guide/customization.md)

# 🛠️ Customization

Wholework adapts to your project through three layers of configuration: `.wholework.yml` for feature flags, `.wholework/domains/` for skill-phase instructions, and adapters for tool integration.

## `.wholework.yml`

Create a `.wholework.yml` file at your project root to enable optional features and configure paths.

```yaml
# .wholework.yml

# Review tool integrations (all disabled by default)
copilot-review: true        # Wait for GitHub Copilot review before merging
claude-code-review: true    # Wait for Claude Code Review before merging
coderabbit-review: true     # Wait for CodeRabbit review before merging
review-bug: false           # Disable bug-detection agent in /review

# Post-skill verification
opportunistic-verify: true  # Run quick verify commands at skill completion

# Skill improvement proposals
skill-proposals: true       # Generate Wholework improvement issues during /verify

# Steering hint (enabled by default; set to false to opt out)
steering-hint: false        # Suppress the "/doc init" hint shown when steering docs are missing

# Custom paths (defaults shown)
spec-path: docs/spec              # Where specs are stored
steering-docs-path: docs          # Where steering documents live

# Production URL for browser-based verify commands
production-url: https://yourapp.example.com

# Watchdog timeout (default: 1800 seconds)
# Increase for slow repos, Size L+ tasks, or slow machines
watchdog-timeout-seconds: 3600

# Optional capabilities
capabilities:
  browser: true             # Enable Playwright-based verify commands
```

All keys are optional. If `.wholework.yml` does not exist, all settings use their defaults.

### Available Keys

This table is the **single source of truth (SSoT)** for all `.wholework.yml` configuration keys. Update this table when adding or changing keys.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `copilot-review` | boolean | `false` | Wait for GitHub Copilot review before merging |
| `claude-code-review` | boolean | `false` | Wait for Claude Code Review before merging |
| `coderabbit-review` | boolean | `false` | Wait for CodeRabbit review before merging |
| `review-bug` | boolean | `true` | Run bug-detection agent in `/review` |
| `opportunistic-verify` | boolean | `false` | Run quick verify commands at skill completion |
| `skill-proposals` | boolean | `false` | Generate Wholework improvement issues during `/verify` |
| `steering-hint` | boolean | `true` | Show `/doc init` hint when steering docs are missing |
| `production-url` | string | `""` | Production URL for browser-based verify commands |
| `spec-path` | string | `docs/spec` | Where specs are stored |
| `steering-docs-path` | string | `docs` | Where steering documents live |
| `capabilities.browser` | boolean | `false` | Enable Playwright-based verify commands |
| `capabilities.mcp` | list | `[]` | MCP tool names available to skills |
| `capabilities.{name}` | boolean | `false` | Dynamic capability mapping (e.g., `capabilities.invoice-api: true`) |
| `watchdog-timeout-seconds` | integer | `1800` | Watchdog timeout in seconds before killing a silent `claude -p` process. Increase for slow repos, Size L+ tasks, or slow machines (e.g., `3600`). Values ≤0 fall back to the default. |

For the full reference including implementation details and YAML parsing rules, see [`modules/detect-config-markers.md`](../../modules/detect-config-markers.md).

## `.wholework/domains/`

Domain files let you add project-specific instructions to individual skill phases without modifying Wholework itself.

Create Markdown files under `.wholework/domains/{skill}/`:

```
.wholework/
└── domains/
    ├── spec/          # Loaded by /spec
    ├── code/          # Loaded by /code
    └── review/        # Loaded by /review
```

For example, to tell `/spec` about your project's API conventions, create `.wholework/domains/spec/api-conventions.md`:

```markdown
# API Conventions

All new endpoints must follow REST naming: GET /resources, POST /resources, GET /resources/:id.
Authentication via Bearer token is required on all routes.
```

When `/spec` runs, it reads all `.md` files in `.wholework/domains/spec/` and incorporates them as constraints. This keeps your project-specific rules out of `CLAUDE.md` and in a structured location.

## Adapters

Wholework uses an adapter pattern to abstract tool access (browser automation, CI checks, external services). Adapters resolve in priority order:

1. **Project-local** — `.wholework/adapters/` in your repository
2. **User-global** — `~/.wholework/adapters/` shared across all your projects
3. **Bundled** — Default adapters included with Wholework

This means you can override any built-in adapter for your project without forking Wholework. A project-local adapter in `.wholework/adapters/` shadows the bundled version.

For details on writing custom adapters and verify command handlers, see [docs/guide/adapter-guide.md](adapter-guide.md).

## Steering Documents

Steering Documents (`docs/product.md`, `docs/tech.md`, `docs/structure.md`) are the primary way to give Wholework deep project context. Skills read them automatically when present.

Run `/doc init` to generate an initial set from your codebase. Run `/doc sync` to keep them in sync as your project evolves.

---

← [User Guide](index.md)
