---
type: steering
ssot_for:
  - tech-stack
  - forbidden-expressions
  - gotchas
  - model-effort-matrix
---

English | [日本語](ja/tech.md)

# Tech

## Language and Runtime

- **Bash/Shell Script**: Wrapper scripts (`scripts/run-*.sh`), utility scripts
- **Markdown**: Skill definitions (`SKILL.md`), agent definitions (`agents/*.md`), shared modules (`modules/*.md`), documentation
- **Python**: Validation scripts (`scripts/validate-skill-syntax.py`)
- **GitHub Actions**: CI/CD workflows (`.github/workflows/`)

## Key Dependencies

| Package | Role |
|---------|------|
| Claude Code CLI (`claude`) | Skill execution engine, sub-agent spawning |
| GitHub CLI (`gh`) | Issue/PR operations, GitHub API access |
| GitHub Copilot | Code review (Step 7), automatic implementation from Issues |
| bats (Bash Automated Testing System) | Shell script testing |

## Architecture Decisions

- **Skills-based workflow**: Each development phase (issue/spec/code/review/merge/verify) is implemented as an independent Claude Code Skill. Processing steps are described in SKILL.md, and the LLM executes them step by step.
- **Plugin directory distribution**: Distributed as a local Claude Code plugin using `--plugin-dir`. Claude Code sets `${CLAUDE_PLUGIN_ROOT}` to the plugin directory at runtime, which skills and modules use to reference scripts and modules. Public distribution is via a Claude Code marketplace (`.claude-plugin/marketplace.json`) so users can install with `/plugin marketplace add saitoco/wholework` + `/plugin install wholework@saitoco-wholework`.
- **fork context vs main context**: Context isolation level is set per skill. Fork justification: "independence/safety" (since 1M context GA, cost/capacity motivation has largely diminished). Fork decision per skill (exhaustive):

  | Skill | Fork needed | Reason |
  |-------|-------------|--------|
  | triage | No (removed) | No need to avoid prior-phase bias; independence not required |
  | issue | Yes | L/XL parallel investigation requires independence; sub-agents run in isolated context |
  | spec | Yes | Reads Issue and investigates codebase independently; not influenced by prior conversation |
  | code | Yes | Reads Spec and executes independently; not influenced by pre-implementation context |
  | review | Yes | Reviews code from a clean perspective without inheriting implementation phase bias |
  | merge | Yes | Decision completes with Spec + PR metadata; does not carry over review context |
  | verify | Yes | Verifies post-merge state independently; must not be influenced by prior phase decisions |

- **`/auto` skill**: Orchestrator that chains spec→code→review→merge→verify sequentially via `run-*.sh`. Each phase runs as an independent process with `claude -p --dangerously-skip-permissions`, guaranteeing fresh context and full permission bypass. Additional capabilities: auto-starts from issue triage/refinement when no `phase/*` label is set; auto-runs `/spec` when `phase/ready` is absent; `--batch N` processes N XS/S Issues from the backlog; XL Issues read the sub-issue dependency graph (`blockedBy`) and execute independent sub-issues in parallel (worktree isolation) before sequencing dependent ones; `--base {branch}` targets a release branch instead of main.
  - **Two-tier orchestration**: `/auto` itself (parent orchestrator) runs in the user's Claude Code session and makes adaptive decisions using LLM reasoning (label state evaluation, Size-based routing, sub-issue dependency analysis). For XL Issues, `run-auto-sub.sh` (child orchestrator) runs each sub-issue's full phase sequence. `run-auto-sub.sh` is a pure bash script — it does not invoke `claude -p` — using deterministic if/case routing based on Size. This is a deliberate design choice, not a technical constraint: current phase routing is deterministic and each phase is self-contained via `run-*.sh`, so LLM reasoning at the child orchestrator level adds cost without benefit. If adaptive recovery were needed (e.g., re-running spec after code failure, adjusting strategy based on review results), upgrading `run-auto-sub.sh` to a `claude -p` orchestrator would be the path forward.
