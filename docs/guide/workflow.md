---
type: project
---

# 🔄 Workflow Guide

This guide explains each Wholework command from a user perspective: what it does, when to use it, and how phases connect.

For internal phase definitions and label transitions, see [docs/workflow.md](../workflow.md).

## The Wholework Workflow

```
Issue → /triage → /issue → /spec → /code → /review → /merge → /verify
```

You can run each command individually or use `/auto` to chain them end-to-end.

## Commands

### `/wholework:triage`

Assigns Type, Priority, and Size labels to an Issue.

```
/wholework:triage 42
```

Use when you want to normalize an existing issue before working on it, or when running `/wholework:triage --backlog` to process a queue of untriaged issues.

### `/wholework:issue`

Refines an Issue's requirements. Adds acceptance criteria, resolves ambiguities, and formats the body consistently.

```
/wholework:issue 42
```

Use when requirements are vague or incomplete. Output is a well-formed Issue body ready for spec writing.

### `/wholework:spec`

Creates an implementation plan at `docs/spec/issue-N-short-title.md`. Adds the `phase/ready` label when complete.

```
/wholework:spec 42
```

Use after `/issue` when the issue is ready to be designed. The Spec is the input to `/code`.

### `/wholework:code`

Implements the Spec. For S/XS issues, commits directly to `main`. For M/L issues, creates a branch and PR.

```
/wholework:code 42
```

Use when the Spec is ready (`phase/ready` label is set).

### `/wholework:review`

Reviews the PR created by `/code`. Posts a review comment and approves or requests changes.

```
/wholework:review 42
```

Use after `/code` creates a PR. `/review` checks Spec compliance, logic errors, and edge cases.

### `/wholework:merge`

Merges the reviewed PR and deletes the branch.

```
/wholework:merge 42
```

Use after the PR is approved and CI passes.

### `/wholework:verify`

Runs acceptance testing against the merged code. Checks off passing conditions and closes the Issue on full pass; reopens it on failure.

```
/wholework:verify 42
```

Use after merge to confirm the implementation matches all acceptance criteria.

### `/wholework:auto`

Chains all phases automatically. The most common entry point for routine tasks.

```
/wholework:auto 42
```

`/auto` picks up wherever the Issue is in the workflow based on its `phase/*` label. You can interrupt and resume at any phase.

## Size-Based Routing

Wholework routes work differently based on Issue size:

| Size | Workflow | PR created |
|------|----------|-----------|
| XS, S | Patch route — commits directly to `main` | No |
| M, L | PR route — creates a branch and Pull Request | Yes |
| XL | Split into sub-issues first | — |

Size is set during `/triage` or manually via the `size/*` label. You can override the route with `--patch` or `--pr` flags.

## Running Phases Individually

You do not have to use `/auto`. Run any phase standalone when you want to review or adjust the output before continuing:

```
/wholework:spec 42        # Review spec before implementation
/wholework:code 42        # Implement after approving spec
/wholework:review 42      # Review PR before merging
```

## Resuming a Workflow

`/auto` checks the current `phase/*` label and resumes from the right step. If `/code` is complete but `/review` has not run, `/auto` starts at review.
