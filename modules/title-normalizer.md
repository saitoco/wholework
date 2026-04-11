# title-normalizer

Normalize Issue titles according to naming conventions for consistent formatting.

## Purpose

Normalize Issue titles according to naming conventions and rewrite them for consistency.

## Input

The following information is passed from the caller:

- **Issue title**: Current Issue title
- **Issue body**: Context used to inform title normalization decisions

## Processing Steps

Normalize the Issue title following the naming convention below.

**Naming convention:** `component: concise description starting with a verb`

**Removal rules:**
- Remove meta-information mixed into the title (e.g., `[priority:high]`)

**Noun-ending rules (for Japanese titles):**
- If the title ends with "〜する", omit the trailing "する" to form a noun-ending
- Example: "ルールを追加する" → "ルールを追加", "設定を変更する" → "設定を変更"
- **Note**: Do not omit "する" that appears mid-description (e.g., "使用する方法", "参照するルール"). Only the trailing "する" at the end of the title is the target. Also, do not remove if omission would make the title incomplete (e.g., "ログインできるようにする" → "ログインできるように" should be kept)

**Component determination criteria:**
- The component is determined from the directory name or skill name of the change target (e.g., `test-runner`, `spec`, `settings`)

**When judgment is difficult:**
- If the body is empty or the title alone is insufficient for judgment, limit changes to minimal formatting of the original title

**Normalization examples:**
- `[priority:high] test-runner: ...` → `test-runner: Add web app test framework detection`
- `bug: login fails` → `auth: Fix authentication error on login`
- `design: Add noun-ending rule` (already ends without verb) → `design: Add noun-ending rule`

### Title Drift Check

After updating the Issue body, check for semantic drift between the current title and the updated body.

**Input:**
- **Current Issue title**: the title before any body update
- **Updated Issue body**: the full body content after update

**Processing:**

1. Read the current Issue title and the updated Issue body
2. Assess whether the body's scope, purpose, or target has changed significantly from what the title describes
3. **Drift criteria** — classify as drift when any of the following apply:
   - The body describes a clearly broader or narrower scope than the title
   - The body's primary subject or component differs from the title
   - The body's goal or purpose has changed substantially
4. **If drift is detected:**
   - Generate a new title following the naming convention: `component: concise description starting with a verb`
   - Apply the same component determination criteria as the normalization rules above
   - Update the title via:
     ```bash
     gh issue edit "$NUMBER" --title "$new_title"
     ```
   - Output the before/after in skill output:
     ```
     Title updated: "{old_title}" → "{new_title}"
     ```
5. **If no drift detected**: do nothing (no output)

## Output

### Caller-Executed (Normalization)

Returns the normalized title string. The caller applies it as the `--title` argument to `gh issue edit`.

Since the title string may contain shell metacharacters, the caller should pass it safely via a variable:

```bash
gh issue edit "$NUMBER" --title "$normalized_title"
```

### Internally Executed (Drift Check)

When drift is detected, this module directly executes `gh issue edit` internally — the caller does not need to handle the title update.

The before/after is output to the terminal:

```
Title updated: "{old_title}" → "{new_title}"
```

If no drift is detected, no output is produced and no action is taken.