- **Sub-agent splitting**: Used in two skills:
  - `/issue` (L/XL): Parallel investigation via three independent sub-agents (`issue-scope`, `issue-risk`, `issue-precedent`) to analyze change scope, risk, and precedents simultaneously.
  - `/review`: Splits into two groups — Spec compliance review (`review-spec`) and bug detection (`review-bug`) — with two-stage verification (detection→verification sub-agents) to eliminate false positives.
- **Shared module pattern**: Common processing across multiple skills is extracted to `modules/*.md`, referenced using the "Read and follow" pattern.
- **Spec-first (disposable)**: Spec is not maintained as an artifact after task completion. Spec-anchored and Spec-as-source approaches are not adopted. Reasons: (1) LLM non-determinism means the same spec does not guarantee the same code regeneration; (2) spec maintenance cost adds overhead to code maintenance cost.
- **Progressive disclosure (Core/Domain separation)**: SKILL.md body contains only generic logic independent of project type or tool. Logic specific to particular tools (Figma, Copilot, etc.) or project types (skill development, IaC, etc.) is extracted to auxiliary files (`skills/{name}/xxx-phase.md`), read only when applicable. Decision criterion: "Is this logic needed in projects that don't use this tool/project type?" — If No, extract it.
  - **Extraction patterns (standard) (exhaustive)**:

    | Pattern | Condition | Example |
    |---------|-----------|---------|
    | Marker detection | YAML key in `.wholework.yml` | `review/external-review-phase.md` (read when `copilot-review: true`, `claude-code-review: true`, or `coderabbit-review: true`) |
    | File existence | Specific file presence | `review/skill-dev-recheck.md` (read when `scripts/validate-skill-syntax.py` exists) |

- **Distributable-first improvement principle**: Improvements identified through retrospectives must be reflected in distributable components (Skills, Agents, Modules, Scripts). CLAUDE.md, Steering Documents, and Project Documents are user-repository-specific artifacts that are not distributed as part of the Wholework plugin — improvements made only to these documents do not reach other Wholework users. When a retrospective identifies an improvement, the implementation target should be the distributable layer; updating only non-distributable artifacts is insufficient.
- **Effort optimization strategy (3 axes)**: Three axes for controlling execution cost and quality in `claude -p` invocations. CLI support status and Wholework adoption policy per axis:
  - **Axis 1 — Model selection** (`--model`): Already implemented. Sonnet is the default; `run-spec.sh --opus` switches to Opus for L-size specs. Reviewed and confirmed.
  - **Axis 2 — Adaptive Thinking** (`--effort`): `claude -p` supports `low/medium/high/max` levels (confirmed via `claude --help`). Implemented in `run-*.sh` with phase-specific effort levels (see matrix below). Combining medium effort with an Opus advisor achieves quality comparable to default-effort Sonnet at lower cost (per Anthropic benchmarks).
  - **Axis 3 — Advisor strategy** (`advisor_20260301`): Anthropic API beta feature (`advisor-tool-2026-03-01` header required). Enabled via the `--betas` flag — API key users only; not available with OAuth/subscription auth (the `run-*.sh` default). Performance gains: Sonnet + Opus advisor achieves SWE-bench +2.7 pp and cost −11.9% vs. Sonnet alone; Haiku + Opus advisor achieves BrowseComp 41.2% (vs. 19.7% solo) and cost −85% vs. Sonnet. Implementation in `run-*.sh` is a follow-up Issue.

  **Phase-specific model and effort matrix** (`ssot_for: model-effort-matrix`):

  | Component | Phase | Model | Effort | Rationale |
  |-----------|-------|-------|--------|-----------|
  | run-spec.sh | spec | Sonnet (Opus via `--opus` for L) | max | Design quality is critical; spec errors propagate to all subsequent phases. `/auto` passes `--opus` for L-size only (XL is split before spec) |
  | run-code.sh | code | Sonnet | high | Implementation requires thorough reasoning |
  | run-review.sh | review | Sonnet | high | Review orchestration; sub-agents handle deep analysis |
  | run-issue.sh | issue | Sonnet | high | L/XL scope analysis and sub-issue splitting require thorough orchestration |
  | run-verify.sh | verify | Sonnet | medium | Structured acceptance testing; moderate complexity |
  | run-merge.sh | merge | Sonnet | low | Mechanical merge operation; minimal reasoning needed |
  | review-bug | review | Opus | — | Bug detection requires highest accuracy (sub-agent, effort inherited from parent) |
  | review-spec | review | Opus | — | Spec deviation requires high accuracy (sub-agent, effort inherited from parent) |
  | review-light | review | Sonnet | — | Lightweight integrated review (sub-agent, effort inherited from parent) |
  | issue-scope | issue (L/XL only) | Opus | — | Called by `/issue` Step 11a for L/XL parallel investigation. Scope identification accuracy is critical for sub-issue boundary decisions |
  | issue-risk | issue (L/XL only) | Opus | — | Called by `/issue` Step 11a for L/XL parallel investigation. Risk assessment accuracy improves acceptance criteria quality |
  | issue-precedent | issue (L/XL only) | Opus | — | Called by `/issue` Step 11a for L/XL parallel investigation. Precedent extraction improves acceptance criteria quality |
  | triage (skill) | triage | Sonnet | — | Metadata assignment; Sonnet sufficient. Invoked inline (no `run-*.sh` wrapper) — including when `/auto` chains triage for unlabeled issues — so effort is not set |

  SSoT note: This matrix is the single source of truth for all model and effort settings. When changing model/effort in run-*.sh, agents, or skills, update this table first.

