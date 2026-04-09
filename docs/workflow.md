---
type: project
ssot_for:
  - workflow-phases
  - label-transitions
---

# Development Workflow

## Overview

Overview of the development workflow using Claude Code Skills. See [docs/product.md](product.md) for flow diagrams.

**Full workflow**: `/issue` → `/auto` (spec auto-execution) → code → review → merge → verify (or `/spec` → `/code` → `/review` → `/merge` → `/verify`)

**Lightweight workflow**: `/code --patch` — Directly commit Size XS/S fixes to main. Also selectable after `/spec` determines Size XS/S. Details: [`skills/code/SKILL.md`](../skills/code/SKILL.md)

**Size→workflow routing**: The Issue's Size property determines the workflow path. See [`modules/size-workflow-table.md`](../modules/size-workflow-table.md) for the decision table (Size determination criteria 2-axis + Size→workflow mapping).

Main branch protection rules: see [CLAUDE.md](../CLAUDE.md).

## Phase Details

For internal skill behavior, see `skills/<name>/SKILL.md`. This section covers only the role and positioning of each phase.

### 0. Foundation Management Phase — `/doc`, `/audit`

Maintains project foundation information in `docs/`. Each document defines its type via the YAML frontmatter `type` field (`type: steering` for Steering Documents, `type: project` for operational documents). `/doc sync` identifies `type: steering` and `type: project` documents and normalizes all of them. `workflow.md` (`type: project`) is included. Each skill conditionally references these documents and skips if not present (backward compatibility). `/doc sync --deep` runs an extended reverse-generation option that includes codebase analysis (entry points, dependency graphs, test files, comments/docstrings) plus integrated scanning of existing .md files (4-pattern classification, absorption target determination). `/doc init --deep` and `/doc {doc} --deep` perform equivalent inline analysis on new file creation, automatically generating drafts without a question flow. `/doc translate {lang}` generates translations of English documentation (README.md, Steering Documents, Project Documents) in the specified language (BCP 47 / ISO 639-1 language code, e.g., `ja`, `ko`, `zh-cn`) under `docs/{lang}/` and `README.{lang}.md`, then commits and pushes automatically. Details: [`skills/doc/SKILL.md`](../skills/doc/SKILL.md)

`/audit drift` uses AI to detect semantic drift between Steering Documents + Project Documents and codebase implementation, automatically generating Issues for code-side fixes. Works complementarily with `/doc sync` (document-side fixes). `/audit fragility` detects structurally fragile areas in project context (missing tests for Core modules, Architecture Decision violations, etc.) and generates risk improvement Issues. `/audit` (no arguments) runs both drift + fragility perspectives together. Details: [`skills/audit/SKILL.md`](../skills/audit/SKILL.md)

### 1. Issue Creation Phase — `/issue`

Clarifies Issue requirements. Two modes: new creation (`/issue "title"`) and existing refinement (`/issue 123`). Performs ambiguity detection, acceptance condition classification, acceptance check assignment, and sub-issue splitting. When refining an existing Issue without a `triaged` label, automatically chains triage execution — a single `/issue` completes both triage + issue creation for standalone Issues. Details: [`skills/issue/SKILL.md`](../skills/issue/SKILL.md)

