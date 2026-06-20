# autonomy-tier

SSoT for Wholework's autonomy tier: the governance declaration that controls how far skills may write GitHub state (L0) and fire follow-on loops via L2→L1 paths.

## Purpose

Define the three autonomy tiers (L1 Report / L2 Assisted / L3 Unattended) and the exhaustive set of L2→L1 firing paths, so that:
- The `.wholework.yml: autonomy:` field has a single authoritative reference for its semantics.
- Skills can declare which paths they use (via frontmatter `loop-paths-used`) and the loader can allow, reject, or degrade based on the active tier.
- The question "is this an L0 write?" is answered per-surface by [`modules/l0-surfaces.md`](l0-surfaces.md) (not duplicated here).

## Input

None. Loaded by skills at phase start via "Read and follow" pattern.

## L0 Layer Table (exhaustive)

L1/L2/L3 loop state only has meaning when it is written back to L0 (public, multi-actor, cross-query-capable GitHub state). The table below makes the four layers explicit.

| Layer | Loop state location | Drive mechanism | Persistence |
|-------|---------------------|-----------------|-------------|
| **L0: GitHub state** | Issues / Labels / PRs / blockedBy / `closes #N` | Event-driven (PR merge, label transition, comment, close) | Public, multi-actor, cross-query-capable |
| **L1: Claude Code primitive** | Session memory | `/loop` / `/goal` / `ScheduleWakeup` | Volatile (session-scoped) |
| **L2: Wholework skill internal** | Spec / retro / `auto-events.jsonl` | Tail extension (#700/702/703) | File-persistent |
| **L3: OS / `CronCreate`** | Crontab / cron registry | OS scheduler | Environment-dependent |

Wholework's XL Issue feature is itself an L0 loop: the parent Issue is the goal, sub-issues + `blockedBy` form the DAG, `phase/*` labels are the state machine, and the aggregation rules in `docs/workflow.md § XL Parent Issue Phase Management` provide the stop condition (all children in `phase/done` closes the parent).

## L2→L1 Path Catalog (exhaustive)

Each row defines one firing path from a Wholework skill (L2) to a Claude Code primitive or external trigger (L1).

| ID | Path | Mechanics | Example |
|----|------|-----------|---------|
| **A** | Advisory | Skill prints a next-step recommendation. Firing responsibility lies with the user. | `Recommend: /loop 1d /audit drift` |
| **B** | CronCreate | Skill registers a persistent schedule via `CronCreate`. | On `/auto 670` completion, register daily `/audit progress 670`. |
| **C** | ScheduleWakeup | Inside a running `/loop`, skill dynamically controls the next wake-up time. | `/verify` UNCERTAIN (CI not yet complete) → schedule re-verify in N minutes. |
| **D** | Detached subprocess | Skill launches `claude -p` detached. **Not supported in current scope** — reliability is low because the subprocess dies when the parent exits. | — |
| **E** | Seed file emission | Skill writes `.tmp/next-cycle.json`; a separate L1 process reads it on the next wake. | `/auto --batch` next-cycle seed (#703). |

## Tier × L2→L1 Path Matrix (exhaustive)

| Tier | A | B | C | E | Default use |
|------|---|---|---|---|-------------|
| **L1 Report** | ○ | × | × | × | Audit and drift detection only. Firing is delegated to the human. |
| **L2 Assisted** | ○ | × | ○ (in-loop) | ○ | Mid-scale modernization (anchor case). Seed is automated; cron requires a human to trigger. |
| **L3 Unattended** | ○ | ○ | ○ | ○ | Fully unattended. `CronCreate` allows self-rescheduling. |

Path D is excluded from the matrix because it is not supported.

## Tier × L0 Write Matrix

Autonomy tier controls how far a skill may write GitHub state. For the exhaustive list of L0 surfaces and their mutation kinds, see [`modules/l0-surfaces.md`](l0-surfaces.md).

| Tier | L0 read | L0 write (label transition, issue close, comment) | Recurring template / cross-issue creation |
|------|---------|--------------------------------------------------|------------------------------------------|
| **L1 Report** | ○ | × (advisory print only; human acts) | × |
| **L2 Assisted** | ○ | ○ (current `/auto` / `/verify` behavior) | × (human judgment required) |
| **L3 Unattended** | ○ | ○ | ○ (`/audit recurring` and future features) |

## `.wholework.yml` Schema

```yaml
autonomy: L2   # L1 | L2 | L3
# Default when unset: L1 (safest)
```

Invalid values (e.g., `autonomy: L9`) fall back to `L1` (same as unset). The AUTONOMY_TIER variable exported by `modules/detect-config-markers.md` carries this resolved value.

## Processing Steps (loader behavior)

When a skill's frontmatter declares paths via `loop-paths-used`, the skill (or its loader) should apply the following check at invocation start:

1. **Read autonomy tier**: load `AUTONOMY_TIER` from `.wholework.yml` via `modules/detect-config-markers.md` (default `L1`).
2. **Check each declared path against the matrix above**:
   - Path allowed in active tier → proceed normally.
   - Path not allowed in active tier:
     - **Mandatory dependency** (the skill cannot function without this path): hard-error — refuse to start and print:
       ```
       Error: path {ID} is not permitted under autonomy tier {TIER}.
       Set autonomy: {required-tier} or higher in .wholework.yml to enable this skill.
       ```
     - **Degradable** (the skill works without this path): warning + degrade to path A (advisory):
       ```
       Warning: path {ID} is not permitted under autonomy tier {TIER}.
       Falling back to path A (advisory): printing recommendation instead of auto-firing.
       ```
3. **Optional `loop-paths-fallback`**: if the skill declares `loop-paths-fallback: [A]` in its frontmatter, use the listed path(s) as the degraded alternative instead of always defaulting to A.

### Skill Frontmatter Declaration Rules

Skills declare which L2→L1 paths they use via YAML frontmatter:

```yaml
---
name: auto
loop-paths-used: [A, E]
---
```

To declare a graceful fallback when the active tier prohibits a path:

```yaml
---
loop-paths-used: [B]
loop-paths-fallback: [A]   # downgrade to advisory when B is not allowed
---
```

Rules:
- `loop-paths-used`: list of path IDs the skill uses (`A`, `B`, `C`, `E`). D is omitted (not supported).
- `loop-paths-fallback`: optional list of path IDs to substitute when `loop-paths-used` paths are blocked. Must be a subset that is always allowed (A is always allowed in all tiers).
- Skills with no `loop-paths-used` declaration are assumed to require no L2→L1 firing and are tier-neutral.

## CronCreate Visibility Note

The cron registry is inspectable via `CronList` (an existing Claude Code primitive). Wholework does not maintain a duplicate cron storage — use `CronList` to audit what schedules have been registered.

## Output

- Tier and path permission context for the calling skill's loader logic.
- Referenced by `modules/detect-config-markers.md` for the `AUTONOMY_TIER` variable definition.
- Referenced by `modules/l0-surfaces.md` as the consumer of L0 write permission segmentation by tier.
