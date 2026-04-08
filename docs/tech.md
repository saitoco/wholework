---
type: steering
ssot_for:
  - tech-stack
  - forbidden-expressions
---

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
| GitHub Copilot | Code review (Step 6), automatic implementation from Issues |
| bats (Bash Automated Testing System) | Shell script testing |

## Architecture Decisions

- **Skills-based workflow**: Each development phase (issue/spec/code/review/merge/verify) is implemented as an independent Claude Code Skill. Processing steps are described in SKILL.md, and the LLM executes them step by step.
- **Plugin directory distribution**: Distributed as a local Claude Code plugin using `--plugin-dir`. Claude Code sets `${CLAUDE_PLUGIN_ROOT}` to the plugin directory at runtime, which skills and modules use to reference scripts and modules.
- **fork context vs main context**: Context isolation level is set per skill. Fork justification: "independence/safety" (since 1M context GA, cost/capacity motivation has largely diminished). Fork decision per skill (exhaustive):

  | Skill | Fork needed | Reason |
  |-------|-------------|--------|
  | triage | No (removed) | No need to avoid prior-phase bias; independence not required |
  | code | Yes | Reads Spec and executes independently; not influenced by pre-implementation context |
  | review | Yes | Reviews code from a clean perspective without inheriting implementation phase bias |
  | merge | Yes | Decision completes with Spec + PR metadata; does not carry over review context |
  | verify | Yes | Verifies post-merge state independently; must not be influenced by prior phase decisions |

- **`/auto` skill**: Orchestrator that runs code→review→merge→verify sequentially via `run-*.sh`. Each phase runs as an independent process with `claude -p --dangerously-skip-permissions`, guaranteeing fresh context and full permission bypass.
- **Sub-agent splitting**: `/review` splits into two groups — Spec compliance review (`review-spec`) and bug detection (`review-bug`) — with two-stage verification (detection→verification sub-agents) to eliminate false positives.
- **Shared module pattern**: Common processing across multiple skills is extracted to `modules/*.md`, referenced using the "Read and follow" pattern.
- **Spec-first (disposable)**: Spec is not maintained as an artifact after task completion. Spec-anchored and Spec-as-source approaches are not adopted. Reasons: (1) LLM non-determinism means the same spec does not guarantee the same code regeneration; (2) spec maintenance cost adds overhead to code maintenance cost.
- **Progressive disclosure (Core/Domain separation)**: SKILL.md body contains only generic logic independent of project type or tool. Logic specific to particular tools (Figma, Copilot, etc.) or project types (skill development, IaC, etc.) is extracted to auxiliary files (`skills/{name}/xxx-phase.md`), read only when applicable. Decision criterion: "Is this logic needed in projects that don't use this tool/project type?" — If No, extract it.
  - **Extraction patterns (standard) (exhaustive)**:

    | Pattern | Condition | Example |
    |---------|-----------|---------|
    | Marker detection | YAML key in `.wholework.yml` | `review/external-review-phase.md` (read when `copilot-review: true` or `claude-code-review: true`) |
    | File existence | Specific file presence | `review/skill-dev-recheck.md` (read when `scripts/validate-skill-syntax.py` exists) |

## Testing Strategy

| Tool | Purpose | When |
|------|---------|------|
| **bats** (Bash Automated Testing System) | Unit tests for shell scripts | Pre-merge (via `command` acceptance check) |
| **validate-skill-syntax.py** | SKILL.md syntax validation (half-width `!` detection, frontmatter validation) | Pre-merge |
| **Acceptance checks** (`<!-- verify: ... -->`) | Mechanical verification of acceptance criteria (file existence, text content, command execution) | At `/verify` skill execution |

## Forbidden Expressions

| Expression | Reason | Alternative |
|------------|--------|-------------|
| Half-width `!` (in SKILL.md body, outside code fences and inline code) | Claude Code's Bash permission checker misdetects it as zsh history expansion, causing errors at skill execution | Full-width "！" or rephrased expression |
| 「設計ファイル」 | Term unification (#422 unified to "Spec") | "Spec" |
| 「Issue Spec」 | Term simplification (#588 changed to "Spec") | "Spec" |
| 「検証ヒント」 | Term redesign (#669 changed to "acceptance check") | "acceptance check" |
| 「共有手順書」 | Term redesign (#669 changed to "shared module") | "shared module" |
| 「ディスパッチ」 | Term redesign (#727 changed to "autonomous execution") | "autonomous execution" |

## Terminology Migration Scope Rule

When creating an Issue that adds deprecated terms to Forbidden Expressions (gradual terminology migration), explicitly state whether replacing deprecated terms within the same file is included in scope.

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
