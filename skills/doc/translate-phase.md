# Translation Generation Phase

`{lang}` is a BCP 47 / ISO 639-1 language code (e.g., `ja`, `ko`, `zh-cn`, `pt-br`, `fr`). Language name resolution is delegated to the LLM's built-in knowledge — no mapping table is maintained. See BCP 47 (IETF RFC 5646) and ISO 639-1 for language code reference.

## Steps

### Step 1: Identify Target Files

Collect all translation target files:

1. Always include: `README.md` (project root)
2. Follow the "Document Traversal (common procedure)" section to collect files with `type: steering` or `type: project` frontmatter from the entire repository
3. Record the collected file list as the **translation target list** (used in Steps 3 and 4 for relative link rewriting and banner generation)
4. Detect existing translations to build the **language list**:
   - Scan `docs/*/` directories: extract directory names as language codes (e.g., `docs/ja/` → `ja`, `docs/ko/` → `ko`)
   - Scan `README.*.md` files in the project root: extract the language code segment (e.g., `README.ja.md` → `ja`)
   - Merge detected codes with the current `{lang}`, de-duplicate
   - Build the language list: `en` first, then remaining codes in alphabetical order (e.g., `[en, ja, ko]`)
   - This list is used in Steps 3 and 4 for generating language navigation banners

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
- Preserve HTML comments (`<!-- ... -->`) as-is (used for verify command hints etc.)
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

**Language Navigation Banner (prepend to translation output):**

Before writing the translated content, generate a language navigation banner and prepend it:

- Use the **language list** built in Step 1 to enumerate all languages
- The current target language (`{lang}`) is rendered as plain text; all other languages are Markdown links
- Use LLM built-in knowledge to resolve language codes to display names (e.g., `ja` → `日本語`, `ko` → `한국어`, `en` → `English`)
- Compute link paths relative to the output file:
  - From `README.{lang}.md` (root): link to `README.md` (en) or `README.{other}.md` (other translations)
  - From `docs/{lang}/{name}.md`: link to `../` + `{name}.md` (en) or `../{other}/{name}.md` (other translations)
- Banner format example (3 languages, current language = `ja`):
  ```
  [English](README.md) | 日本語 | [한국어](README.ko.md)
  ```
- Since the source frontmatter is removed in translation output, insert the banner at the very beginning (line 1) followed by a blank line

Write the translated content (with banner) to the output path using the Write tool.

### Step 4: Add Language Navigation Banners to Source Documents

For each source document in the translation target list, update the source (English) file to include the language navigation banner:

- Use the **language list** built in Step 1
- `en` (English) is rendered as plain text (current/active language); other languages are Markdown links
- Use LLM built-in knowledge to resolve language codes to display names
- Compute link paths relative to the source file position:
  - From `README.md` (root): link to `README.{lang}.md` for each translation
  - From `docs/{name}.md`: link to `{lang}/{name}.md` for each translation (same directory → no `../` needed)
- Banner format example (3 languages, source = `README.md`):
  ```
  English | [日本語](README.ja.md) | [한국어](README.ko.md)
  ```
- **Insertion position** (detect frontmatter first):
  - If the source file begins with `---` (frontmatter): insert the banner immediately after the closing `---` line, followed by a blank line
  - If no frontmatter: insert the banner at line 1, followed by a blank line
- **Existing banner replacement**: if the first non-frontmatter line starts with `English |` or `[English]`, replace that line (and the following blank line if present) with the new banner and a blank line
- Rewrite the source file using the Edit tool

### Step 5: Review Generated Translations

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

### Step 6: Commit and Push

```bash
git status
git add README.md README.{lang}.md docs/ 
git commit -s -m "docs: regenerate {lang} translations

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push origin HEAD
```

### Step 7: Completion Report

Display the following message to complete:

```
{lang} translation generation complete.
  Committed and pushed: README.{lang}.md, docs/{lang}/ ({N} files)

To regenerate translations, run `/doc translate {lang}` again.
```
