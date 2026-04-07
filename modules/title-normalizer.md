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

## Output

Normalized title string. The caller applies it as the `--title` argument to `gh issue edit`.

Since the title string may contain shell metacharacters, the caller should pass it safely via a variable:

```bash
gh issue edit "$NUMBER" --title "$normalized_title"
```
