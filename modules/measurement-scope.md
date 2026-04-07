# measurement-scope

Guidelines for documenting measurement scope in Spec quantitative data.

## Purpose

Provides guidelines for including measurement scope (target directory, file types, exclusion conditions, etc.) alongside quantitative survey results (file counts, line counts, grep hit counts, etc.) recorded in Specs. Without documented scope, implementation divergence can occur when re-measuring with different criteria.

## Input

Read and referenced by the calling skill (`/spec`) when recording quantitative data in Specs.

- **Quantitative data**: File counts, line counts, grep hit counts, occurrence locations, etc.

## Processing Steps

When recording quantitative survey results in Specs, follow these rules.

**Rule**: Always include measurement scope alongside numerical data. Without clear scope, implementers re-measuring with different scope will get different numbers, causing rework.

**Format**: Immediately after the number or in the table header, explicitly state the following (examples):

- **Scope**: "All files", ".md files only", "under `skills/` only", ".md files under `modules/`", etc.
- **Exclusions** (if applicable): "excluding `node_modules/`", "excluding `.tmp/`", "excluding test files", etc.
- **Measurement command** (when reproducibility is required): The actual grep/find command used

**Good examples:**

```
Scattered file count: 22 (under `~/.claude/`, .md files only, excluding `docs/spec/`)
```

```
| Path constant | Scattered file count (all files, excluding `node_modules/`) |
|--------------|-------------------------------------------------------------|
| `~/.claude/` | 22 |
```

**Bad example:**

```
Scattered file count: 22
```

(Scope is unclear; divergence can occur at implementation time if "all files yields 33 files")

## Output

Quantitative data recorded in Specs by the calling skill, with measurement scope included alongside.
