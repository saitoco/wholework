# ambiguity-detector

Pattern table for detecting ambiguous expressions in Issue requirements.

## Purpose

Provides a pattern table for detecting ambiguous expressions in Issue requirements and acceptance criteria. The calling skills (`/issue`, `/spec`) reference this table to extract ambiguity points.

## Input

Available from the calling skill:

- **Issue requirement text**: Background, purpose, and acceptance criteria from the Issue body

## Pattern Table (Examples)

| Pattern | Example | What to Ask | Information to Research |
|---------|---------|-------------|------------------------|
| Unclear subject | "confirm", "check" | Who? (Claude / user / automated) | Existing skill responsibility patterns |
| Unclear timing | "when complete", "as appropriate" | When? (at PR creation / after merge / after production confirmation) | Workflow definition, phase label transitions |
| Unclear criteria | "appropriately", "correctly", "without issues" | What constitutes achievement? | Acceptance condition patterns in similar Issues |
| Unclear scope | "handle", "improve" | What specifically? | Affected files, module dependencies |
| Unclear condition | "as needed", "depending on the case" | Under what conditions? | Existing conditional branch patterns |
| Missing requirements | Input/output, error handling, UI, etc. are missing | What are the specific specs? | Implementation patterns for similar features |

## Usage

The calling skill references the table above and extracts ambiguity points up to the detection limit based on the Issue's Size.

### Size Routing Table (exhaustive)

| Size | Detection Limit | Auto-Resolution |
|------|----------------|----------------|
| XS/S/M | Max 3 | Dynamic (0-3) |
| L/XL | Max 5 | Dynamic (0-5) |
| Unset | Max 3 | Dynamic (0-3) |

The clarification question and Issue update procedures after extraction are described in each skill's SKILL.md.

## Non-Interactive Mode Handling

When invoked via `run-*.sh` with `claude -p --dangerously-skip-permissions`, skills operate in **non-interactive mode** (signaled by `--non-interactive` in ARGUMENTS). In this mode, `AskUserQuestion` is unavailable — the process would hang waiting for stdin that never arrives. Instead, apply the following three-tier policy at every decision point:

### Three-Tier Policy

**1. Auto-resolve** (default for most ambiguity points)

Adopt the most reasonable default choice using model judgment and record it in the Auto-Resolve Log:

```markdown
## Autonomous Auto-Resolve Log

- **[chosen option]** — reason: [model judgment rationale]
  - Other candidates: [unchosen options]
```

Auto-Resolve Log placement (per skill):
- `code` / `verify` phases: append to the Spec's retrospective section (`$SPEC_PATH/issue-$NUMBER-*.md`)
- `issue` / `spec` phases: post as an issue retrospective comment via `gh-issue-comment.sh`
- `review` / `merge` phases: post as an issue comment (or PR comment if no issue number)

Model judgment heuristics:
- Prefer the least-risk option (fewest downstream side effects)
- Prefer options consistent with existing codebase patterns
- When both options are safe, prefer the simpler one
- When in doubt, use skip (see tier 2) if the skill can continue without the decision

**2. Skip** (for High-Stakes Decisions)

Output a warning message and continue the main workflow without executing the risky action. The user can perform the skipped action manually afterward.

High-Stakes Decisions (exhaustive list — skip these in non-interactive mode):
- **Sub-issue splitting**: creating sub-issues from a parent issue (irreversible structural change; high cost if wrong)
- **Bulk approvals**: approving multiple issues/PRs at once in `--backlog` flows (high blast radius)
- **Optional section additions**: adding optional steering document sections during `/doc` creation (user preference; safe to defer)
- **Size downgrade from XL to L**: requires human judgment on scope; skip and retain XL label

Warning message format:
```
[non-interactive mode] Skipping high-stakes action: {action description}
To perform this action, run `/{skill} {number}` interactively.
```

**3. Hard-error abort** (for prerequisites that cannot be auto-resolved)

Some conditions must exit with a non-zero exit code because proceeding would corrupt the workflow:
- Size not set (code skill: cannot determine patch vs. pr route)
- Size is XL without sub-issue splitting (code skill: XL requires splitting before coding)

These are documented in each skill's own error handling section and are outside the scope of this module's auto-resolve guidance.
