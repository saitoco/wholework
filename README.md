English | [日本語](README.ja.md)

# Wholework

GitHub issue-driven Claude Code skills for agentic work.

A workflow harness for the Claude Code agent — turns your issues into shipped, verified work.

## 🌐 Why Wholework

1. **Issue-to-spec design** — Issues define *what* and *when it's done*; specs break down *how* to get there. Verifiable acceptance criteria come first — and `/verify` checks them automatically after merge.
2. **Full-phase workflow with size-based routing** — `/issue → /spec → /code → /review → /merge → /verify` covers the entire lifecycle from requirements to post-merge verification.
3. **Agentic execution** — `/auto` turns Claude Code into a long-horizon coding agent — issues are broken down into executable tasks and driven through every phase unattended. Hand off a single issue or your whole backlog, for as long as the work takes.
4. **Works with what you have** — Runs on your existing GitHub repo and standard GitHub Flow, and you can step in or hand off at any phase.
5. **Issue-driven, not code-specific** — Applies anywhere issues drive the work: websites, documentation, IaC, research, OSS operations.

## 📋 Requirements

- **Claude Code** — latest stable version
- **[gh](https://cli.github.com/)** — GitHub CLI, used for Issue/PR operations
- **git** — version control
- **[jq](https://jqlang.github.io/jq/)** — JSON processor, used internally by verify commands

## 📦 Install

```sh
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

Skills are available as `wholework:<skill-name>` (e.g., `/wholework:review`, `/wholework:code`).

For development setup, see [docs/structure.md](docs/structure.md#install).

## 🚀 Quick Start

New to Wholework? The [Quick Start guide](docs/guide/quick-start.md) walks you through installation and your first manual `/issue` → `/code` → `/verify` cycle in about 5 minutes.

For a broader overview of every topic, see the [User Guide index](docs/guide/index.md).

## 🔄 Workflow Overview

Wholework covers the full development lifecycle through six composable skills:

`/issue` → `/spec` → `/code` → `/review` → `/merge` → `/verify`

Run the full cycle with a single command: `/auto N`. For a deeper look at each phase and size-based routing, see the [Workflow Overview](docs/guide/workflow.md).

## 🛠️ Customization

Wholework adapts to your project through `.wholework.yml` (feature flags and paths), `.wholework/domains/` (per-skill instructions), and adapters (tool integrations). See the [Customization guide](docs/guide/customization.md) for details.

## 🔒 Security

Wholework skills perform `gh`, `git`, and file-write operations on your repository. `/auto` uses `--dangerously-skip-permissions` by default, or `--permission-mode auto` when `permission-mode: auto` is set in `.wholework.yml`. See [SECURITY.md](SECURITY.md) for a full description of side effects, required permissions, and permission mode options.

## 💬 Support

- **Bug reports & feature requests** — open an issue via [GitHub Issues](https://github.com/saitoco/wholework/issues/new/choose). Templates are provided for bug reports and feature requests.
- **Security concerns** — see [SECURITY.md](SECURITY.md) for the full description of side effects, required permissions, and permission-bypass behavior.

## 🌱 Contributing

Contributions require a DCO sign-off on every commit. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## ⚖️ License

Apache License 2.0. See [LICENSE](LICENSE).
