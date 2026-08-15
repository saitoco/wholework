# costly-step-protocol

SSoT for marking costly/irreversible Implementation Steps in a Spec and for how `/code` must handle them.

## Purpose / Background

`/spec` sometimes pre-authorizes an Implementation Step that is costly (incurs real expense or non-trivial token consumption) or irreversible (has a production/irreversible side effect), on the assumption that `/code` will simply execute it. `/code` runs non-interactively (via `run-code.sh`, `claude -p`, no `AskUserQuestion`), so it has no channel to get a live human confirmation before executing such a step — and has twice independently reconsidered and deferred the pre-authorization instead:

- **#903** (Sonnet 5 watchdog recalibration): `/spec` pre-authorized a new benchmark run; `/code` declined it for cost reasons and substituted log-based reconstruction.
- **#939** (Fable 5 spec silent-window measurement): `/spec` pre-authorized a new `--fable` run; `/code` deferred it for cost, cross-Issue side-effect, and authorization reasons.

In both cases the Issue's acceptance criteria were written assuming the step *would* execute, so `/code`'s deferral left those AC failing `/verify` — a candidate for the auto-retry loop, since nothing recorded that the gap was an intentional deferral rather than an implementation bug.

This is the producer-side counterpart to **#947** (`/verify`'s documented-deferral escape hatch, `skills/verify/SKILL.md` Step 11(b)): #947 detects an already-occurred deferral reactively, at `/verify` time. This module prevents the ambiguity that made the deferral undetectable in the first place, proactively, at `/spec`/`/code` time. The two are complementary, not overlapping — #947's detection logic is unchanged by this module; it already reads the `## Code Retrospective` > `### Deviations from Design` location this module's Consumer contract writes to.

## Marker Format

Append the following HTML comment to the end of the Implementation Step line in the Spec:

```
<!-- spec-approval-needed: cost=<low|high>, reversibility=<low|high> -->
```

Two-value scale only (`low`/`high`) — matches the Issue #951 approach (a) example (`cost=high, reversibility=low`). Extending to a finer-grained scale is out of scope for this module.

**Tagging criterion**: apply the marker only when a step is `cost=high` or `reversibility=low`. Routine steps — a git commit, a file edit, a CLI call with no real expense — are not marked.

**Attribute values are currently inert metadata**: the Consumer Contract below triggers identically on marker presence alone — `cost`/`reversibility` values are not consumed by any branching logic today. They exist as a human-readable record of *why* the step was flagged (useful when a human reviews the Deferral Protocol later), not as a machine-actionable signal. Wiring finer-grained consumer behavior to these values (e.g. auto-resolving `reversibility=high`-only steps to a lighter-weight tier) is out of scope for this module.

## Producer Contract (`/spec`)

When authoring an Implementation Step that triggers a new costed-model run (e.g. a new `--fable` run, a new `--opus` run) or a production/irreversible side effect (e.g. a mutating call to a production API), `/spec` must:

1. Append the `spec-approval-needed` marker to that step, with `cost`/`reversibility` set per the tagging criterion above.
2. Add a corresponding **Deferral Protocol** entry to the Spec's `## Notes` section describing what `/code` should do instead if it defers the step — e.g., "record the planned command and arguments in the Code Retrospective and do not execute it."

Both are required together: a step marked but with no Deferral Protocol leaves `/code` to invent its own substitute action; a Deferral Protocol with no marker risks `/code` never noticing the step needs special handling at all.

## Consumer Contract (`/code`)

Before executing a step carrying the `spec-approval-needed` marker:

- **Interactive mode**: confirm via `AskUserQuestion` before executing. If the user declines, apply the non-interactive fallback below instead of inventing a substitute action.
- **Non-interactive mode**: treat as a High-Stakes Decision under `modules/ambiguity-detector.md`'s Three-Tier Policy (skip tier) — do not execute the step. Instead, follow the Spec's Deferral Protocol and record the deferral under `## Code Retrospective` > `### Deviations from Design`, tagged (e.g. `(deferred — spec-approval-needed)`). Leave the marked Implementation Step and its marker intact in the Spec (do not let a later "sync Spec to actual implementation" pass strip it), and leave the associated acceptance criteria unchecked (`- [ ]`) rather than marking it as passing.
- **Deferral Protocol missing** (Producer Contract violation — reachable via pre-existing or hand-written Specs): if the marker is present but no matching Deferral Protocol entry exists in the Spec's `## Notes`, do not invent a substitute action. Apply the same non-interactive handling above — record the planned action (command/arguments, or a one-line description of the step) verbatim under `### Deviations from Design`, do not execute it, and leave the associated AC unchecked.

The deferral record lands in the same location `/verify` Step 11(b) (Documented deferral detection) already reads — `skills/verify/SKILL.md` requires no change for this module to take effect.

## Notes

- Why not an interactive fallback from `/code` to a parent session (rejected alternative (b))? `/code`'s non-interactive execution has no guaranteed live interactive parent — `/auto --batch` and scheduled runs are normal cases with no human watching. Introducing a "fall back to the parent session" channel would contradict the premise of non-interactive execution itself. The Three-Tier Policy's skip tier already handles this exact shape of problem (a high-risk decision that cannot be made non-interactively) via one more High-Stakes Decision entry, with no new mechanism required.
- **Code-side auto-retry (`run-code.sh`'s `auto-retry-on-fail`) is out of scope for this module.** Unlike `/verify`'s auto-retry gate, it has no documented-deferral escape hatch analogous to #947. In the narrow case of an Issue whose Implementation Steps consist entirely of one deferred `spec-approval-needed` step, `reconcile-phase-state.sh`'s `matches_expected` check could still classify the run as a silent no-op and trigger a retry that defers again. Addressing this is deferred to a follow-up Issue rather than this module.
