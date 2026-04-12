# domain-loader

## Purpose

Discover and load project-local Domain files from `.wholework/domains/{skill}/`. Enables project-specific behavior customization by reading user-placed Markdown files at skill startup.

## Input

- `SKILL_NAME`: The skill requesting domain files (one of: `spec`, `code`, `review`)

## Processing Steps

1. Glob for `.wholework/domains/{SKILL_NAME}/*.md`
2. If no files found: output nothing and return (silent skip)
3. For each discovered file (alphabetical order): Read the file. The content becomes part of the skill's execution context, influencing subsequent steps.
4. Output a summary line: "Loaded N project-local domain file(s) from .wholework/domains/{SKILL_NAME}/"

## Output

Domain file contents loaded into the skill's context. Summary line for traceability.
