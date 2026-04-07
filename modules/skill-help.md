# skill-help

Shared module for displaying skill help when the `--help` flag is specified.

## Purpose

Output skill usage information to the terminal when the `--help` flag is specified. Extracts information from the SKILL.md frontmatter and body and formats description, argument list, option list, and usage examples for output.

## Input

Information readable from the calling skill:

- **Frontmatter**: `name` (skill name), `description` (skill description)
- **SKILL.md body**: Argument parsing section (sections containing flag definitions, option descriptions, and usage examples)

## Processing Steps

1. Get `name` and `description` from the calling skill's frontmatter (read from the already-loaded SKILL.md)
2. Scan the SKILL.md body and extract a list of flags and options starting with `--`
   - Collect each flag and its description (extracted from bullet points or descriptive text in the body)
   - Include `--help` itself as an option
3. Extract usage examples (from backtick-wrapped notation in the `description` field, or from examples in the body)
4. Output help information following the output format below
5. After output, do not execute the remainder of the skill's processing (skip subsequent steps in the calling skill)

## Output Format

Output as plain text directly (do not wrap in code fence):

```
## /{name}

{description (original text including backticks)}

**Usage:**
  /{name} {argument summary}

**Options:**
  --help           Show this help
  {flag1}          {description of flag1}
  {flag2}          {description of flag2}

**Examples:**
  /{name} {example1}
  /{name} {example2}
```

- `{name}`: Value of the `name` field in frontmatter
- `{description}`: Value of the `description` field in frontmatter (verbatim)
- `{argument summary}`: Short notation indicating argument types such as issue number, PR number, subcommand, etc. (e.g., `123`, `88`, `[subcommand]`)
- Flag list: Flags and descriptions extracted from the body (may be omitted if not extractable)
- Usage examples: `/name args` format from description, or examples in body (list multiple if available)
