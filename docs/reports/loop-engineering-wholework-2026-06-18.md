English | [日本語](ja/reports/loop-engineering-wholework-2026-06-18.md)

# Loop Engineering Applied to Wholework

**Report date**: 2026-06-18
**Author**: Memo session triggered by user reading Addy Osmani's "Loop Engineering" and suwash's Zenn translation/expansion
**Status**: Analytical memo — not a finalized roadmap; intended as input to product/spec decisions

**Sources surveyed**:
- Addy Osmani, *Loop Engineering* (Substack, 2026-06-08) — https://addyo.substack.com/p/loop-engineering
- suwash, *Loop Engineering 入門* (zenn.dev/suwash/articles/loop-engineering_20260610) — practical CLI/GitHub-Actions playbook with `loop-audit` and `loop-init` tooling
- Wholework repository at HEAD (`f9a1629`)

## 1. What is Loop Engineering, and why bring it to Wholework?

Osmani's framing is: stop being the human who prompts the agent every turn; design a system that prompts agents on your behalf. The leverage point moves up one floor from harness engineering (the single-agent environment) to loop engineering (the schedule, dispatcher, verifier and memory that drive multiple harnesses over time).

He decomposes a loop into **5 building blocks + memory**:

| # | Block | Function |
|---|-------|----------|
| 1 | **Automations / scheduling** | Heartbeat: cron/`/loop`/`/goal`/hooks fire work without you typing |
| 2 | **Worktrees** | Parallel agents don't collide on files |
| 3 | **Skills** | Project intent (`SKILL.md`) — written once, read every run |
| 4 | **Plugins / Connectors** | The loop reaches issue trackers, CI, Slack, browsers via MCP |
| 5 | **Sub-agents** | Maker / checker split — the writer is not the grader |
| + | **Memory** | Markdown/board/JSON outside the conversation: the repo doesn't forget what the model does |

suwash's Zenn article makes that practical: a `loop-audit` CLI that scores a repo's readiness, a `loop-init` scaffolder, an **Autonomy Tier (L1 Report / L2 Assisted / L3 Unattended)** framework, and concrete `STATE.md` / `LOOP.md` patterns including token budgets, denylists, and multi-loop collision detection via `acting_on:` keys.

Wholework's stated vision (`docs/product.md`) is *a governance-and-verification harness for autonomous coding agents on GitHub*. The vocabulary already overlaps — harness, sub-agents, retrospectives — but the two framings sit at different floors. This report asks: how much of Loop Engineering is *already* in Wholework, and where does the remaining headroom lie?

## 2. Mapping the 5+1 blocks onto Wholework today

The short answer: **Wholework already covers blocks 2, 3, 5, and 6 (Memory) at production quality, block 4 (Connectors) at GitHub-CLI-deep but cross-tool-shallow, and block 1 (Automation/heartbeat) only as a manually-invoked orchestrator.** The asymmetry is the interesting part.

### 2.1 Worktrees — fully covered

`modules/worktree-lifecycle.md` provides a shared Entry/Exit lifecycle used by `/spec`, `/code`, `/review`, `/merge`, `/verify`. Branch naming SSoT is `worktree-<phase>+issue-N` (`modules/phase-state.md`). `scripts/worktree-merge-push.sh` performs lock acquisition + ff-only merge + conflict-marker check + push as one atomic unit. XL Issues run sub-issues in parallel under per-sub-issue worktree isolation gated by the `blockedBy` dependency graph (`skills/auto/SKILL.md`, `scripts/get-sub-issue-graph.sh`).

This is materially more than what most other Skills frameworks ship: collisions are not just isolated but actively reconciled with `ff-only-merge-fallback` and rebase-from-inside-worktree paths in `modules/orchestration-fallbacks.md`.

### 2.2 Skills (intent persistence) — fully covered

Ten skills are registered (`auto`, `audit`, `code`, `doc`, `issue`, `merge`, `review`, `spec`, `triage`, `verify`), backed by 36 shared modules under `modules/`. The adapter-resolver pattern (`modules/adapter-resolver.md`) implements a **3-layer fallback** for project-local → user-global → bundled adapter files keyed by capability name (`browser`, `mcp`, `visual-diff`, ...). `.wholework.yml` exposes per-project capabilities. Steering Documents (`product.md`, `tech.md`, `structure.md`) carry the cross-skill conventions that Osmani calls "intent written down."

The **distinctive piece** is the Spec file (`docs/spec/issue-N-*.md`). It is created by `/spec` as a design artifact, but each subsequent phase appends a Retrospective and a rotating Phase Handoff (`modules/phase-handoff.md`), so the Spec doubles as cross-phase memory. Osmani's "the repo doesn't forget" is realized at sub-issue granularity rather than repo-global.

