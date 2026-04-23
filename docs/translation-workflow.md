---
type: project
ssot_for: ja-translation-sync
---

English | [日本語](ja/translation-workflow.md)

# Translation Workflow

This document defines the rules for maintaining `docs/ja/` mirror files in sync with English source documents. Skills that modify top-level `docs/*.md` files must consult this document and apply the sync procedure described below.

## When to Sync

Sync `docs/ja/` mirror files whenever a top-level `docs/*.md` file is added or modified during skill execution (e.g., `/code`, `/spec`, `/review`).

## Exclusions

The following paths are **excluded** from the sync obligation:

- `docs/spec/` — Issue specifications (disposable, not translated)
- `docs/reports/` — Audit and optimization reports (not translated)
- `docs/ja/` — Translation files themselves (not recursively synced)

## Sync Procedure

1. Identify all top-level `docs/*.md` files in the changed-files list (excluding the paths above).
2. For each identified file, locate the corresponding `docs/ja/<filename>.md` mirror.
3. If the mirror does not exist, create it.
4. Update the mirror to reflect the English changes, writing in Japanese. Preserve structure, headings, and formatting consistent with the English original.

## Skills That Consult This Document

| Skill | SKILL.md path | When triggered |
|-------|---------------|----------------|
| `/code` | `skills/code/SKILL.md` | After documentation consistency check (Step 9) |
| `/spec` | `skills/spec/SKILL.md` | When building the Changed Files list (Step 10) |
| `/review` | `skills/review/SKILL.md` | During documentation consistency review (review checklist) |
