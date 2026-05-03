---
type: project
ssot_for:
  - user-onboarding-flow
---

English | [日本語](../ja/guide/quick-start.md)

# 🚀 Quick Start

Walk through `/issue` → `/code` → `/verify` on a sample Issue in about 5 minutes.

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

We need a simple shell script to verify the project setup.

## Purpose

Add `scripts/hello.sh` that prints "Hello, Wholework!" when run.

## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] <!-- verify: file_exists "scripts/hello.sh" --> `scripts/hello.sh` exists
- [ ] <!-- verify: command "bash scripts/hello.sh | grep -qF 'Hello, Wholework!'" --> Running `bash scripts/hello.sh` outputs `Hello, Wholework!`
```

Note the Issue number (e.g., `#42`) — you will use it in the next steps.

## Step 3 — Run `/issue`

In Claude Code, run:

```
/issue 42
```

Replace `42` with your actual Issue number.

`/issue` triages the Issue: it assigns a Size label (XS for this sample), sets Type to Feature, and adds the `phase/ready` label. You can observe the triage result in the Issue metadata on GitHub.

## Step 4 — Run `/code`

```
/code 42
```

`/code` reads the Issue, implements `scripts/hello.sh`, and commits directly to main (this is the XS patch route — no spec phase or pull request). You can watch the commit appear in your repository.

> **Note on XS patch route**: For XS Issues, Wholework skips the `/spec` phase and commits directly. A retrospective spec file (`docs/spec/issue-N-*.md`) is auto-generated for use by the `/verify` phase.

## Step 5 — Run `/verify`

```
/verify 42
```

`/verify` checks the acceptance criteria defined in the Issue: it confirms `scripts/hello.sh` exists and outputs the expected string, then closes the Issue and checks the checkboxes.

## Step 6 — Check the Results

When `/verify` finishes, check the following:

- The Issue should be **closed** on GitHub
- `scripts/hello.sh` should exist in your repository
- The Issue's acceptance criteria checkboxes should be checked

If anything looks wrong, see [Troubleshooting](troubleshooting.md).

## Step 7 — Try the Full Automated Workflow

Ready for more? Create a more complex Issue (Size M or L) and run `/auto` — Wholework will route it through a full spec → code → review → merge → verify cycle automatically.

## 🧭 Next Steps

You have completed the basics. Here are three directions to explore next:

- **Set up Steering Documents with `/doc init`** — Steering Documents (`docs/product.md`, `docs/tech.md`, `docs/structure.md`) give Wholework project-specific context. Skills like `/spec` and `/code` read them automatically. Running `/doc init` creates an initial set tailored to your codebase, which meaningfully improves the quality of generated specs and implementations.

- **Customize Wholework for your project** — The `.wholework.yml` file controls review tool integrations, spec paths, and optional features. The `.wholework/domains/` directory lets you add project-specific instructions to each skill phase. See [Customization](customization.md) for details.

- **Explore ongoing operation commands** — Once you have a backlog of Issues, `/triage --backlog` assigns sizes and types in bulk. `/audit` detects drift between your documentation and code. These commands help maintain project health as the backlog grows.
