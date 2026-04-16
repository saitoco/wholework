---
type: project
ssot_for:
  - routines-adoption
  - tier-roadmap
  - open-questions
---

# Routines Adoption

Long-term initiative document for adopting Claude Code's Routines feature into wholework. Captures direction, open questions, tier roadmap, and PoC learnings as they accumulate across sessions.

Reference: https://claude.com/blog/introducing-routines-in-claude-code

## Background

Claude Code Routines (announced 2026-04) provides cloud-hosted, event-driven execution of Claude prompts via three trigger types: cron schedule, HTTP API endpoint, and GitHub webhook. Each routine runs on Claude's web infrastructure without requiring a local machine.

For wholework this is architecturally significant. Currently wholework skills run locally via Claude Code CLI, which means `/auto` batch runs require the user's machine to stay on, and skills cannot react to GitHub events without manual invocation. Routines removes both constraints.

## Core Insight

Routines can elevate wholework from "locally-invoked CLI skills" to a "cloud-resident event-driven workflow engine". Three structural wins:

1. **Local dependency removed** — `/auto` overnight batch no longer needs the user's PC running
2. **GitHub event reactivity** — skills gain the reactive behavior they currently lack
3. **Per-PR persistent session** — Routines' official "session per PR" pattern aligns structurally with wholework's PR lifecycle model

## Design Principles

- **Phase label as state machine** — wholework already uses `phase/*` labels. Treating label transitions as routine triggers enables lifecycle-wide automation (label = state, routine = transition)
- **Quota economics** — Pro 5/day, Max 15/day, Team/Enterprise 25/day. High-frequency webhooks need debounce/batching layers. Reserve routine quota for human-bottleneck elimination, not trivial automation
- **Human-in-the-loop boundaries** — `/merge` must not be routine-ized (destructive). `/verify` FAIL handling should include a mode flag for human confirmation before reopening
- **Idempotence mandatory** — webhooks retry; commands must detect existing comments/labels and skip

## Tier Roadmap

| Tier | Theme | Status | Notes |
|---|---|---|---|
| 1 | Webhook-reactive (low-risk, high-value) | planned | PoC candidate: auto-triage on `issues.opened` |
| 2 | Per-PR Shepherd (continuous PR assistant) | planned | Lower personal priority (covered by `/auto`), high value for manual-merge users |
| 3 | Cron (backlog digestion) | planned | Requires decision on schedule timing vs Claude usage limits |
| 4 | API-triggered bridges (Slack, alerts) | planned | |
| — | `/auto` deconstruction | exploratory | Phase-transition routines may render `/auto` redundant; migration path TBD |

### Tier 1 — Webhook-reactive

| Routine | Trigger | Action | Status |
|---|---|---|---|
| auto-triage | `schedule` (hourly/daily) | inline prompt invoking `gh` CLI, or `/triage` as project skill | **redesigned** — Issues webhook events not supported (see Learnings Log 2026-04-16) |
| phase-transition executor | (Issues webhook) | Kick corresponding skill (`/spec`, `/code`) | **blocked** — depends on future Issues webhook support |
| verify-on-merge | `pull_request.closed` (merged) | `/verify` (via project skill) — eliminate the "manual verify forgotten" failure mode | viable |

#### Setup Runbook — auto-triage (schedule-based batch)

This runbook documents the steps to configure the auto-triage routine via the Claude Code web UI. The original design (`issues.opened` → `/triage`) is not viable because Routines GitHub webhook support is currently limited to Pull Request and Release events only. The runbook below uses a schedule-based trigger with an inline prompt that processes untriaged Issues in batch.

**Prerequisites**

- Claude Code account with Routines access (Pro/Max/Team/Enterprise)
- GitHub repository connected to Claude Code (`/web-setup` grants clone access; webhook triggers separately require installing the Claude GitHub App)
- Target repository contains the `triaged` label (created automatically on first use, or pre-create via `gh label create triaged`)

**Action Prompt Options**

Two patterns work in the Routines runtime. Choose based on whether the target repository has wholework skills committed to `.claude/skills/`:

**Option A — Inline prompt (skill-independent, works on any repo):**

