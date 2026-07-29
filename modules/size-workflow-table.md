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

### ALWAYS_PR Override

When `.wholework.yml` sets `always-pr: true` (`modules/detect-config-markers.md` provides this as `ALWAYS_PR=true`), a Size-derived `patch` route is promoted to `pr` regardless of Size. Only `patch` is promoted — `pr` and `split guidance` (XL) are unaffected, since their result already matches or is orthogonal to the override.

**Priority order (exhaustive)**, applied before any caller uses the Size-to-Workflow Mapping Table's result:

1. operate route (`### Diff-less Axis (operate route)` below) — takes priority over both `always-pr: true` and explicit `--patch`/`--pr` flags
2. explicit `--pr` flag
3. `ALWAYS_PR=true` — overrides an explicit `--patch` flag too (a caller honoring this override outputs a warning that `--patch` is ignored and pr route is forced)
4. explicit `--patch` flag
5. Size-to-Workflow Mapping Table above

This override applies not only to the route value itself but to any **route-dependent behavior** derived from Size. A rule that assumes "Size XS/S implies patch route, therefore no PR exists" is in scope of this override: under `always-pr: true`, Size XS/S resolves to pr route, a PR does exist, and a `github_check "gh pr checks"` acceptance condition is valid and must not be rewritten to `gh run list` form. See `modules/verify-classifier.md` § "Patch Route CI Verification Note".

**Callers that must apply this override (exhaustive)**: `skills/auto/SKILL.md` (Step 2, Step 3a), `skills/code/SKILL.md` (Step 0, Patch route verify command check), `skills/spec/SKILL.md` (Patch route verify command check, Step 18), `skills/issue/SKILL.md` (Acceptance Criteria Writing Guide), `skills/issue/spec-test-guidelines.md` (Route selection), `skills/triage/skill-dev-verify-audit.md` (Pattern 4), `scripts/run-auto-sub.sh`.

### Diff-less Axis (operate route)

Orthogonal to Axes 1–2 above. Size (Axis 1–2) measures change scope/effort (XS–XL); the diff-less axis determines whether a route produces a git diff at all. This axis contributes a third route value, `operate`, alongside `patch` and `pr` in the Size-to-Workflow Mapping Table above — `operate` is a route value, not a Size value, so it does not replace or extend the Size scale.

**Determination criteria** (both must hold; evaluated by `/spec` from the Spec it produces, and re-checked by `/code` from the same Spec):
- `## Changed Files` contains no repository file entries (empty, "none", or only external-system targets)
- Every entry in `## Implementation Steps` is an external-tool operation (an MCP tool call, or a CLI/HTTP API call against an external system) — no file edits or commit steps

When both hold, ROUTE=operate. This determination takes priority over the Size-to-Workflow Mapping Table above and over explicit `--patch`/`--pr` flags or `always-pr: true` (an empty diff cannot produce a meaningful PR, so PR route cannot apply regardless of flags).

**operate route characteristics**: no worktree-based commit/push/PR for the implementation diff; external operations (MCP/CLI/API) execute directly from `/code`; results are recorded as an Issue comment (`## Execution Log`) and Phase Handoff in place of a git diff; phase label transition mirrors patch route (`phase/code` → `phase/verify`, skipping `/review`/`/merge`).

### Phase-Level Light/Full Mapping

| Phase | patch (XS/S) | pr (M/L) | operate (diff-less) |
|-------|-------------|---------|---------------------|
| spec  | XS: not required, S: required | Required | Required |
| code  | Direct to main (`--patch`) | Branch + PR | Direct external operation execution (no implementation-diff commit) |
| review | None | M: lightweight (`--light`), L: full (`--full`) | None (no PR to review) |
| merge | None | Execute | None (no PR to merge) |
| verify | Execute | Execute | Execute |

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