### 2.3 Sub-agents — fully covered, with diversity

`agents/` ships eight sub-agents, each scoped to a distinct role:

| Agent | Phase | Role |
|-------|-------|------|
| `issue-scope`, `issue-precedent`, `issue-risk` | Issue creation (L/XL) | Parallel investigation along three axes |
| `review-bug`, `review-spec`, `review-light` | Review | Maker/checker split — code is not graded by the writer |
| `frontend-visual-review` | Verify (visual) | Structured-JSON visual diff grading |
| `orchestration-recovery` | Recovery (Tier 3) | Unknown-failure diagnostician producing a recovery-plan JSON |

The `claude -p --dangerously-skip-permissions` pattern in every `run-*.sh` wrapper gives each phase a fresh context (`skills/code/SKILL.md`, `skills/review/SKILL.md`), preventing the maker-grades-itself failure mode at the *process* level rather than just the prompt level. `/code` carries an internal **Tier 0 → Tier 3 escalation** (`skills/code/SKILL.md:239`) where structured test-failure recovery is attempted before handing off to the recovery sub-agent.

This is the building block where Wholework looks *closest* to the Loop Engineering ideal. The "verifier decides if the loop is done" pattern that Osmani attributes to Claude Code's `/goal` is partially implemented: a separate-context `/verify` invocation decides phase/done, not the `/code` session that wrote the change.

### 2.4 Memory — multi-layer, durable

Wholework persists state on at least six distinct surfaces:

1. **GitHub Issues/Labels/PRs** — the public SSoT (`docs/workflow.md § Label Transition Map`)
2. **Spec file + Retrospective + Phase Handoff** — per-Issue cross-phase memory
3. **`.tmp/auto-state-N.json`, `.tmp/auto-batch-state.json`** — checkpoint files for resume (`/auto --resume`, `/auto --batch --resume`)
4. **`.tmp/auto-events.jsonl`** — append-only event stream via `scripts/emit-event.sh` with `session_id`-keyed records and `flock`-based concurrency
5. **`docs/reports/orchestration-recoveries.md`** — append-only cross-Issue recovery log, mined by `/audit recoveries`
6. **`docs/reports/auto-events-rollup-YYYY-MM-DD.md`** — daily curated rollups generated by `scripts/auto-events-rollup.sh`

This is denser than the typical `STATE.md` pattern in the Zenn article: Wholework separates *recoverable session state* (`.tmp/*.json`), *durable per-Issue memory* (Spec), and *cross-Issue learning* (orchestration-recoveries + audit retro-proposals). The auto-memory under `~/.claude/projects/.../memory/` adds a seventh, user-level surface that survives across repos.

The one design constraint to note: **`acting_on:` style multi-loop collision detection is absent.** Wholework relies on GitHub labels + `worktree-merge-push.sh`'s lock, not on cross-session presence keys. This matters once multiple long-running loops touch the same repo concurrently.

### 2.5 Plugins / Connectors — GitHub-CLI-deep, cross-tool-shallow

Wholework ships as a Claude Code Plugin (`.claude-plugin/plugin.json` v0.3.0) and is self-hosting (auto-memory `project_selfhost.md`). The de-facto connector layer is the `gh` CLI plus a stable of helper scripts: `gh-graphql.sh`, `gh-issue-edit.sh`, `gh-issue-comment.sh`, `gh-label-transition.sh`, `gh-check-blocking.sh`, `gh-pr-merge-status.sh`, `gh-pr-review.sh`. Capability-resolved adapters extend the surface for `browser`, `lighthouse`, `visual-diff`. `skills/spec/SKILL.md` even names Figma MCP tools in its `allowed-tools` for design-fetch.

What is **not** present: Slack/Linear/email/calendar connectors. The loop's outbound channel is GitHub itself (Issue comments, PR descriptions, labels). For Pattern A/B mid-scale migrations on a single team's repo this is sufficient — Issues *are* the human-visible inbox. For multi-team or long-tail observation, the absence is real.

### 2.6 Automations / heartbeat — only event-driven, no cron

The biggest gap. Wholework has:

- **Event-driven automation**: `.github/workflows/kanban-automation.yml` reacts to `issues.types: [labeled]` and moves the project card.
- **One-shot orchestrator**: `/auto` and `/auto --batch` chain phases procedurally — but the user types the slash command. There is no `schedule:` block in `.github/workflows/`.
- **Watchdog as heartbeat-detector**: `scripts/claude-watchdog.sh` emits `watchdog_kill` events on silence-window timeouts (default 1800s), which is the *opposite* of a heartbeat — it kills hangs rather than wake the loop.

