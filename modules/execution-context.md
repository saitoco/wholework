# execution-context

SSoT for skill execution context (fork vs main) determination criteria and per-context constraints.

## Purpose

Wholework skills run in two execution contexts:

- **fork context** — headless `claude -p` process spawned by `run-*.sh`. No prior-session context. `--non-interactive` flag is injected automatically.
- **main context** — in-session execution triggered directly by the user (`/code`, `/spec`, etc.). Runs within the active Claude Code session.

This module is the authoritative reference for:
1. How to detect which context the current execution is in
2. What constraints apply in each context (verify command mode, AskUserQuestion availability)

## Context Detection

Inspect `ARGUMENTS` at skill start:

| Condition | Context |
|-----------|---------|
| `--non-interactive` present in ARGUMENTS | **fork context** |
| `--non-interactive` absent from ARGUMENTS | **main context** |

`--non-interactive` is injected by `run-*.sh` scripts when invoking skills via `claude -p`. It is never passed by direct user invocation.

## Per-Skill Context Table

| Skill | Via `run-*.sh` | Direct invocation | Notes |
|-------|----------------|-------------------|-------|
| triage | — (no wrapper) | main | Always in-session |
| issue | fork (run-issue.sh) | main | L/XL parallel sub-agents also run in fork |
| spec | fork (run-spec.sh) | main | |
| code | fork (run-code.sh) | main | |
| review | fork (run-review.sh) | main | |
| merge | fork (run-merge.sh) | main | |
| verify | — (no wrapper) | main | Always in-session |
| auto | — (no wrapper) | main | Child phases run in fork via run-*.sh |
| audit | — (no wrapper) | main | Always in-session |
| doc | — (no wrapper) | main | Always in-session |

## Context Constraints

### Fork Context (`--non-interactive` present)

| Constraint | Rule |
|------------|------|
| `AskUserQuestion` | **Not available** — the process has no interactive TTY. Calling it would hang indefinitely. Use auto-resolve instead (see `modules/ambiguity-detector.md`). |
| verify-executor mode | **safe mode** — `command` and `build_success` verify commands are skipped (UNCERTAIN). Read-only commands (`file_exists`, `file_contains`, `section_contains`, `grep`, `rubric`, etc.) execute normally; some commands (`http_status`, `github_check`, etc.) run with restrictions. See `modules/verify-executor.md` for the complete per-command safe mode behavior. |
| Error handling | Apply auto-resolve + log policy for ambiguities. Abort only for hard-error conditions (missing Size label, XL without sub-issues, test FAIL after 1 repair on patch route). |

### Main Context (no `--non-interactive`)

| Constraint | Rule |
|------------|------|
| `AskUserQuestion` | **Available** — interactive session with a live user. |
| verify-executor mode | **full mode** — all verify command types execute, including `command` and `build_success`. |
| Error handling | Use `AskUserQuestion` for ambiguities requiring user judgment. |

## Re-invocation Guarantee and Notification-Dependent Waiting

**Definition — re-invocation guarantee**: a background task's completion notification only reaches
a session if the harness re-invokes that session to deliver it. Re-invocation is guaranteed **only
for direct execution inside an interactive session** — a live user turn where the harness is known
to call back.

**Execution surfaces without this guarantee (exhaustive)**:
- headless `claude -p` (the fork context described above — `run-*.sh`-launched processes)
- a Skill launched as a forked execution (`Skill launched as forked execution`)
- the Workflow tool's execution path
- any sub-agent or background Bash process (`run_in_background: true`) started from inside any of
  the above

**MUST rule**: in these execution surfaces, do not end a turn by waiting on a mechanism that
depends on a completion notification to resume — this includes `run_in_background: true`, the
Workflow tool, and any Agent/Task dispatch that returns before the dispatched work completes.
Execute synchronously in the foreground instead.

**Rationale**: a notification that cannot be delivered does not make the phase merely late — it
makes the phase permanently incomplete (a silent no-op), because nothing will ever re-invoke the
session to observe the result.

