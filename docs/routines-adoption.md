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

| Routine | Trigger | Action |
|---|---|---|
| auto-triage | `issues.opened` | `/triage N` — assign Type/Priority/Size/Value immediately |
| phase-transition executor | `issues.labeled` (e.g., `phase/spec-ready`, `phase/code-ready`) | Kick corresponding skill (`/spec`, `/code`) |
| verify-on-merge | `pull_request.closed` (merged) | `/verify` — eliminate the "manual verify forgotten" failure mode |

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

## Rollout Plan

1. **PoC: auto-triage routine** — `issues.opened` → `/triage N`. Minimal, low-risk, high-frequency value. Gather data on quota consumption, idempotence behavior, label race conditions
2. **verify-on-merge** — immediate ROI, eliminates manual-forget failure mode
3. **Nightly batch auto** — routine-ize existing `/auto --batch`, validate Q1 timing decision
4. **Phase-transition executor** — core of state-machine vision, triggers `/auto` deconstruction discussion
5. **Per-PR shepherd** — most ambitious, maximum value, deferred until earlier tiers prove quota/idempotence assumptions

## Learnings Log

PoC findings and decisions will be appended here as they accumulate. Each entry should include date, tier, observation, and any design adjustment.

(No entries yet.)