There is no equivalent of Claude Code's `/loop <interval>` or `/goal <condition>` primitive embedded in Wholework. The Zenn article's Daily Triage / CI Sweeper / Dependency Sweeper patterns have no Wholework counterpart — they would have to be wired by the user via cron, GitHub Actions `schedule:`, or claude-code-host scheduling outside the Skills surface.

This matches Wholework's stated positioning (`docs/reports/wholework-positioning-memo-2026-06-13.md`): the anchor case is *mid-scale modernization* with a human in the loop, not a 24/7 unattended sweep. But it also means the "loop" is currently a half-loop — work is dispatched by `/auto`, processed autonomously, then *returns to the human* rather than the system finding the next thing to do.

## 3. Score sheet

| Loop Engineering block | Wholework status | Evidence |
|------------------------|------------------|----------|
| 1. Automations / scheduling | **Partial — orchestrator only** | `/auto`, `/auto --batch`, watchdog. No cron / `/loop` / `/goal`. |
| 2. Worktrees | **Full** | `modules/worktree-lifecycle.md`, atomic `worktree-merge-push.sh`, XL parallel. |
| 3. Skills | **Full** | 10 skills, 36 modules, adapter-resolver, Steering Documents, `.wholework.yml`. |
| 4. Plugins / Connectors | **Partial — GitHub-deep** | `gh` CLI + adapters + Figma MCP. No Slack/Linear/email. |
| 5. Sub-agents | **Full + recovery tier** | 8 agents; per-phase context isolation; Tier 0→3 escalation. |
| 6. Memory | **Full, multi-layer** | Spec + retro + handoff; `.tmp/*.json`; events.jsonl; recoveries.md; rollups. |

In Loop Engineering terms, Wholework is a **harness, plus a sequential orchestrator with verifier sub-agents and durable memory** — everything needed to *act* on a single discovered piece of work. What it lacks is the **discovery and re-firing layer**: the part of the loop that decides "there is something new to do, dispatch it" without a human typing a slash command.

## 4. Extension opportunities — graded by fit with Wholework's positioning

Wholework's positioning memo is explicit that fleet-class 100+ concurrent execution is out of scope (Anchor: mid-scale modernization, 5–10 concurrent, $10K/10 days/50–100 PRs). The proposals below are filtered through that lens — they extend Wholework *toward* a fuller loop without breaking the subscription-auth / GitHub-native moat.

Two design principles narrow the proposal space further:

- **Local-first execution.** Loop-fire happens inside a Claude Code session on the user's machine (subscription-auth preserved). Remote execution via Claude Code Action / GitHub Actions `schedule:` is technically possible (the action accepts a `claude_code_oauth_token` secret) but is deferred until the per-skill *execution-surface* question is solved separately. Each Skill differs in how cleanly it crosses local↔CI — `${CLAUDE_PLUGIN_ROOT}` resolution, `.tmp/` ephemerality, `run-*.sh` `claude -p` subprocesses, git worktree lifetime, MCP server availability — and `/auto` in particular carries most of that risk. CI execution is a later track, not part of E1–E4.
- **Tail extension over new primitives.** Wholework's existing design pattern (Phase Handoff written at each phase's *exit*, read at the next's *entry*) generalizes: the loop is built by *folding the existing workflow's terminus back to its entry under a budget*, not by inserting a new top-level orchestrator. This keeps the existing human-gate placement (PR review, AC confirmation, retro-proposal approval) intact and reuses Spec/retrospective/event-log infrastructure unchanged. E1–E4 below are therefore reframed as *tail extensions of existing skills*, not new skills.

### 4.1 High fit — tail extensions of existing skills

These extend the existing workflow's tail under an opt-in budget. No new top-level skills. No new schedulers. Everything fires inside the running Claude Code session.

**E3. `/verify` tail — `auto-retry-on-fail` (the smallest first step)**
Today's `/verify` FAIL path: `gh issue reopen` + remove all `phase/*` → return control to the user, who manually picks `/code --patch` vs `/code --pr` vs `/spec`. Extension: when `.wholework.yml: auto-retry-on-fail` is set (opt-in) and the retry budget is not exhausted, the tail folds back automatically — re-fire `/code` with the same Spec and the captured verify-failure context, then re-run `/verify`. Stop when AC PASS, when `max_iterations` is reached, or when `budget_tokens` is exhausted. The maker/checker split is already structural (`/code` and `/verify` run in separate `claude -p` processes), so the change is *loop wiring*, not agent design. New surface: an `.wholework.yml` flag, a few SKILL.md steps in `/verify`, a retry counter in the Spec retrospective, a `verify_retry_fire` event in `auto-events.jsonl`. This is the closest Wholework analogue of Claude Code's `/goal` and is the recommended first step because it materializes the "tail extension" pattern with the smallest change set.

