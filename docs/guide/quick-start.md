---
type: project
ssot_for:
  - user-onboarding-flow
---

English | [日本語](../ja/guide/quick-start.md)

# 🚀 Quick Start

Get from zero to your first autonomous `/auto` run in 10–15 minutes.

## Prerequisites

- Claude Code installed (desktop app or CLI)
- A GitHub account with a repository you want to use
- `gh` CLI authenticated (`gh auth login`)

## Step 1 — Install Wholework

Open Claude Code and run:

```
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

Verify the installation by typing `/wholework:` — you should see the available skills in the autocomplete list.

Wholework will automatically create the labels it needs on first run — no manual setup required.

## Step 2 — Create a Sample Issue

In your GitHub repository, create an Issue with the following title and body. You can copy and paste these directly.

**Title:**

```
Add a hello world script
```

**Body:**

```markdown
## Background

We need a simple script to verify the project setup.

## Goal

Create a shell script that prints "Hello, Wholework!" when run.

## Acceptance Criteria

- [ ] `scripts/hello.sh` exists
- [ ] Running `bash scripts/hello.sh` outputs `Hello, Wholework!`
```

Note the Issue number (e.g., `#42`) — you will use it in the next step.

## Step 3 — Run `/auto`

In Claude Code, run:

```
/auto 42
```

Replace `42` with your actual Issue number.

Wholework will:

1. Triage and size the Issue (XS or S — small enough for a direct commit)
2. Run `/spec` to create an implementation plan
3. Run `/code` to implement the script and commit to main
4. Run `/verify` to confirm the acceptance criteria are met

You will see phase banners like `/spec #42`, `/code #42`, `/verify #42` as it progresses.

## Step 4 — Check the Results

When `/auto` finishes, check the following:

- The Issue should be **closed** on GitHub
- `scripts/hello.sh` should exist in your repository
- The Issue's acceptance criteria checkboxes should be checked

If anything looks wrong, see [Troubleshooting](troubleshooting.md).

## Step 5 — Try a PR-based Workflow

For larger changes (Size M or L), Wholework creates a pull request instead of committing directly. To try this, create a more complex Issue and run `/auto` again — Wholework will route it through a full spec → code → review → merge → verify cycle.

## 🧭 Next Steps

You have completed the basics. Here are three directions to explore next:

- **Set up Steering Documents with `/doc init`** — Steering Documents (`docs/product.md`, `docs/tech.md`, `docs/structure.md`) give Wholework project-specific context. Skills like `/spec` and `/code` read them automatically. Running `/doc init` creates an initial set tailored to your codebase, which meaningfully improves the quality of generated specs and implementations.

- **Customize Wholework for your project** — The `.wholework.yml` file controls review tool integrations, spec paths, and optional features. The `.wholework/domains/` directory lets you add project-specific instructions to each skill phase. See [Customization](customization.md) for details.

- **Explore ongoing operation commands** — Once you have a backlog of Issues, `/triage --backlog` assigns sizes and types in bulk. `/audit` detects drift between your documentation and code. These commands help maintain project health as the backlog grows.
