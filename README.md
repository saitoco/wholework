# Wholework Skills – spec-driven skills for autonomous work on GitHub

Spec-driven skills for autonomous work on GitHub — a public repository for sharing Skills, modules, and workflow automation built on the Claude Agent SDK.

## Install

```sh
git clone https://github.com/saitoco/wholework.git
cd wholework
./install.sh
```

This creates symlinks in your `~/.claude/` directory:

| Repository directory | Install destination |
|---|---|
| `skills/` | `~/.claude/skills/wholework/` |
| `modules/` | `~/.claude/skills/wholework/modules/` |
| `agents/` | `~/.claude/agents/wholework/` |
| `scripts/` | `~/.claude/skills/wholework/scripts/` |

To uninstall:

```sh
./install.sh --uninstall
```

## Repository structure

See [`docs/structure.md`](docs/structure.md) for the full directory layout and installation conventions.

## License

Apache License 2.0. See [LICENSE](LICENSE).