**E2. `/verify` retrospective tail — `/audit recoveries` auto-fire on threshold cross**
`/audit recoveries` exists today but is user-invoked. Extension: at the tail of `/verify`'s retrospective-proposal writeout, evaluate whether any orchestration-recovery symptom has crossed the frequency threshold (currently 3) and auto-file the improvement Issue inline. Same skill, same retrospective hook, no new entry point. Converts "verifier feedback loop" from a manual ritual into a real loop by piggybacking on a step that already runs every verify.

**E1. `/auto --batch` tail — next-cycle seed emission**
Today, `/auto --batch N1 N2 ...` finishes a batch and stops. Extension: at the batch's tail, optionally run a lightweight scan (`/audit drift --since=<batch start>` + `/audit fragility --since=<batch start>` + filter for `audit/*` Issues newly created since batch start) and emit a `next-cycle.json` listing the next batch's candidate Issue numbers. The user (or a follow-up `/auto --batch --resume`) picks it up next session. This is the Daily Triage pattern from Osmani's loop — but expressed as "each batch leaves the seed for the next" rather than "a cron decides what to do." No `schedule:` block, no Actions, no API-key concern.

**E4. Phase-transition tail — heartbeat as side-effect, not a separate reporter**
Each `/auto` phase transition already emits an event to `auto-events.jsonl` and updates `phase/*` labels. Extension: at each transition's tail, append one line to `docs/reports/loop-state-YYYY-MM-DD.md` summarizing the repo-wide phase snapshot derived from `scripts/reconcile-phase-state.sh`. No separate scheduled reporter — the heartbeat is a side-effect of the workflow advancing. Reading the file gives the "look before stepping" surface (Zenn article's `STATE.md`); writing it costs essentially nothing per transition.

### 4.2 Medium fit — touch the connectors block

These require new connectors but stay in scope.

**E5. Slack/Linear notification adapter**
Add `notify-adapter.md` to the capability-resolver chain. Sites of invocation are already named: `/verify` FAIL, `/review` MUST findings, `/auto` Tier 3 recovery success, `/audit recoveries` threshold-crossing. The adapter is a thin shim over an MCP server (slack-mcp, linear-mcp). Distinguishes Wholework from "GitHub-only" by recognising that GitHub is the SSoT but not always the channel humans read. Confine to outbound only — inbound triggers stay GitHub-native.

**E6. MCP-bundling plugin distribution**
The Zenn article makes the point that plugin = distribution form, skill = authoring form. Wholework distributes skills via Claude Code Plugin already, but project-local adapters require manual install under `.wholework/adapters/`. A bundled `wholework-connectors` plugin that ships browser-adapter + lighthouse-adapter + (optional) slack/linear MCP servers as one install reduces onboarding from "edit `.wholework.yml` and copy files" to one `claude plugin install`.

### 4.3 Speculative fit — autonomy-tier explicitization

These touch governance, which is Wholework's core differentiator.

