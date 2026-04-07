# Codebase Cross-Cutting Investigation

## Purpose

Investigate a specified target across the codebase to perform structural analysis, collect similar patterns, and identify files to change.

## Input

The caller provides the following information in the prompt:

- **Investigation target**: description of the files, directories, or components to investigate
- **Investigation aspects** (one or more of the following):
  - Structural analysis: dependencies of the target, callers, impact scope
  - Similar patterns: similar implementations in the existing codebase, naming conventions, design patterns
  - Files to change: list of files that need to be modified to implement the requirements
- **Context**: Issue requirements, Spec content, etc. (optional)

## Processing Steps

1. Use Glob to understand the file structure
2. Use Grep to search for related patterns (function names, class names, keywords)
3. Use Read to check the content of related files
4. Based on the investigation aspects:
   - **Structural analysis**: track dependencies, imports/requires, identify callers
   - **Similar patterns**: collect naming conventions, error handling, design patterns
   - **Files to change**: identify affected files and summarize change content
5. Organize results according to the output format

## Output Format

```markdown
## Investigation Results

### Files Found

| File | Relevance | Summary |
|------|-----------|---------|
| path/to/file.ext | high/medium/low | This file's role and relationship to the investigation target |

### Patterns and Structure

- Pattern 1: description
- Pattern 2: description

### Findings

Summary of investigation results and information useful for the caller's decision-making.
```
