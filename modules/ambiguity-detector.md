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
