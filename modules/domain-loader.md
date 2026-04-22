# domain-loader

## Purpose

Discover and load Domain files for the calling skill from two sources: bundled Domain files (`${CLAUDE_PLUGIN_ROOT}/skills/{SKILL_NAME}/*.md`) with conditional loading, and project-local Domain files (`.wholework/domains/{SKILL_NAME}/*.md`) with unconditional loading.

## Input

- `SKILL_NAME`: The skill requesting domain files (one of: `spec`, `code`, `review`, `issue`, `verify`, `doc`)
- Context variables available from calling skill: `SPEC_DEPTH`, `ARGUMENTS`; `marker:` and `capability:` conditions are evaluated by reading `.wholework.yml` directly if needed

## Processing Steps

### Phase 1: Bundled Domain Files

1. Glob `${CLAUDE_PLUGIN_ROOT}/skills/{SKILL_NAME}/*.md`
2. If no files found: skip to Phase 2
3. For each file (alphabetical order):
   a. Read the file
   b. If `type: domain` is absent from frontmatter: skip this file
   c. If `skill:` field is an array (e.g., `skill: [spec, issue]`): skip if SKILL_NAME is not in the array
   d. If `load_when:` is absent: load unconditionally (backward compatible)
   e. If `load_when:` is present: evaluate all typed keys with AND semantics. Load only when all specified keys evaluate to true (see `## load_when Evaluation` below)

### Phase 2: Project-local Domain Files

1. Glob `.wholework/domains/{SKILL_NAME}/*.md`
2. If no files found: output nothing and return (silent skip)
3. For each discovered Markdown file (alphabetical order): Read the file. The content becomes part of the skill's execution context, influencing subsequent steps.

### Summary Output

Output a summary line: "Loaded N bundled + M project-local domain file(s) for {SKILL_NAME}"
(N = bundled files loaded in Phase 1; M = project-local files loaded in Phase 2; omit the phrase for zero-count sources)

## load_when Evaluation

Evaluate each specified key. All specified keys must evaluate to true (AND semantics). Unspecified keys are ignored.

| Key | Value Form | Evaluates to true when |
|-----|-----------|----------------------|
| `spec_depth` | `{level}` | `SPEC_DEPTH` equals `{level}` (e.g., `spec_depth: full` → true if `SPEC_DEPTH=full`) |
| `capability` | `{name}` | `capabilities.{name}: true` in `.wholework.yml`; for `capability: mcp`, true if `capabilities.mcp` list is non-empty |
| `file_exists_any` | `[path1, path2]` | Any listed path exists (OR within key; use Glob check) |
| `marker` | `{key}` or `[key1, key2]` | Any listed key is `true` in `.wholework.yml` (OR within key) |
| `arg_starts_with` | `{prefix}` | `ARGUMENTS` starts with `{prefix}` |

**AND semantics**: when multiple keys are specified, all must evaluate to true. Example: `file_exists_any` AND `marker` both must be true for the file to be loaded.

**`skill:` array handling**: when `skill:` is a string, match exact equality. When `skill:` is an array (e.g., `skill: [spec, issue]`), match if SKILL_NAME appears in the array.

## Output

Domain file contents loaded into the skill's context. Summary line for traceability.
