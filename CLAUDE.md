# Wholework

Spec-first Claude Code skills for autonomous GitHub workflows.

## Language Conventions

- Source code: **English** (variable names, function names, comments, file names)
- Documentation: **English** (README, module docs, skill docs)
- Spec files: **Japanese** (disposable, same treatment as issue bodies)
- Issue titles: English
- Issue bodies: Japanese (for now)
- Commit messages: English

## Skills Migration Guidelines

When migrating Skills from private repositories to this public repo:

1. **English conversion**: Translate all Japanese text in source files — comments, variable names, string literals, documentation — to English before merging
   - Also check output strings not covered by test assertions (summary lines, warning messages, usage text, completion messages) — these are easy to miss because test failures will not catch them; use the checklist in `docs/migration-notes.md`
2. **Refactoring**: Use migration as an opportunity to improve clarity; remove private-repo-specific assumptions, hardcoded paths, or internal references
3. **Generalization**: Ensure Skills work as standalone, reusable components without depending on private configuration
4. **Testing**: Add or update tests to reflect the migrated and refactored behavior

## Repository Structure

See `docs/structure.md` if present for the current directory layout.

## Notes

This CLAUDE.md covers only wholework-specific conventions. Global rules (workflow commands, branch protection, commit style, etc.) are managed in `~/.claude/CLAUDE.md`.
