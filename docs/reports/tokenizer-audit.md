# Tokenizer Audit Report: Character-count / Token Budget Assumptions

**Date**: 2026-04-18
**Scope**: 22 `skills/*.md` files, 6 `agents/*.md` files, 27 `modules/*.md` files, 34 `scripts/` files
**Purpose**: Audit distributable components for assumptions that may break under Claude Opus 4.7's new tokenizer (1.0–1.35× more tokens per text unit)

---

## Summary

| Category | Count |
|----------|-------|
| Total findings | 0 |
| Inline fixes applied | 0 |
| Follow-up issues created | 0 |
| Preserved (intentional, token-non-sensitive) | 3 |

**Detection patterns applied**:
1. `max_tokens` / `max-tokens` / `MAX_TOKENS` explicit settings
2. `head -c N` character-based truncation
3. `head -n N` line-based limits (manual confirm: token vs. pagination)
4. `1 char ≈ 1 token` implicit assumption (comments / documentation)
5. Character-based chunking / splitting
6. Log / output truncation sizing

---

## Findings

No findings. All six patterns returned zero matches across the audited scope.

---

## Remediation

No inline fixes or follow-up issues required.

---

## Preserved

The following character-count usages were identified but classified as **intentional and token-non-sensitive** — no action required.

| File | Line | Usage | Reason |
|------|------|-------|--------|
| `scripts/triage-backlog-filter.sh` | 64 | `head -n "$LIMIT"` | GitHub API pagination limit (user-configurable `LIMIT` variable); controls how many Issue numbers are returned, not a token budget |
| `skills/doc/SKILL.md` | 490 | `20 characters or less` | Content classification heuristic to exclude short lines (tool names, URLs) from common-line counts; not a token budget |
| `skills/spec/SKILL.md` | 356 | `max 30 characters` | Spec filename naming convention (URL-safety constraint for kebab-case slugs); not a token budget |
