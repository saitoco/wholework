---
type: project
---

English | [日本語](../ja/guide/autonomy.md)

# Autonomy Tier

Wholework's **autonomy tier** controls how far skills may write GitHub state (L0) and fire follow-on loops. It is a project-level governance declaration set in `.wholework.yml`.

## Why it exists

Wholework skills can write GitHub state (create labels, close issues, post comments) and fire follow-on loops through Claude Code primitives (`CronCreate`, `ScheduleWakeup`). How much of this you want to happen automatically depends on your project's trust level, review culture, and tolerance for autonomous side effects.

The autonomy tier gives you a single dial to control all of this — without having to configure each skill individually.

## Three tiers

### L1 Report (default)

Skills read GitHub state and print recommendations. **No automatic writes to GitHub state, no automatic loop firing.**

Use L1 when:
- You are evaluating Wholework for the first time
- Your project requires human approval for every GitHub state change
- You want audit and drift detection without any autonomous action

Allowed L2→L1 paths: **A (Advisory only)**

### L2 Assisted

Skills write GitHub state (same as current `/auto` and `/verify` behavior). **No automatic cron scheduling.**

Use L2 when:
- You are running mid-scale modernization (the Wholework anchor case: $10K / 10 days / 50–100 PRs)
- You want the main workflow (issue → spec → code → review → merge → verify) to run autonomously
- You are comfortable with Wholework closing Issues and transitioning labels automatically
- You prefer to trigger recurring schedules manually (e.g., running `/auto --batch` yourself)

Allowed L2→L1 paths: **A (Advisory), C (ScheduleWakeup in-loop)**

### L3 Unattended

Skills write GitHub state (label transitions, close/reopen, comments) fully unattended. `CronCreate` is available as an L2→L1 path (B), but it is session-scoped and in-memory — nothing is written to disk, registered jobs auto-expire after 7 days, and unattended self-registration is blocked by the Claude Code auto mode classifier. Registering a `CronCreate` schedule therefore requires an attended session; it is not something an unattended L3 run can do on its own.

Use L3 when:
- You have verified that L2 works well for your project
- You want GitHub-state work (label transitions, close/reopen, comments) to proceed without any human trigger
- You accept that Wholework will modify GitHub state autonomously, while registering any `CronCreate` schedule still requires an attended session

Allowed L2→L1 paths: **A, B (CronCreate), C**

## Setting the tier

In `.wholework.yml` at your project root:

```yaml
# .wholework.yml
autonomy: L2   # L1 | L2 | L3
```

If `autonomy` is not set (or is set to an unrecognized value), it defaults to `L1`.

## What happens when a skill needs a path your tier does not allow

Skills declare the L2→L1 paths they use in their frontmatter (`loop-paths-used`). When a skill invokes a path that your tier prohibits:

- **Mandatory dependency** (the skill cannot work without it): the skill refuses to start and prints an error telling you which tier to set.
- **Degradable** (the skill works without it): the skill prints a warning and falls back to path A (advisory — it prints a recommendation for you to act on).

## How the tier relates to `--permission-mode`

Claude Code's `--permission-mode` flag controls subprocess permissions (which `gh` and shell commands are auto-approved vs. prompted). The autonomy tier controls **which GitHub state Wholework may write and which loops it may fire**. They are orthogonal — subprocess permission handling and `autonomy: L1` can be set independently.

For the complete tier × path permission matrix and L0 write rules, see [`modules/autonomy-tier.md`](../../modules/autonomy-tier.md).

---

← [User Guide](index.md)
