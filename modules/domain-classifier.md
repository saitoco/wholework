# domain-classifier

## Purpose

Classify an improvement proposal against a list of pre-loaded Domain files and return the matching domain name, rewrite path, and ambiguity information. Designed as a composable module: the calling skill runs `domain-loader.md` first, then passes the loaded content to this classifier. The classifier performs no file I/O.

## Input

- **Improvement proposal text**: free-form text (typically an Issue body or excerpt) describing the change being proposed
- **Loaded Domain file contents**: list of Domain file contents already loaded into context by `domain-loader.md` (frontmatter parsed). Only Domain files that declare `applies_to_proposals` are classification candidates; files without this block are skipped.

Each qualifying Domain file's `applies_to_proposals` block provides:
- `file_patterns`: glob patterns for Core files the proposal touches (OR evaluation)
- `content_keywords`: keywords identifying the proposal as a candidate for this Domain (OR evaluation)
- `rewrite_target`: one or more `from`/`to` path pairs for Core → Domain file rewriting (sub-field of `applies_to_proposals`)
- The enclosing Domain file's frontmatter `domain:` key (required when `applies_to_proposals` is declared)

## Processing Steps

### 1. Filter Candidate Domain Files

For each loaded Domain file:
- If `applies_to_proposals` is absent from the frontmatter: skip this file.
- Otherwise: include it as a classification candidate.

### 2. Evaluate Match Criteria

For each candidate Domain file, evaluate two independent criteria against the proposal text:

**`file_patterns` match**: Check whether the proposal text mentions any Core file path that matches at least one glob pattern in `applies_to_proposals.file_patterns`. Evaluation is OR — a single matching pattern is sufficient.

**`content_keywords` match**: Check whether the proposal text contains at least one keyword listed in `applies_to_proposals.content_keywords`. Evaluation is OR — a single matching keyword is sufficient.

Record which criteria matched for each candidate in `matched_keys`.

### 3. Apply Priority Rules

After evaluating all candidates, select the winning Domain using this priority order:

1. **Both criteria match** (`file_patterns` AND `content_keywords`): highest priority
2. **Single criterion match** (`file_patterns` OR `content_keywords`, but not both): second priority
3. **No criteria match**: the Domain is not a candidate

Within each priority tier, apply **declaration order** as the tie-break (the alphabetical file order as loaded by `domain-loader.md`).

Multiple Domain candidates are always resolved by this priority rule — they never produce `ambiguous`.

If no candidate satisfies any criterion: return `domain: none`. The calling skill preserves the Core target without rewriting.

### 4. Resolve `rewrite_target`

For the winning Domain, identify the applicable `rewrite_target` entry from `applies_to_proposals.rewrite_target`:

**Exact path in `to`**: Select that entry directly. Set `rewrite_target.to` to the specified path.

**Wildcard in `to`** (e.g., `skills/code/skill-dev-*.md`): Use LLM semantic matching to select the single best-fitting target file from the candidates implied by the wildcard pattern, based on the proposal's content and intent.

- If one candidate is clearly the best match: select it and set `rewrite_target.to` to that resolved path.
- If multiple candidates are equally plausible and a unique selection cannot be made: set `domain: ambiguous` and record the reason in `fallback_reason`. The calling skill falls back to the Core target or escalates to `/spec` for human judgment.

`ambiguous` fires only during wildcard resolution. Multi-domain candidate sets are always resolved by the priority rules in Step 3 and never reach this state.

### 5. Return Output

Assemble and return the output object described in `## Output`.

## Output

```json
{
  "domain": "skill-dev",
  "matched_keys": ["file_patterns", "content_keywords"],
  "rewrite_target": {
    "from": "skills/code/SKILL.md",
    "to": "skills/code/skill-dev-constraints.md"
  },
  "fallback_reason": null
}
```

**Field definitions:**

| Field | Type | Description |
|-------|------|-------------|
| `domain` | string | Value of the matched Domain file's frontmatter `domain:` key; `"none"` when no Domain matched; `"ambiguous"` when wildcard resolution could not select a unique target |
| `matched_keys` | array | Criteria that matched: a subset of `["file_patterns", "content_keywords"]`. Empty array when `domain` is `"none"` or `"ambiguous"` |
| `rewrite_target` | object or null | `from`/`to` path pair for Core → Domain file rewriting. `null` when `domain` is `"none"` |
| `fallback_reason` | string or null | Non-null only when `domain` is `"ambiguous"`. Explains why unique wildcard resolution failed |

**`matched_keys` and `fallback_reason`** are explainability fields for debugging and log output by the calling skill. They are always returned for interface consistency even when their informational value is low.

**Behavior by `domain` value:**
- `"none"`: no Domain matched — calling skill preserves the Core target as-is
- `"ambiguous"`: wildcard resolution failed — calling skill falls back to Core target or routes to `/spec`
- any other value: matched Domain name sourced directly from the frontmatter `domain:` key; inference from file naming conventions is not performed
