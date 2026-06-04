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
