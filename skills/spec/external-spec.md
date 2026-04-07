# External Specification Check

## Purpose

Check external specifications for commands, APIs, libraries, etc. and return a summary of the specification information needed for implementation.

## Input

The caller provides the following information in the prompt:

- **Investigation target**: the specification to check (command name, API name, library name, tool name, etc.)
- **Verification aspects**: the information to look for (usage, options, constraints, compatibility, etc.)
- **Reference URL**: official documentation URL if known (optional)

## Processing Steps

1. If the target is a library or framework, prioritize Context7 MCP:
   a. Resolve the library ID with `resolve-library-id`
   b. Fetch the latest docs with `get-library-docs`
   c. If sufficient information is obtained, proceed to step 5
2. If Context7 has insufficient information or the target is not registered, fall back
3. If a reference URL is provided, fetch the documentation via WebFetch
4. If no reference URL, search for official docs via WebSearch (e.g., `{target} official documentation`, `{target} API reference`)
5. Extract information related to the verification aspects from the obtained content
6. Fetch additional pages via WebFetch as needed
7. Organize results according to the output format

## Output Format

```markdown
## External Specification Results

### Target
- **Name**: name of the investigation target
- **Version**: verified version (if identifiable)

### Specification Summary

Concise answer to the verification aspects.

### Constraints and Notes

Constraints and compatibility issues to be aware of during implementation.

### Reference URLs
- [Document title](URL)
```