**E7. `.wholework.yml: autonomy:` field — L1/L2/L3 tiers**
The Zenn article's L1 Report / L2 Assisted / L3 Unattended frame is already implicit in Wholework's routes: `/review --review-only` is roughly L1, `/auto` patch route is L2, `/auto --batch` is L3. Naming the tiers explicitly (and gating tail-extension behavior like E3's `auto-retry-on-fail` behind tier ≥ L2) would let teams adopt loop semantics incrementally without surprises. Pairs naturally with E4's transition-tail heartbeat.

**E8. Multi-loop collision detection (`acting_on:` keys)**
The Zenn article's `grep "acting_on:" state-*.md | sort | uniq -d` collision check has no Wholework counterpart. Today, two concurrent `/auto N` invocations on the same Issue would race on the worktree lock and on phase labels. A presence file under `.tmp/auto-lock-<issue>-<sid>` written at Step 1 of `/auto` and checked at every checkpoint resume would close the gap. Only meaningful once E1/E3 generate scheduled fire.

**E9. Token budget gates (`token_daily_budget`)**
`claude-watchdog.sh` enforces a *time* budget per invocation. A *token* budget across a calendar day would protect users from runaway tail-extension loops once E3 lands and `auto-retry-on-fail` starts firing automatically. Wire as a hook fired before every `run-*.sh` invocation; on exceed, log to `auto-events.jsonl` and exit with a defined code so `/audit recoveries` picks it up.

### 4.4 Out of scope (consistent with `wholework-positioning-memo-2026-06-13.md`)

Listing these explicitly to preempt scope creep:

- **Fleet-class 100+ concurrent execution** — Managed Agents territory; would break the subscription-auth moat.
- **Loop-as-product orchestrator separate from Wholework** (e.g., a `wholework loop` daemon, a new `/goal`/`/loop` top-level skill) — Wholework's surface should remain *Skills + GitHub*, and loops are built by extending existing skills' tails, not by inserting a new orchestrator.
- **CI-driven scheduled execution (Claude Code Action / GitHub Actions `schedule:`) for E1–E4** — deferred, not rejected. The blocker is a separate per-skill "execution surface" question (which Skills run cleanly in a runner vs. require a local session) that should be answered before scheduling lands. Local-first is the explicit starting point.
- **Interactive single-task UI inside the loop** — interactive sessions are Cursor/Claude Code's job; the loop's role is unattended dispatch.

## 5. The harder question Osmani raises — does this change the way Wholework should be sold?

Osmani's core argument has two halves. The first ("the building blocks ship in the product now, so loops are a design problem not a tooling problem") is *fully aligned* with Wholework's GitHub-native, no-extra-service stance. The second ("loops sharpen verification debt, comprehension debt, and cognitive surrender") is where Wholework's differentiation gets sharper, not blunter.

Re-reading `docs/product.md` after Osmani:

- **"Spec as cross-phase memory"** is the comprehension-debt countermeasure: a human and a future session can read what each phase decided and why.
- **"Human review gates as first-class"** is the cognitive-surrender countermeasure: the loop does not collapse the gate, it routes through it.
- **"Post-merge verification (`/verify`)"** is the verification-debt countermeasure: "done" is a claim made by code; `/verify` turns it into a check.

A useful framing for the product narrative going forward: **Wholework is not "build me a loop." It is "build the harness that makes someone else's loop trustworthy."** The 5 blocks ship in Claude Code; the verification rigor, the GitHub-visible audit trail, and the spec-as-memory practice are what Wholework adds on top.

That framing should survive the introduction of E1–E4: tail extensions are fire control on top of the existing harness, not a replacement for human gate placement.

## 6. Recommended next actions

In priority order, sized against the current backlog (#583–#591 already filed). Each step is a *tail extension of an existing skill* — no new top-level skills, no new schedulers, all local-first.

1. **Spike: E3 `/verify` tail `auto-retry-on-fail`** — the smallest first step. Adds an opt-in `.wholework.yml` flag, a few SKILL.md steps to `/verify`, a retry counter in the Spec retrospective, and one new event type. Proves the tail-extension pattern in the place where the loop is most clearly half-closed today (FAIL → human). Cap with `max_iterations` and `budget_tokens`.
2. **Spike: E2 `/verify` retrospective tail auto-fire** — piggyback on the same retrospective hook E3 modifies. Threshold-cross detection moves from `/audit recoveries` user-invocation to a side-effect of every verify run.
3. **Design: E7 `.wholework.yml: autonomy:` field** — name the tiers before tail-extension behavior compounds, so E3's `auto-retry-on-fail` and later additions have a gate to live behind.
4. **Spike: E4 phase-transition tail heartbeat** — append one line per transition to `docs/reports/loop-state-*.md` derived from `reconcile-phase-state.sh`. No separate reporter; the heartbeat is the workflow's side-effect.
5. **Spike: E1 `/auto --batch` next-cycle seed** — closest to the Zenn article's Daily Triage, but realized as "each batch leaves the seed for the next" rather than a cron. Lands last in this group so the seed has somewhere to flow.
6. **Defer**: E5–E6 (Slack/Linear, MCP-bundled plugin), E8 (multi-loop collision), E9 (token budget), plus the broader CI-execution track (Claude Code Action + per-skill execution-surface declaration) — open as Icebox per the positioning memo's convention; re-evaluate after E1–E4 land.

The cumulative effect of E3 → E2 → E7 → E4 → E1 is the smallest set of additions that lets Wholework run a **complete** Osmani loop end-to-end while staying inside its positioning: the workflow becomes self-feeding by extension, not by replacement. Everything else is optional and should be triggered by evidence, not aspiration.

---

*This memo is analytical; it does not override `docs/product.md` on items where the latter is SSoT. Confirmed extensions graduate from this memo to Issues and (eventually) Steering Documents.*