```
You are running in a Claude Code Routine (cloud environment).
Execute these steps autonomously without asking for confirmation.
Use only `gh` CLI — do not reference plugin paths.

Step 1: List untriaged open issues
  Run: gh issue list --state open --search "-label:triaged" --json number,title,body --limit 10

Step 2: For each issue returned, classify:
  - Type: Bug / Feature / Task (from title + body keywords)
  - Size: XS / S / M / L / XL (estimate from scope in body)
  - Priority: urgent / high / medium / low (only if explicitly stated)

Step 3: Apply labels (run each command individually, no && chaining):
  - gh issue edit <N> --add-label "type/<type>"
  - gh issue edit <N> --add-label "size/<size>"
  - gh issue edit <N> --add-label "priority/<priority>"   (skip if not detected)
  - gh issue edit <N> --add-label "triaged"

Step 4: Post a single summary comment via:
  gh issue comment <N> --body "Auto-triage: Type=<type>, Size=<size>, Priority=<priority or none>"

Step 5: Output a results table summarizing all processed issues.
```

**Option B — Project skill (requires `.claude/skills/triage/` committed to the target repo):**

```
/triage --limit 10
```

Routines load project skills from the cloned repository's `.claude/skills/` directory but do **not** load plugin-distributed skills. For wholework's own repository this works because `skills/` is structured as both plugin and project skills; for other repositories, either vendor wholework's skill into `.claude/skills/` or use Option A.

**Configuration Steps**

1. Open the Claude Code web UI and navigate to **Routines**
2. Click **New Routine**
3. Name the routine (e.g., `wholework-auto-triage`) and paste one of the action prompt options above
4. Select the target repository
5. Select environment (Default is fine for `gh` CLI; ensure network access is enabled)
6. Under **Select a trigger**, choose **Schedule** and pick a frequency (daily weekday morning is a reasonable default)
7. Save the routine
8. Verify delivery: click **Run now** on the routine's detail page and confirm the test run processes any currently-untriaged Issues

**Idempotence**

Both options are idempotent via the `-label:triaged` filter at Step 1 / `--search` predicate: already-triaged Issues are excluded from the listing, so repeated invocations (scheduled or manual re-run) will not reprocess the same Issue. This replaces the prior design's reliance on `/triage`'s in-skill label detection, which is still effective but now redundant with the list-level filter.

**Quota Impact**

One routine invocation per scheduled fire processes up to N Issues in a single batch (N = `--limit` in the prompt). Compared to the original per-Issue webhook design (one invocation per `issues.opened`), schedule-based batch is significantly more quota-efficient on active repositories, at the cost of triage latency (Issues wait for the next scheduled run rather than triaging on creation).

**Expected Outcome**

On each scheduled fire, all Issues matching `-label:triaged` up to the configured limit receive Type/Size/Priority labels (via label fallback) and a summary comment. Project v2 field updates are omitted by default in Option A because inline prompts cannot invoke wholework's `project-field-update.md` module; use Option B when Project v2 fields are required.

### Tier 2 — Per-PR Shepherd

Assign one routine per PR, managing lifecycle in a single persistent session:
- `pull_request_review_comment.created` → commit addressing feedback
- `workflow_run.completed` (failure) → diagnose CI failure, attempt fix
- Conflict detected → attempt rebase (escalate to human on failure)
- Approve + CI green → attach `phase/ready-to-merge` label (merge itself stays human)

Evolves `/review` from single-shot to continuous PR assistant. Migration is clean because `/auto` already implements equivalent review-fix-merge logic.

### Tier 3 — Cron

- **Nightly batch auto**: `/auto --batch 3` for XS/S — replaces current manual overnight kickoff
- **Weekly audit suite**: `/audit drift` + `/audit fragility` — generated Issues picked up by auto-triage routine next business day
- **Monthly health report**: `/audit stats` posted to Discussions

Schedule timing is an open question (see below).

### Tier 4 — API-triggered

- **Slack → `/issue`** — create Issue from thread summary (serves stakeholders without GitHub access)
- **Incident → Issue** — from monitoring/alerting, fast-path triage with Priority=P0 forced

## Open Questions

### Q1. Nightly batch schedule timing (Tier 3)

The user wants to avoid running routines during hours of strict Claude usage limits. Interpretation determines the optimal window:

- **(a) Avoid personal 5-hour quota conflict with interactive use** → JST 02:00-05:00 optimal (user asleep, zero interactive competition)
- **(b) Avoid global API congestion** → JST 14:00-18:00 optimal (= US deep night), but conflicts with Japanese working hours
- **(c) Compromise** → JST 05:00-06:00 start (PT 13:00 / ET 16:00, US end-of-day decline phase); results available just before user wakes

