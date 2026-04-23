# Wholework

GitHub issue-driven Claude Code skills for agentic work.

## Language Conventions

These conventions apply to all Skill-generated output (Issue bodies, Spec files, PR bodies, commit messages, etc.).

| Artifact | Language | Notes |
|----------|----------|-------|
| Source code | English | Variable names, function names, comments, file names |
| Documentation | English | README, module docs, skill docs |
| Commit messages | English | |
| Issue titles | Japanese | For now |
| Issue bodies | Japanese | For now |
| Spec files | Japanese | Disposable, same treatment as issue bodies |
| PR body | Japanese | Summaries and verification sections |
| Skill output (terminal) | Japanese | User-facing messages and status output |

## Skills Migration Guidelines

When migrating Skills from private repositories to this public repo:

1. **English conversion**: Translate all Japanese text in source files — comments, variable names, string literals, documentation — to English before merging
   - Also check output strings not covered by test assertions (summary lines, warning messages, usage text, completion messages) — these are easy to miss because test failures will not catch them; use the checklist in `docs/migration-notes.md`
2. **Refactoring**: Use migration as an opportunity to improve clarity; remove private-repo-specific assumptions, hardcoded paths, or internal references
3. **Generalization**: Ensure Skills work as standalone, reusable components without depending on private configuration
4. **Testing**: Add or update tests to reflect the migrated and refactored behavior

## Repository Structure

See `docs/structure.md` if present for the current directory layout.

## 用語

- `verify hint` / `verification hint` / `verify ヒント` / `検証ヒント` は deprecated。常に `verify command` を使用する (SSoT: `docs/product.md § Terms`)。

## Notes

This CLAUDE.md covers only wholework-specific conventions. Global rules (workflow commands, branch protection, commit style, etc.) are managed in `~/.claude/CLAUDE.md`.