## Testing Strategy

| Tool | Purpose | When |
|------|---------|------|
| **bats** (Bash Automated Testing System) | Unit tests for shell scripts | Pre-merge (via `command` verify command) |
| **validate-skill-syntax.py** | SKILL.md syntax validation (half-width `!` detection, frontmatter validation) | Pre-merge |
| **Verify commands** (`<!-- verify: ... -->`) | Mechanical verification of acceptance criteria (file existence, text content, command execution) | At `/verify` skill execution |

## Forbidden Expressions

| Expression | Reason | Alternative |
|------------|--------|-------------|
| Half-width `!` (in SKILL.md body, outside code fences and inline code) | Claude Code's Bash permission checker misdetects it as zsh history expansion, causing errors at skill execution | Full-width "！" or rephrased expression |
| Acceptance check | Term redesign (changed to "verify command") | "verify command" |

## Terminology Migration Scope Rule

When creating an Issue that adds deprecated terms to Terms 'Formerly called' (gradual terminology migration), explicitly state whether replacing deprecated terms within the same file is included in scope.

### Scope Declaration Template

Include one of the following in the "Scope" or "Acceptance Criteria" section of the Issue body:

```
[Same-file deprecated term replacement] included / not included (handled in follow-up Issue #N)
```

### Reason

In gradual migration, there is a period where deprecated terms remain in the same file after adding them to Forbidden Expressions. During this period, reviewers (Copilot, etc.) may flag the contradiction between Forbidden Expressions and the body text, conflicting with the gradual migration policy. Explicit scope declaration prevents false review comments.

### Applicability

- Applies to all Issues that include adding deprecated terms to Forbidden Expressions
- If "not included," handle deprecated term replacement in a follow-up Issue and reference its Issue number

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WHOLEWORK_CI_TIMEOUT_SEC` | `1200` | Maximum wait time in seconds for `wait-ci-checks.sh`. Set to a lower value (e.g., `60`) to test timeout behavior. |

## Gotchas

### `.claude/settings.json` is not hot-reloaded

`.claude/settings.json` is cached at session start and **is not reloaded during the session**. Changes to `permissions.allow` patterns (or any other settings) take effect only after restarting the Claude Code session.

**Implication**: After modifying `settings.json`, always restart the session before testing whether the new permission patterns work correctly.

**False-negative risk with in-session probes**: Verifying a new `permissions.allow` pattern by probing within the same session where the old config was loaded can yield false negatives. The probe may succeed (or fail) based on the cached config, not the updated one — masking whether the new pattern actually works. Always restart the session before running permission verification probes.