Current leaning: interpretation (a), JST 03:00 start, integrated into morning review flow. Validate with PoC usage data before committing.

### Q2. `/auto` obsolescence

If Tier 1 phase-transition executor materializes, it becomes a cloud-native state machine that replaces `/auto`'s local phase-chain simulation. Migration path:

1. Routines coexist with `/auto` (opt-in experimental)
2. Routines default, `/auto` demoted to "local fallback" (retained for offline/private-repo usage where webhooks cannot reach)
3. Full migration decision — delete or retain as fallback

`/auto` has standalone value for repos where webhook delivery is impossible. "Local fallback" positioning likely survives even post-Routines.

### Q3. Quota exhaustion on active repos

Webhook frequency on active repositories can easily exceed the daily routine quota. Requires a debounce/aggregation layer — e.g., collapsing label changes on the same Issue within a 5-minute window into a single routine invocation.

### Q4. Race conditions between manual skill invocation and routines

User runs `/triage 123` locally while auto-triage routine fires for the same Issue. Need lock/claim mechanism — candidate: `routine/claim` label applied at routine start, cleared on completion, respected by local skills.

### Q5. Phase label SSoT integrity

Currently `phase/*` labels are managed inside skill implementations. If routines update labels directly from webhook handlers, integrity across skill ↔ routine writes needs a contract.

### Q6. `/verify` FAIL handling mode

Current `/verify` auto-reopens Issue on FAIL. Under routine execution this may be too aggressive (the FAIL might need human interpretation before reopening). Propose `mode: auto-reopen | notify-only` flag.

### Q7. Skill distribution for Routines consumers

The 2026-04-16 PoC revealed that plugin-distributed skills are not loaded in the Routines runtime — only project skills (`.claude/skills/` in the cloned repository) are visible. This creates a distribution fork for wholework:

- **(a) Dual distribution** — maintain both plugin manifest and a parallel `.claude/skills/` tree. Doubles file layout and forces every path-resolution token (`${CLAUDE_PLUGIN_ROOT}` vs `${CLAUDE_SKILL_DIR}`) to work in both contexts.
- **(b) Setup-script install** — cloud environment setup script clones the wholework plugin and installs it before each run. Adds per-run install overhead and requires users to configure a custom environment.
- **(c) Inline-prompt patterns only** — give up on invoking wholework skills from Routines, use hand-written inline prompts per routine. Loses composability but has zero distribution friction.

No decision yet. verify-on-merge implementation (Tier 1 next step) will be the forcing function: whichever path is taken for `/verify` sets the pattern for subsequent routines.

## Rollout Plan

1. **PoC: auto-triage routine** — originally planned as `issues.opened` → `/triage N`; revised 2026-04-16 to `schedule` + inline-prompt (see Learnings Log). Minimal, low-risk value. Gather data on quota consumption, idempotence, skill distribution
2. **verify-on-merge** (`pull_request.closed` → `/verify`) — immediate ROI, eliminates manual-forget failure mode. Forcing function for Q7 skill-distribution decision
3. **Nightly batch auto** — routine-ize existing `/auto --batch`, validate Q1 timing decision
4. **Phase-transition executor** — blocked on Issues webhook support (see Tier 1 table). Revisit when Anthropic expands event coverage
5. **Per-PR shepherd** — most ambitious, maximum value, deferred until earlier tiers prove quota/idempotence/distribution assumptions

## Learnings Log

PoC findings and decisions will be appended here as they accumulate. Each entry should include date, tier, observation, and any design adjustment.

### 2026-04-16 — auto-triage PoC (Tier 1)

**Context**

Attempted to configure the auto-triage routine in the Claude Code web UI following the runbook in this document (pre-revision version). Three runtime constraints surfaced during setup that invalidate the original design and force a rewrite of both the Tier 1 table and the Setup Runbook.

**Observations**

