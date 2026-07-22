# phase-handoff

Shared module for Phase Handoff read/write between phases of `/auto`.

## Purpose

Each `/auto` phase runs in a forked session with no shared in-context memory. This module provides a lightweight mechanism to carry forward a summary of the current phase's key decisions, deferred items, and notes for the next phase — stored directly in the Spec file (the existing cross-phase memory channel).

The handoff retains only the **latest 1 phase** at a time (rotation): when a new handoff is written, the old one is replaced.

## Phase Handoff Section Format

```markdown
## Phase Handoff
<!-- phase: {phase-name} -->

### Key Decisions
- {decision and rationale}

### Deferred Items
- {item deferred and why}

### Notes for Next Phase
- {what the next phase should pay attention to}
```

- `{phase-name}`: one of `spec`, `code`, `review`, `merge`
- Each subsection: 3–5 bullets as a guideline; omit if nothing to record (write "- None")

## Input

- `SPEC_PATH`: path to the Spec directory (e.g., `docs/spec`)
- `ISSUE_NUMBER`: the Issue number (e.g., `501`)
- `PHASE_NAME`: the current phase name (`spec`, `code`, `review`, `merge`, or `verify`)

## Write Procedure

Calling phases: `spec` (write only), `code` (read then write), `review` (read then write), `merge` (read then write). `verify` does **not** write.

1. **Spec existence check**: Glob `$SPEC_PATH/issue-$ISSUE_NUMBER-*.md`.
   - If no file found: output `[phase-handoff] No Spec found — skipping handoff write.` and return (graceful skip).

2. **Generate handoff content**: Based on the work done in this phase, write a summary with:
   - `### Key Decisions`: 3–5 bullets on the most important design or implementation decisions made (why this approach was chosen over alternatives)
   - `### Deferred Items`: 3–5 bullets on items that were explicitly left for a later phase, follow-up Issue, or post-merge observation
   - `### Notes for Next Phase`: 3–5 bullets on what the next phase should pay special attention to (known risks, ambiguities resolved, constraints discovered)
   - Write "- None" if a subsection has nothing to record

3. **Check for existing handoff section**: Search the Spec file for `^## Phase Handoff`.
   - If found (rotation case): Use the Edit tool to replace the **entire existing `## Phase Handoff` block** (from `## Phase Handoff` through the end of that section — i.e., up to the next `## ` header or end of file) with the new handoff content.
   - If not found: Use the Edit tool to append the new handoff content after the last line of the file.

4. **Include in the same commit**: The handoff write happens in the same step as the retrospective append — stage the Spec file once and commit together.

### Rotation boundary detection

When replacing an existing `## Phase Handoff` section, the section ends at the line immediately before the next `## ` (level-2) heading, or at end of file if no subsequent heading exists. Replace from `## Phase Handoff` through that boundary (exclusive of the next `## ` heading line).

## Read Procedure

Calling phases: `code` (after Step 5 Spec load), `review` (after Step 5), `merge` (after Step 1 Issue fetch), `verify` (after Step 4 Spec load). `spec` does **not** read.

1. **Spec existence check**: Glob `$SPEC_PATH/issue-$ISSUE_NUMBER-*.md`.
   - If no file found: output `[phase-handoff] No Spec found — skipping handoff read.` and return (graceful skip).

2. **Handoff section check**: Search the Spec for `^## Phase Handoff`.
   - If not found: output `[phase-handoff] No handoff from prior phase.` and continue (normal — first run or spec phase with no prior handoff).

3. **Read and apply**: Read the `## Phase Handoff` section content and incorporate it into the current phase's execution context:
   - Review `### Key Decisions` to understand why the previous phase made the choices it did
   - Review `### Deferred Items` to be aware of explicitly deferred work that may affect this phase
   - Review `### Notes for Next Phase` for direct guidance from the prior phase

   Output: `[phase-handoff] Loaded handoff from phase: {phase-name}` (extract `{phase-name}` from the `<!-- phase: {phase-name} -->` marker).

4. **AC cross-reference (Deferred Items staleness check)**: This step is part of the Read Procedure's common processing and therefore applies automatically to all four calling phases (`code`, `review`, `merge`, `verify`) — no per-skill logic is required. `### Deferred Items` is written once by the producing phase and does not update on its own; if the referenced acceptance conditions change out-of-band (a different session, a human's manual follow-up, or a concurrently running skill) after the handoff was written, the stale text would otherwise be surfaced verbatim in this phase's own report. Cross-reference each Deferred Items line against the Issue's current AC checkbox state before using it:
   - For each bullet under `### Deferred Items`, attempt to extract an AC reference: an explicit AC number, an `ac=` index list, or a quoted condition string that matches an Issue checklist line. If no AC reference can be identified in a bullet, leave that bullet as-is (skip the cross-reference for it) — do not guess at a match.
   - Fetch the current Issue body: `gh issue view $ISSUE_NUMBER --json body`.
   - For each extracted AC reference, locate the corresponding checkbox line in the Issue body's Acceptance Criteria list, using the same 1-based index convention as `gh-issue-edit.sh --checkbox`.
   - If the located checkbox is already `[x]`: the item was resolved after the handoff was written. Either exclude that bullet from this phase's own output/report entirely, or — if retaining full text for audit purposes — append `~~` around the bullet text plus the literal string `(resolved after handoff)`, so the resolution is visible without erasing the historical record.
   - If the checkbox is still `[ ]`, or no AC reference could be identified for the bullet: leave the bullet unchanged and continue treating it as an active deferred item.

## Phase Position Asymmetry

| Phase | Read | Write | Reason |
|-------|------|-------|--------|
| spec | No | Yes | First execution phase — no prior phase handoff exists |
| code | Yes | Yes | Intermediate phase |
| review | Yes | Yes | Intermediate phase |
| merge | Yes | Yes | Intermediate phase |
| verify | Yes | No | Last execution phase — no subsequent phase to hand off to |

## Notes

- This module's read/write operations are deterministic (Spec file existence check → Edit/Read). No AskUserQuestion required; safe in `--non-interactive` mode.
- XS route: In `/auto` XS handling, the Spec may not exist at code execution time (it is generated post-code in Step 4b). The Spec existence check (step 1 of both procedures) handles this gracefully — output the skip log and continue without error.
- The handoff section is part of the Spec file and will be included in the worktree branch, committed with the retrospective.
- **Handoff semantics — writer's viewpoint, Issue body is the final authority**: Phase Handoff reflects the producing phase's assessment at the moment it was written, including the AC checkbox state observed at that time. It is not re-synchronized when the Issue changes afterward. When a handoff's `### Deferred Items` (or any other subsection) disagrees with the Issue body's current AC checkbox state, the Issue body is the source of truth — the Read Procedure's AC cross-reference step (above) exists specifically to reconcile this gap for Deferred Items, but the same precedence rule applies to any other observed conflict between handoff text and live Issue state.