**Default when undetermined**: if direct interactive execution cannot be confirmed, assume no
re-invocation guarantee and apply the MUST rule above.

**Corollary — an explicit `timeout` does not by itself keep a command in the foreground**: the Bash
tool's `timeout` ceiling is 600000 ms (10 minutes), and a command that runs past it is moved to the
background automatically — from the caller's side indistinguishable from the notification-dependent
wait the MUST rule above forbids. Commands that risk approaching the ceiling must be shortened
instead (for a full bats suite: run it in parallel). If the tool backgrounds a command anyway,
report it as a failure rather than waiting on its completion notification.

**Precedents**: #994 (`/code`'s bats run), #1097 (`/review`'s bats run), #1103 (the Workflow tool
path), #1142 (a fork-executed `/review`), #1213/#1234 (the tool-ceiling corollary — an explicit
`timeout` alone was insufficient because the command itself exceeded the ceiling).

### Wrapper-Level Constraint Injection

The MUST rule above only reaches a phase if that phase's SKILL.md carries an instruction that
surfaces it — and a phase with no full-suite execution instruction of its own has nothing to
carry it. Three generations of prose fixes (#994 for code, #1097 for review, #1213 iteration 0/1
for both) moved or restated the constraint inside SKILL.md prose — #1175 separately added
wrapper-side detection for the review phase without touching the prose — and each time, a phase
without such an instruction reproduced the same silent no-op regardless — most recently `/spec`
(#1130, 2026-08-10), whose SKILL.md has no full-suite execution instruction at all; the agent
chose to run the suite on its own judgment and hit the same wait.

Iteration 2 of #1213 moves the backstop out of SKILL.md prose entirely and injects it at the
layer that starts every wrapper-launched phase process: `scripts/guard-prefix.sh`. All five
wrapper scripts (`run-issue.sh`, `run-spec.sh`, `run-code.sh`, `run-review.sh`, `run-merge.sh`)
source this file and prepend its `GUARD_PREFIX` string to the `PROMPT` passed to `claude -p`. A
paragraph stating the MUST rule (no re-invocation guarantee, do not end a turn waiting on
`run_in_background: true` / the Workflow tool / an Agent or Task dispatch that returns before the
work finishes, run synchronously in the foreground and consume the result within the same turn,
the Bash tool's 600000 ms timeout ceiling and the need to shorten commands that risk it, and
reporting a command as failed immediately if it is backgrounded anyway) lives in that single
string, so it reaches every phase these five wrappers launch **(exhaustive)**: issue, spec, code,
review, merge — including spec, which has no full-suite execution instruction of its own for a
body-level fix to attach to. Other `claude -p` launch paths outside these five wrappers
(`scripts/spawn-recovery-subagent.sh`, the Tier 3 recovery sub-agent dispatched from
`scripts/run-auto-sub.sh`) do not source `guard-prefix.sh` and are not covered by this injection
point; whether they need the same constraint is undecided (#1213 iteration 2 deferred item).

Skills with no wrapper (`verify`, `triage`, `audit`, `doc`, `auto`) are not reached by this
injection point. They normally run in main context (an interactive session with a re-invocation
guarantee — see the Per-Skill Context Table above), where the MUST rule does not apply. But if one
of them is dispatched as a nested `Skill()` call from a fork-context phase (e.g. `/review`'s
Opportunistic Verification dispatching `/verify`), the exhaustive surface list and "Default when
undetermined" clause above still apply, and this injection point does not reach that nested
invocation either.

The SKILL.md-level guards added by earlier generations (`skills/code/SKILL.md` Step 9,
`skills/review/SKILL.md` Step 12.3, `modules/test-runner.md`) remain in place; they were not
removed by this change. They serve a different role: concrete, execution-point guidance for a
phase that does have a full-suite instruction (e.g. how to parallelize a `bats` run into the
timeout ceiling), while the wrapper-level paragraph is a phase-agnostic backstop that does not
depend on any SKILL.md carrying it. This remains prompt-level guidance, not a mechanical
enforcement: #1168 (recorded in `docs/spec/issue-1175-review-background-noop-fix.md`) showed the
same rule present in the prompt yet violated 2/2. The wrapper position raises salience (prompt
head, every phase) but does not remove the need for the detection/recovery side (#1323 detector
signatures, `run-*.sh` auto-retry).

**Recurrence check (2026-08-22, Issue #1443):** `background-notification-wait` recurred in the
review phase (Issue #1271, `docs/reports/orchestration-recoveries.md` 2026-08-22 10:10 UTC entry),
12 days after PR #1332 (this section's iteration 2 injection) merged. Re-confirmed that
`scripts/run-review.sh` unconditionally sources `guard-prefix.sh` and prepends `GUARD_PREFIX` to
`PROMPT` on every `claude -p` invocation (`run-review.sh:251-257`), with no bypass branch — so
#1271's execution path did receive the guard; this is not the same coverage gap as #1130 (where
`/spec` carried no guard text at all before iteration 2). Quantitative background: in the 12-day
window between PR #1332's merge (2026-08-10T06:55:56Z) and #1271, roughly 51 PRs were created in
this repository (`gh pr list --state all --search "created:2026-08-10..2026-08-22" --limit 300`),
and this pattern recurred exactly once, recovered automatically by Tier 3 recovery
(`agents/orchestration-recovery`, cause=`background-notification-wait`, Outcome: success) with no
manual intervention and no lost work. **Verdict: maintain.** This residual rate is consistent with
what this section already states — the injected paragraph is prompt-level guidance, not mechanical
enforcement, and #1168 already demonstrated non-zero violation even when present — so a single
Tier-3-recovered recurrence in 51 PRs does not indicate the three-tier detection/recovery design is
insufficient. One narrow, separately-addressed gap was found during this check: `/review` Step 10
dispatches the orchestrator's own `Task(...)` sub-agent calls, and no SKILL.md guidance explicitly
named that dispatch as requiring foreground/synchronous handling — the existing Step 10-adjacent
prose (`## Non-Interactive Mode Behavior`) only covered commands run *by* the review sub-agents
themselves. See `skills/review/SKILL.md` Step 10 for the added reminder. Re-evaluation trigger:
reassess this verdict if `background-notification-wait` recurs again in any phase, or if the
observed rate materially exceeds this window's ~1-in-51 approximation.

## How to Reference

In a skill's SKILL.md, reference this module at the step where context affects behavior:

```
Read `${CLAUDE_PLUGIN_ROOT}/modules/execution-context.md` and determine the current
context from ARGUMENTS. If `--non-interactive` is present, apply fork context constraints
(no AskUserQuestion, safe mode for verify-executor). Otherwise apply main context behavior.
```

The `code` skill uses this pattern in its Mode Detection section and Error Handling
section. The `verify` skill always runs in main context and does not need to check.

## Callers

Skills/modules that explicitly read this module:

- Fork/main context detection pattern (top of this file): none (SSoT reference — skills use the
  detection pattern described above without explicitly reading this file; referenced by
  `docs/tech.md` for the fork context policy)
- "Re-invocation Guarantee and Notification-Dependent Waiting" section: `modules/test-runner.md`
  (Step 2 non-interactive Note), `skills/review/SKILL.md` (Non-Interactive Mode Behavior Foreground
  bullet; Step 12.3 Lightweight Re-check local reminder), `skills/review/workflow-guidance.md`
  (Pre-flight section), `skills/code/SKILL.md` (Step 9 execution surface constraint, stated once
  before the Behavioral Change Detection subsection)
- `scripts/guard-prefix.sh` — not a reader of this module; distributes this section's MUST rule
  into the prompt for every phase, via the `GUARD_PREFIX` string the five `run-*.sh` wrappers
  prepend to `PROMPT` (see "Wrapper-Level Constraint Injection" above)

Update this list when a skill or module begins reading `modules/execution-context.md` explicitly.
