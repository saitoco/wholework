# Translation Generation Phase

`{lang}` is a BCP 47 / ISO 639-1 language code (e.g., `ja`, `ko`, `zh-cn`, `pt-br`, `fr`). Language name resolution is delegated to the LLM's built-in knowledge — no mapping table is maintained. See BCP 47 (IETF RFC 5646) and ISO 639-1 for language code reference.

## Steps

### Step 1: Identify Target Files

Collect all translation target files:

1. Always include: `README.md` (project root)
2. Follow the "Document Traversal (common procedure)" section to collect files with `type: steering` or `type: project` frontmatter from the entire repository
3. Record the collected file list as the **translation target list** (used in Step 3 for relative link rewriting)

### Step 2: Prepare Output Directory

Create the `docs/{lang}/` directory:

```bash
mkdir -p docs/{lang}
```

### Step 3: Translate Each File

For each file in the translation target list, translate and write the output:

**Output path rules:**
- `README.md` → `README.{lang}.md` (project root)
- `docs/{name}.md` → `docs/{lang}/{name}.md`
- Other paths → `docs/{lang}/{filename}.md`

**Translation instructions (apply to all files):**

Translate the entire file content to the target language (language code: `{lang}`) following these rules:

- Preserve Markdown structure (heading hierarchy, lists, tables, code blocks)
- Do NOT translate content inside code fences (` ``` `) or inline code (backticks) — keep as-is
- Preserve external URLs (`http://`, `https://`) as-is; translate only the link text
- Preserve HTML comments (`<!-- ... -->`) as-is (used for acceptance check hints etc.)
- Remove the source file's frontmatter (`---`...`---`) from the translation output — output pure Markdown without frontmatter
- Preserve proper nouns and product names (Wholework, Claude Code, GitHub, etc.) as-is

**Relative Link Rewriting Rules (apply during translation):**

Because output placement changes, rewrite relative links. Apply rules in order:

*Rule 1 — Depth adjustment (for `docs/{name}.md` → `docs/{lang}/{name}.md` case):*

Output directory is one level deeper, so rewrite paths starting with `../` to `../../`.

| Original (inside `docs/workflow.md`) | Rewrite for translation (`docs/{lang}/workflow.md`) |
|---|---|
| `../skills/code/SKILL.md` | `../../skills/code/SKILL.md` |
| `../modules/size-workflow-table.md` | `../../modules/size-workflow-table.md` |
| `../README.md` | `../../README.{lang}.md` (if translation exists) or `../../README.md` |
| `../CLAUDE.md` | `../../CLAUDE.md` |

Same-directory links (e.g., `[workflow.md](workflow.md)` inside `docs/product.md`) remain unchanged — `docs/{lang}/product.md` pointing to `workflow.md` correctly resolves to `docs/{lang}/workflow.md`.

*Rule 2 — Translation version substitution (rewrite link targets):*

If a link target is included in the translation target list, substitute with the translated path.

| Original (inside `README.md`) | Rewrite for translation (`README.{lang}.md`) |
|---|---|
| `docs/structure.md` | `docs/{lang}/structure.md` (translation target → substitute) |
| `LICENSE` | `LICENSE` (not a translation target → keep as-is) |

*Rule 3 — Excluded from rewriting:*
- External URLs (`http://`, `https://` prefix)
- Anchor-only links (`#section-name`)
- Links to files not in the translation target list

*Rule 4 — Application order:*
1. Apply Rule 1 (depth adjustment) first
2. Apply Rule 2 (translation version substitution) after, replacing `../../` paths that have translated versions with `../../docs/{lang}/{name}.md`

Write the translated content to the output path using the Write tool.

### Step 4: Review Generated Translations

Display a summary of generated files (file list and line count). Ask with AskUserQuestion for approval:

```
Generated {N} translation files.
  - README.{lang}.md
  - docs/{lang}/{name}.md
  ...

Proceed to commit and push?
- Yes, commit and push
- No, abort (keep generated files without committing)
```

If "No" is selected, display "Translation files were generated but not committed. Review them and run `/doc translate {lang}` again to commit." and exit.

### Step 5: Commit and Push

```bash
git status
git add README.{lang}.md docs/{lang}/
git commit -m "docs: regenerate {lang} translations

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push origin HEAD
```

### Step 6: Completion Report

Display the following message to complete:

```
{lang} translation generation complete.
  Committed and pushed: README.{lang}.md, docs/{lang}/ ({N} files)

To regenerate translations, run `/doc translate {lang}` again.
```
