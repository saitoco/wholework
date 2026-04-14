---
type: project
ssot_for:
  - customization-entry-points
---

# 🛠️ Customization

Wholework works out of the box without any configuration. This guide describes how to tailor it to your project.

## `.wholework.yml`

Place a `.wholework.yml` file at your project root to configure Wholework behavior per project.

```yaml
# .wholework.yml
opportunistic-verify: true   # Run a lightweight verify check at the end of /code and /review
skill-proposals: true        # Suggest related skill runs at the end of each phase
production-url: "https://example.com"  # Used by browser-based verify commands
```

### Available Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `opportunistic-verify` | boolean | `false` | Run lightweight acceptance checks at /code and /review completion |
| `skill-proposals` | boolean | `false` | Show next-step skill suggestions after each phase |
| `production-url` | string | `""` | Base URL for browser-based verify commands |
| `copilot-review` | boolean | `false` | Enable GitHub Copilot as an additional reviewer in /review |
| `claude-code-review` | boolean | `false` | Enable Claude Code as an additional reviewer in /review |
| `coderabbit-review` | boolean | `false` | Enable CodeRabbit as an additional reviewer in /review |
| `spec-path` | string | `docs/spec` | Directory where Spec files are stored |
| `steering-docs-path` | string | `docs` | Directory where Steering Documents are stored |
| `capabilities.browser` | boolean | `false` | Enable browser-based verify commands (requires Playwright MCP) |

For the full list of configuration keys, see [modules/detect-config-markers.md](../../modules/detect-config-markers.md).

## Domain Files

Domain files let you inject project-specific instructions into individual skills without modifying the skill source.

Place Markdown files under `.wholework/domains/{skill}/` and they are automatically loaded when that skill runs:

```
.wholework/
└── domains/
    ├── spec/          # Loaded by /spec
    │   └── api-conventions.md
    ├── code/          # Loaded by /code
    │   └── testing-rules.md
    └── review/        # Loaded by /review
        └── security-checklist.md
```

Example domain file for `/code`:

```markdown
# Testing Rules

- All new functions must have a corresponding unit test in `tests/`
- Use `pytest` with `pytest-asyncio` for async functions
- Mock external HTTP calls with `respx`
```

Skills read all `.md` files in the relevant `domains/` subdirectory (alphabetical order) and incorporate their content into the execution context.

## Steering Documents

Steering Documents (`docs/product.md`, `docs/tech.md`, `docs/structure.md`) provide project-wide context to every skill. They are especially useful for:

- Defining forbidden expressions or naming conventions (`tech.md`)
- Describing the project vision and non-goals (`product.md`)
- Documenting directory layout and key files (`structure.md`)

Initialize Steering Documents with:

```
/wholework:doc init
```

## Adapters

Adapters extend skill behavior for specific tools or environments. They follow a three-layer resolution order:

1. **Project-local** (`.wholework/adapters/`) — highest priority, project-specific
2. **User-global** (`~/.wholework/adapters/`) — applies across all your projects
3. **Bundled** (built into Wholework) — default fallback

### When to Use an adapter

Use adapters when you want to replace or supplement a verify command handler. For example, to add a custom `api_health_check` verify command type for your project:

1. Create `.wholework/adapters/verify-api_health_check.md`
2. Implement the check logic in that file

For a complete guide to writing adapters, see [docs/adapter-guide.md](../adapter-guide.md).
