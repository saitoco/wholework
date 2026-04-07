# Wholework

Spec-first Claude Code skills for autonomous GitHub workflows.

## Why Wholework

1. **Issue-to-spec design** — Issues define *what* and *when it's done*; specs break down *how* to get there. Verifiable acceptance criteria come first — and where possible, are checked automatically.
2. **Full-phase workflow with size-based routing** — `/issue → /spec → /code → /review → /merge → /verify` covers the entire lifecycle from requirements to post-merge verification.
3. **Autonomous execution** — `/auto` chains phases based on issue size and runs the full workflow without human intervention when you want it to.
4. **Works with what you have** — Runs on GitHub and Claude Code. Follows standard GitHub Flow; you can step in at any phase.
5. **Beyond software development** — Applies to any issue-driven project: websites, documentation, IaC, research, OSS operations.

## Install

```sh
git clone https://github.com/saitoco/wholework.git
```

Then launch Claude Code with the `--plugin-dir` flag pointing to the cloned repository:

```sh
claude --plugin-dir ~/src/wholework
```

Skills are available as `wholework:<skill-name>` (e.g., `/wholework:review`, `/wholework:code`).

To always load wholework as a plugin, add it to your Claude Code settings:

```json
{
  "pluginDirectories": ["~/src/wholework"]
}
```

## Repository structure

See [`docs/structure.md`](docs/structure.md) for the full directory layout and installation conventions.

## License

Apache License 2.0. See [LICENSE](LICENSE).
