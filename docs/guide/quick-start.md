---
type: project
ssot_for:
  - user-onboarding-flow
---

# 🚀 Quick Start

Get from zero to your first `/auto` execution in 10–15 minutes.

## Prerequisites

- [Claude Code](https://claude.ai/code) installed and authenticated
- A GitHub repository with Issues enabled
- `gh` CLI installed and authenticated (`gh auth login`)

## 1. Install Wholework

Run the following two commands inside Claude Code:

```
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

Skills are now available as `wholework:<skill-name>` (e.g., `/wholework:issue`, `/wholework:auto`).

## 2. Create a Sample Issue

Create a small GitHub Issue to try the workflow. Here is a copy-paste ready example:

**Title:**
```
Add greeting endpoint
```

**Body:**
```markdown
## Background

The API currently has no greeting endpoint.

## Goal

Add a `GET /hello` endpoint that returns `{ "message": "Hello, world!" }`.

## Acceptance Criteria

- [ ] `GET /hello` returns HTTP 200
- [ ] Response body is `{ "message": "Hello, world!" }`
```

Create the issue with:
```bash
gh issue create --title "Add greeting endpoint" --body "$(cat <<'EOF'
## Background

The API currently has no greeting endpoint.

## Goal

Add a `GET /hello` endpoint that returns `{ "message": "Hello, world!" }`.

## Acceptance Criteria

- [ ] `GET /hello` returns HTTP 200
- [ ] Response body is `{ "message": "Hello, world!" }`
EOF
)"
```

Note the issue number printed after creation (e.g., `#1`).

## 3. Run `/auto`

Inside Claude Code, run:

```
/wholework:auto 1
```

(Replace `1` with your issue number.)

`/auto` runs the full workflow without intervention:

1. **triage** — assigns Type, Size, and Priority labels
2. **issue** — refines requirements and adds acceptance criteria
3. **spec** — creates an implementation plan at `docs/spec/`
4. **code** — implements, tests, and creates a PR
5. **review** — reviews the PR
6. **merge** — merges the PR
7. **verify** — checks the merged code against acceptance criteria

You can follow along in the terminal. Each phase prints a banner like `/code #1`.

## 4. Read the Log

Key lines to look for in the terminal output:

| Pattern | Meaning |
|---------|---------|
| `/spec #1` | Spec phase started |
| `/code #1` | Implementation started |
| `PR created: https://github.com/...` | Pull Request is open |
| `/verify #1` | Acceptance testing started |
| `All conditions PASS` | Issue closed successfully |

If a phase fails, the output will explain why and suggest next steps.

## 5. Verify the Result

After `/auto` completes successfully:

- The GitHub Issue should be closed with all checkboxes checked
- A merged PR should exist in your repository
- `docs/spec/issue-1-*.md` contains the implementation record including retrospectives from each phase

## 🧭 Next Steps

You have completed the core workflow. Here are recommended next steps to get more out of Wholework:

- **Set up Steering Documents** — Run `/doc init` (or `/wholework:doc init`) to create `docs/product.md`, `docs/tech.md`, and `docs/structure.md`. These documents guide every phase and significantly improve skill output quality. Without them, skills use defaults; with them, outputs align to your project's conventions and architecture decisions.

- **Customize behavior** — Read [customization.md](customization.md) to learn how to configure `.wholework.yml` (e.g., enable opportunistic verify, set a production URL), add project-specific domain files in `.wholework/domains/`, and create adapters for your tools.

- **Run ongoing workflow commands** — Use `/wholework:audit` to detect documentation drift, and `/wholework:triage --backlog` to normalize and prioritize a batch of existing issues.
