# Size-to-Workflow Decision Table

A 1:1 mapping table linking Issue Size properties to workflow routes, including Size judgment criteria (2 axes).

## Input

Information provided by the calling skill:
- Estimated scope of changes (expected number of changed files)
- Summary of changes (used for complexity adjustment)

## Processing Steps

Skills that Read this file should reference the tables below for Size determination and workflow selection.

### Size Determination Flow

```
Estimated file count → Provisional Size → Complexity adjustment (±1 step) → CI dependency check → Final Size → Workflow selection
```

### Axis 1: Change Scope (Quantitative) — Determine provisional Size by file count estimate

| Size | File Count Estimate |
|------|-------------------|
| XS   | 1                 |
| S    | 1-2               |
| M    | 3-5               |
| L    | 6-10              |
| XL   | 11+ or multiple independent features |

### Axis 2: Complexity Adjustment (Qualitative, ±1 step)

Factors to **increase** size by one step:
- Introduction of new architecture patterns (no similar implementation exists in codebase)
- Changes spanning multiple skills/agents
- Breaking changes to existing public interfaces
- Script logic changes (adding branches, argument handling changes, etc.; not documentation-only changes)

Factors to **decrease** size by one step:
- Simple lateral extension of existing patterns (copy & adapt)
- Documentation-only changes
- Bug fixes with clear root cause

### CI Dependency Minimum Override

After applying Axes 1–2, if the changed files match any of the following patterns, upgrade the Final Size to **Size M at minimum** (PR route required; CI runs before merge):

| Pattern | Examples | Reason |
|---------|----------|--------|
| CI workflow changes | `.github/workflows/*.yml` | CI configuration changes cannot be validated without CI itself running |
| Test parallelization / fixture shared-structure changes | `tests/` parallelization flags, shared mock fixture additions | Race conditions and fixture interference only manifest under concurrent execution |
| CI-environment-dependent verification changes | Changes that rely on CI-specific environment variables, services, or timing | Cannot replicate CI environment locally; merge-first detection risks breaking main |

**Minimum upgrade target: Size M** (PR route; CI runs before merge)

Note: This override is additive — if Axes 1–2 already produce L or XL, that result is preserved. The override only raises the floor to M; it does not cap at M.

### Size-to-Workflow Mapping Table

| Size | Route Name | Characteristics | Spec | Verify |
|------|-----------|----------------|------|--------|
| XS   | patch     | Direct commit to main, no PR, no review | Not required | Yes |
| S    | patch     | Direct commit to main, no PR, no review | Required | Yes |
| M    | pr        | Branch + PR, lightweight review | Required | Yes |
| L    | pr        | Branch + PR, full review | Required | Yes |
| XL   | split guidance | Guide to split into sub-issues | Required | — |

### Phase-Level Light/Full Mapping

| Phase | patch (XS/S) | pr (M/L) |
|-------|-------------|---------|
| spec  | XS: not required, S: required | Required |
| code  | Direct to main (`--patch`) | Branch + PR |
| review | None | M: lightweight (`--light`), L: full (`--full`) |
| merge | None | Execute |
| verify | Execute | Execute |

### Option System

| Skill | Option | Meaning |
|-------|--------|---------|
| `/spec` | `--light` / `--full` | Depth of process |
| `/code` | `--patch` / `--pr` | patch route / pr route |
| `/review` | `--light` / `--full` | Depth of process |
| `/auto` | `--patch` / `--pr` | Route specification |
| `/auto` | `--review=full` / `--review=light` | Review depth override |

### Fallback When Size Is Not Set

When a skill that requires routing is run against an Issue without Size set, use AskUserQuestion to have the user select a route (patch / pr).

**Design principle**: Size is the single input that determines workflow "weight". Once size is set by `/triage`, one of the two routes (patch / pr) is automatically determined.
