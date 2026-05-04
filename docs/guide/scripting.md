---
type: project
---

English | [日本語](../ja/guide/scripting.md)

# Scripting Guide

Conventions and patterns for writing shell scripts in Wholework.

---

## jq Patterns

### `// empty` Guard for `.[0].field`

When using `gh ... --json X --jq '.[0].field'` to extract the first element, **always append `// empty`**:

```bash
# Bad: returns literal string "null" when the result is an empty array
VALUE=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
if [[ -n "$VALUE" ]]; then  # "null" is non-empty — proceeds incorrectly
  ...
fi

# Good: returns empty string when the result is an empty array
VALUE=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId // empty')
if [[ -n "$VALUE" ]]; then  # empty string — correctly skips
  ...
fi
```

**Why `// empty`?** When the input array is `[]`, jq evaluates `.[0]` to `null`, and
`null.field` also produces `null`. jq then outputs the string `"null"` on stdout.
A subsequent `[[ -n "$var" ]]` check treats `"null"` as a non-empty string, so the
condition evaluates to true even though no result was returned.

`// empty` is the jq alternative operator: if the left side is `null` or `false`, jq
produces no output at all (not even a newline). Bash then captures an empty string, and
`[[ -n "$var" ]]` correctly evaluates to false.

**Rule**: Use `// empty` on every `.[0].field` (or `.[N].field`) jq expression whose
result is used in a non-empty check.

### Alternative: `!= "null"` String Check

When `// empty` cannot be added (e.g., the jq expression is in a context that requires
output), guard with an explicit string comparison instead:

```bash
VALUE=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
if [[ -n "$VALUE" && "$VALUE" != "null" ]]; then
  ...
fi
```

Prefer `// empty` over the `!= "null"` check — it eliminates the `"null"` string at the
source and keeps downstream checks simple.

### `first // empty` for Filtered Arrays

When filtering with `select()` and taking the first match, use `first // empty`:

```bash
# Good: returns empty string when no matching label exists
LABEL=$(gh issue view "$NUMBER" --json labels \
  -q '[.labels[].name | select(startswith("type/"))] | first // empty')
```

---

## Error Handling

### Suppress stderr for Optional Lookups

Use `2>/dev/null || true` (or `2>/dev/null || echo ""`) for lookups where absence is
expected and should not cause the script to fail:

```bash
VALUE=$(gh issue view "$NUMBER" --json labels \
  -q '...' 2>/dev/null || true)
```

---

## Related

- Issue #355 — original discovery of `.[0].field` returning `"null"` for empty arrays
- `scripts/get-issue-type.sh` — example using `// empty` for both GraphQL and label lookups
- `scripts/run-verify.sh` — example using `.[0].databaseId // empty`