**Responsibility boundary between `/issue` and `/spec`**: [docs/product.md — Responsibility Boundary Table](product.md#spec-design-boundary)

### 2. Specification Phase — `/spec`

Investigates the codebase from Issue requirements and creates a Spec (`docs/spec/issue-N-short-title.md`). On design completion, performs Size→workflow routing and presents the next action based on Size (`/code --patch` / `/code`). `--light` for lightweight design (omits ambiguity resolution, uncertainty detection, self-review, etc.), `--full` for full design. When the option is omitted, auto-determines from the Size label (M → `--light`, L/XL → `--full`). Details: [`skills/spec/SKILL.md`](../skills/spec/SKILL.md)

### 3. Implementation Phase — `/code`, `/auto`

Three options for implementation:
- **GitHub Copilot**: Select "Assign to Copilot" in the Issue
- **Claude Code**: `/code 123` for local implementation (Size-based routing: XS/S→patch=direct commit to main, M/L→pr=branch+PR), `/auto 123 [--patch|--pr] [--review=full|--review=light]` for end-to-end execution with Size-based routing (if `phase/ready` is absent, auto-executes spec first. If no `phase/*` label, starts from issue refinement. patch XS/S: spec(if needed)→code→verify, pr: spec(if needed)→code→review(M→--light,L→--full)→merge→verify, XL: reads sub-issue dependency graph for parallel execution, auto-executes spec for each sub-issue). `/auto --batch N` bulk-processes N XS/S Issues from the backlog in newest-first order
- **Manual**: User implements manually

`/code` supports explicit route specification with `--patch`/`--pr` flags. The patch route (XS/S) directly commits and pushes to main without creating a PR.

**Release branch workflow (`--base` option)**: Use the `--base` option when consolidating multiple Issue changes into a release branch (e.g., `release/v2.0`) before releasing.

```
# Create release branch
git checkout -b release/v2.0 main
git push origin release/v2.0

# Implement each Issue on release/v2.0 base
/code 123 --base release/v2.0
/auto 124 --base release/v2.0

# Final merge: release/v2.0 → main is handled with the standard /code → /review → /merge flow
```

When `--base` specifies a branch other than main, `closes #N` does not auto-close Issues (GitHub only works when merging to the default branch). Close Issues manually at the final merge of `release/v2.0` into main, or run `gh issue close` manually.

**Spec reference**: During implementation, reference the Spec saved at `docs/spec/issue-N-short-title.md`. The Spec contains target files, implementation steps, and verification methods. If no Spec exists, read requirements from the Issue body.

Details: [`skills/code/SKILL.md`](../skills/code/SKILL.md), [`skills/auto/SKILL.md`](../skills/auto/SKILL.md)

### 4. Review Phase — `/review`

Integrates PR acceptance criteria verification, multi-perspective code review, and issue resolution. MUST findings are auto-fixed before proceeding to `/merge`. Details: [`skills/review/SKILL.md`](../skills/review/SKILL.md)

**Review mode**: Auto-determined based on Size (Project field preferred → label fallback). Can also be explicitly specified with `--light`/`--full`.

| Size | Review mode | Behavior |
|------|-------------|----------|
| XS, S | skip (early exit) | Exits with "review not required" message (patch route) |
| M | light | Runs Step 9 as lightweight integrated review (1 agent) |
| L, XL | full | Runs all steps |

**External review tool integration**: Create `.wholework.yml` at the project root and set values to enable (all disabled by default):

```yaml
# .wholework.yml
copilot-review: true        # Enable GitHub Copilot review (wait and handle findings in Step 6)
claude-code-review: true    # Enable official Claude Code Review (wait and handle findings in Step 6)
review-bug: false           # Disable review-bug agent in Step 9 (only review-spec runs)
```

If `.wholework.yml` does not exist, all settings are treated as default (disabled).

**`--review-only` option**: `/review {PR number} --review-only` stops after review posting (Step 10) and skips fixes (Steps 11–13). Fixes are delegated to the user or Copilot. The `phase/review` status label remains unchanged.

### 5. Merge Phase — `/merge`

Executes squash merge and deletes the remote branch. Attempts automatic conflict resolution if conflicts exist. Details: [`skills/merge/SKILL.md`](../skills/merge/SKILL.md)

### 6. Acceptance Test Phase — `/verify`

Automatically verifies post-merge acceptance conditions. All conditions PASS completes the flow; on FAIL, `gh issue reopen` returns to the fix cycle. Performs a cross-phase retrospective review of all phases, always creates Issues for code improvements, and creates Issues for skill infrastructure (Wholework) improvements only when `.wholework.yml` has `skill-proposals: true`. Details: [`skills/verify/SKILL.md`](../skills/verify/SKILL.md)

## Skill List

See [README.md](../README.md) for the skill list.

## Agent Infrastructure

See [docs/structure.md](structure.md) for agent infrastructure (agents/, modules/ list and placement).

## Progress Management (Label-Based)

Uses `phase/*` labels to visualize Issue progress. Each skill automatically manages labels as the workflow advances.

Setup: Create labels with `scripts/setup-labels.sh`.

### Label Transition Map

| Label | Meaning | Assigned by | Removed by |
|-------|---------|-------------|------------|
| `phase/issue` | Issue creation phase | `/issue` | `/spec` |
| `phase/spec` | Specification phase | `/spec` (on start) | `/spec` (after spec push) |
| `phase/ready` | Design complete, awaiting implementation | `/spec` (after design push) | `/code` |
| `phase/code` | Implementation phase | `/code` | `/review` |
| `phase/review` | Review phase | `/review` | `/merge` |
| `phase/verify` | Acceptance test phase | `/merge` | `/verify` |
| `phase/done` | Complete | `/verify` (no post-merge conditions) | — |
| (no label) | Backlog / not started | — | `/verify` (on FAIL) |

### XL Parent Issue Phase Management

XL (sub-issue split) parent Issues have their phase automatically aggregated based on child Issue progress.

| Child state | Parent phase | Notes |
|-------------|-------------|-------|
| 1+ children at `phase/code` or later | `phase/code` | Implementation in progress |
| All children at `phase/verify` or later | `phase/verify` | Awaiting verification |
| All children `phase/done` + no parent conditions | `phase/done` + close | Auto-close |
| All children `phase/done` + parent conditions exist | `phase/verify` | Final confirmation by `/verify` before close |

Aggregation updates run at each level completion in `/auto` XL orchestration.

### Standard Flow via `closes #N`

Adding `closes #N` to PR body auto-closes the Issue on merge (GitHub standard feature).

```
/code: Add `closes #N` to PR body
  ↓
/merge: Merge → Issue auto-closes
  ↓
/verify: Verify closed Issue
  - PASS → Complete (remove phase/verify label)
  - FAIL → gh issue reopen + remove all phase/* → return to fix cycle
```

### Triage-Related Labels

| Label | Meaning | Assigned by |
|-------|---------|-------------|
| `triaged` | Triaged | `/triage` |
| `type/bug` | Type: bug | `/triage` |
| `type/feature` | Type: feature | `/triage` |
| `type/task` | Type: task | `/triage` |

`/triage` is managed independently from `phase/*` (a utility skill outside the workflow). `/triage --backlog` (no perspective) runs bulk unprocessed triage + all 4 deep-analysis perspectives together. When a perspective is specified (e.g., `--backlog value`), only that perspective's analysis runs without assigning `triaged`. An approval flow is displayed before each perspective is applied. Details: [`skills/triage/SKILL.md`](../skills/triage/SKILL.md)

### Audit-Related Labels

| Label | Meaning | Assigned by |
|-------|---------|-------------|
| `audit/drift` | Fix Issue for drift detected by `/audit drift` | `/audit` |
| `audit/fragility` | Improvement Issue for structural fragility detected by `/audit fragility` | `/audit` |

### Projects Integration

`.github/workflows/kanban-automation.yml` implements auto Kanban column movement by `phase/*` labels. `phase/issue`, `phase/spec` → Plan, `phase/ready` → Ready, `phase/code` → Implementation. Review/Verification/Done use Projects built-in automations.

## Documentation Sync Rules

Document structure:
- `docs/workflow.md` — Development workflow overview (phase details, label transitions, progress management)
- `docs/product.md` — Project vision, flow diagrams, Terms (terminology)
- `docs/tech.md` — Tech stack, coding conventions, Forbidden Expressions
- `docs/structure.md` — Directory structure, agent infrastructure

**Rule**: When making changes that affect the workflow — such as adding, modifying, or removing skills — also update `docs/workflow.md` and `README.md`.

Reason: To keep implementation and documentation always in sync and maintain an accurate overall view of the workflow. The 2 files target different audiences (human / Claude Code) so both must be kept in sync.

**Key Files table sync rule**: When the role or description of files listed in the Key Files table in `docs/structure.md` changes, or when files are added, removed, or renamed, also update the Key Files table in `docs/structure.md`.

## Related Documents

- [CLAUDE.md](../CLAUDE.md) - Global guidelines
- [README.md](../README.md) - Setup and Skill list
- [docs/product.md](product.md) - Project vision, flow diagrams
- [docs/tech.md](tech.md) - Tech stack, coding conventions
- [docs/structure.md](structure.md) - Directory structure, agent infrastructure
