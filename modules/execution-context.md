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

**Precedents**: #994 (`/code`'s bats run), #1097 (`/review`'s bats run), #1103 (the Workflow tool
path), #1142 (a fork-executed `/review`).

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
  bullet), `skills/review/workflow-guidance.md` (Pre-flight section), `skills/code/SKILL.md`
  (Behavioral Change Detection foreground-execution note)

Update this list when a skill or module begins reading `modules/execution-context.md` explicitly.