- **Supported GitHub webhook events are Pull Request and Release only.** The Claude Code web UI event picker does not expose `issues.opened` or any Issues-category event. This matches the official docs (https://code.claude.com/docs/en/routines, "Supported events" section, confirmed 2026-04-16). Prior runbook text that referenced `issues.opened` → `/triage N` was not implementable. Anthropic's Threads post mentions "More event sources are coming soon" (https://www.threads.com/@claudeai/post/DXHotXUADxk), so Issues events may land later; treat this as blocked-by-feature-availability rather than a permanent constraint.

- **Plugin-distributed skills are not loaded in the Routines runtime.** An action prompt of `/triage N` did not resolve — the remote Claude Code session started but terminated without invoking the skill. Per the official docs: "The session can run shell commands, use skills committed to the cloned repository, and call any connectors you include." This means only **project skills** (`.claude/skills/` committed to the cloned repository) are available, not plugin skills loaded from a marketplace. wholework's skill distribution needs a project-skill vendor path (or a setup-script install path) for Routines-driven execution.

- **Schedule trigger + inline `gh` CLI prompt is the minimum viable pattern.** A manually-fired test routine running an inline prompt (list untriaged Issues, classify with `gh`, apply labels, post comment) succeeded end-to-end on Issue #206: labels `triaged`, `type/feature`, `size/xs` were applied and an auto-triage comment was posted. This confirms `gh` CLI is available and authenticated in the Routines runtime, `gh issue edit --add-label` writes succeed, and inline prompts without slash-command dependencies execute correctly.

- **quota observations (limited, PoC scope).** Only two routine invocations were consumed during the PoC (one failed `/triage` attempt, one successful inline run on #206). Meaningful per-day quota profiling requires sustained operation under organic Issue creation rates, deferred to post-rollout monitoring. Note: schedule-based batch (single invocation covers N Issues) is inherently more quota-efficient than the originally-planned per-Issue webhook model would have been, regardless of exact numbers.

- **idempotence confirmed at the list-filter level.** The inline prompt's `gh issue list --search "-label:triaged"` predicate guarantees already-triaged Issues are excluded from each batch, so scheduled re-runs (or `Run now` during debugging) do not reprocess Issues. This is a stronger idempotence guarantee than the prior design's reliance on `/triage`'s in-skill label detection, because it short-circuits before any classification work.

**Design adjustments**

- **Tier 1 table rewritten.** auto-triage moved from `issues.opened` webhook to `schedule` trigger with inline-prompt execution; phase-transition executor marked as blocked pending Issues webhook support; verify-on-merge remains viable because `pull_request.closed` is supported.
- **Setup Runbook rewritten.** Original webhook-based flow replaced with a schedule-based flow offering two action-prompt options: (A) inline `gh` CLI prompt for any repository, (B) `/triage` as a project skill for repositories that vendor wholework's `.claude/skills/`.
- **New open question (Q7) added below** tracking plugin-vs-project skill distribution strategy for Routines consumers.

**Stop / Disable Procedure**

If the auto-triage routine needs to be paused or removed:

1. Open the Claude Code web UI and navigate to **Routines**
2. Locate the `wholework-auto-triage` routine
3. Choose one of:
   - **Disable (reversible)** — toggle the routine to `disabled`. The schedule stops firing; re-enable by toggling back.
   - **Delete (irreversible)** — remove the routine entirely. Re-enabling requires re-running the full setup runbook.
4. Verify: `Run now` is no longer available (or no longer effective) for the disabled routine.

Prefer **disable** over **delete** for temporary pauses. Reserve **delete** for genuine decommissioning.

**Tier 1 next step recommendation**

Based on what was learned, the ordered next steps are:

1. **verify-on-merge** (`pull_request.closed` → `/verify`) — the PR webhook is officially supported and `/verify` already has idempotence semantics, so this is the lowest-risk next routine. Requires vendoring `.claude/skills/verify/` (or equivalent inline-prompt rewrite of the critical path) because `/verify` is a plugin skill today.
2. **Refactor wholework for Routines compatibility** — generalize scripts/modules to work under `${CLAUDE_SKILL_DIR}` (project-skill context) in addition to `${CLAUDE_PLUGIN_ROOT}`. Alternatively, commit to a setup-script-based plugin install pattern inside the cloud environment. Whichever path is chosen needs to be documented and test-covered before Tier 1 expansion.
3. **Keep the schedule-based auto-triage enabled** to accumulate real quota data (currently insufficient signal from the 2-invocation PoC) and surface edge cases before scaling to more routines.
4. **phase-transition executor deferred** until Issues webhook support ships. Revisit when Anthropic announces expanded event coverage.

Deferred explicitly: `/merge` routine-ization remains out of scope (destructive action, human-in-the-loop mandatory per Design Principles).

**Related Issues**

- Setup runbook (pre-revision): #189 (closed)
- This PoC: #191
